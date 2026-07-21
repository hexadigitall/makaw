const { contextBridge, ipcRenderer, clipboard } = require('electron');

contextBridge.exposeInMainWorld('makaw', {
  // ─── Media Sniffer ──────────────────────────────────────────────────────────
  injectHTML: (htmlString) => ipcRenderer.invoke('inject-html', htmlString),
  onMediaDetected: (cb) => ipcRenderer.on('media-detected', (e, data) => cb(data)),
  onManifestDetected: (cb) => ipcRenderer.on('manifest-detected', (e, data) => cb(data)),

  // ─── Downloads ──────────────────────────────────────────────────────────────
  startDownload: (url, type, filename) => ipcRenderer.invoke('start-download', { url, type, filename }),
  pauseDownload: (id) => ipcRenderer.invoke('pause-download', id),
  resumeDownload: (id) => ipcRenderer.invoke('resume-download', id),
  retryDownload: (id) => ipcRenderer.invoke('retry-download', id),
  cancelDownload: (id) => ipcRenderer.invoke('cancel-download', id),
  getDownloads: () => ipcRenderer.invoke('get-downloads'),
  clearDownloads: () => ipcRenderer.invoke('clear-downloads'),
  retryAllFailed: () => ipcRenderer.invoke('retry-all-failed'),
  onDownloadProgress: (cb) => ipcRenderer.on('download-progress', (e, data) => cb(data)),

  // ─── Content Blocker ────────────────────────────────────────────────────────
  contentBlockerGetConfig: () => ipcRenderer.invoke('content-blocker-get-config'),
  contentBlockerSetConfig: (config) => ipcRenderer.invoke('content-blocker-set-config', config),
  contentBlockerAddRule: (pattern, action) => ipcRenderer.invoke('content-blocker-add-rule', { pattern, action }),
  contentBlockerRemoveRule: (index) => ipcRenderer.invoke('content-blocker-remove-rule', index),
  contentBlockerAllowSite: (domain) => ipcRenderer.invoke('content-blocker-allow-site', domain),
  contentBlockerDisallowSite: (domain) => ipcRenderer.invoke('content-blocker-disallow-site', domain),
  contentBlockerGetUserRules: () => ipcRenderer.invoke('content-blocker-get-user-rules'),
  contentBlockerGetHideScript: () => ipcRenderer.invoke('content-blocker-get-hide-script'),
  contentBlockerGetPopupBlockerScript: () => ipcRenderer.invoke('content-blocker-get-popup-blocker-script'),

  // ─── Auto-Updater ───────────────────────────────────────────────────────────
  checkForUpdates: () => ipcRenderer.invoke('check-for-updates'),
  installUpdate: () => ipcRenderer.invoke('install-update'),
  onUpdateStatus: (cb) => ipcRenderer.on('update-status', (e, data) => cb(data)),

  // ─── Projects & Snippets ────────────────────────────────────────────────────
  saveProject: (project) => ipcRenderer.invoke('save-project', project),
  loadProject: (id) => ipcRenderer.invoke('load-project', id),
  listProjects: () => ipcRenderer.invoke('list-projects'),
  exportProject: (id, format) => ipcRenderer.invoke('export-project', { id, format }),
  getSnippets: (language) => ipcRenderer.invoke('get-snippets', language),
  saveSnippet: (snippet) => ipcRenderer.invoke('save-snippet', snippet),

  // ─── Git ────────────────────────────────────────────────────────────────────
  gitInit: (projectPath) => ipcRenderer.invoke('git-init', projectPath),
  gitStatus: (projectPath) => ipcRenderer.invoke('git-status', projectPath),
  gitAddCommit: (projectPath, message, files) => ipcRenderer.invoke('git-add-commit', { projectPath, message, files }),
  gitPush: (projectPath, remote, branch) => ipcRenderer.invoke('git-push', { projectPath, remote, branch }),
  gitPull: (projectPath, remote, branch) => ipcRenderer.invoke('git-pull', { projectPath, remote, branch }),
  gitClone: (url, projectPath) => ipcRenderer.invoke('git-clone', { url, projectPath }),
  gitAddRemote: (projectPath, name, url) => ipcRenderer.invoke('git-add-remote', { projectPath, name, url }),
  gitDiff: (projectPath, file) => ipcRenderer.invoke('git-diff', { projectPath, file }),
  gitDiffStaged: (projectPath) => ipcRenderer.invoke('git-diff-staged', projectPath),
  gitBranches: (projectPath) => ipcRenderer.invoke('git-branches', projectPath),
  gitCheckout: (projectPath, branch) => ipcRenderer.invoke('git-checkout', { projectPath, branch }),
  gitCreateBranch: (projectPath, branchName) => ipcRenderer.invoke('git-create-branch', { projectPath, branchName }),
  gitLog: (projectPath, limit) => ipcRenderer.invoke('git-log', { projectPath, limit }),
  gitMerge: (projectPath, branch) => ipcRenderer.invoke('git-merge', { projectPath, branch }),
  gitConflictedFiles: (projectPath) => ipcRenderer.invoke('git-conflicted-files', projectPath),
  gitShowConflict: (projectPath, file) => ipcRenderer.invoke('git-show-conflict', { projectPath, file }),
  gitResolveConflict: (projectPath, file, resolution) => ipcRenderer.invoke('git-resolve-conflict', { projectPath, file, resolution }),
  gitStash: (projectPath, message) => ipcRenderer.invoke('git-stash', { projectPath, message }),
  gitStashPop: (projectPath) => ipcRenderer.invoke('git-stash-pop', projectPath),
  gitBlame: (projectPath, file) => ipcRenderer.invoke('git-blame', { projectPath, file }),
  gitReset: (projectPath, mode, commit) => ipcRenderer.invoke('git-reset', { projectPath, mode, commit }),
  gitTag: (projectPath, tagName, message) => ipcRenderer.invoke('git-tag', { projectPath, tagName, message }),
  gitFetch: (projectPath) => ipcRenderer.invoke('git-fetch', projectPath),
  gitRemotes: (projectPath) => ipcRenderer.invoke('git-remotes', projectPath),

  // ─── Terminal ───────────────────────────────────────────────────────────────
  terminalCreate: () => ipcRenderer.invoke('terminal-create'),
  terminalWrite: (data) => ipcRenderer.send('terminal-to-pty', data),
  terminalResize: (cols, rows) => ipcRenderer.invoke('terminal-resize', { cols, rows }),
  onTerminalData: (cb) => ipcRenderer.on('terminal-incoming', (e, data) => cb(data)),
  terminalKill: () => ipcRenderer.invoke('terminal-kill'),

  // ─── Theme ──────────────────────────────────────────────────────────────────
  setThemeSource: (source) => ipcRenderer.invoke('set-theme-source', source),

  // ─── Clipboard & Paste ──────────────────────────────────────────────────────
  onMenuSmartPaste: (cb) => ipcRenderer.on('menu-smart-paste', () => cb()),
  onGlobalPaste: (cb) => ipcRenderer.on('global-paste', (e, text) => cb(text)),
  onWslPasteTrigger: (cb) => ipcRenderer.on('wsl-paste-trigger', () => cb()),
  getClipboardText: () => ipcRenderer.invoke('get-clipboard-text'),
  wslClipboardCopy: (text) => ipcRenderer.invoke('wsl-clipboard-copy', text),
  wslClipboardPaste: () => ipcRenderer.invoke('wsl-clipboard-paste'),

  // ─── Path & File ────────────────────────────────────────────────────────────
  resolvePath: (key) => ipcRenderer.invoke('resolve-path', key),
  openFileDialog: () => ipcRenderer.invoke('open-file-dialog'),
  openFolderDialog: () => ipcRenderer.invoke('open-folder-dialog'),
  readFile: (filePath) => ipcRenderer.invoke('read-file', filePath),
  writeFile: (filePath, content) => ipcRenderer.invoke('write-file', { path: filePath, content }),
  listFolder: (folderPath) => ipcRenderer.invoke('list-folder', folderPath),
  createFile: (folder, name) => ipcRenderer.invoke('create-file', { folder, name }),
  createFolder: (parent, name) => ipcRenderer.invoke('create-folder', { parent, name }),

  // ─── Clipboard ──────────────────────────────────────────────────────────────
  clipboardCopy: (text) => {
    clipboard.writeText(text);
    try { clipboard.writeText(text, 'selection'); } catch (_) {}
  },
  clipboardPaste: () => {
    const text = clipboard.readText();
    if (!text) { try { return clipboard.readText('selection'); } catch (_) {} }
    return text;
  },
});
