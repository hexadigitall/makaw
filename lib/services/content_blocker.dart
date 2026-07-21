import 'dart:convert';

class ContentBlocker {
  bool enabled = true;
  bool blockAds = true;
  bool blockTrackers = true;
  bool blockPopups = true;
  bool blockMalware = true;
  bool blockAnnoyances = true;
  bool blockNotifications = true;
  bool blockTabnabbing = true;
  bool blockClickjacking = true;
  bool blockHistoryHijack = true;
  bool blockStickyVideos = true;
  bool blockDriveByDownloads = true;
  bool preventCls = true;
  bool protectTyposquatting = true;

  final List<FilterRule> _userRules = [];
  final List<String> _allowedSites = [];

  static const _adDomains = [
    'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
    'google-analytics.com', 'googletagmanager.com', 'googletagservices.com',
    'adservice.google.com', 'pagead2.googlesyndication.com',
    'advertising.com', 'adnxs.com', 'adsrvr.org', 'adsymptotic.com',
    'adzerk.net', 'amazon-adsystem.com', 'casalemedia.com',
    'contextweb.com', 'criteo.com', 'criteo.net', 'crwdcntrl.net',
    'everesttech.net', 'exelator.com', 'facebook.com/tr',
    'fastlane.rubiconproject.com', 'indexww.com', 'lijit.com',
    'media.net', 'moatads.com', 'openx.net', 'pubmatic.com',
    'pubnub.com', 'quantserve.com', 'rubiconproject.com',
    'scorecardresearch.com', 'serving-sys.com', 'sharethis.com',
    'spotxchange.com', 'taboola.com', 'teads.tv', 'tidaltv.com',
    'turn.com', 'twitter.com/analytics', 'outbrain.com',
    'connatix.com', 'inmobi.com', 'adcolony.com', 'applovin.com',
    'chartboost.com', 'supersonicads.com', 'vungle.com',
    'admarvel.com', 'millennialmedia.com', 'adf.ly', 'adfoc.us',
    'popads.net', 'propellerads.com', 'adsterra.com', 'exoclick.com',
    'trafficjunky.com', 'adreactor.com', 'adultadvertising.net',
    'pixfuture.com', 'revcontent.com', 'mgid.com', 'nativeads.com',
    'adthrive.com', 'mediavine.com', 'sovrn.com', 'skimlinks.com',
    'viglink.com', 'zanox.com', 'tradeadexchange.com',
    'adsafeprotected.com', 'adssettings.google.com',
    '2mdn.net', 'adobedtm.com', 'demdex.net', 'dpm.demdex.net',
    'agkn.com', 'bkrtx.com', 'bluekai.com',
    'addthis.com', 'addthisedge.com', 'summerhamster.com',
    'pixel.quantserve.com', 'cm.g.doubleclick.net',
    'stats.g.doubleclick.net', 'ad.doubleclick.net',
    'securepubads.g.doubleclick.net', 'tpc.googlesyndication.com',
    'partner.googleadservices.com', 'www.googleadservices.com',
    'googleads.g.doubleclick.net', 'adservice.google.com.tr',
    'adservice.google.co.uk', 'adservice.google.co.jp',
    'fundingchoicesmessages.google.com',
    'pagead2.googleadservices.com', 'google.com/pagead/',
    'youtube.com/pagead/', 'youtube.com/api/stats/ads',
    'youtube.com/youtubei/v1/player/ads',
    'imasdk.googleapis.com', 'gstatic.com/doubleclick',
    'gstatic.com/admob', 'g.doubleclick.net',
    'googleoptimize.com', 'googletagservices.com/tagjs/gpt.js',
    'an.yandex.ru', 'mc.yandex.ru', 'yandex.com/ads',
    'adriver.ru', 'marketgid.com', 'adfox.ru',
    'ad.projektmarswars.eu', 'ad.digitalcamp.ru',
    'pagepeeker.com', 'hit.gemius.pl', 'gemius.pl',
    'adtech.de', 'adform.net', 'adform.com',
    'adition.com', 'smartadserver.com', 'adspirit.de',
    'netze.de', 'adjust.com', 'appsflyer.com',
    'branch.io', 'adjust.io', 'kochava.com',
  ];

  static const _trackerDomains = [
    'facebook.com/tr/', 'connect.facebook.net', 'analytics.twitter.com',
    'ads-api.twitter.com', 'static.ads-twitter.com',
    'pixel.quantserve.com', 'b.scorecardresearch.com',
    's0.2mdn.net', 'akamai.net', 'moat.com', 'moatads.com',
    'hotjar.com', 'mouseflow.com', 'fullstory.com', 'luckyorange.com',
    'crazyegg.com', 'clicktale.net', 'sessioncam.com', 'inspectlet.com',
    'amplitude.com', 'segment.com', 'mixpanel.com', 'heap.io',
    'usermaven.com', 'posthog.com', 'matomo.org', 'piwik.org',
    'bugsnag.com', 'sentry.io', 'rollbar.com', 'datadog.com',
    'newrelic.com', 'appdynamics.com', 'dynatrace.com',
    'zendesk.com', 'intercom.io', 'drift.com', 'olark.com',
    'livechat.com', 'tawk.to', 'freshchat.com',
    'optimizely.com', 'vwo.com', 'convert.com', 'abtasty.com',
    'snapchat.com/ads', 'tiktok.com/analytics',
    'linkedin.com/analytics', 'pinterest.com/analytics',
    'hubspot.com/analytics', 'marketo.com', 'pardot.com',
    'eloqua.com', 'act-on.com', 'mailchimp.com/tracking',
    'sendgrid.com/tracking', 'postmarkapp.com/tracking',
    'salesforce.com/serving', 'salesforceliveagent.com',
    'google.com/ads/measurement', 'google.com/ads/user-lists',
    'googlesource.com/measurement', 'googleadsserving.cn',
    'googletagmanager.com/ns.html', 'analytics.google.com',
    'region1.google-analytics.com', 'region1.analytics.google.com',
    'www.googletagmanager.com/gtag/js', 'www.googletagmanager.com/gtm.js',
    'stats.wp.com', 'pixel.wp.com', 'sstats.adobe.com',
    'sc.omtrdc.net', 'metrics.apple.com', 'metrics.icloud.com',
    'app-measurement.com', 'firebase-settings.crashlytics.com',
    'stats.g.doubleclick.net/g/collect',
    'cdn.segment.com', 'cdn.mxpnl.com', 'cdn.heapanalytics.com',
    'cdn.amplitude.com', 'cdn.hotjar.com', 'cdn.luckyorange.com',
    'cdn.fullstory.com', 'cdn.bugsnag.com', 'cdn.rollbar.com',
    'www.google-analytics.com', 'ssl.google-analytics.com',
    'www.googletagmanager.com/gtag/js?id=',
    'bat.bing.com', 'bat.bing.net',
    'static.ads-twitter.com/uwt.js',
    'snap.licdn.com', 'px.ads.linkedin.com',
    'ads.pinterest.com', 'ct.pinterest.com',
    'analytics.tiktok.com', 'ads.tiktok.com',
    'analytics.snapchat.com', 'tr.snapchat.com',
    'www.clarity.ms', 'clarity.ms',
    'cdn-cookieyes.com', 'cdn.cookielaw.org',
  ];

  static const _malwareDomains = [
    'bitcoin.xyz', 'cryptoloot.pro', 'coin-hive.com', 'coinhive.com',
    'crypto-loot.com', 'miner.pr0gramm.com', 'serversminer.net',
    'webmine.pro', 'wpmine.org', 'cpuminer.net', 'cryptonight.win',
    'coinnebula.com', 'minero.cc', 'monerominer.rocks',
    'cdn.cloudflare.com/ajax/libs/coin', 'coinwidget.com',
    'jquery.com/drew/coin', 'coinpot.co', 'freebitcoin.com',
    'crpt.cryptonight.club', 'miner.miniacash.com',
    'cryptomining-blog.com', 'minexmr.com', 'minr.pw',
    'coinminer.net', 'litecoinminer.net', 'ethminer.net',
    'btcminer.net', 'xmrminer.net', 'monerominer.net',
    'cryptotab.farm', 'cryptotab.org', 'honeyminer.com',
    'cryptobrowserminer.com', 'cryptobrowser.com',
    'jsecoin.com', 'coinimp.com', 'coinhive-js.com',
    'coinhiveproxy.com', 'coin-have.com', 'coin-have-proxy.com',
    'afminer.com', 'ad-miner.com', 'autominer.net',
    'coinblind.com', 'coinerra.com', 'coinmeb.com',
    'cryptaloot.pro', 'crypto-loot.org', 'cryptoloot.org',
    'deepminer.net', 'dmminer.com', 'dutchminer.nl',
    'gastarget.net', 'gunminer.com', 'hashminer.net',
    'hashing.win', 'hashpays.com', 'hashvault.pro',
    'hellominer.com', 'iceminer.net', 'jsminer.net',
    'lightminer.net', 'liteminer.net', 'madminer.net',
    'masterminer.net', 'mega-miner.net', 'miner.cm',
    'miner.js', 'miner.tips', 'miner01.com', 'mineralt.com',
    'minerhills.com', 'minermore.com', 'minerr.pro',
    'miners.pro', 'minersilo.com', 'minerstart.com',
    'minertroop.com', 'minerunion.com', 'minerworld.net',
    'mineryard.com', 'minetech.net', 'minethd.com',
    'monerominer.xyz', 'neutrominer.net', 'newminer.net',
    'ninjamining.net', 'openminer.net', 'pminer.net',
    'power-miner.com', 'projectminer.net', 'rapidminer.net',
    'reminer.net', 'rockminer.net', 'royalminer.net',
    'safeminer.net', 'smartermine.com', 'sockminer.com',
    'solominer.net', 'speedminer.net', 'stormminer.net',
    'strongminer.net', 'supermninerr.com', 'thadminer.net',
    'tigerminer.net', 'tokenminer.net', 'turbominer.com',
    'ultraminer.net', 'unionminer.com', 'videominer.net',
    'vipminer.net', 'webminerpool.com', 'winminer.net',
    'x11miner.net', 'xcoinminer.net', 'xenminer.net',
    'xmrmining.net', 'zecminer.net',
  ];

  static const _annoyanceDomains = [
    'cookiebot.com', 'cookie-script.com', 'cookieconsent.com',
    'cookiepro.com', 'onetrust.com', 'usercentrics.eu',
    'cookiefirst.com', 'cookieinfo.com', 'cookiescript.com',
    'cookiesandyou.com', 'cmp.usercentrics.eu',
    'cc.cdn.civiccomputing.com', 'consent.cookiebot.com',
    'cookie-cdn.cookiepro.com', 'platform.linkedin.com/badges',
    'widget.trustpilot.com', 'widget.reviews.io',
    'static.elfsight.com', 'apps.elfsight.com',
    'assets.calendly.com', 'newsletter.perfect-audience.com',
    'popupmaker.com', 'sumo.com', 'hello-bar.com', 'getsitecontrol.com',
    'optinmonster.com', 'widgeo.co', 'exitintel.com',
    'sociallocker.com', 'gtranslate.net', 'translate.google.com/translate_a/l',
    'cookieyes.com', 'cookie-law.info', 'cookielaw.org',
    'cookie-script.com', 'cookiebot.com', 'cookiepro.com',
    'termly.io', 'cookies.eu', 'cookieserve.com',
    'iubenda.com', 'privacypolicies.com', 'freeprivacypolicy.com',
    'cmp.usercentrics.eu', 'consent.google.com',
    'fundingchoicesmessages.google.com',
    'advertisement.news', 'popup.news', 'survey.news',
    'exitpopup.net', 'exitpopup.org', 'popupmania.net',
    'popupdomination.com', 'popupally.com', 'popupmaker.com',
    'sumo.com/app', 'optinmonster.com/app',
    'getsitecontrol.com/app', 'widgeo.co/app',
  ];

  static const _adCssSelectors = [
    'div[class*="ad"]', 'div[id*="ad"]', 'div[class*="ads"]', 'div[id*="ads"]',
    'ins.adsbygoogle', 'iframe[src*="doubleclick"]', 'iframe[src*="googlead"]',
    'iframe[src*="adservice"]', 'a[href*="doubleclick"]', 'a[href*="adservice"]',
    'div[class*="banner"]', 'div[id*="banner"]', 'div[class*="sponsor"]',
    'div[id*="sponsor"]', 'div[class*="promo"]', 'div[id*="promo"]',
    'div[class*="commercial"]', 'aside[class*="ad"]', 'aside[id*="ad"]',
    'section[class*="ad"]', 'section[id*="ad"]', 'amp-ad', 'amp-embed',
    'div[data-ad-*]', 'div[data-google-query-id]',
    'div[class*="Advertisement"]', 'div[id*="Advertisement"]',
    'div[class*="advertisement"]', 'div[id*="advertisement"]',
    '.ad-container', '.ad-wrapper', '.ad-slot', '.ad-box', '.ad-banner',
    '.ad-placeholder', '.ad-content', '.ad-inner', '.ad-unit',
    '#ad-container', '#ad-wrapper', '#ad-slot', '#ad-box', '#ad-banner',
    '[id*="-ad-"]', '[class*="-ad-"]',
    'div[class*="taboola"]', 'div[id*="taboola"]',
    'div[class*="outbrain"]', 'div[id*="outbrain"]',
    'div[class*="native-ad"]', 'div[class*="sponsored-content"]',
    'div[class*="in-feed-ad"]', 'div[class*="in-content-ad"]',
    '.google-auto-placed', '.google-advertisement',
    'amp-auto-ads', 'amp-sticky-ad',
    'div[aria-label*="ad"]', 'div[aria-label*="sponsor"]',
    'div[data-ad-placement]', 'div[data-ad-size]',
    'div[data-ad-unit]', 'div[data-ad-slot]',
    'div[class*="prebid"]', 'div[id*="prebid"]',
    'div[class*="dfp"]', 'div[id*="dfp"]',
    'div[class*="gpt"]', 'div[id*="gpt"]',
    'div[class*="google_ads"]', 'div[id*="google_ads"]',
  ];

  static const _annoyanceCssSelectors = [
    'div[class*="cookie"]', 'div[id*="cookie"]', 'div[class*="consent"]',
    'div[id*="consent"]', '.cookie-banner', '.cookie-consent', '.cookie-notice',
    '#cookie-banner', '#cookie-consent', '#cookie-notice',
    'div[class*="gdpr"]', 'div[id*="gdpr"]', '.gdpr-banner', '.gdpr-consent',
    'div[class*="newsletter-popup"]', 'div[class*="subscribe-popup"]',
    'div[class*="exit-popup"]', 'div[id*="popup"]',
    '.newsletter-popup', '.subscribe-popup', '.exit-intent-popup',
    'div[class*="social-share"]', 'div[class*="share-buttons"]',
    'div[class*="sticky-header"]', 'div[class*="sticky-footer"]',
    'div[class*="floating-bar"]', 'div[class*="notification-bar"]',
    'div[class*="slide-in"]', 'div[class*="slideup"]',
    'div[class*="overlay"]', 'div[class*="modal"]',
    'div[class*="interstitial"]', 'div[class*="fullscreen-banner"]',
    'div[class*="welcome-banner"]', 'div[class*="age-gate"]',
    'div[class*="paywall"]', 'div[class*="subscription-banner"]',
    'div[class*="push-notification"]', 'div[class*="permission-banner"]',
    'div[class*="app-banner"]', 'div[class*="install-banner"]',
    'div[class*="survey"]', 'div[class*="feedback-widget"]',
    'div[class*="chat-widget"]', 'div[class*="live-chat"]',
  ];

  // Trusted domains for typosquatting protection
  static const _trustedDomains = [
    'google.com', 'youtube.com', 'facebook.com', 'twitter.com', 'x.com',
    'instagram.com', 'linkedin.com', 'whatsapp.com', 'tiktok.com',
    'amazon.com', 'netflix.com', 'spotify.com', 'microsoft.com', 'apple.com',
    'github.com', 'stackoverflow.com', 'reddit.com', 'wikipedia.org',
    'yahoo.com', 'bing.com', 'duckduckgo.com',
    'paypal.com', 'bankofamerica.com', 'wellsfargo.com', 'chase.com',
    'dropbox.com', 'drive.google.com', 'mail.google.com',
    'outlook.live.com', 'office.com', 'adobe.com', 'zoom.us',
    'telegram.org', 'discord.com', 'slack.com',
    'medium.com', 'quora.com', 'pinterest.com', 'ebay.com',
    'walmart.com', 'target.com', 'bestbuy.com', 'homedepot.com',
    'roblox.com', 'twitch.tv', 'steampowered.com', 'epicgames.com',
    'cloudflare.com', 'vercel.com', 'netlify.com', 'heroku.com',
    'digitalocean.com', 'aws.amazon.com', 'azure.microsoft.com',
    'npmjs.com', 'pypi.org', 'pub.dev', 'crates.io',
    'docker.com', 'kubernetes.io', 'gitlab.com', 'bitbucket.org',
    'atlassian.com', 'notion.so', 'figma.com', 'canva.com',
    'wordpress.com', 'blogger.com', 'squarespace.com', 'wix.com',
    'shopify.com', 'bigcommerce.com', 'stripe.com', 'square.com',
    'coinbase.com', 'binance.com', 'kraken.com',
    'usps.com', 'fedex.com', 'ups.com', 'dhl.com',
    'irs.gov', 'usa.gov', 'gov.uk', 'canada.ca',
    'nih.gov', 'cdc.gov', 'who.int', 'un.org',
    'cnn.com', 'bbc.com', 'bbc.co.uk', 'nytimes.com',
    'wsj.com', 'reuters.com', 'ap.org',
    'imdb.com', 'rottentomatoes.com',
  ];

  static const _typosquatTlds = [
    '.xyz', '.top', '.gq', '.tk', '.ml', '.ga', '.cf', '.click',
    '.download', '.review', '.work', '.date', '.men', '.loan',
    '.win', '.bid', '.trade', '.webcam', '.science', '.party',
    '.racing', '.online', '.site', '.website', '.space', '.tech',
    '.host', '.press', '.wiki', '.design',
    '.rest', '.bond', '.faith', '.monster', '.cruise',
    '.cyou', 'cfd', '.sbs', '.beauty', '.skin',
  ];

  // ── JS Scripts ──────────────────────────────────────────────────────

  String get adBlockScript {
    if (!enabled || !blockAds) return '';
    return _buildHideScript(_adCssSelectors);
  }

  String get popupBlockerScript {
    if (!enabled || !blockPopups) return '';
    return '''
(function() {
  if (window._makawPopupBlock) return;
  window._makawPopupBlock = true;
  const originalOpen = window.open;
  window.open = function(url, name, specs, replace) {
    window.flutter_inappwebview.callHandler('popupBlocked', url || '');
    return null;
  };
  document.addEventListener('click', function(e) {
    let target = e.target;
    while (target && target.tagName !== 'A') target = target.parentElement;
    if (target && target.getAttribute('target') === '_blank') {
      if (target.hasAttribute('onclick') && target.getAttribute('onclick').includes('window.open')) {
        e.preventDefault();
        e.stopPropagation();
        window.flutter_inappwebview.callHandler('popupBlocked', target.href || '');
      }
    }
  }, true);
})();
''';
  }

  String get popUnderProtectionScript {
    if (!enabled || !blockPopups) return '';
    return '''
(function() {
  if (window._makawPopUnder) return;
  window._makawPopUnder = true;
  const originalOpen = window.open;
  window.open = function(url, name, specs, replace) {
    window.flutter_inappwebview.callHandler('popupBlocked', url || '');
    return null;
  };
  let focusCount = 0;
  window.addEventListener('blur', function() {
    focusCount++;
    if (focusCount > 5) {
      window.flutter_inappwebview.callHandler('popUnderDetected', '');
    }
  });
  const visibilityHandler = function() {
    if (document.hidden && document.querySelector('video, audio')) {
      const media = document.querySelector('video, audio');
      if (!media.paused) {
        window.flutter_inappwebview.callHandler('popUnderDetected', 'media playing in background');
      }
    }
  };
  document.addEventListener('visibilitychange', visibilityHandler);
})();
''';
  }

  String get annoyanceBlockScript {
    if (!enabled || !blockAnnoyances) return '';
    return _buildHideScript(_annoyanceCssSelectors);
  }

  String get notificationBlockScript {
    if (!enabled || !blockNotifications) return '';
    return '''
(function() {
  if (window._makawNotifBlock) return;
  window._makawNotifBlock = true;
  if (typeof Notification !== 'undefined') {
    Notification.requestPermission = function() { return Promise.resolve('denied'); };
    Notification.permission = 'denied';
    const desc = Object.getOwnPropertyDescriptor(Notification, 'permission');
    if (desc && desc.configurable) {
      Object.defineProperty(Notification, 'permission', { value: 'denied', writable: false });
    }
  }
  if (navigator.serviceWorker && navigator.serviceWorker.pushManager) {
    const orig = navigator.serviceWorker.pushManager.subscribe;
    navigator.serviceWorker.pushManager.subscribe = function() {
      return Promise.reject(new Error('Notifications blocked by Makaw'));
    };
    navigator.serviceWorker.pushManager.getSubscription = function() {
      return Promise.resolve(null);
    };
  }
  if ('Notification' in window && navigator.permissions) {
    navigator.permissions.query({name:'notifications'}).then(function(r) {
      try { r.onchange = null; } catch(e) {}
    });
  }
})();
''';
  }

  String get tabnabbingProtectionScript {
    if (!enabled || !blockTabnabbing) return '';
    return '''
(function() {
  if (window._makawTabnabbing) return;
  window._makawTabnabbing = true;
  function fixLinks(root) {
    const links = root.querySelectorAll ? root.querySelectorAll('a[target="_blank"]') : [];
    links.forEach(function(a) {
      const rel = (a.getAttribute('rel') || '').toLowerCase();
      if (!rel.includes('noopener')) {
        a.setAttribute('rel', (rel + ' noopener noreferrer').trim());
      }
    });
  }
  fixLinks(document);
  const obs = new MutationObserver(function(muts) {
    muts.forEach(function(m) {
      m.addedNodes.forEach(function(n) {
        if (n.nodeType === 1) fixLinks(n);
      });
    });
  });
  obs.observe(document.documentElement, {childList: true, subtree: true});
  const origPushState = history.pushState;
  history.pushState = function() {
    setTimeout(function() { fixLinks(document); }, 100);
    return origPushState.apply(this, arguments);
  };
})();
''';
  }

  String get clickjackingProtectionScript {
    if (!enabled || !blockClickjacking) return '';
    return '''
(function() {
  if (window._makawClickjack) return;
  window._makawClickjack = true;
  if (window.top !== window.self) {
    window.top.location = window.self.location;
  }
  function removeClickjackingOverlays() {
    document.querySelectorAll('div, iframe, embed, object').forEach(function(el) {
      try {
        const style = window.getComputedStyle(el);
        if (style.opacity === '0' && style.position === 'fixed' && parseInt(style.zIndex) > 0) {
          el.style.setProperty('display', 'none', 'important');
        }
        if (style.opacity === '0' && style.position === 'absolute') {
          const rect = el.getBoundingClientRect();
          if (rect.width >= window.innerWidth || rect.height >= window.innerHeight) {
            el.style.setProperty('display', 'none', 'important');
          }
        }
      } catch(e) {}
    });
  }
  removeClickjackingOverlays();
  const obs = new MutationObserver(removeClickjackingOverlays);
  obs.observe(document.documentElement, {childList: true, subtree: true, attributes: true});
})();
''';
  }

  String get historyHijackProtectionScript {
    if (!enabled || !blockHistoryHijack) return '';
    return '''
(function() {
  if (window._makawHistoryHijack) return;
  window._makawHistoryHijack = true;
  let pushCount = 0;
  const maxPushes = 20;
  const origPush = history.pushState;
  const origReplace = history.replaceState;
  history.pushState = function() {
    pushCount++;
    if (pushCount > maxPushes) { console.warn('Makaw: blocked pushState spam'); return; }
    return origPush.apply(this, arguments);
  };
  history.replaceState = function() {
    pushCount++;
    if (pushCount > maxPushes) { console.warn('Makaw: blocked replaceState spam'); return; }
    return origReplace.apply(this, arguments);
  };
  let popstateCount = 0;
  const origAddEventListener = window.addEventListener;
  window.addEventListener = function(type, fn, opts) {
    if (type === 'popstate') {
      popstateCount++;
      if (popstateCount > 3) { console.warn('Makaw: blocked popstate listener'); return; }
    }
    if (type === 'beforeunload') {
      const fnStr = fn.toString();
      if (fnStr.includes('preventDefault') || fnStr.includes('returnValue')) {
        console.warn('Makaw: blocked beforeunload trap');
        return;
      }
    }
    return origAddEventListener.call(this, type, fn, opts);
  };
})();
''';
  }

  String get stickyVideoProtectionScript {
    if (!enabled || !blockStickyVideos) return '';
    return '''
(function() {
  if (window._makawStickyVideo) return;
  window._makawStickyVideo = true;
  function handleStickyVideos() {
    document.querySelectorAll('video, .video-player, [class*="video-container"], [class*="video-wrapper"]').forEach(function(el) {
      try {
        const style = window.getComputedStyle(el);
        if (style.position === 'fixed' || style.position === 'sticky') {
          const parent = el.closest('[class*="ad"], [id*="ad"], [class*="sponsor"], [class*="promo"]');
          if (parent) { el.style.setProperty('display', 'none', 'important'); return; }
          const rect = el.getBoundingClientRect();
          if (rect.width < 100 || rect.height < 80) return;
          if (rect.left > window.innerWidth || rect.top > window.innerHeight) return;
          if (!el.querySelector('._makaw-close-video')) {
            const btn = document.createElement('button');
            btn.className = '_makaw-close-video';
            btn.textContent = '×';
            Object.assign(btn.style, {
              position: 'absolute', top: '-12px', right: '-12px', zIndex: '99999',
              background: '#000', color: '#fff', borderRadius: '50%',
              width: '26px', height: '26px', fontSize: '16px', cursor: 'pointer',
              border: '2px solid #fff', display: 'flex', alignItems: 'center',
              justifyContent: 'center', lineHeight: '1', padding: '0',
              boxShadow: '0 2px 6px rgba(0,0,0,0.3)',
            });
            btn.onclick = function(e) { e.stopPropagation(); el.style.setProperty('display', 'none', 'important'); };
            el.style.position = 'relative';
            el.appendChild(btn);
          }
        }
      } catch(e) {}
    });
  }
  handleStickyVideos();
  const obs = new MutationObserver(handleStickyVideos);
  obs.observe(document.documentElement, {childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class']});
})();
''';
  }

  String get driveByDownloadProtectionScript {
    if (!enabled || !blockDriveByDownloads) return '';
    return '''
(function() {
  if (window._makawDriveBy) return;
  window._makawDriveBy = true;
  const binExts = ['zip','rar','7z','tar','gz','apk','exe','msi','iso','img','dmg','deb','rpm','bin','exe','scr','bat','cmd','vbs','ps1','jar','wasm'];
  const metaRefresh = document.querySelector('meta[http-equiv="refresh"]');
  if (metaRefresh) {
    const content = (metaRefresh.getAttribute('content') || '').toLowerCase();
    for (const ext of binExts) {
      if (content.includes('.' + ext)) { metaRefresh.remove(); break; }
    }
  }
  function sanitizeIframes() {
    document.querySelectorAll('iframe').forEach(function(f) {
      try {
        const rect = f.getBoundingClientRect();
        const style = window.getComputedStyle(f);
        if ((rect.width < 10 && rect.height < 10) || style.display === 'none' || style.visibility === 'hidden') {
          const src = (f.getAttribute('src') || '').toLowerCase();
          if (src && !src.startsWith('about:') && !src.startsWith('javascript:')) {
            f.setAttribute('data-original-src', f.src);
            f.src = 'about:blank';
          }
        }
      } catch(e) {}
    });
  }
  sanitizeIframes();
  const obs = new MutationObserver(sanitizeIframes);
  obs.observe(document.documentElement, {childList: true, subtree: true});
  const origFetch = window.fetch;
  window.fetch = function(input, init) {
    const url = (typeof input === 'string' ? input : input?.url || '').toLowerCase();
    for (const ext of binExts) {
      if (url.includes('.' + ext) && !url.startsWith('http')) {
        console.warn('Makaw: blocked drive-by fetch download');
        return Promise.reject(new Error('Blocked by Makaw'));
      }
    }
    return origFetch.apply(this, arguments);
  };
})();
''';
  }

  String get clsPreventionScript {
    if (!enabled || !preventCls) return '';
    return '''
(function() {
  if (window._makawCLS) return;
  window._makawCLS = true;
  const s = document.createElement('style');
  s.textContent = `
    ins.adsbygoogle, div[class*="ad"], div[id*="ad"],
    iframe[src*="doubleclick"], iframe[src*="googlead"],
    div[class*="banner"], div[id*="banner"],
    [data-ad-*], [data-google-query-id]
    { min-height: 1px !important; }
    img:not([width]):not([height]):not(.ignore-cls) { aspect-ratio: 16/9; }
    iframe:not([width]):not([height]) { min-height: 200px; }
  `;
  document.documentElement.appendChild(s);
  function reserveSpace() {
    document.querySelectorAll('img, iframe, video').forEach(function(el) {
      if (!el.hasAttribute('width') && !el.hasAttribute('height') && !el.classList.contains('ignore-cls')) {
        el.classList.add('ignore-cls');
        if (el.tagName === 'IMG' && !el.complete) {
          el.style.aspectRatio = '16/9';
        } else if (el.tagName === 'IFRAME') {
          el.style.minHeight = '200px';
        } else if (el.tagName === 'VIDEO') {
          el.style.aspectRatio = '16/9';
        }
        el.addEventListener('load', function() {
          el.style.aspectRatio = '';
          el.style.minHeight = '';
        }, {once: true});
      }
    });
  }
  reserveSpace();
  const obs = new MutationObserver(reserveSpace);
  obs.observe(document.documentElement, {childList: true, subtree: true});
})();
''';
  }

  static const _lookalikeChars = {
    '0': 'o', '1': 'l', '2': 'z', '3': 'e', '4': 'a', '5': 's',
    '6': 'g', '7': 't', '8': 'b', '9': 'g',
  };

  bool _levenshtein(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    final aa = a.toLowerCase(), bb = b.toLowerCase();
    if (aa == bb) return false;
    final m = aa.length, n = bb.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (int i = 0; i <= m; i++) dp[i][0] = i;
    for (int j = 0; j <= n; j++) dp[0][j] = j;
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (aa[i - 1] == bb[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] = 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]].reduce((a, b) => a < b ? a : b);
        }
      }
    }
    return dp[m][n] == 1;
  }

  bool _isTransposed(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length - 1; i++) {
      if (a[i] != b[i]) {
        if (a[i] == b[i + 1] && a[i + 1] == b[i]) { diff++; i++; }
        else return false;
      }
    }
    return diff == 1;
  }

  bool isTyposquat(String host) {
    if (!protectTyposquatting) return false;
    final h = host.toLowerCase();
    for (final tld in _typosquatTlds) {
      if (h.endsWith(tld)) return true;
    }
    for (final trusted in _trustedDomains) {
      if (h == trusted) return false;
      final sub = h
          .replaceAll('0', 'o').replaceAll('1', 'l').replaceAll('3', 'e')
          .replaceAll('4', 'a').replaceAll('5', 's').replaceAll('6', 'g')
          .replaceAll('7', 't').replaceAll('8', 'b').replaceAll('9', 'g');
      if (sub == trusted) return true;
      if (_levenshtein(h, trusted)) return true;
      if (_isTransposed(h, trusted)) return true;
    }
    return false;
  }

  String get typosquattingScript {
    if (!enabled || !protectTyposquatting) return '';
    return '''
(function() {
  if (window._makawTyposquat) return;
  window._makawTyposquat = true;
  const trusted = ${jsonEncode(_trustedDomains)};
  const susTlds = ${jsonEncode(_typosquatTlds)};
  const host = location.hostname.toLowerCase();
  const isSus = susTlds.some(function(t) { return host.endsWith(t); });
  if (isSus) {
    console.warn('Makaw: suspicious TLD detected - ' + host);
    window.flutter_inappwebview.callHandler('typosquatWarning', {host: host, reason: 'suspicious TLD'});
  }
  for (const t of trusted) {
    const thost = t.split(':')[0];
    if (host === thost) break;
    const sub = host.replace(/0/g,'o').replace(/1/g,'l').replace(/3/g,'e').replace(/4/g,'a').replace(/5/g,'s').replace(/6/g,'g').replace(/7/g,'t').replace(/8/g,'b').replace(/9/g,'g');
    if (sub === thost) {
      window.flutter_inappwebview.callHandler('typosquatWarning', {host: host, reason: 'lookalike of ' + thost});
      break;
    }
    if (host.length === thost.length) {
      let diffs = 0;
      for (let i = 0; i < host.length; i++) { if (host[i] !== thost[i]) diffs++; }
      if (diffs === 1) {
        window.flutter_inappwebview.callHandler('typosquatWarning', {host: host, reason: 'typosquat of ' + thost});
        break;
      }
    }
  }
})();
''';
  }

  // ── Combined Script ─────────────────────────────────────────────────

  String get fullUserScript {
    final scripts = <String>[];
    if (blockAds) scripts.add(adBlockScript);
    if (blockPopups) {
      scripts.add(popupBlockerScript);
      scripts.add(popUnderProtectionScript);
    }
    if (blockAnnoyances) scripts.add(annoyanceBlockScript);
    if (blockNotifications) scripts.add(notificationBlockScript);
    if (blockTabnabbing) scripts.add(tabnabbingProtectionScript);
    if (blockClickjacking) scripts.add(clickjackingProtectionScript);
    if (blockHistoryHijack) scripts.add(historyHijackProtectionScript);
    if (blockStickyVideos) scripts.add(stickyVideoProtectionScript);
    if (blockDriveByDownloads) scripts.add(driveByDownloadProtectionScript);
    if (preventCls) scripts.add(clsPreventionScript);
    if (protectTyposquatting) scripts.add(typosquattingScript);
    if (scripts.isEmpty) return '';
    return scripts.join('\n');
  }

  // ── CSS Hide ─────────────────────────────────────────────────────────

  String _buildHideScript(List<String> selectors) {
    final joined = selectors.map((s) => '"${s.replaceAll('"', '\\"')}"').join(', ');
    return '''
(function() {
  const selectors = [$joined];
  const style = document.createElement('style');
  style.textContent = selectors.join(', ') + ' { display: none !important; }';
  document.documentElement.appendChild(style);
  const observer = new MutationObserver(function() {
    const style2 = document.createElement('style');
    style2.textContent = selectors.join(', ') + ' { display: none !important; }';
    document.documentElement.appendChild(style2);
    setTimeout(function() { style2.remove(); }, 100);
  });
  observer.observe(document.documentElement, {childList: true, subtree: true});
})();
''';
  }

  // ── URL Blocking ─────────────────────────────────────────────────────

  bool shouldBlockUrl(String url) {
    if (!enabled || !url.startsWith('http')) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    final fullUrl = url.toLowerCase();

    for (final allowed in _allowedSites) {
      if (host.contains(allowed)) return false;
    }
    if (blockAds) {
      for (final domain in _adDomains) {
        if (fullUrl.contains(domain)) return true;
      }
    }
    if (blockTrackers) {
      for (final domain in _trackerDomains) {
        if (fullUrl.contains(domain)) return true;
      }
    }
    if (blockMalware) {
      for (final domain in _malwareDomains) {
        if (fullUrl.contains(domain)) return true;
      }
    }
    if (blockAnnoyances) {
      for (final domain in _annoyanceDomains) {
        if (fullUrl.contains(domain)) return true;
      }
    }
    for (final rule in _userRules) {
      if (rule.matches(url)) return rule.action == FilterAction.block;
    }
    return false;
  }

  bool shouldBlockPopup(String url) {
    if (!enabled || !blockPopups) return false;
    if (url.isEmpty || url == 'about:blank') return true;
    return shouldBlockUrl(url);
  }

  // ── User Rules ───────────────────────────────────────────────────────

  void addUserRule(FilterRule rule) => _userRules.add(rule);
  void removeUserRule(FilterRule rule) => _userRules.remove(rule);
  void allowSite(String domain) => _allowedSites.add(domain.toLowerCase());
  void disallowSite(String domain) => _allowedSites.remove(domain.toLowerCase());

  List<FilterRule> get userRules => List.unmodifiable(_userRules);
  List<String> get allowedSites => List.unmodifiable(_allowedSites);

  Map<String, bool> get settings => {
    'blockAds': blockAds,
    'blockTrackers': blockTrackers,
    'blockPopups': blockPopups,
    'blockMalware': blockMalware,
    'blockAnnoyances': blockAnnoyances,
    'blockNotifications': blockNotifications,
    'blockTabnabbing': blockTabnabbing,
    'blockClickjacking': blockClickjacking,
    'blockHistoryHijack': blockHistoryHijack,
    'blockStickyVideos': blockStickyVideos,
    'blockDriveByDownloads': blockDriveByDownloads,
    'preventCls': preventCls,
    'protectTyposquatting': protectTyposquatting,
  };

  void updateSettings(Map<String, bool> s) {
    if (s.containsKey('blockAds')) blockAds = s['blockAds']!;
    if (s.containsKey('blockTrackers')) blockTrackers = s['blockTrackers']!;
    if (s.containsKey('blockPopups')) blockPopups = s['blockPopups']!;
    if (s.containsKey('blockMalware')) blockMalware = s['blockMalware']!;
    if (s.containsKey('blockAnnoyances')) blockAnnoyances = s['blockAnnoyances']!;
    if (s.containsKey('blockNotifications')) blockNotifications = s['blockNotifications']!;
    if (s.containsKey('blockTabnabbing')) blockTabnabbing = s['blockTabnabbing']!;
    if (s.containsKey('blockClickjacking')) blockClickjacking = s['blockClickjacking']!;
    if (s.containsKey('blockHistoryHijack')) blockHistoryHijack = s['blockHistoryHijack']!;
    if (s.containsKey('blockStickyVideos')) blockStickyVideos = s['blockStickyVideos']!;
    if (s.containsKey('blockDriveByDownloads')) blockDriveByDownloads = s['blockDriveByDownloads']!;
    if (s.containsKey('preventCls')) preventCls = s['preventCls']!;
    if (s.containsKey('protectTyposquatting')) protectTyposquatting = s['protectTyposquatting']!;
  }

  // ── Video Detection (legacy) ─────────────────────────────────────────

  String get videoDetectionScript => '''
(function() {
  function extractVideos() {
    const results = [];
    const videos = document.querySelectorAll('video');
    videos.forEach(function(v) {
      if (v.src && v.src.startsWith('http')) {
        results.push({url: v.src, type: 'video'});
      }
      v.querySelectorAll('source').forEach(function(s) {
        if (s.src && s.src.startsWith('http')) {
          results.push({url: s.src, type: 'video/' + (s.type.replace('video/', '') || 'mp4')});
        }
      });
    });
    const iframes = document.querySelectorAll('iframe[src*="youtube"], iframe[src*="youtube-nocookie"]');
    iframes.forEach(function(f) {
      let url = f.src;
      if (url.includes('embed/')) {
        const id = url.split('embed/')[1].split('?')[0];
        results.push({url: 'https://www.youtube.com/watch?v=' + id, type: 'youtube'});
      }
    });
    const links = document.querySelectorAll('a[href*="youtube.com/watch"], a[href*="youtu.be/"]');
    links.forEach(function(a) {
      results.push({url: a.href, type: 'youtube'});
    });
    const pageVideos = document.querySelectorAll('[data-video-url], [data-video-src]');
    pageVideos.forEach(function(el) {
      const url = el.getAttribute('data-video-url') || el.getAttribute('data-video-src');
      if (url && url.startsWith('http')) {
        results.push({url: url, type: 'video'});
      }
    });
    return results;
  }
  const found = extractVideos();
  if (found.length > 0) {
    window.flutter_inappwebview.callHandler('videoDetected', JSON.stringify(found));
  }
})();
''';
}

enum FilterAction { block, allow }

class FilterRule {
  final String pattern;
  final FilterAction action;
  final bool isRegex;
  final bool isDomain;

  FilterRule({required this.pattern, required this.action, this.isRegex = false, this.isDomain = false});

  bool matches(String url) {
    if (isRegex) {
      return RegExp(pattern, caseSensitive: false).hasMatch(url);
    }
    if (isDomain) {
      final uri = Uri.tryParse(url);
      return uri != null && uri.host.toLowerCase().contains(pattern.toLowerCase());
    }
    return url.toLowerCase().contains(pattern.toLowerCase());
  }

  Map<String, dynamic> toJson() => {'pattern': pattern, 'action': action.name, 'isRegex': isRegex, 'isDomain': isDomain};

  factory FilterRule.fromJson(Map<String, dynamic> json) => FilterRule(
    pattern: json['pattern'] as String,
    action: json['action'] == 'allow' ? FilterAction.allow : FilterAction.block,
    isRegex: json['isRegex'] as bool? ?? false,
    isDomain: json['isDomain'] as bool? ?? false,
  );
}
