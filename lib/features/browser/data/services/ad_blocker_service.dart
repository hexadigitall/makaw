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
  bool _loaded = false;
  bool get loaded => _loaded;

  /// Called after blacklist loads. Tabs can regenerate contentBlockers.
  void Function()? onBlacklistUpdated;

  // ── Hardcoded ad network domains (full domain only, no bare substrings) ───
  // ── Path-based patterns (require full URL match, not just domain) ─────────
  static const _rawPathPatterns = [
    '/redirect?', '/out.php', '/adclick', '/trackclick', '/clicktrack',
  ];

  // ── Query parameter patterns (block if URL contains these) ────────────────
  static const _rawQueryPatterns = [
    'adurl=', 'clickid=', 'aff_id=',
  ];

  /// Domains that must never be blocked as a whole. EasyList/AdGuard contain
  /// many *path*-scoped rules (e.g. `||google.com/adsense/`); if a parser turns
  /// those into bare-domain blocks it breaks core sites and, critically, the
  /// static-asset host `gstatic.com` that Google/Bing search pages load from.
  static const _allowlistedDomains = <String>{
    'google.com', 'gstatic.com', 'googleapis.com', 'googleusercontent.com',
    'googlevideo.com', 'google-analytics.com', 'googletagmanager.com',
    'youtube.com', 'youtu.be', 'ytimg.com', 'ggpht.com',
    'bing.com', 'live.com', 'microsoft.com', 'microsoftonline.com',
    'office.com', 'msn.com', 'windows.com', 'windowsupdate.com',
    'duckduckgo.com', 'yahoo.com', 'yandex.com', 'baidu.com',
    'openai.com', 'chatgpt.com', 'anthropic.com', 'claude.ai',
    'perplexity.ai', 'gemini.google.com', 'copilot.microsoft.com',
    'facebook.com', 'fbcdn.net', 'instagram.com', 'cdninstagram.com',
    'twitter.com', 'x.com', 'twimg.com', 'linkedin.com', 'licdn.com',
    'reddit.com', 'redd.it', 'redditstatic.com',
    'amazon.com', 'media-amazon.com', 'ssl-images-amazon.com',
    'apple.com', 'icloud.com', 'mzstatic.com',
    'github.com', 'githubusercontent.com', 'github.io',
    'stackoverflow.com', 'stackexchange.com', 'cloudflare.com',
    'wikipedia.org', 'wikimedia.org', 'netflix.com', 'spotify.com',
    'whatsapp.com', 'telegram.org', 'discord.com', 'discordapp.com',
  };

  /// True if [host] (or one of its parents) is allowlisted.
  static bool _isAllowlistedHost(String host) {
    if (host.isEmpty) return false;
    final h = host.toLowerCase();
    if (_allowlistedDomains.contains(h)) return true;
    var dot = h.indexOf('.');
    while (dot != -1 && dot < h.length - 1) {
      final parent = h.substring(dot + 1);
      if (_allowlistedDomains.contains(parent)) return true;
      dot = h.indexOf('.', dot + 1);
    }
    return false;
  }


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

    // Never block trusted/popular sites or search engines.
    if (_isAllowlistedHost(domain)) return false;

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

  static const _cacheKey = 'adblocker_dynamic_domains_v3';
  static const _cacheTimestampKey = 'adblocker_last_update_v3';
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
        _dynamicDomains.addAll(cached.where((d) => !_isAllowlistedHost(d)));
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
      // IMPORTANT: only accept rules that target the *whole domain*. Rules such
      // as `||google.com/adsense/` or `||site.com/ads/banner.png` are
      // path-scoped and must NOT be collapsed to a bare-domain block — doing so
      // over-blocks core sites (google.com, gstatic.com, facebook.com, ...).
      if (line.startsWith('||')) {
        final rest = line.substring(2);
        final beforeCaret = rest.split('^').first;
        final afterCaret = rest.contains('^') ? rest.substring(rest.indexOf('^') + 1) : '';
        final candidate = beforeCaret
            .split('/')
            .first
            .split(r'$')
            .first
            .toLowerCase()
            .trim();
        // Reject if the rule scopes to a path (a '/' before the domain separator)
        final hasPathScope = beforeCaret.contains('/');
        // Accept `||domain^`, `||domain^$options`; reject `||domain^path...`
        final hasSubpathAfter = afterCaret.isNotEmpty && !afterCaret.startsWith(r'$');
        final isPureDomain = candidate.contains('.') &&
            !candidate.contains('*') &&
            !candidate.contains('^') &&
            candidate.length < 60;
        if (isPureDomain &&
            !hasPathScope &&
            !hasSubpathAfter &&
            !_isAllowlistedHost(candidate)) {
          out.add(candidate);
        }
      }
      // Simple bare domain (no path, no wildcards, no options)
      else if (!line.startsWith('/') && !line.contains('*') &&
               !line.contains('[') && !line.contains('#') &&
               !line.contains(',') && line.contains('.') &&
               !line.contains('^') && !line.contains('/') &&
               !_isAllowlistedHost(line.toLowerCase().trim())) {
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
