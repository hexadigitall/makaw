# Makaw — Phases & Tasks Master Plan
**Project:** Makaw (Hybrid Browser, Creative Studio & Media Platform)  
**Standard:** 14 Nov 2026 PRD Specifications (Mobile + Windows Desktop)  
**Status:** In Active Execution  
**Last Updated:** November 20, 2026  

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
- [x] **3.3 Metadata Extraction & "Needs Attention"**
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
  - [x] Full automated unit test suite passing (93/93 tests across Core, Domain, Studio, Documents, and Browser).
  - [x] Unit tests for file exclusion filter, document reader contract, studio terminal, and entity serialization.
- [x] **7.2 Device Testing & CI Checklist**
  - [x] Android CI verification: `build-android.yml` Run ID `44709694251` succeeded (per-ABI split APKs and AAB generated).
  - [x] Windows CI verification: `build-windows.yml` Run ID `44713455869` succeeded (Release EXE and portable ZIP generated).
- [ ] **7.3 Release Packaging & GitHub Tagging**
  - [x] Bump version to `1.0.3+103` in `pubspec.yaml`.
  - [ ] Tag `v1.0.3` to trigger GitHub Actions release pipeline.
  - [ ] Verify APKs, AAB, and Windows release artifacts attached to GitHub Release.
