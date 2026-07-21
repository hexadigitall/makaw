const { app, BrowserWindow, session, ipcMain, dialog, Menu, nativeTheme, clipboard, globalShortcut } = require('electron');
const { autoUpdater } = require('electron-updater');
app.commandLine.appendSwitch('ignore-gpu-blocklist');
app.commandLine.appendSwitch('enable-unsafe-swiftshader');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const { spawn } = require('child_process');
const https = require('https');
const http = require('http');
const Database = require('better-sqlite3');
const ffmpegPath = require('ffmpeg-static');
const os = require('os');
const pty = require('node-pty');

let ptyProcess;

let db;
let mainWindow;
const activeDownloads = new Map();
const downloadQueue = [];
const downloadIdMap = new Map(); // dbId -> runtimeId

const MAX_PARALLEL_DOWNLOADS = 3;

// ─── Content Blocker ─────────────────────────────────────────────────────────

const contentBlocker = {
  enabled: true,
  blockAds: true,
  blockTrackers: true,
  blockPopups: true,
  blockMalware: true,
  blockAnnoyances: true,
  allowedSites: [],
  userRules: [],
  blockedCount: 0,

  adDomains: [
    'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
    'google-analytics.com', 'googletagmanager.com', 'googletagservices.com',
    'adservice.google.com', 'pagead2.googlesyndication.com',
    'advertising.com', 'adnxs.com', 'adsrvr.org', 'adsymptotic.com',
    'adzerk.net', 'amazon-adsystem.com', 'casalemedia.com',
    'contextweb.com', 'criteo.com', 'criteo.net', 'crwdcntrl.net',
    'everesttech.net', 'exelator.com', 'facebook.com/tr',
    'fastlane.rubiconproject.com', 'indexww.com', 'lijit.com',
    'media.net', 'moatads.com', 'openx.net', 'pubmatic.com',
    'quantserve.com', 'rubiconproject.com', 'scorecardresearch.com',
    'serving-sys.com', 'sharethis.com', 'spotxchange.com', 'taboola.com',
    'teads.tv', 'outbrain.com', 'connatix.com', 'inmobi.com',
    'adcolony.com', 'applovin.com', 'popads.net', 'propellerads.com',
    'adsterra.com', 'exoclick.com', 'revcontent.com', 'mgid.com',
    'skimlinks.com', '2mdn.net', 'adobedtm.com', 'demdex.net',
    'addthis.com', 'pixel.quantserve.com', 'cm.g.doubleclick.net',
    'stats.g.doubleclick.net', 'ad.doubleclick.net', 'tpc.googlesyndication.com',
    'imasdk.googleapis.com', 'gstatic.com/doubleclick',
    'youtube.com/pagead/', 'youtube.com/api/stats/ads',
  ],

  trackerDomains: [
    'connect.facebook.net', 'analytics.twitter.com',
    'pixel.quantserve.com', 'b.scorecardresearch.com',
    'hotjar.com', 'mouseflow.com', 'fullstory.com', 'luckyorange.com',
    'crazyegg.com', 'amplitude.com', 'segment.com', 'mixpanel.com',
    'matomo.org', 'piwik.org', 'sentry.io', 'datadog.com',
    'intercom.io', 'drift.com', 'tawk.to',
    'optimizely.com', 'vwo.com',
    'snapchat.com/ads', 'tiktok.com/analytics',
    'linkedin.com/analytics', 'pinterest.com/analytics',
    'mailchimp.com/tracking', 'sendgrid.com/tracking',
    'analytics.google.com', 'region1.google-analytics.com',
    'www.googletagmanager.com/gtag/js', 'www.googletagmanager.com/gtm.js',
    'stats.wp.com', 'pixel.wp.com',
    'app-measurement.com', 'firebase-settings.crashlytics.com',
  ],

  malwareDomains: [
    'coinhive.com', 'crypto-loot.com', 'webmine.pro',
    'cryptoloot.pro', 'miner.pr0gramm.com', 'serversminer.net',
  ],

  annoyanceDomains: [
    'cookiebot.com', 'cookie-script.com', 'cookieconsent.com',
    'onetrust.com', 'usercentrics.eu',
    'widget.trustpilot.com', 'platform.linkedin.com/badges',
    'popupmaker.com', 'sumo.com', 'optinmonster.com',
  ],

  adCssSelectors: [
    'div[class*="ad"]', 'div[id*="ad"]', 'div[class*="ads"]', 'div[id*="ads"]',
    'ins.adsbygoogle', 'iframe[src*="doubleclick"]', 'iframe[src*="googlead"]',
    'div[class*="banner"]', 'div[id*="banner"]', 'div[class*="sponsor"]',
    'div[class*="promo"]', 'div[id*="promo"]', 'amp-ad', 'amp-embed',
    '.ad-container', '.ad-wrapper', '.ad-slot', '.ad-banner',
    '#ad-container', '#ad-wrapper', '#ad-slot',
    'div[class*="taboola"]', 'div[class*="outbrain"]',
    '.google-auto-placed', 'amp-auto-ads',
  ],

  annoyanceCssSelectors: [
    'div[class*="cookie"]', 'div[id*="cookie"]',
    '.cookie-banner', '.cookie-consent', '.cookie-notice',
    'div[class*="gdpr"]', 'div[id*="gdpr"]',
    'div[class*="newsletter-popup"]', 'div[class*="subscribe-popup"]',
    'div[class*="exit-popup"]', 'div[id*="popup"]',
  ],

  shouldBlockUrl(url) {
    if (!this.enabled || !url.startsWith('http')) return false;
    const lower = url.toLowerCase();
    for (const site of this.allowedSites) {
      if (lower.includes(site)) return false;
    }
    const lists = [];
    if (this.blockAds) lists.push(this.adDomains);
    if (this.blockTrackers) lists.push(this.trackerDomains);
    if (this.blockMalware) lists.push(this.malwareDomains);
    if (this.blockAnnoyances) lists.push(this.annoyanceDomains);
    for (const list of lists) {
      for (const domain of list) {
        if (lower.includes(domain)) { this.blockedCount++; return true; }
      }
    }
    for (const rule of this.userRules) {
      if (lower.includes(rule.pattern)) return rule.action === 'block';
    }
    return false;
  },

  getHideScript() {
    const selectors = [
      ...(this.blockAds ? this.adCssSelectors : []),
      ...(this.blockAnnoyances ? this.annoyanceCssSelectors : []),
    ];
    if (!selectors.length) return '';
    const joined = selectors.map(s => `"${s}"`).join(', ');
    return `
(function() {
  const s = document.createElement('style');
  s.textContent = '${joined} { display: none !important; }';
  document.documentElement.appendChild(s);
  new MutationObserver(function() {
    const s2 = document.createElement('style');
    s2.textContent = '${joined} { display: none !important; }';
    document.documentElement.appendChild(s2);
    setTimeout(() => s2.remove(), 100);
  }).observe(document.documentElement, {childList: true, subtree: true});
})();
`;
  },

  getPopupBlockerScript() {
    if (!this.enabled || !this.blockPopups) return '';
    return `
(function() {
  const orig = window.open;
  window.open = function(url) {
    return null;
  };
  document.addEventListener('click', function(e) {
    let t = e.target;
    while (t && t.tagName !== 'A') t = t.parentElement;
    if (t && t.getAttribute('target') === '_blank' && t.hasAttribute('onclick') && t.getAttribute('onclick').includes('window.open')) {
      e.preventDefault(); e.stopPropagation();
    }
  }, true);
})();
`;
  },

  getVideoDetectionScript() {
    return `
(function() {
  const results = [];
  document.querySelectorAll('video').forEach(function(v) {
    if (v.src && v.src.startsWith('http')) results.push({url: v.src, type: 'video'});
    v.querySelectorAll('source').forEach(function(s) {
      if (s.src && s.src.startsWith('http')) results.push({url: s.src, type: s.type || 'video/mp4'});
    });
  });
  document.querySelectorAll('[data-video-url], [data-video-src]').forEach(function(el) {
    const u = el.getAttribute('data-video-url') || el.getAttribute('data-video-src');
    if (u && u.startsWith('http')) results.push({url: u, type: 'video'});
  });
  return results;
})();
`;
  }
};

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1600,
    height: 1000,
    icon: path.join(__dirname, 'assets', 'makaw_logo.ico'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: true
    },
    title: 'Makaw Studio'
  });
  mainWindow.loadFile('index.html');
  if (process.argv.includes('--dev')) mainWindow.webContents.openDevTools();

  // Right-click context menu (cut/copy/paste)
  mainWindow.webContents.on('context-menu', (event, params) => {
    const { editFlags } = params;
    Menu.buildFromTemplate([
      { role: 'cut', enabled: editFlags.canCut },
      { role: 'copy', enabled: editFlags.canCopy },
      { role: 'paste', enabled: editFlags.canPaste },
      { type: 'separator' },
      { role: 'selectAll', enabled: editFlags.canSelectAll }
    ]).popup({ window: mainWindow });
  });

  const menuTemplate = [
    {
      label: 'File',
      submenu: [
        { role: 'quit' }
      ]
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        {
          label: 'Smart Paste',
          accelerator: 'CmdOrCtrl+Shift+V',
          click: () => { if (mainWindow) mainWindow.webContents.send('menu-smart-paste'); }
        },
        { role: 'selectAll' }
      ]
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { type: 'separator' },
        {
          label: 'Toggle Main DevTools',
          click: () => mainWindow.webContents.toggleDevTools()
        },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' }
      ]
    },
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'close' }
      ]
    }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(menuTemplate));

  // Intercept Ctrl+V before menu/DOM to handle paste anywhere (including webview)
  mainWindow.webContents.on('before-input-event', (event, input) => {
    if ((input.control || input.meta) && input.key.toLowerCase() === 'v' && !input.alt && !input.shift) {
      const text = clipboard.readText() || (process.platform === 'linux' ? clipboard.readText('selection') : '');
      if (text) {
        mainWindow.webContents.send('global-paste', text);
      } else if (isWSL) {
        // On WSL, the Linux clipboard may be empty; trigger renderer to try Windows clipboard
        mainWindow.webContents.send('wsl-paste-trigger');
      }
    }
  });
}

app.whenReady().then(() => {
  db = new Database(path.join(app.getPath('userData'), 'makaw-cache.db'));
  db.exec(`
    CREATE TABLE IF NOT EXISTS injected_pages (
      hash_id TEXT PRIMARY KEY,
      html_content TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS downloads (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      url TEXT,
      type TEXT,
      status TEXT,
      progress REAL,
      filepath TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS projects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT,
      type TEXT,
      content TEXT,
      language TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS snippets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT,
      category TEXT,
      language TEXT,
      code TEXT,
      description TEXT
    );
  `);

  // Seed default snippets
  const defaultSnippets = [
    { name: 'HTML5 Boilerplate', category: 'boilerplate', language: 'html', code: '<!DOCTYPE html>\\n<html>\\n<head>\\n  <meta charset="UTF-8">\\n  <title>Document</title>\\n</head>\\n<body>\\n  \\n</body>\\n</html>', description: 'Basic HTML5 structure' },
    { name: 'Fetch API', category: 'snippet', language: 'javascript', code: 'fetch(url)\\n  .then(res => res.json())\\n  .then(data => console.log(data))\\n  .catch(err => console.error(err));', description: 'Simple fetch request' },
    { name: 'Express Server', category: 'boilerplate', language: 'javascript', code: 'const express = require("express");\\nconst app = express();\\napp.get("/", (req, res) => res.send("Hello"));\\napp.listen(3000);', description: 'Minimal Express server' },
    { name: 'React Component', category: 'boilerplate', language: 'javascript', code: 'import React from "react";\\n\\nexport default function Component() {\\n  return <div></div>;\\n}', description: 'Functional React component' }
  ];
  const snippetCount = db.prepare('SELECT COUNT(*) as count FROM snippets').get().count;
  if (snippetCount === 0) {
    const insert = db.prepare('INSERT INTO snippets (name, category, language, code, description) VALUES (?, ?, ?, ?, ?)');
    defaultSnippets.forEach(s => insert.run(s.name, s.category, s.language, s.code, s.description));
  }

  createWindow();

  // Grant clipboard-read permission for the main window (needed for navigator.clipboard.readText())
  session.defaultSession.setPermissionRequestHandler((webContents, permission, callback) => {
    if (permission === 'clipboard-read' || permission === 'clipboard-write') {
      callback(true);
    } else {
      callback(false);
    }
  });

  ipcMain.handle('get-clipboard-text', () => {
    return clipboard.readText() || (process.platform === 'linux' ? clipboard.readText('selection') : '');
  });

  // WSL clipboard bridge: detect if running under WSL
  const isWSL = process.platform === 'linux' && fs.existsSync('/mnt/c/Windows/System32/clip.exe');
  const clipExe = '/mnt/c/Windows/System32/clip.exe';
  const psExe = '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe';

  ipcMain.handle('wsl-clipboard-copy', async (event, text) => {
    if (!isWSL) return false;
    try {
      const { execFile } = require('child_process');
      await new Promise((resolve, reject) => {
        const proc = execFile(clipExe, [], (err) => err ? reject(err) : resolve());
        proc.stdin.write(text);
        proc.stdin.end();
      });
      return true;
    } catch (_) { return false; }
  });

  ipcMain.handle('wsl-clipboard-paste', async () => {
    if (!isWSL) return '';
    try {
      const { execFile } = require('child_process');
      const result = await new Promise((resolve, reject) => {
        execFile(psExe, ['-NoProfile', '-Command', 'Get-Clipboard'], { maxBuffer: 1024 * 1024 }, (err, stdout) => {
          if (err) reject(err);
          else resolve(stdout.trim());
        });
      });
      return result;
    } catch (_) { return ''; }
  });

  ipcMain.handle('set-theme-source', (event, source) => {
    nativeTheme.themeSource = source;
  });

  // File / folder dialogs
  ipcMain.handle('open-file-dialog', async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      properties: ['openFile'],
      filters: [
        { name: 'All Files', extensions: ['*'] },
        { name: 'Code', extensions: ['html','js','ts','jsx','tsx','css','json','py','md','xml','c','cpp','h','java','rb','go','rs','sh','yaml','yml','sql','vue','php','swift','kt','dart','lua'] }
      ]
    });
    if (result.canceled || !result.filePaths.length) return { canceled: true };
    const filePath = result.filePaths[0];
    const content = fs.readFileSync(filePath, 'utf-8');
    return { canceled: false, path: filePath, name: path.basename(filePath), content };
  });

  ipcMain.handle('open-folder-dialog', async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      properties: ['openDirectory']
    });
    if (result.canceled || !result.filePaths.length) return { canceled: true };
    return { canceled: false, path: result.filePaths[0] };
  });

  // Resolve special paths ($HOME, $WINDOWS_ROOT) or verify a raw path exists
  ipcMain.handle('resolve-path', async (event, key) => {
    const os = require('os');
    if (key === '$HOME') return { path: os.homedir() };
    if (key === '$WINDOWS_ROOT') {
      const p = '/mnt/c';
      return { path: fs.existsSync(p) ? p : null };
    }
    return { path: fs.existsSync(key) ? key : null };
  });

  ipcMain.handle('read-file', async (event, filePath) => {
    try {
      const content = fs.readFileSync(filePath, 'utf-8');
      return { success: true, content, name: path.basename(filePath) };
    } catch (err) {
      return { success: false, error: err.message };
    }
  });

  ipcMain.handle('write-file', async (event, { path: filePath, content }) => {
    try {
      fs.writeFileSync(filePath, content, 'utf-8');
      return { success: true };
    } catch (err) {
      return { success: false, error: err.message };
    }
  });

  ipcMain.handle('list-folder', async (event, folderPath) => {
    try {
      const items = fs.readdirSync(folderPath, { withFileTypes: true });
      const files = items.map(d => ({
        name: d.name,
        isDir: d.isDirectory(),
        path: path.join(folderPath, d.name)
      }));
      files.sort((a, b) => {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.localeCompare(b.name);
      });
      return { success: true, files, folder: folderPath };
    } catch (err) {
      return { success: false, error: err.message };
    }
  });

  ipcMain.handle('create-file', async (event, { folder, name }) => {
    try {
      const filePath = path.join(folder, name);
      fs.writeFileSync(filePath, '', 'utf-8');
      return { success: true, path: filePath, name };
    } catch (err) {
      return { success: false, error: err.message };
    }
  });

  ipcMain.handle('create-folder', async (event, { parent, name }) => {
    try {
      const dirPath = path.join(parent, name);
      fs.mkdirSync(dirPath, { recursive: true });
      return { success: true, path: dirPath, name };
    } catch (err) {
      return { success: false, error: err.message };
    }
  });

  // ─── Content Blocker: Block requests ───────────────────────────────────────
  session.defaultSession.webRequest.onBeforeRequest({ urls: ['*://*/*'] }, (details, callback) => {
    if (contentBlocker.shouldBlockUrl(details.url)) {
      callback({ cancel: true });
    } else {
      callback({ cancel: false });
    }
  });

  // ─── Media Sniffer ─────────────────────────────────────────────────────────
  session.defaultSession.webRequest.onResponseStarted({ urls: ['*://*/*'] }, (details) => {
    const headers = details.responseHeaders;
    const rawType = (headers['content-type'] || headers['Content-Type'] || '');
    const contentType = Array.isArray(rawType) ? rawType[0] : rawType;
    if (!contentType) return;
    const ct = contentType.toLowerCase();
    
    if (['video/', 'audio/', 'image/', 'application/x-mpegurl', 'application/dash+xml'].some(t => ct.includes(t))) {
      mainWindow.webContents.send('media-detected', { url: details.url, type: ct, timestamp: Date.now() });
    }
    if (details.url.includes('.m3u8')) mainWindow.webContents.send('manifest-detected', { url: details.url, type: 'hls' });
    if (details.url.includes('.mpd')) mainWindow.webContents.send('manifest-detected', { url: details.url, type: 'dash' });
  });

  // ─── Auto-Updater ──────────────────────────────────────────────────────────
  const updateFeedURL = 'https://your-org.github.io/makaw/';
  try { autoUpdater.setFeedURL(updateFeedURL); } catch (_) {}

  autoUpdater.on('checking-for-update', () => {
    mainWindow?.webContents.send('update-status', { status: 'checking' });
  });

  autoUpdater.on('update-available', (info) => {
    mainWindow?.webContents.send('update-status', { status: 'available', version: info.version, releaseDate: info.releaseDate });
  });

  autoUpdater.on('update-not-available', (info) => {
    mainWindow?.webContents.send('update-status', { status: 'up-to-date' });
  });

  autoUpdater.on('download-progress', (progress) => {
    mainWindow?.webContents.send('update-status', { status: 'downloading', percent: progress.percent, bytesPerSecond: progress.bytesPerSecond });
  });

  autoUpdater.on('update-downloaded', (info) => {
    mainWindow?.webContents.send('update-status', { status: 'downloaded', version: info.version });
  });

  autoUpdater.on('error', (err) => {
    mainWindow?.webContents.send('update-status', { status: 'error', message: err.message });
  });

  // Check for updates on startup (with delay)
  setTimeout(() => {
    try { autoUpdater.checkForUpdates(); } catch (_) {}
  }, 5000);
});

// ─── Content Blocker IPC ──────────────────────────────────────────────────────
ipcMain.handle('content-blocker-get-config', () => ({
  enabled: contentBlocker.enabled,
  blockAds: contentBlocker.blockAds,
  blockTrackers: contentBlocker.blockTrackers,
  blockPopups: contentBlocker.blockPopups,
  blockMalware: contentBlocker.blockMalware,
  blockAnnoyances: contentBlocker.blockAnnoyances,
  blockedCount: contentBlocker.blockedCount,
  allowedSites: contentBlocker.allowedSites,
}));

ipcMain.handle('content-blocker-set-config', (event, config) => {
  Object.assign(contentBlocker, config);
});

ipcMain.handle('content-blocker-add-rule', (event, { pattern, action }) => {
  contentBlocker.userRules.push({ pattern, action });
});

ipcMain.handle('content-blocker-remove-rule', (event, index) => {
  contentBlocker.userRules.splice(index, 1);
});

ipcMain.handle('content-blocker-allow-site', (event, domain) => {
  if (!contentBlocker.allowedSites.includes(domain)) {
    contentBlocker.allowedSites.push(domain);
  }
});

ipcMain.handle('content-blocker-disallow-site', (event, domain) => {
  contentBlocker.allowedSites = contentBlocker.allowedSites.filter(s => s !== domain);
});

ipcMain.handle('content-blocker-get-user-rules', () => [...contentBlocker.userRules]);

ipcMain.handle('content-blocker-get-hide-script', () => contentBlocker.getHideScript());

ipcMain.handle('content-blocker-get-popup-blocker-script', () => contentBlocker.getPopupBlockerScript());

// ─── Enhanced Download Manager ────────────────────────────────────────────────

function processDownloadQueue() {
  const running = activeDownloads.size;
  const slots = MAX_PARALLEL_DOWNLOADS - running;
  for (let i = 0; i < slots && downloadQueue.length > 0; i++) {
    const item = downloadQueue.shift();
    executeDownload(item);
  }
}

function executeDownload(item) {
  const downloadsPath = app.getPath('downloads');
  const outputPath = path.join(downloadsPath, item.filename);

  const stmt = db.prepare('INSERT INTO downloads (url, type, status, progress, filepath) VALUES (?, ?, ?, ?, ?)');
  const info = stmt.run(item.url, item.type || 'direct', 'downloading', 0, outputPath);
  item.dbId = info.lastInsertRowid;
  downloadIdMap.set(item.dbId, item.id);
  activeDownloads.set(item.id, item);

  mainWindow.webContents.send('download-progress', {
    id: item.id, dbId: item.dbId, url: item.url, filename: item.filename,
    status: 'downloading', progress: 0, speed: 0,
  });

  const file = fs.createWriteStream(outputPath);
  const client = item.url.startsWith('https') ? https : http;

  const req = client.get(item.url, { headers: item.rangeHeaders || {} }, (res) => {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      const total = parseInt(res.headers['content-length'] || '0', 10);
      let received = 0;
      let lastBytes = 0;
      let lastTime = Date.now();

      res.on('data', (chunk) => {
        if (item.paused) {
          res.destroy();
          file.end();
          const partPath = outputPath + '.part';
          fs.renameSync(outputPath, partPath);
          item.partPath = partPath;
          db.prepare('UPDATE downloads SET status = ? WHERE id = ?').run('paused', item.dbId);
          mainWindow.webContents.send('download-progress', { id: item.id, dbId: item.dbId, status: 'paused' });
          processDownloadQueue();
          return;
        }
        received += chunk.length;
        file.write(chunk);
        const now = Date.now();
        const dt = (now - lastTime) / 1000;
        const speed = dt > 0 ? Math.round((received - lastBytes) / dt) : 0;
        lastBytes = received;
        lastTime = now;
        const progress = total > 0 ? received / total : 0;
        item.received = received;
        item.total = total;
        db.prepare('UPDATE downloads SET progress = ? WHERE id = ?').run(progress * 100, item.dbId);
        mainWindow.webContents.send('download-progress', {
          id: item.id, dbId: item.dbId, progress, received, total, speed, status: 'downloading',
        });
      });

      res.on('end', () => {
        file.end();
        if (!item.paused) {
          item.status = 'completed';
          db.prepare('UPDATE downloads SET status = ?, progress = ? WHERE id = ?').run('completed', 100, item.dbId);
          mainWindow.webContents.send('download-progress', {
            id: item.id, dbId: item.dbId, status: 'completed', progress: 1, filepath: outputPath,
          });
          downloadIdMap.delete(item.dbId);
          activeDownloads.delete(item.id);
          // Clean up any partial file
          const partPath = outputPath + '.part';
          if (fs.existsSync(partPath)) fs.unlinkSync(partPath);
          processDownloadQueue();
        }
      });
    } else {
      file.close();
      fs.unlink(outputPath, () => {});
      db.prepare('UPDATE downloads SET status = ? WHERE id = ?').run('failed', item.dbId);
      mainWindow.webContents.send('download-progress', { id: item.id, dbId: item.dbId, status: 'failed', error: `HTTP ${res.statusCode}` });
      downloadIdMap.delete(item.dbId);
      activeDownloads.delete(item.id);
      processDownloadQueue();
    }
  });

  req.on('error', (err) => {
    file.close();
    fs.unlink(outputPath, () => {});
    db.prepare('UPDATE downloads SET status = ? WHERE id = ?').run('failed', item.dbId);
    mainWindow.webContents.send('download-progress', { id: item.id, dbId: item.dbId, status: 'failed', error: err.message });
    activeDownloads.delete(item.id);
    processDownloadQueue();
  });

  item.req = req;
  item.file = file;
  item.outputPath = outputPath;
}

function mimeToExtension(url) {
  const u = url.toLowerCase();
  if (u.includes('.mp4') || u.includes('video/mp4')) return '.mp4';
  if (u.includes('.webm')) return '.webm';
  if (u.includes('.mkv')) return '.mkv';
  if (u.includes('.mp3')) return '.mp3';
  if (u.includes('.jpg') || u.includes('.jpeg')) return '.jpg';
  if (u.includes('.png')) return '.png';
  if (u.includes('.pdf')) return '.pdf';
  if (u.includes('.zip')) return '.zip';
  return '.bin';
}

function inferFilename(url, type) {
  const urlObj = new URL(url);
  let name = path.basename(urlObj.pathname);
  if (!name || !name.includes('.')) {
    const ext = type === 'hls' ? '.ts' : mimeToExtension(url);
    name = `makaw_${Date.now()}${ext}`;
  }
  return name;
}

ipcMain.handle('start-download', async (event, { url, type, filename }) => {
  const id = Date.now().toString() + Math.random().toString(36).slice(2, 6);
  const item = {
    id, url, type: type || 'direct',
    filename: filename || inferFilename(url, type),
    status: 'queued', paused: false, received: 0, total: 0,
    rangeHeaders: null, req: null, file: null, outputPath: null, partPath: null,
  };

  const stmt = db.prepare('INSERT INTO downloads (url, type, status, progress, filepath) VALUES (?, ?, ?, ?, ?)');
  const info = stmt.run(item.url, item.type, 'queued', 0, '');
  item.dbId = info.lastInsertRowid;
  downloadIdMap.set(item.dbId, item.id);
  downloadIdMap.set(item.id, item.id);

  mainWindow.webContents.send('download-progress', {
    id: item.id, dbId: item.dbId, url: item.url, filename: item.filename, status: 'queued', progress: 0,
  });

  downloadQueue.push(item);
  processDownloadQueue();
  return { id: item.id, dbId: item.dbId };
});

function resolveDownloadId(id) {
  const runtimeId = downloadIdMap.get(id);
  if (runtimeId && activeDownloads.has(runtimeId)) return runtimeId;
  if (activeDownloads.has(id)) return id;
  return null;
}

ipcMain.handle('pause-download', async (event, id) => {
  const rid = resolveDownloadId(id);
  const item = rid ? activeDownloads.get(rid) : null;
  if (item && item.req) {
    item.paused = true;
    item.req.destroy();
    return { success: true };
  }
  const qId = downloadIdMap.get(id) || id;
  const idx = downloadQueue.findIndex(d => d.id === qId);
  if (idx >= 0) {
    downloadQueue.splice(idx, 1);
    const dbId = typeof id === 'number' ? id : (item ? item.dbId : null);
    if (dbId) db.prepare('UPDATE downloads SET status = ? WHERE id = ?').run('paused', dbId);
    return { success: true };
  }
  return { success: false };
});

ipcMain.handle('resume-download', async (event, id) => {
  const rid = resolveDownloadId(id);
  const item = rid ? activeDownloads.get(rid) : null;
  if (item && item.partPath) {
    const partSize = fs.statSync(item.partPath).size;
    item.rangeHeaders = { 'Range': `bytes=${partSize}-` };
    item.paused = false;
    item.received = partSize;
    const outputPath = item.outputPath;
    // Rename .part back to original
    fs.renameSync(item.partPath, outputPath);
    executeDownload(item);
    return { success: true };
  }
  return { success: false };
});

ipcMain.handle('retry-download', async (event, id) => {
  const download = db.prepare('SELECT * FROM downloads WHERE id = ?').get(id);
  if (download) {
    const item = {
      id: Date.now().toString(), url: download.url, type: download.type,
      filename: path.basename(download.filepath) || inferFilename(download.url, download.type),
      status: 'queued', paused: false, received: 0, total: 0,
      rangeHeaders: null, req: null, file: null, outputPath: null, partPath: null,
    };
    const stmt = db.prepare('INSERT INTO downloads (url, type, status, progress, filepath) VALUES (?, ?, ?, ?, ?)');
    const info = stmt.run(item.url, item.type, 'queued', 0, '');
    item.dbId = info.lastInsertRowid;
    downloadIdMap.set(item.dbId, item.id);
    downloadIdMap.set(item.id, item.id);
    mainWindow.webContents.send('download-progress', {
      id: item.id, dbId: item.dbId, url: item.url, filename: item.filename, status: 'queued', progress: 0,
    });
    downloadQueue.push(item);
    processDownloadQueue();
    return { success: true, id: item.id, dbId: item.dbId };
  }
  return { success: false };
});

ipcMain.handle('cancel-download', async (event, id) => {
  const rid = resolveDownloadId(id);
  const item = rid ? activeDownloads.get(rid) : null;
  if (item && item.req) {
    item.req.destroy();
    item.file?.close();
    if (item.outputPath && fs.existsSync(item.outputPath)) fs.unlinkSync(item.outputPath);
    const partPath = item.outputPath + '.part';
    if (fs.existsSync(partPath)) fs.unlinkSync(partPath);
    activeDownloads.delete(rid);
    db.prepare('UPDATE downloads SET status = ? WHERE id = ?').run('cancelled', item.dbId);
    processDownloadQueue();
    return { success: true };
  }
  const qId = downloadIdMap.get(id) || id;
  const qIdx = downloadQueue.findIndex(d => d.id === qId);
  if (qIdx >= 0) {
    const [removed] = downloadQueue.splice(qIdx, 1);
    db.prepare('UPDATE downloads SET status = ? WHERE id = ?').run('cancelled', removed.dbId);
    downloadIdMap.delete(removed.dbId);
    downloadIdMap.delete(removed.id);
    return { success: true };
  }
  return { success: false };
});

ipcMain.handle('get-downloads', async () => {
  return db.prepare('SELECT * FROM downloads ORDER BY created_at DESC LIMIT 100').all();
});

ipcMain.handle('clear-downloads', async () => {
  db.prepare('DELETE FROM downloads WHERE status = "completed" OR status = "cancelled"').run();
});

ipcMain.handle('retry-all-failed', async () => {
  const failed = db.prepare('SELECT * FROM downloads WHERE status = "failed"').all();
  for (const d of failed) {
    const item = {
      id: Date.now().toString() + Math.random().toString(36).slice(2, 6),
      url: d.url, type: d.type,
      filename: path.basename(d.filepath) || inferFilename(d.url, d.type),
      status: 'queued', paused: false, received: 0, total: 0,
      rangeHeaders: null, req: null, file: null, outputPath: null, partPath: null,
    };
    const stmt = db.prepare('INSERT INTO downloads (url, type, status, progress, filepath) VALUES (?, ?, ?, ?, ?)');
    const info = stmt.run(item.url, item.type, 'queued', 0, '');
    item.dbId = info.lastInsertRowid;
    downloadIdMap.set(item.dbId, item.id);
    downloadIdMap.set(item.id, item.id);
    mainWindow.webContents.send('download-progress', {
      id: item.id, dbId: item.dbId, url: item.url, filename: item.filename, status: 'queued', progress: 0,
    });
    downloadQueue.push(item);
  }
  processDownloadQueue();
});

// ─── Auto-Updater IPC ─────────────────────────────────────────────────────────
ipcMain.handle('check-for-updates', async () => {
  try {
    autoUpdater.checkForUpdates();
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('install-update', async () => {
  autoUpdater.quitAndInstall();
});

// ─── HTML Injection & Projects, Snippets, Git, Terminal (unchanged) ───────────

// HTML Injection
ipcMain.handle('inject-html', async (event, htmlString) => {
  const hash_id = crypto.createHash('sha256').update(htmlString).digest('hex').slice(0, 16);
  db.prepare('INSERT OR REPLACE INTO injected_pages (hash_id, html_content) VALUES (?, ?)').run(hash_id, htmlString);
  const base64 = Buffer.from(htmlString).toString('base64');
  return { success: true, hash_id, local_route: `local://${hash_id}/index.html`, data_uri: `data:text/html;charset=utf-8;base64,${base64}` };
});

// Trebedit: Project Management
ipcMain.handle('save-project', async (event, { name, type, content, language }) => {
  const stmt = db.prepare('INSERT INTO projects (name, type, content, language, updated_at) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)');
  const info = stmt.run(name, type, content, language);
  return { id: info.lastInsertRowid };
});

ipcMain.handle('load-project', async (event, id) => {
  return db.prepare('SELECT * FROM projects WHERE id = ?').get(id);
});

ipcMain.handle('list-projects', async () => {
  return db.prepare('SELECT id, name, type, language, updated_at FROM projects ORDER BY updated_at DESC').all();
});

ipcMain.handle('export-project', async (event, { id, format }) => {
  const project = db.prepare('SELECT * FROM projects WHERE id = ?').get(id);
  if (!project) return { success: false };
  
  const { filePath } = await dialog.showSaveDialog({
    defaultPath: `${project.name}.${format === 'vscode' ? 'code-workspace' : 'txt'}`,
    filters: format === 'vscode' ? [{ name: 'VS Code Workspace', extensions: ['code-workspace'] }] : [{ name: 'Text', extensions: ['txt'] }]
  });
  
  if (!filePath) return { success: false };
  
  if (format === 'vscode') {
    const workspace = {
      folders: [{ path: '.' }],
      settings: { "makaw.project": project.name, "makaw.language": project.language }
    };
    fs.writeFileSync(filePath, JSON.stringify(workspace, null, 2));
  } else {
    fs.writeFileSync(filePath, project.content);
  }
  return { success: true, path: filePath };
});

// Snippets
ipcMain.handle('get-snippets', async (event, language) => {
  if (language) return db.prepare("SELECT * FROM snippets WHERE language = ? OR language = 'all'").all(language);
  return db.prepare('SELECT * FROM snippets').all();
});

ipcMain.handle('save-snippet', async (event, snippet) => {
  const stmt = db.prepare('INSERT INTO snippets (name, category, language, code, description) VALUES (?, ?, ?, ?, ?)');
  stmt.run(snippet.name, snippet.category, snippet.language, snippet.code, snippet.description);
  return { success: true };
});

// --- Git Integration ---
const simpleGit = require('simple-git');

ipcMain.handle('git-init', async (event, projectPath) => {
  try {
    const git = simpleGit(projectPath);
    await git.init();
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-status', async (event, projectPath) => {
  try {
    const git = simpleGit(projectPath);
    const status = await git.status();
    return { success: true, status };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-add-commit', async (event, { projectPath, message, files }) => {
  try {
    const git = simpleGit(projectPath);
    await git.add(files || '.');
    const result = await git.commit(message);
    return { success: true, result };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-push', async (event, { projectPath, remote = 'origin', branch = 'main' }) => {
  try {
    const git = simpleGit(projectPath);
    await git.push(remote, branch);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-pull', async (event, { projectPath, remote = 'origin', branch = 'main' }) => {
  try {
    const git = simpleGit(projectPath);
    await git.pull(remote, branch);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-clone', async (event, { url, projectPath }) => {
  try {
    await simpleGit().clone(url, projectPath);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-add-remote', async (event, { projectPath, name, url }) => {
  try {
    const git = simpleGit(projectPath);
    await git.addRemote(name, url);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});
// --- Git Diff & Branching ---
ipcMain.handle('git-diff', async (event, { projectPath, file = null }) => {
  try {
    const git = simpleGit(projectPath);
    const diff = file? await git.diff([file]) : await git.diff();
    return { success: true, diff };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-diff-staged', async (event, projectPath) => {
  try {
    const git = simpleGit(projectPath);
    const diff = await git.diff(['--staged']);
    return { success: true, diff };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-branches', async (event, projectPath) => {
  try {
    const git = simpleGit(projectPath);
    const branches = await git.branchLocal();
    return { success: true, branches };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-checkout', async (event, { projectPath, branch }) => {
  try {
    const git = simpleGit(projectPath);
    await git.checkout(branch);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-create-branch', async (event, { projectPath, branchName }) => {
  try {
    const git = simpleGit(projectPath);
    await git.checkoutLocalBranch(branchName);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-log', async (event, { projectPath, limit = 10 }) => {
  try {
    const git = simpleGit(projectPath);
    const log = await git.log({ maxCount: limit });
    return { success: true, log };
  } catch (err) {
    return { success: false, error: err.message };
  }
});
// --- Advanced Git: Merge, Conflicts, Stash, Tags ---
ipcMain.handle('git-merge', async (event, { projectPath, branch }) => {
  try {
    const git = simpleGit(projectPath);
    const result = await git.mergeFromTo('HEAD', branch);
    return { success: true, result };
  } catch (err) {
    // Merge conflicts throw but we still want the conflicted files
    if (err.git) {
      const status = await simpleGit(projectPath).status();
      return { success: false, conflicts: true, conflicted: status.conflicted, error: err.message };
    }
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-conflicted-files', async (event, projectPath) => {
  try {
    const git = simpleGit(projectPath);
    const status = await git.status();
    return { success: true, files: status.conflicted };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-show-conflict', async (event, { projectPath, file }) => {
  try {
    const fs = require('fs');
    const content = fs.readFileSync(path.join(projectPath, file), 'utf8');
    // Parse conflict markers
    const conflicts = [];
    const lines = content.split('\n');
    let current = null;
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('<<<<<<<')) {
        current = { start: i, ours: [], theirs: [], base: [] };
      } else if (lines[i].startsWith('=======')) {
        current.split = i;
      } else if (lines[i].startsWith('>>>>>>>')) {
        current.end = i;
        conflicts.push(current);
        current = null;
      } else if (current) {
        if (current.split === undefined) current.ours.push(lines[i]);
        else current.theirs.push(lines[i]);
      }
    }
    return { success: true, raw: content, conflicts };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-resolve-conflict', async (event, { projectPath, file, resolution }) => {
  try {
    fs.writeFileSync(path.join(projectPath, file), resolution);
    await simpleGit(projectPath).add(file);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-stash', async (event, { projectPath, message }) => {
  try {
    const git = simpleGit(projectPath);
    await git.stash(['push', '-m', message || 'Makaw stash']);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-stash-pop', async (event, projectPath) => {
  try {
    const git = simpleGit(projectPath);
    await git.stash(['pop']);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-blame', async (event, { projectPath, file }) => {
  try {
    const git = simpleGit(projectPath);
    const blame = await git.raw(['blame', '--line-porcelain', file]);
    return { success: true, blame };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-reset', async (event, { projectPath, mode = 'hard', commit = 'HEAD' }) => {
  try {
    const git = simpleGit(projectPath);
    await git.reset([`--${mode}`, commit]);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-tag', async (event, { projectPath, tagName, message }) => {
  try {
    const git = simpleGit(projectPath);
    if (message) await git.addAnnotatedTag(tagName, message);
    else await git.addTag(tagName);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-fetch', async (event, projectPath) => {
  try {
    const git = simpleGit(projectPath);
    await git.fetch();
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('git-remotes', async (event, projectPath) => {
  try {
    const git = simpleGit(projectPath);
    const remotes = await git.getRemotes(true);
    return { success: true, remotes };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('terminal-create', (event) => {
  const shell = os.platform() === 'win32' ? 'powershell.exe' : 'bash';
  ptyProcess = pty.spawn(shell, [], {
    name: 'xterm-color',
    cols: 80,
    rows: 30,
    cwd: app.getPath('home'),
    env: process.env
  });

  ptyProcess.onData((data) => {
    mainWindow.webContents.send('terminal-incoming', data);
  });

  return { pid: ptyProcess.pid };
});

ipcMain.on('terminal-to-pty', (event, data) => {
  ptyProcess?.write(data);
});

ipcMain.handle('terminal-resize', (event, { cols, rows }) => {
  ptyProcess?.resize(cols, rows);
});

ipcMain.handle('terminal-kill', () => {
  ptyProcess?.kill();
});

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });