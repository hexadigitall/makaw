## Objective
- Complete a working in‑app browser with fullscreen video support, downloads managed in‑app, file chooser working via JS‑Flutter bridge, media sniffer, password manager, terminal, and proper device back‑button handling

## Important Details
- `flutter_inappwebview` 6.1.5 with `InAppWebView` widget, `WebUri()` for URLs, `evaluateJavascript`, `callHandler` for bidirectional JS‑Flutter communication
- File chooser uses `callHandler` + `file_picker` with `withData: true` — JS intercepts `<input type="file">` click, returns base64 bytes to JS, creates `File` via `DataTransfer`, sets `input.files`
- Downloads: `onDownloadStartRequest` + JS interceptor + `shouldOverrideUrlLoading` file‑extension check → `_downloadManager.enqueue(url)` → Dio download with pause/resume/retry
- Fullscreen: `onEnterFullscreen`/`onExitFullscreen` hide URL bar + bottom nav via `_isFullscreen` flag; floating `fullscreen_exit` FAB when fullscreen
- Media Sniffer: `_injectMediaSnifferScript` scans `<video>`, `<audio>`, `<img>` every 3s; sends to `MakawMediaSnifferChannel`
- Pull‑to‑refresh: `PullToRefreshController` on `InAppWebView` (replaced non‑working `RefreshIndicator`)
- Terminal: `TerminalView` with `autofocus: true` handles keyboard input through `Terminal.onOutput` → PTY; toolbar has Ctrl+C, Ctrl+D, Clear buttons
- Permissions: `MICROPHONE` → `Permission.microphone`, `CAMERA` → `Permission.camera` in `onPermissionRequest`
- SSL: `onReceivedServerTrustAuthRequest` → `ServerTrustAuthResponseAction.PROCEED`
- Back button: `PopScope(canPop: false, onPopInvokedWithResult:)` — WebView `goBack()` if browsing, else set `_showHomeScreen = true` (preserves tab), never exits app on back
- `StatefulBuilder` inside `showDialog` must not shadow the dialog builder’s `ctx`
- `MANAGE_EXTERNAL_STORAGE` + `requestLegacyExternalStorage` for full file system access
- Public storage data dir (`/storage/emulated/0/Download/Makaw/`) survives uninstall/reinstall; `makaw_data.json` stores shortcuts, history, theme, download location
- `_exportAppData()` called on shortcut save, theme change; `_importAppData()` on startup
- `open_filex` auto‑opens completed downloads

## Work State
### Completed
- Fullscreen video with chrome hiding + floating exit FAB
- Downloads: JS interceptor (anchor[download], file‑extension clicks, blob URLs, window.open), `shouldOverrideUrlLoading` file‑extension check, `onDownloadStartRequest` → `DownloadManager` with Dio
- Pull‑to‑refresh via `PullToRefreshController`
- File chooser: JS `callHandler` → Flutter `file_picker` → base64 bytes → `File` via `DataTransfer`
- Media Sniffer injected JS on every page load
- Terminal: `autofocus: true`, removed separate TextField, Ctrl+C/D/Clear toolbar
- Shortcut edit dialog fixed: `StatefulBuilder` shadowing fixed, try‑catch around save
- `_reloadCurrentPage()` — uses `getUrl()` + `loadUrl()` instead of bare `reload()` to avoid `net::ERR_FAILED`
- Public Makaw data directory at `/storage/emulated/0/Download/Makaw/` (survives uninstall)
- `_exportAppData()` / `_importAppData()` for settings persistence across reinstalls
- `_requestFileAccess()` method + "Storage Access" drawer item
- Back button: goes to Makaw home when no WebView history left (tab stays alive)
- Footer nav bar height reduced to 40px, icons 18px, padding shrunk
- `open_filex` auto‑opens completed downloads
- APK built at `build\app\outputs\flutter-apk\app-release.apk` (55.2MB)

### Active
- User should test download interception from various sites and back button behavior

### Known Issues
- `net::ERR_FAILED(-1)` on refresh should be fixed by `_reloadCurrentPage` (loadUrl instead of reload)
- Pull‑to‑refresh now uses native Android `PullToRefreshController` instead of Flutter's `RefreshIndicator`

## Relevant Files
- `D:\projects\makaw\lib\main.dart` — all UI, WebView, handlers, terminal, shortcuts, data persistence; ~3438 lines
- `D:\projects\makaw\lib\services\download_manager.dart` — `DownloadManager` with Dio, pause/resume/retry, parallel queue, `onComplete` callback
- `D:\projects\makaw\lib\widgets\downloads_widget.dart` — Download manager UI with progress bars, speed, state indicators
- `D:\projects\makaw\lib\services\password_manager.dart` — encrypted password storage via `flutter_secure_storage`
- `D:\projects\makaw\android\app\src\main\AndroidManifest.xml` — CAMERA, RECORD_AUDIO, MANAGE_EXTERNAL_STORAGE, `requestLegacyExternalStorage`
- `D:\projects\makaw\build\app\outputs\flutter-apk\app-release.apk` — latest release APK (55.2MB)
