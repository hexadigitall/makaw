import 'dart:convert';

class ContentBlockerService {
  bool enabled = true;
  bool blockAds = true;
  bool blockTrackers = true;
  bool blockAnnoyances = true;
  bool blockCryptominers = true;
  bool blockPhishing = true;
  bool blockDriveByDownloads = true;
  bool blockMalware = true;
  bool blockTypoSquatting = true;
  bool block3rdPartyCookies = false;
  bool blockWebRTC = false;
  bool blockPopups = true;
  bool blockNotifications = true;
  bool blockTabnabbing = true;
  bool blockClickjacking = true;
  bool blockHistoryHijack = true;
  bool blockStickyVideos = true;
  bool preventCls = true;
  bool protectTyposquatting = true;

  // ── Filters (deterministic, first-party) ──────────────────────────────────

  /// Returns JavaScript to inject into a web page for ad blocking.
  String generateBlockerScript(String url, {bool devTools = false}) {
    final buf = StringBuffer();
    if (blockAds) {
      buf.writeln(_adBlockFilters());
    }
    if (blockTrackers) {
      buf.writeln(_trackerBlockFilters());
    }
    if (blockAnnoyances) {
      buf.writeln(_annoyanceFilters());
    }
    buf.writeln(_commonBlockLogic());
    if (devTools) {
      buf.writeln(_devToolsHelpers());
    }
    return buf.toString();
  }

  /// Returns CSS to hide blocked elements.
  String getBlockingCss() {
    final parts = <String>[];
    if (blockAds) {
      parts.add(_adCss());
    }
    if (blockTrackers) {
      parts.add(_trackerCss());
    }
    if (blockAnnoyances) {
      parts.add(_annoyanceCss());
    }
    return parts.join('\n');
  }

  /// Returns a content-blocking rules JSON string (for in-app webview).
  String getContentBlockerRules() {
    final rules = <Map<String, dynamic>>[];
    if (blockAds) {
      rules.addAll(_adBlockRules());
    }
    if (blockTrackers) {
      rules.addAll(_trackerBlockRules());
    }
    if (blockAnnoyances) {
      rules.addAll(_annoyanceRules());
    }
    return jsonEncode(rules);
  }

  // Re-expose for backward compat
  bool get isEnabled => enabled;

  /// Check if a URL should be blocked.
  bool shouldBlock(String url) {
    if (!enabled) return false;
    if (blockAds && _isAd(url)) return true;
    if (blockTrackers && _isTracker(url)) return true;
    if (blockMalware && _isMalware(url)) return true;
    if (blockPhishing && _isPhishing(url)) return true;
    if (blockTypoSquatting && _isTypoSquat(url)) return true;
    return false;
  }

  bool _isAd(String url) => _adPatterns.any((p) => url.contains(p));
  bool _isTracker(String url) => _trackerPatterns.any((p) => url.contains(p));
  bool _isMalware(String url) => _malwarePatterns.any((p) => url.contains(p));
  bool _isPhishing(String url) => _phishingPatterns.any((p) => url.contains(p));
  bool _isTypoSquat(String url) => _typoSquatPatterns.any((p) => url.contains(p));

  // ── Embedded filter lists ─────────────────────────────────────────────────

  static const _adPatterns = [
    'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
    'google-analytics.com', 'googletagmanager.com', 'adservice.google.com',
    'pagead2.googlesyndication.com', 'adserver.', 'ad.doubleclick.net',
    'adzerk.net', 'exelator.com', 'scorecardresearch.com', 'adsrvr.org',
    'adsymptotic.com', 'adnxs.com', 'rubiconproject.com', 'criteo.com',
    'criteo.net', 'casalemedia.com', 'openx.net', 'pubmatic.com',
    'contextweb.com', 'bidswitch.net', 'agkn.com', 'media.net',
    'advertising.com', 'atdmt.com', 'bluekai.com', 'demdex.net',
    'adsafeprotected.com', 'moatads.com', 'adroll.com', 'outbrain.com',
    'taboola.com', 'exponential.com', 'tribalfusion.com', 'turn.com',
    'revjet.com', 'adbrn.com', 'adfusion.com', 'adk2.com', 'admonkey.com',
    'adthis.com', 'bravenet.com', 'burstnet.com', 'clicksor.com',
    'fastclick.com', 'popads.net', 'propellerads.com', 'trafficforce.com',
    'adsterra.com', 'adcash.com', 'exoclick.com', 'juicyads.com',
    'ad-maven.com', 'popunder.net', 'plugrush.com', 'revenuehits.com',
    'ero-advertising.com', 'adultadvertising.com', 'adxpansion.com',
    'adbooth.com', 'adbrite.com', 'adbutler.com', 'adultad.net',
    'advertisingbox.com', 'adzones.com', 'affiliate.com', 'bannerconnect.com',
    'bannerspace.com', 'caniamedia.com', 'clickthru.net', 'cyberbounty.com',
    'displayads.com', 'e-advertising.com', 'feedbanner.com',
    'globaladvertising.com', 'gorgeousads.com', 'hotlog.com',
    'infinityads.com', 'intelliads.com', 'leadclick.com', 'madisonavenue.com',
    'mads.com', 'marketadvertising.com', 'mediaon.com', 'nuffnang.com',
    'omgads.com', 'oxado.com', 'partneradvertising.com', 'pheedo.com',
    'pinads.com', 'popupad.net', 'pro-advertising.com', 'pulsead.com',
    'retargetad.com', 'smartadserver.com', 'spacash.com', 'specificmedia.com',
    'sumo.com', 'trafficadbar.com', 'trafficfactory.com', 'tribalad.com',
    'underconstruction.com', 'valuead.com', 'venturead.com', 'vibrantmedia.com',
    'web广告.com', 'xad.com', 'yieldmanager.com', 'zedo.com', '/ad/',
    '/ads/', '/advert', '/banner/', '/campaign', '/pagead/',
  ];

  static const _trackerPatterns = [
    'facebook.com/tr/', 'facebook.com/plugins/', 'connect.facebook.net',
    'platform.twitter.com', 'pixel.quantserve.com', 'pixel.rubiconproject.com',
    'static.hotjar.com', 'script.hotjar.com', 'vars.hotjar.com',
    'mc.yandex.ru', 'd37gvrvc0wt4s1.cloudfront.net',
    'www.google-analytics.com', 'ssl.google-analytics.com',
    'stats.g.doubleclick.net', 'analytics.twitter.com',
    'bat.bing.com', 'bat.r.msn.com', 'ads.linkedin.com',
    'px.ads.linkedin.com', 'snap.licdn.com', 'www.linkedin.com/px',
    'amazon-adsystem.com', 'pixel.adsafeprotected.com',
    'dpm.demdex.net', 'tags.bluekai.com', 'ib.adnxs.com',
    'secure.adnxs.com', 'sync.1rx.io', 'sync.mathtag.com',
    'pixel.tapad.com', 'idsync.rlcdn.com', 'sync.crwdcntrl.net',
    'd.turn.com', 'sync.adkernel.com', 'tag.yieldoptimizer.com',
    'bounceexchange.com', 'cdn.heapanalytics.com', 'cdn.segment.com',
    'api.segment.io', 'js.hs-scripts.com', 'track.hubspot.com',
    'analytics.pinterest.com', 'ads.pinterest.com', 'ct.pinterest.com',
    'static.ads-twitter.com', 'analytics.snapchat.com', 'tr.snapchat.com',
    's.pinimg.com/ct/', 'sc-static.net/scevent.min.js',
  ];

  static const _malwarePatterns = [
    '.exe?', '.scr?', '.bat?', '.cmd?', '.ps1?', '.vbs?',
    'malware', 'trojan', 'ransomware', 'keylogger',
  ];

  static const _phishingPatterns = [
    '.secure-login.', 'account-verify.', 'banking-secure.',
    'update-payment.', 'verify-account.', 'secure-signin.',
    'password-reset-confirm.', 'security-check.',
  ];

  static const _typoSquatPatterns = [
    'go0gle.com', 'g00gle.com', 'goog1e.com', 'googie.com', 'googale.com',
    'faceb00k.com', 'facebok.com', 'faceboook.com', 'facebo0k.com',
    'y0utube.com', 'youtuhe.com', 'youtub.com', 'youtube.cm',
    'wikipedia.cm', 'wikipedi.org', 'wikipideia.org',
    'amaz0n.com', 'amzon.com', 'amazn.com', 'amazoon.com',
    'tw1tter.com', 'twiter.com', 'twittr.com', 'twtter.com',
    'instagr4m.com', 'instagrm.com', 'instagrram.com',
    'whatsapp.cm', 'whatsap.com', 'whatssap.com',
  ];

  // ── Script generation helpers ─────────────────────────────────────────────

  String _adBlockFilters() {
    return '''
(function(){
  const ads = [
    'ins.adsbygoogle',
    'iframe[src*="doubleclick"]','iframe[src*="googlead"]','iframe[src*="ads"]',
    'div[class*="ad-container"]','div[class*="ad-wrapper"]','div[class*="ad-slot"]','div[class*="ad-unit"]',
    'div[class*="ad-banner"]','div[class*="ad-box"]','div[class*="ad-section"]',
    'div[id*="ad-container"]','div[id*="ad-wrapper"]','div[id*="ad-slot"]','div[id*="ad-unit"]',
    'aside[class*="ad-"]',
    'div[class*="sponsor"]','div[class*="promo"]','div[id*="sponsor"]','div[id*="promo"]',
    'div[class*="banner-ad"]','div[id*="banner-ad"]','div[class*="commercial"]',
    'amp-ad','amp-embed[type*="ad"]','[data-ad]','[data-ad-*]',
    '.ad-container','.ad-wrapper','.adsbygoogle','.ad-slot','.ad-unit',
    '.sponsored-content','.sponsored-post','.promoted-content',
    '.native-ad','.in-feed-ad','.article-ad','.sidebar-ad',
    '#ad-container','#ad-wrapper','#adsbygoogle','#ad-slot','#ad-unit',
    '.post-ad','.content-ad','.header-ad','.footer-ad',
    '.advertisement','.advertisement-box','.advertising',
    '.ad-label','.ad-text','.ad-image','.ad-link',
    'div[class*="advert-"]','div[class*="advert_"]','div[id*="advert-"]','div[id*="advert_"]',
    'div[class*="Ad-container"]','div[class*="Ad-wrapper"]',
    'amp-ad-container',
  ];
  function hide(sel) {
    document.querySelectorAll(sel).forEach(el => { if(el && el.style) el.style.display = 'none'; });
  }
  ads.forEach(hide);
  new MutationObserver(() => ads.forEach(hide)).observe(document.body, {childList:true, subtree:true});
})();
''';
  }

  String _trackerBlockFilters() {
    return '''
(function(){
  const trackers = [
    'script[src*="analytics"]','script[src*="tracking"]','script[src*="pixel"]',
    'img[src*="pixel"]','img[src*="analytics"]','img[src*="tracking"]',
    'script[src*="hotjar"]','script[src*="fullstory"]','script[src*="heap"]',
    'script[src*="segment"]','script[src*="mouseflow"]',
    'script[src*="crazyegg"]','script[src*="optimizely"]','script[src*="vwo"]',
    'noscript[src*="analytics"]','noscript[src*="pixel"]',
  ];
  function kill(sel) {
    document.querySelectorAll(sel).forEach(el => el.remove());
  }
  trackers.forEach(kill);
  new MutationObserver(() => trackers.forEach(kill)).observe(document.body, {childList:true, subtree:true});
})();
''';
  }

  String _annoyanceFilters() {
    return '''
(function(){
  const annoy = [
    '.cookie-banner','.cookie-notice','.cookie-consent','.cc-window','.cookies-popup',
    '#cookie-law','#cookie-notice','.eu-cookie','.gdpr-cookie','.cookie-bar',
    '.newsletter-popup','.subscribe-popup','.email-popup','.signup-popup',
    '.app-download-banner','.app-promo','.mobile-app-banner',
    '.survey-popup','.feedback-popup','.rating-popup','.review-popup',
    // OneTrust
    '#onetrust-consent-sdk','#onetrust-banner-sdk','.optanon-alert-box-wrapper',
    // Cookiebot
    '#CybotCookiebotDialog','#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll',
    // Quantcast / CMP
    '.qc-cmp2-container','.qc-cmp-ui-container',
    // Didomi
    '#didomi-popup','#didomi-notice',
    // TrustArc
    '.truste_box_overlay','.truste_overlay','#truste-consent-track',
    // Generic consent frameworks (specific, not broad)
    '[class*="consent-banner"]','[id*="consent-banner"]',
    '[class*="gdpr-banner"]','[id*="gdpr-banner"]',
    '[class*="cookie-wall"]','[id*="cookie-wall"]',
  ];
  function hide(sel) {
    document.querySelectorAll(sel).forEach(el => { if(el && el.style) el.style.display = 'none'; });
  }
  annoy.forEach(hide);
  // Auto-click common "Accept" buttons
  const acceptSelectors = [
    '#onetrust-accept-btn-handler',
    '#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll',
    '.qc-cmp2-summary-buttons button[mode="primary"]',
    'button[aria-label*="Accept"]','button[aria-label*="accept"]',
    'button[title*="Accept"]','button[title*="accept"]',
    '#L2AGLb', '.Fx4iiw',
  ];
  acceptSelectors.forEach(sel => {
    try { const b = document.querySelector(sel); if(b) b.click(); } catch(e) {}
  });
  setTimeout(() => {
    acceptSelectors.forEach(sel => {
      try { const b = document.querySelector(sel); if(b) b.click(); } catch(e) {}
    });
  }, 2000);
})();
''';
  }

  String _commonBlockLogic() {
    return '''
(function(){
  // Anti-detection: hide automation flags
  try { Object.defineProperty(navigator, 'webdriver', { get: () => undefined }); } catch(e) {}
  try { window.chrome = window.chrome || { runtime: {}, loadTimes: function(){}, csi: function(){} }; } catch(e) {}
  try {
    const origQuery = window.navigator.permissions.query;
    window.navigator.permissions.query = (params) => (
      params.name === 'notifications' ?
        Promise.resolve({ state: Notification.permission }) :
        origQuery(params)
    );
  } catch(e) {}
  try { Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] }); } catch(e) {}
  try { Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] }); } catch(e) {}
  // NOTE: Do NOT kill cookies, service workers, or sendBeacon — they break logins, PWAs, and normal page behavior
})();
''';
  }

  String _devToolsHelpers() {
    return '''
window.__blockerInfo = {
  version: "1.0",
  adsBlocked: 0,
  trackersBlocked: 0,
  annoyancesBlocked: 0,
};
// Override MutationObserver to count blocks
const origObs = MutationObserver;
window.MutationObserver = function(cb) {
  return new origObs(function(mutations) {
    mutations.forEach(function(m) {
      m.addedNodes.forEach(function(n) {
        if(n.nodeType === 1) {
          const tag = n.tagName || '';
          const cls = n.className || '';
          const id = n.id || '';
          if(tag.match(/^IFRAME|^SCRIPT|^IMG|^DIV/) &&
             (cls.match(/ad|tracker|cookie|popup/i) || id.match(/ad|tracker|cookie|popup/i))) {
            window.__blockerInfo.adsBlocked++;
          }
        }
      });
    });
    cb(mutations);
  });
};
''';
  }

  // ── CSS helpers ───────────────────────────────────────────────────────────

  String _adCss() {
    return '''
ins.adsbygoogle,
iframe[src*="doubleclick"], iframe[src*="googlead"], iframe[src*="ads"],
div[class*="ad-container"], div[class*="ad-wrapper"], div[class*="ad-slot"], div[class*="ad-unit"],
div[class*="ad-banner"], div[class*="ad-box"], div[class*="ad-section"],
div[id*="ad-container"], div[id*="ad-wrapper"], div[id*="ad-slot"], div[id*="ad-unit"],
div[class*="sponsor"], div[class*="promo"], div[class*="banner-ad"],
amp-ad, amp-embed[type*="ad"], [data-ad], [data-ad-*],
.ad-container, .ad-wrapper, .adsbygoogle, .ad-slot, .ad-unit,
.sponsored-content, .sponsored-post, .promoted-content,
.advertisement, .advertisement-box, .advertising,
div[class*="advert-"], div[class*="advert_"], div[id*="advert-"], div[id*="advert_"] { display: none !important; }
''';
  }

  String _trackerCss() {
    return '''
iframe[src*="analytics"],
#facebook, #twitter-widget, #twitter-follow { display: none !important; }
''';
  }

  String _annoyanceCss() {
    return '''
.cookie-banner, .cookie-notice, .cookie-consent, .cc-window, .cookies-popup,
#cookie-law, #cookie-notice, .eu-cookie, .gdpr-cookie, .cookie-bar,
.newsletter-popup, .subscribe-popup, .email-popup, .signup-popup,
.app-download-banner, .app-promo, .mobile-app-banner,
#onetrust-consent-sdk, #onetrust-banner-sdk, .optanon-alert-box-wrapper,
#CybotCookiebotDialog, .qc-cmp2-container, .qc-cmp-ui-container,
#didomi-popup, #didomi-notice,
.truste_box_overlay, .truste_overlay, #truste-consent-track,
div[class*="consent-banner"], div[id*="consent-banner"],
div[class*="gdpr-banner"], div[id*="gdpr-banner"],
div[class*="cookie-wall"], div[id*="cookie-wall"] { display: none !important; }
''';
  }

  // ── Content blocker rules (JSON) ──────────────────────────────────────────

  List<Map<String, dynamic>> _adBlockRules() {
    return _adPatterns.map((p) => {
      'trigger': {'url-filter': '.*$p.*'},
      'action': {'type': 'block'}
    }).toList();
  }

  List<Map<String, dynamic>> _trackerBlockRules() {
    return _trackerPatterns.map((p) => {
      'trigger': {'url-filter': '.*$p.*'},
      'action': {'type': 'block'}
    }).toList();
  }

  List<Map<String, dynamic>> _annoyanceRules() {
    return [];
  }

  bool shouldBlockUrl(String url) {
    return shouldBlock(url);
  }

  String get fullUserScript {
    if (!enabled) return '';
    return generateBlockerScript('', devTools: false);
  }
}
