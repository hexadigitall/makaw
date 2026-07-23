import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Rule-based ad/redirect blocking engine using native WebView ContentBlocker
/// rules (hardware-accelerated) plus a dynamically updated domain blacklist
/// fetched from community-maintained filter lists.
class AdBlockerService {
  static final AdBlockerService _instance = AdBlockerService._();
  factory AdBlockerService() => _instance;
  AdBlockerService._();

  // ── Domain sets (Set for O(1) lookup) ──────────────────────────────────────
  final Set<String> _hardcodedDomains = {};
  final Set<String> _dynamicDomains = {};
  final Set<String> _pathPatterns = {};
  bool _loaded = false;
  bool get loaded => _loaded;

  /// Called after blacklist loads. Tabs can regenerate contentBlockers.
  void Function()? onBlacklistUpdated;

  // ── Hardcoded ad network domains (full domain only, no bare substrings) ───
  static const _rawHardcodedDomains = [
    // Pop-under / pop-up networks
    'popads.net', 'popcash.net', 'popmyads.com', 'propu.sh',
    'exoclick.com', 'exdynsrv.com', 'exoclicktoolbar.com',
    'adsterra.com', 'propellerads.com', 'juicyads.com',
    'hilltopads.com', 'clickadu.com', 'clickaine.com',
    'ad-maven.com', 'popunder.net', 'plugrush.com',
    'revenuehits.com', 'adcash.com', 'adspirit.de',
    'bidvertiser.com', 'bidgear.com', 'admixer.com',
    'traffichunt.com', 'trafficstars.com', 'trafficforce.com',
    'trafficfactory.com', 'trafficjunky.com',
    'galaksion.com', 'monetag.com', 'clickadilla.com',
    // DSP / RTB / ad exchanges
    'adnxs.com', 'criteo.com', 'pubmatic.com',
    'rubiconproject.com', 'casalemedia.com', 'openx.net',
    'bidswitch.net', 'smartadserver.com', 'indexww.com',
    'sharethrough.com', 'connatix.com', 'moatads.com',
    'doubleverify.com', 'adsafeprotected.com', 'spotx.tv',
    'outbrain.com', 'taboola.com', 'revcontent.com', 'mgid.com',
    'teads.tv', 'teads.com', 'adform.net', 'adform.com',
    'serving-sys.com', 'doubleclick.net', 'googlesyndication.com',
    'googleadservices.com', 'pagead2.googlesyndication.com',
    'adsrvr.org', 'demdex.net', 'fastclick.net',
    'mediaforge.net', 'mathtag.com', 'turn.com', 'lijit.com',
    'adskeeper.com', 'viralcpx.net', 'crwdcntrl.net',
    'mediaplex.com', 'adlog.com',
    // Mobile ad SDKs (in-app)
    'adcolony.com', 'inmobi.com', 'smaato.net', 'mopub.com',
    'startapp.com', 'applovin.com', 'leadbolt.com',
    'chartboost.com', 'vungle.com', 'fyber.com',
    'inner-active.com', 'matomy.com', 'belboon.com',
    'adbutler.com', 'bannersbroker.com',
    // Push notification / malvert adware
    'notifpush.com', 'pushwoosh.com', 'cdn.pushame.com', 'pusham.pro',
    'onesignal.com', 'cdn.pnotop.com',
    // Obscure / rotating domains from filter lists
    'ufiler.pro', 'bngpt.com', 'trklp.com',
    'dpirw.com', 'mekadr.com', 'bcsrot.ru',
    'runtic.com', 'adfox.ru', 'begun.ru', 'ruboard.ru',
    'monuanceli.com', 'surmounttemperbooklet.com',
    'lievestcrasser.com', 'responservbzh.icu',
    'acscdn.com', 'aclib.js',
    'd33f51dyacx7bd.cloudfront.net', 'dpjf9a2rbjbvp.cloudfront.net',
    'softonixs.xyz', 'dolepl.com', 'vaost.net', 'bemobtrk.com',
    'adsteroid.pro', 'adspend001.net',
    // Betting / gambling
    '1xbet.com', '1xbet.co', '1xbet.ng',
    'bet9ja.com', 'betway.com', 'bet365.com',
    'sportybet.com', 'merrybet.com', 'nairabet.com',
    // Adult
    'pornhub.com', 'xvideos.com', 'xhamster.com',
    'redtube.com', 'youporn.com', 'spankbang.com',
  ];

  // ── Path-based patterns (require full URL match, not just domain) ─────────
  static const _rawPathPatterns = [
    '/redirect?', '/out.php', '/go.php', '/click?',
    '/adclick', '/trackclick', '/clicktrack',
  ];

  // ── Query parameter patterns (block if URL contains these) ────────────────
  static const _rawQueryPatterns = [
    'adurl=', 'clickid=', 'aff_id=',
  ];

  /// Extracts the registrable domain from a URL for Set lookups.
  static String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      // Strip www. prefix
      return host.startsWith('www.') ? host.substring(4) : host;
    } catch (_) {
      return '';
    }
  }

  /// Returns native ContentBlocker rules, split into safe-sized batches.
  List<ContentBlocker> getContentBlockerRules() {
    final rules = <ContentBlocker>[];

    // Rule 1: Block ad network domains — split into batches of 15
    // to avoid Android regex stack overflow
    final domainList = _hardcodedDomains.toList();
    for (var i = 0; i < domainList.length; i += 15) {
      final batch = domainList.skip(i).take(15);
      final pattern = batch
          .map((d) => '.*${RegExp.escape(d)}.*')
          .join('|');
      rules.add(ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: pattern),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ));
    }

    // Rule 2: Block path-based redirect patterns (safe size — 7 items)
    final pathPattern = _rawPathPatterns
        .map((p) => RegExp.escape(p))
        .join('|');
    rules.add(ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: '.*($pathPattern).*'),
      action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
    ));

    // Rule 3: Cosmetic hide — targeted pop-under overlays and ad iframes
    rules.add(ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: '.*'),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.CSS_DISPLAY_NONE,
        selector: [
          '.pop-overlay', '.ad-overlay',
          '[class*="popunder"]', '[id*="popunder"]',
          'div[style*="z-index: 2147483647"]',
          '.interstitial-ad',
          'iframe[src*="popads"]', 'iframe[src*="exoclick"]',
          'iframe[src*="propeller"]', 'iframe[src*="adsterra"]',
          'iframe[src*="hilltopads"]', 'iframe[src*="clickadu"]',
          'iframe[src*="juicyads"]', 'iframe[src*="trafficjunky"]',
          'iframe[src*="monetag"]', 'iframe[src*="ad-maven"]',
          'iframe[src*="popcash"]', 'iframe[src*="plugrush"]',
          'iframe[src*="bidvertiser"]', 'iframe[src*="revenuehits"]',
        ].join(', '),
      ),
    ));

    return rules;
  }

  /// O(1) check: should this URL be blocked?
  bool isBlocked(String url) {
    final domain = _extractDomain(url);
    if (domain.isEmpty) return false;

    // Fast domain lookup (Set.contains is O(1))
    if (_hardcodedDomains.contains(domain)) return true;
    if (_dynamicDomains.contains(domain)) return true;

    // Check subdomains: e.g. "ads.example.com" → check "example.com"
    final dotIdx = domain.indexOf('.');
    if (dotIdx > 0) {
      final parentDomain = domain.substring(dotIdx + 1);
      if (_hardcodedDomains.contains(parentDomain)) return true;
      if (_dynamicDomains.contains(parentDomain)) return true;
    }

    // Check path patterns (only on specific domains we know)
    final lowerUrl = url.toLowerCase();
    for (final p in _rawPathPatterns) {
      if (lowerUrl.contains(p)) return true;
    }

    // Check query patterns
    for (final q in _rawQueryPatterns) {
      if (lowerUrl.contains(q)) return true;
    }

    return false;
  }

  // ── Dynamic blacklist fetching + caching ─────────────────────────────────

  static const _cacheKey = 'adblocker_dynamic_domains_v2';
  static const _cacheTimestampKey = 'adblocker_last_update_v2';
  static const _cacheDuration = Duration(days: 7);

  /// Fetches EasyList + AdGuard popup list, with local caching.
  Future<void> updateBlacklist() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUpdate = prefs.getInt(_cacheTimestampKey);
    final now = DateTime.now().millisecondsSinceEpoch;

    // Use cache if less than 7 days old
    if (lastUpdate != null && (now - lastUpdate) < _cacheDuration.inMilliseconds) {
      final cached = prefs.getStringList(_cacheKey);
      if (cached != null && cached.isNotEmpty) {
        _dynamicDomains.addAll(cached);
        _loaded = true;
        onBlacklistUpdated?.call();
        return;
      }
    }

    // Fetch fresh lists
    final sources = [
      'https://easylist.to/easylist/easylist.txt',
      'https://easylist.to/easylist/fanboy-annoyance.txt',
      'https://raw.githubusercontent.com/AdguardTeam/AdGuardSDNSFilter/master/Filters/popups.txt',
    ];

    final newDomains = <String>{};
    for (final url in sources) {
      try {
        final resp = await http.get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          _parseFilterList(resp.body, newDomains);
        }
      } catch (_) {}
    }

    _dynamicDomains.addAll(newDomains);
    _loaded = true;

    // Cache to disk
    try {
      await prefs.setStringList(_cacheKey, _dynamicDomains.toList());
      await prefs.setInt(_cacheTimestampKey, now);
    } catch (_) {}

    onBlacklistUpdated?.call();
  }

  /// Parses EasyList/AdGuard-style filter text, extracting domain-level blocks.
  void _parseFilterList(String body, Set<String> out) {
    for (var line in body.split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('!') || line.startsWith('[')) continue;

      // @@ exception rules — skip (allowlist)
      if (line.startsWith('@@')) continue;

      // ## element hiding rules — skip (CSS-only, not domain blocking)
      if (line.contains('##') || line.contains('#@#')) continue;

      // ##^ scriptlet injection rules — skip
      if (line.contains('##^')) continue;

      // ||domain^ pattern (most common in EasyList)
      if (line.startsWith('||')) {
        final rest = line.substring(2);
        final domain = rest
            .split('^')
            .first
            .split('/')
            .first
            .toLowerCase()
            .trim();
        if (domain.isNotEmpty && domain.contains('.') && !domain.contains('*') && domain.length < 60) {
          out.add(domain);
        }
      }
      // Simple bare domain (no path, no wildcards, no options)
      else if (!line.startsWith('/') && !line.contains('*') &&
               !line.contains('[') && !line.contains('#') &&
               !line.contains(',') && line.contains('.') &&
               !line.contains('^')) {
        final domain = line.toLowerCase().trim();
        if (domain.length < 60 && domain.contains('.')) {
          out.add(domain);
        }
      }
    }
  }

  /// Clear cache (for settings/reset).
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimestampKey);
    _dynamicDomains.clear();
  }
}
