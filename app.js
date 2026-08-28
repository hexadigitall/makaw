(function () {
  'use strict';

  var OWNER = 'hexadigitall';
  var REPO = 'makaw';
  // Default to the latest known release so links always work even if the
  // GitHub API is rate-limited. Refresh it from the API on load when possible.
  var LATEST_TAG = 'v1.0.45';
  var API = 'https://api.github.com/repos/' + OWNER + '/' + REPO + '/releases/latest';

  var ASSETS = {
    apk:   'app-arm64-v8a-release.apk',
    win:   'makaw-windows-x64.zip',
    mac:   'makaw-macos.zip',
    linux: 'makaw-linux-x64.tar.gz'
  };

  var LABELS = {
    apk:   'Android APK',
    win:   'Windows ZIP',
    mac:   'macOS ZIP',
    linux: 'Linux tarball'
  };

  function assetUrl(key) {
    return 'https://github.com/' + OWNER + '/' + REPO +
      '/releases/download/' + LATEST_TAG + '/' + ASSETS[key];
  }

  function osKey() {
    var ua = (navigator.userAgent || '').toLowerCase();
    var platform = (navigator.platform || navigator.userAgentData && navigator.userAgentData.platform || '').toLowerCase();
    if (/android/.test(ua)) return 'apk';
    if (/iphone|ipad|ipod/.test(ua)) return null; // no iOS build
    if (/mac|os x/.test(platform) || /macintosh/.test(ua)) return 'mac';
    if (/linux/.test(platform) || /x11/.test(ua)) return 'linux';
    if (/win/.test(platform) || /windows/.test(ua)) return 'win';
    return null;
  }

  function download(url) {
    var a = document.createElement('a');
    a.href = url;
    a.rel = 'noopener';
    a.download = '';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  }

  // Hero "Download for my device" — auto-detects the OS.
  function smartDownload(e) {
    if (e) e.preventDefault();
    var key = osKey();
    var btn = document.getElementById('smart-dl');
    var sub = document.getElementById('plat-sub');
    if (!key) {
      // Fall back to the most common path: open releases page.
      window.open('https://github.com/' + OWNER + '/' + REPO + '/releases/latest', '_blank', 'noopener');
      return false;
    }
    var url = assetUrl(key);
    download(url);
    btn.textContent = '\u2b07 Downloading ' + LABELS[key] + '\u2026';
    if (sub) sub.textContent = 'Your download should start automatically.';
    return false;
  }

  // Platform cards — direct download.
  function wireCards() {
    var cards = document.querySelectorAll('.dl-card');
    Array.prototype.forEach.call(cards, function (card) {
      card.addEventListener('click', function (ev) {
        ev.preventDefault();
        var key = card.getAttribute('data-asset');
        var url = assetUrl(key);
        download(url);
        if (card.querySelector('em')) card.querySelector('em').textContent = 'Downloading\u2026';
        card.classList.add('downloading');
      });
    });
  }

  // Refresh the latest tag from the API (best-effort; never breaks the page).
  function refreshTag() {
    fetch(API, { headers: { Accept: 'application/vnd.github+json' } })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(); })
      .then(function (data) {
        if (data && data.tag_name && /^v\d+\.\d+\.\d+$/.test(data.tag_name)) {
          LATEST_TAG = data.tag_name;
        }
      })
      .catch(function () { /* rate-limited; keep default */ })
      .then(wireCards)
      .then(function () {
        var key = osKey();
        var sub = document.getElementById('plat-sub');
        if (sub) sub.textContent = key ? 'Detected: ' + LABELS[key] : 'Or pick your platform below.';
      });
  }

  // Initial wiring so cards work even before the API responds.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { wireCards(); refreshTag(); });
  } else {
    wireCards();
    refreshTag();
  }

  window.smartDownload = smartDownload;
})();
