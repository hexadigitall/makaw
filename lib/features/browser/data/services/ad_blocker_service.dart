import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

/// Rule-based ad/redirect blocking engine using native WebView ContentBlocker
/// rules (hardware-accelerated) plus a dynamically updated domain blacklist
/// fetched from community-maintained filter lists.
class AdBlockerService {
  static final AdBlockerService _instance = AdBlockerService._();
  factory AdBlockerService() => _instance;
  AdBlockerService._();

  final Set<String> _dynamicBlockedDomains = {};
  bool _loaded = false;
  bool get loaded => _loaded;

  // ── Hardcoded ad network domains (the script bundles sites paste in) ──────
  static const _hardcodedAdDomains = [
    'popads.net', 'popcash.net', 'exoclick.com', 'adsterra.com',
    'propellerads.com', 'juicyads.com', 'hilltopads.com', 'clickadu.com',
    'ad-maven.com', 'popunder.net', 'plugrush.com', 'revenuehits.com',
    'adcash.com', 'exponential.com', 'tribalfusion.com', 'trafficjunky.com',
    'trafficfactory.com', 'trafficforce.com', 'galaksion.com', 'monetag.com',
    'monuanceli.com', 'surmounttemperbooklet.com', 'lievestcrasser.com',
    'responservbzh.icu', 'aclib.js', 'acscdn.com',
    'd33f51dyacx7bd.cloudfront.net', 'dpjf9a2rbjbvp.cloudfront.net',
    'adnxs.com', 'criteo.com', 'pubmatic.com', 'rubiconproject.com',
    'casalemedia.com', 'openx.net', 'bidswitch.net', 'smartadserver.com',
    'indexww.com', 'sharethrough.com', 'connatix.com', 'moatads.com',
    'doubleverify.com', 'adsafeprotected.com', 'spotx.tv',
    'outbrain.com', 'taboola.com', 'revcontent.com', 'mgid.com',
    'teads.tv', 'teads.com',
    '1xbet.com', '1xbet.co', 'bet9ja.com', 'betway.com', 'bet365.com',
    'casino.com', 'slots.com', 'poker.com',
    'pornhub.com', 'xvideos.com', 'xhamster.com', 'redtube.com', 'youporn.com',
    'adnxs.com', 'adform.net', 'serving-sys.com', 'doubleclick.net',
    'googlesyndication.com', 'googleadservices.com', 'pagead2.googlesyndication.com',
    'adlog.com', 'adsrvr.org', 'demdex.net', 'doubleclick.net',
    'fastclick.net', 'mediaforge.net', 'mathtag.com', 'turn.com',
    'lijit.com', 'adskeeper.com', 'viralcpx.net', 'notifpush.com',
    'pushwoosh.com', 'onesignal.com', 'cdn.pushame.com',
    'belboon.com', 'adbutler.com', 'adspirit.de', 'adsteroid.pro',
    'bannersbroker.com', 'crwdcntrl.net', 'mediaplex.com',
    'adcolony.com', 'inmobi.com', 'smaato.net', 'mopub.com',
    'startapp.com', 'applovin.com', 'unity3d.com/ads',
    'leadbolt.com', 'chartboost.com', 'vungle.com', 'fyber.com',
    'fyber.com', 'inner-active.com', 'matomy.com',
    'adfox.ru', 'begun.ru', 'ruboard.ru', 'runtic.com',
    'bcsrot.ru', 'dpirw.com', 'mekadr.com', 'bngpt.com',
    'trklp.com', 'ufiler.pro', 'traffichunt.com', 'hilltopads.com',
    'clickadu.com', 'clickaine.com', 'bidvertiser.com', 'bidgear.com',
    'serving-sys.com', 'adform.com', 'admixer.com',
    'popmyads.com', 'propu.sh', 'onclickmax.com', 'exdynsrv.com',
    'exoclicktoolbar.com', 'trafficstars.com', ' traffpartners.com',
    'dolepl.com', 'vaost.net', 'bemobtrk.com', 'clickgate',
    'softonixs.xyz', 'adsplanet', 'adspend',
    'redirect', 'trackclick', 'clkmg', 'clickadilla',
    'adspend001', 'adsterra-h', 'pusham.pro',
    'o2tvseries.com/redirect', 'o2tvseries.com/ad',
  ];

  // ── Hardcoded redirect domain patterns ────────────────────────────────────
  static const _redirectPatterns = [
    '/redirect?', '/out.php', '/go.php', '/click?',
    '/adclick', '/trackclick', '/clicktrack',
    'adurl=', 'clickid=', 'aff_id=', 'tracking=',
  ];

  /// Fetches EasyList + AdGuard popup list and merges into the blocked set.
  Future<void> updateBlacklist() async {
    final sources = [
      'https://easylist.to/easylist/easylist.txt',
      'https://easylist.to/easylist/fanboy-annoyance.txt',
      'https://raw.githubusercontent.com/AdguardTeam/AdGuardSDNSFilter/master/Filters/popups.txt',
    ];

    for (final url in sources) {
      try {
        final resp = await http.get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          _parseFilterList(resp.body);
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  /// Parses EasyList/AdGuard-style filter text into domain entries.
  void _parseFilterList(String body) {
    final lines = body.split('\n');
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('!') || line.startsWith('[')) continue;

      // Extract domain from ||domain^ pattern
      if (line.startsWith('||')) {
        final domain = line
            .replaceFirst('||', '')
            .split('^')
            .first
            .split('/')
            .first
            .toLowerCase();
        if (domain.contains('.') && !domain.contains('*')) {
          _dynamicBlockedDomains.add(domain);
        }
      }
      // Extract domain from @@ exception rules — skip (allowlist)
      else if (line.startsWith('@@')) {
        continue;
      }
      // Simple domain matches
      else if (!line.contains('/') && !line.contains('*') && !line.contains('[') && line.contains('.')) {
        final domain = line.toLowerCase();
        if (domain.length < 60) {
          _dynamicBlockedDomains.add(domain);
        }
      }
    }
  }

  /// Returns native ContentBlocker rules for InAppWebViewSettings.
  List<ContentBlocker> getContentBlockerRules() {
    final rules = <ContentBlocker>[];

    // Rule 1: Block ad network script bundles at native level
    final adDomainPatterns = _hardcodedAdDomains
        .where((d) => d.contains('.'))
        .map((d) => '.*${RegExp.escape(d)}.*')
        .join('|');
    if (adDomainPatterns.isNotEmpty) {
      rules.add(ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: adDomainPatterns),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ));
    }

    // Rule 2: Block suspicious redirect URL patterns
    final redirectPattern = _redirectPatterns
        .map((p) => RegExp.escape(p))
        .join('|');
    rules.add(ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: '.*($redirectPattern).*'),
      action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
    ));

    // Rule 3: Cosmetic hide — pop-under overlays and fake buttons
    rules.add(ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: '.*'),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.CSS_DISPLAY_NONE,
        selector: [
          '.pop-overlay', '.ad-overlay', '[class*="popunder"]',
          '[id*="popunder"]', 'div[style*="z-index: 2147483647"]',
          'div[style*="z-index:99999"]', '.interstitial-ad',
          '[class*="ad-wrapper"]', '[class*="ad-container"]',
          'iframe[src*="popads"]', 'iframe[src*="exoclick"]',
          'iframe[src*="propeller"]', 'iframe[src*="adsterra"]',
          'iframe[src*="hilltopads"]', 'iframe[src*="clickadu"]',
          'iframe[src*="juicyads"]', 'iframe[src*="trafficjunky"]',
          'iframe[src*="monetag"]', 'iframe[src*="ad-maven"]',
        ].join(', '),
      ),
    ));

    return rules;
  }

  /// Checks if a URL should be blocked by the dynamic blacklist.
  bool isBlocked(String url) {
    final lower = url.toLowerCase();
    // Check hardcoded ad domains
    for (final d in _hardcodedAdDomains) {
      if (lower.contains(d)) return true;
    }
    // Check dynamic blacklist
    for (final d in _dynamicBlockedDomains) {
      if (lower.contains(d)) return true;
    }
    // Check redirect patterns
    for (final p in _redirectPatterns) {
      if (lower.contains(p)) return true;
    }
    return false;
  }
}
