# Makaw — Phases & Tasks Master Plan
**Project:** Makaw (Hybrid Browser, Creative Studio & Media Platform)  
**Standard:** 14 Nov 2026 PRD Specifications (Mobile + Windows Desktop)  
**Status:** In Active Execution  
**Last Updated:** November 26, 2026  

---

## Architecture Principles (Non-Negotiable)
1. **One App, Five Systems:** Home | Browser | Media | Documents | Studio.
2. **No Hub Screens:** Zero intermediate hub screens, zero duplicate tiles, single back-stack.
3. **Clean Architecture:** Domain (Entities/Contracts) <- Application (Use Cases) <- Presentation (Mobile/Desktop Shells) & Data (Adapters).
4. **Desktop is Native, Not Stretched Mobile:** Menu bar, 3 panes (Sidebar, Main, Inspector), resizable splitters, keyboard-first, right-click context menus.
5. **Autosave & Persistence:** Progress, watch positions, reading states, open tabs saved across app restarts.

---

## Phase Breakdown & Work Packages

### Phase 1: Architecture Core & Hub Decommissioning (Foundations)
- [ ] **1.1 Hub Infrastructure Eradication**
  - [ ] Remove `_HubRouteObserver` from `lib/main.dart`.
  - [ ] Delete `lib/features/portal/presentation/pages/ecosystem_hub_page.dart`.
  - [ ] Refactor `lib/features/portal/domain/ecosystem.dart` into system routing enums.
  - [ ] Ensure all 5 bottom navigation tabs point directly to root workspaces:
    - `home` -> `MakawHomePortalPage`
    - `media` -> `MediaLibraryPage`
    - `browser` -> `BrowserActivePage` / `BrowserNewTabView`
    - `files` / `documents` -> `DocumentsLibraryPage`
    - `studio` -> `MakawIdeWorkspace`
- [ ] **1.2 Database Unification & Schema Alignment**
  - [ ] Unify `makaw.db` and `makaw_mgr.db` into a single `makaw.db` SQLite schema.
  - [ ] Standardize migrations to versioned migrations (v1 -> v5).
  - [ ] Implement tables for: `files`, `playlists`, `document_state`, `browser_tabs`, `bookmarks`, `history`, `code_projects`.
- [x] **1.3 Sensitive & System File Filtering**
  - [x] Update `DocumentService` and `FileRecentsService` to exclude system files (`desktop.ini`, `.DS_Store`, `Thumbs.db`).
  - [x] Add privacy filters excluding credential/password exports (e.g. `*password*.csv`).
  - [x] Implement comprehensive unit tests in `test/core/file_exclusion_filter_test.dart`.
- [ ] **1.4 Monolith Modularization (`lib/main.dart`)**
  - [ ] Extract browser controller and tab state out of `_MakawHomeState`.
  - [ ] Extract media player lifecycle and notification bindings.
  - [ ] Extract dialog helpers and route builders into feature presentation modules.

---

### Phase 2: Build Pipeline & GitHub Actions Stability
- [x] **2.1 Android Build Fixes (`run_android_err.txt`)**
  - [x] Add standard Google Flutter storage Maven repository to resolve `io.flutter:arm64_v8a_debug` / `io.flutter:flutter_embedding_debug`.
  - [x] Upgrade Gradle wrapper to 8.14.0 (`gradle-8.14-all.zip`).
  - [x] Upgrade Android Gradle Plugin (AGP) to 8.11.1 in `android/settings.gradle.kts`.
  - [x] Update Kotlin version to 2.2.20 in `android/settings.gradle.kts`.
  - [x] Safeguard machine storage by redirecting `PUB_CACHE` and `GRADLE_USER_HOME` to `D:\develop\`.
  - [ ] Audit dependencies applying legacy Kotlin Gradle Plugin (`ffmpeg_kit_flutter_new`, `flutter_tts`, `mobile_scanner`, `package_info_plus`).
- [ ] **2.2 Windows Desktop Build Stabilization (`run_err.txt`)**
  - [ ] Address CMake CMP0175 deprecation in `flutter_inappwebview_windows`.
  - [ ] Update Firebase C++ SDK CMake minimum version configuration.
  - [ ] Validate MSIX packaging script with `dart run msix:create`.
- [ ] **2.3 GitHub Actions Workflow Hardening**
  - [x] Verify `.github/workflows/build-android.yml` runs cleanly on JDK 17 with caching (Run ID 44709694251: Split APKs & AAB succeeded in 10m50s).
  - [x] Verify `.github/workflows/build-windows.yml` outputs portable zip and release artifacts (Run ID 44713455869: Windows Release EXE & ZIP succeeded in 14m36s).
  - [ ] Enable workflow run triggers on PR and main push for continuous validation.

---

### Phase 3: Media System Unification (PRD Milestone M3)
- [x] **3.1 Unified Media Library**
  - [x] Consolidate `features/music` and `features/media` into a single `MediaLibraryPage` ([media_library_page.dart](file:///D:/projects/makaw/lib/features/media/presentation/pages/media_library_page.dart)).
  - [x] Implement filter tabs: `All` | `Music` | `Video` | `Photos`.
  - [x] Wire `MediaLibraryPage` into bottom navigation bar and view router in `lib/main.dart`.
- [x] **3.2 Player System & Docked Mini-Player**
  - [x] Ensure bottom clearance on `MediaLibraryPage` so docked mini-player never covers content.
  - [x] Implement 1-tap playback from library into full-screen video/music players.
- [x] **3.3 Metadata & Artwork Extraction**
  - [x] Native Kotlin `MediaMetadataRetriever` extraction (`embeddedPicture` and `getFrameAtTime`) via MethodChannel `com.hexadigitall.makaw/metadata`.
  - [x] Cached `MediaThumbnailService` and `MediaArtworkWidget` with automatic fallback.
  - [x] Render real album artwork, video thumbnails, and optimized photo cards across library and player pages.
  - [x] "Needs Attention" filter tab surfacing tracks missing proper artist or title tags.

---

### Phase 4: Documents System & Universal Reader Contract (PRD Milestone M4)
- [x] **4.1 Universal Reader Contract**
  - [x] Create universal reader contract and state model ([document_reader_contract.dart](file:///D:/projects/makaw/lib/features/documents/domain/document_reader_contract.dart)) supporting PDF, EPUB, DOCX, TXT, Sheet.
  - [x] Reading position progress (currentPage, totalPages, scrollProgress), theme (Dark/Light/Sepia), font size, and bookmarks.
  - [x] Unit test suite created and passing: `test/domain/document_reader_contract_test.dart` (3/3 tests passed).
- [ ] **4.2 Documents Library UI**
  - [ ] Grid and Table view modes with sort by Name, Date, Size, Category.
  - [ ] Reading progress indicators on document cards.

---

### Phase 5: Studio Workspace Modernization (PRD Milestone M2)
- [x] **5.1 Unified Desktop/Mobile Studio Workspace**
  - [x] Multi-pane resizable layout on Desktop (File tree | Editor | Terminal | Preview) with interactive split drag and settings persistence.
  - [x] Collapsible drawer and bottom tab switching on Mobile.
  - [x] Monaco / `flutter_code_editor` configuration with auto-saving and dirty indicator.
  - [x] Desktop keyboard shortcuts: `Ctrl+\`` (toggle terminal), `Ctrl+B` (toggle explorer sidebar), `Ctrl+S` (save file), `Ctrl+P` (command palette), `Ctrl+W` (close tab).
- [x] **5.2 Native Terminal Integration**
  - [x] Windows: Spawn interactive PowerShell / CMD / Git Bash session via PTY with `findGitBash()` discovery and `wsl.exe` fallback.
  - [x] Android: Integrate `flutter_pty` with fallback SSH client.
  - [x] Unit test suite created and passing: `test/features/studio/studio_terminal_test.dart`.
- [ ] **5.3 Git Integration**
  - [ ] Visual Git status panel: staged, unstaged, untracked files.
  - [ ] Branch switcher and quick commit UI.

---

### Phase 6: Desktop (Windows) Native Experience
- [x] **6.1 Desktop Shell & Workspace Management**
  - [x] 3-pane responsive desktop shell: Collapsible Sidebar + Main Content + Docked Mini-Player (in-place workspace switching).
  - [x] In-place native rendering inside `DesktopPortalShell` (zero route pushes when switching workspaces).
  - [ ] Window position/geometry persistence across app sessions.
- [x] **6.2 Keyboard Shortcuts & Navigation**
  - [x] Global shortcut map in `MakawHome`:
    - `Ctrl+P` / `Ctrl+L` / `Cmd+P`: Universal Omnibox Quick Open
    - `Ctrl+T` / `Cmd+T`: New Browser Tab
    - `Ctrl+W` / `Cmd+W`: Close Current Browser Tab
    - `Ctrl+\`` / `Cmd+\``: Toggle Code Studio
    - `Ctrl+H` / `Cmd+H`: Browser History
    - `Ctrl+J` / `Cmd+J`: Downloads
    - `Ctrl+Shift+M` / `Cmd+Shift+M`: Media Library
    - `Ctrl+Shift+D` / `Cmd+Shift+D`: File Explorer / Documents
  - [ ] Right-click context menus for files, browser tabs, and editor text.
- [ ] **6.3 Windows OS Integrations**
  - [ ] Windows System Tray with quick controls (Play/Pause, Next, New Tab).
  - [ ] Media Keys hardware listener.
  - [ ] Windows Jump List tasks (New Tab, New Code File, Continue Media).

---

### Phase 7: Verification, Device Testing & Release (PRD Milestone M7)
- [x] **7.1 Automated Test Suite**
  - [x] Full automated unit test suite passing (93/93 tests across Core, Domain, Studio, Documents, and Browser; plus Sprint 7 media sorting, markdown export & AI session suites passing).
  - [x] Unit tests for file exclusion filter, document reader contract, studio terminal, media natural sort/format badges/markdown exports, and entity serialization.
- [x] **7.2 Device Testing & CI Checklist**
  - [x] Android CI verification: `build-android.yml` Run ID `44709694251` and Run ID `45526057854` succeeded (per-ABI split APKs and AAB generated).
  - [x] Windows CI verification: `build-windows.yml` Run ID `44713455869` succeeded (Release EXE and portable ZIP generated).
- [ ] **7.3 Release Packaging & GitHub Tagging**
  - [x] Bump version to `1.0.3+103` in `pubspec.yaml`.
  - [ ] Tag `v1.0.3` to trigger GitHub Actions release pipeline.
  - [ ] Verify APKs, AAB, and Windows release artifacts attached to GitHub Release.

---

### Phase 8: Media Experience, Home Hygiene, AI Rich Text & Music UI Overhaul (Sprint 7)
- [x] **8.1 Direct Video Tool Access & Playback Wake Lock**
  - [x] Prominent Video Tool entry card, AppBar action, and section button inside `MediaLibraryPage`.
  - [x] Android `FLAG_KEEP_SCREEN_ON` MethodChannel (`setKeepScreenOn`) keeping screen awake during active video playback.
- [x] **8.2 Natural Alphabetical Sorting, Filtering & Deduplication**
  - [x] Chunked natural sort (`0-9` then `A-Z`) with `NEW` badge retention and dud/partial-download filtering.
  - [x] Music deduplication preserving distinct format variants with clear `[FLAC]`, `[WAV]`, `[AAC]`, `[MP3]` badges.
  - [x] Live download completion auto-refresh hooks and pull-to-refresh across Video, Music, and Media Library.
- [x] **8.3 Home Recent Deduplication & AI Rich Formatting**
  - [x] Deduplicate Home `Recent` items to latest instance while preserving full Browser History.
  - [x] Native AI markdown rendering plus `.md`, `.txt`, `.html`, `.doc`, and `.json` formatted exports.
- [x] **8.4 Music Tool Aesthetic Redesign**
  - [x] Live animated spectrum visualizer (`MusicVisualizerBars`), floating glass mini-player with bottom progress bar, Studio header card, pill capsule tabs, and thematic gradient cards.

---

### Phase 9: AI Context/PDF, File Explorer Archives, Lyrics Studio & Player Settings (Sprint 8)
- [x] **9.1 AI Assistant Upgrades**
  - [x] Preserve proven `GenerativeModel` streaming with `gemini-3.8-flash` / `3.5-flash` / `3.5-flash-lite` failover and keep-alive HTTP client.
  - [x] Add browser-page HTTP reading, repository file inlining, binary PDF/image attachments, and **Open in Makaw** actions on exports & snippets.
  - [x] Add pure-Dart multipage PDF export with sanitized ASCII-safe rendering ([ai_pdf_exporter.dart](file:///D:/projects/makaw/lib/features/ai/data/services/ai_pdf_exporter.dart)).
- [x] **9.2 File Explorer & Archive Engine**
  - [x] Add isolate-based recursive search with category filters, natural sorting, and `FileExclusionFilter` enforcement.
  - [x] Add multi-select, create folder, rename, permanent delete, share, and properties actions.
  - [x] Add ZIP/TAR.GZ creation and ZIP/TAR/GZ/BZ2/XZ/RAR inspection/extraction with background isolates ([archive_service.dart](file:///D:/projects/makaw/lib/features/documents/data/services/archive_service.dart)).
  - [x] Harden archive extraction with `p.isWithin` destination checks, Windows `tar.exe` listing validation, and sanitized archive output names.
- [x] **9.3 Lyrics Studio**
  - [x] Add universal LRC storage/resolution across sidecar files, `Download/MakawLyrics`, SQLite cache, LRCLIB, and lyrics.ovh.
  - [x] Add karaoke synced lyrics view with auto-scroll, tap-to-seek, timing offset, and fullscreen mode.
  - [x] Add live tap-to-stamp Lyrics Creator Studio with clipboard/file import and `.lrc`/sidecar/SQLite export.
- [x] **9.4 Music & Video Player Settings**
  - [x] Persist music sort/buffer/skip/crossfade/speed/lyrics/EQ settings and wire native Android equalizer/bass boost.
  - [x] Persist video background play, night mode, mirror, loop, shuffle, skip interval, aspect ratio, and decoder preference.
  - [x] Add A-B repeat, sleep timer, playlist auto-advance, smoother scrubbing, and live Home player/video cards.
  - [x] Remove redundant mobile bottom footer from Makaw Home so the home canvas runs edge-to-edge with full vertical height for cards & Apps.
  - [x] Unify `MusicQueueSheet` across Makaw Music and Home Music Widget, wire Music footer Settings to `_openMusicSettings`, and suppress floating FAB while Home queue modals are open.
- [x] **9.5 Documents, Downloads & Verification**
  - [x] Render Word-HTML `.doc` bodies cleanly, add Markdown raw/source toggle, and route more code/subtitle extensions to `TextViewerPage`.
  - [x] Add styled download start/complete/failed notifications with Open, folder, and Downloads actions.
  - [x] Add Sprint 8 regression tests for LRC, archives, path traversal, PDF, and Word-HTML `.doc` ([sprint8_upgrades_test.dart](file:///D:/projects/makaw/test/features/media/sprint8_upgrades_test.dart)).
  - [x] Local verification: `flutter test --no-pub` **135/135 passed**; `flutter analyze --no-pub` **0 errors, 0 warnings**.
- [x] **9.6 Sprint 8 Sign-Off**
  - [x] Commit/push Sprint 8 (`cc82d69`) and verify Android GitHub Actions Run `45930971191` (`10m48s`).
  - [x] Install fresh Sprint 8 APK (`app-arm64-v8a-release.apk`) on TECNO CG8h (`H854CG8012345678`, PID `21302`) and Redmi 14C (`JF9HQ8XOT4LVYPKV`, PID `5578`).
  - [ ] Verify Windows desktop UI build and right-click menus on the fresh commit.

---

### Phase 10: Documents Workspace Overhaul, Video Player UX & Global Multi-Select (Sprint 9)
- [x] **10.1 Sprint 8.1 Navigation & Resume Fixes**
  - [x] Direct file opening & reading/scroll resume from Home Continue/Recent across PDF, TXT/MD, DOCX/RTF, HTML, Spreadsheets, and Music.
  - [x] Natural step-by-step tool Back navigation from Home-launched files (`Viewer -> Owning Tool -> Makaw Home`), plus full ancestor folder stack & archive scroll-to-highlight in `FoldersPage`.
- [x] **10.2 Documents Format Registry, SQLite State & Thumbnails (Phases A–B)**
  - [x] Pure-Dart `DocumentFormatRegistry` mapping ~145 document extensions into 7 Semantic Families and 4 Engine Tiers with `%PDF-` / ZIP magic-byte sniffing ([document_format_registry.dart](file:///D:/projects/makaw/lib/features/documents/domain/document_format_registry.dart)).
  - [x] Expand `DocumentService` indexer across all 7 families + custom folders, and unify SQLite `document_state` + `document_collections` in `MakawManagerDb` v2 ([document_state_service.dart](file:///D:/projects/makaw/lib/features/documents/data/services/document_state_service.dart), [makaw_manager_db.dart](file:///D:/projects/makaw/lib/core/storage/makaw_manager_db.dart)).
  - [x] Async cover & page-1 thumbnail extractor (`DocumentThumbnailService`) for EPUB, CBZ/CBT, Office ZIP, and Apple QuickLook packages.
  - [x] Redesigned `DocumentWidget` library with Continue Reading carousel, 7 family tabs, dynamic extension chips, Grid/List toggle, sort controls, PDF Merge/Organize tools, and Windows Desktop 3-pane workspace ([document_page.dart](file:///D:/projects/makaw/lib/features/documents/presentation/pages/document_page.dart)).
- [x] **10.3 Specialized Viewers (Phases C–D)**
  - [x] Native Comic/Manga Archive Reader (`ComicViewerPage`) with LTR, Manga RTL, and Webtoon vertical strip modes.
  - [x] Interactive Slide Deck Viewer (`SlideViewerPage`) for PPTX/ODP/FODP/KEY with slide filmstrip & speaker notes.
  - [x] Mail/Calendar/Contact PIM Viewer (`PimViewerPage`) for EML/MBOX/ICS/VCF/MSG and Vector/CAD Viewer (`VectorCadViewerPage`) for SVG/DXF/XPS/VSDX/ODG/AI.
  - [x] Upgraded multi-sheet `SpreadsheetViewerPage` (XLSX/XLSM/ODS/CSV/TSV/DIF/SLK/GNUMERIC), MHTML/FB2/ENEX/ABW support in `DocumentToHtml` & `HtmlViewerPage`, and Screenplay `.fountain`/`.fdx` + Reader Themes in `TextViewerPage`.
- [x] **10.4 Video Player Redesign, Auto-Hide Start Over & Global Multi-Select**
  - [x] Redesign `DirectVideoPlayer` overlay layout, dimensions/aspect ratio geometry, playlist sheet, centered `-10s / Play / +10s` transport, and deterministic 4-second auto-dismissing `"Resumed from MM:SS · Start Over"` pill ([video_player_page.dart](file:///D:/projects/makaw/lib/features/media/presentation/pages/video_player_page.dart)).
  - [x] Implement consistent hold-to-select + tap-to-add multi-select & batch action bars across `VideoPlayerWidget`, `MediaLibraryPage`, `DocumentWidget`, and `ImageViewerWidget`.
  - [x] **10.5 Sprint 9 Sign-Off:** Commit/push `1f9bbaa` & `d6f6c2c` (`_openEcosystem('documents')` routing fix), Android CI Run `45947892328` (`8m34s`), and install `app-arm64-v8a-release.apk` on TECNO CG8h (`H854CG8012345678`, `PID 7124`) & Redmi 14C (`JF9HQ8XOT4LVYPKV`, `PID 15944`).
  - [x] **10.6 Sprint 10 Viewer Hardening, EPUB Overhaul, PDF Progress & AI Markdown Polish:**
    - [x] Pure-Dart crash-proof EPUB engine (`parseEpubBytes`, EPUB 2/3 TOC) & distraction-free Reader UI (`Serif/Sans/Mono`, 4 themes, search, bookmarks, scroll tracking).
    - [x] Pure-Dart OLE2 BIFF8 `.xls` parser, `workbook.xml.rels` `.xlsx` resolver, `namespace: '*'` XML matching (`XLSX/ODS/PPTX/ODP/FB2/ODT`), CSV auto-delimiter/BOM, and OLE2 `.doc` text extraction.
    - [x] EPS/PS PostScript vector/bitmap interpreter, XPS/OXPS `FixedPage` SVG converter, and PDF continuous bottom progress scrubber.
    - [x] Portrait Documents header overflow fix (`360px`), `AiMarkdownView` table/heading/export markdown sanitization, and **150/150** local tests passing (`b4b5d40`, CI Run `45965341822`, installed on TECNO `PID 25851` & Redmi `PID 16005`).
  - [x] **10.7 Sprint 11 Toasts, Video Subtitles, Step-by-Step Home Back Nav, Physical Book EPUB & Listen Upgrades:**
    - [x] `MakawToast` floating obsidian toast overlay (`core/ui/makaw_toast.dart`) + `SnackBarThemeData`.
    - [x] Always-visible multi-format subtitles (`.srt`/`.vtt`/`.ass`/`.ssa`/`.sub`), gzip auto-decompression, subfolder discovery, and live sync offset sheet in `DirectVideoPlayer`.
    - [x] Full step-by-step Back chain (`DirectVideoPlayer -> VideoPlayerWidget -> MediaLibrary -> Makaw Home`) across Home Continue, Recent, and Live Video Card launchers.
    - [x] Physical book EPUB page-flip swipe, `resolveEpubChapterLink` internal chapter link fix, 4-color highlights/notes, inline Meaning & Pronounce dock, bookmark ribbon, Warmth filter, non-blocking chunked Read Aloud / Listen overlay across Document/Text/Slide/PIM/PDF viewers, portrait header consolidation, **157/157** tests passing (`2ba7296`, CI Run `45977148583` `9m15s`, installed on TECNO `PID 4585` & Redmi `PID 25724`).
  - [x] **10.8 Sprint 12 Makaw Terminal 2.0 (Phase 1–3) & Cross-Viewer In-Reader Video/Web Link Browser:**
    - [x] Singleton `TerminalRuntimeManager` + rich `TerminalSessionsStore` (`cwd`, `shellId`, `hostId`, `isPinned`, appearance prefs) so switching tabs/routes never kills live shells.
    - [x] Multi-shell discovery (`pwsh`, `powershell`, `cmd`, `Git Bash`, `WSL Ubuntu`, `zsh`, `bash`, `fish`) + Android `makaw-sh` hybrid built-in POSIX/archive/curl/git/ssh REPL (`MakawHybridShell`).
    - [x] Cross-platform pure-Dart `dartssh2` SSH transport, `FlutterSecureStorage` Host Vault + pure-Dart Ed25519 keygen, Studio SSH unification, 2-row sticky soft-keys/trackpad, 6 themes, scrollback search & wide split panes.
    - [x] Shared in-reader video/web link browser (`MakawExternalLinks` / `MakawExtractedLinksBar`) replacing EPUB external-link blocking and wired across EPUB, PDF, Document, HTML/MHT, Slides, PIM Mail/Calendar, Vector/SVG & Markdown viewers; fixed Redmi/Android wrapped-line Backspace duplication, Tab-completion wrapping, IME stabilizer, & Appearance sheet layout; completed **Phase 2 SFTP Explorer & Remote File Editor** across Terminal & Studio (**173/173** tests passing; `e1bd865`, CI Run `45990382417` `12m20s`).
  - [x] **10.9 Sprint 13 Makaw Terminal 2.0 Full Completion (Phases 4–6):**
    - [x] **Phase 4 Developer Productivity & AI/Toolchain Hub:** Auto-detected `pubspec.yaml`/`package.json`/`pyproject.toml`/`Cargo.toml`/`go.mod`/`Makefile` Runbook bar, stack-trace & URL link extractor (`TerminalLinkDetector`), encrypted AI CLI Vault (`Gemini CLI`, `Claude Code`, `Codex`, `Aider`, `Ollama`) with secret masking + Error Doctor, and `ToolchainManager` + Git Repo Cloner.
    - [x] **Phase 5 Workstation Companion & Continuum Sync:** LAN HTTP + WebSocket Desktop Companion Host strictly guarded by `FileExclusionFilter` & Bearer pairing tokens, remote Desktop folder browser/editor + live Desktop WebSocket shell from Mobile, and `MakawContinuumSync` LAN/Firestore snapshot handoff.
    - [x] **Phase 6 Verification:** **180/180** tests passing (`terminal_phase4_5_6_test.dart` live Companion/Continuum/Security verification).
  - [ ] Future enhancements: Native binary PPT/MSG OLE2 streams & SQLite FTS5 document full-text search.
