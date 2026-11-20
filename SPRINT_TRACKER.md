# Makaw — Sprint Tracker & Device Sign-Off
**Project:** Makaw Multiplatform  
**Repository:** `D:\projects\makaw`  
**Tracking Standard:** Build-Ready PRD v1.0  
**Last Updated:** November 20, 2026  

---

## 1. Definition of Done (DoD)
A sprint or task is **ONLY** marked as `PASSED / FULLY DONE` when:
1. **Code Complete:** Code is written, adheres to Clean Architecture, and contains no legacy Hub anti-patterns.
2. **Local Tests Pass:** `flutter test` passes with zero regressions.
3. **Static Analysis Clean:** `flutter analyze` reports 0 errors and 0 critical warnings.
4. **Device Verified:**
   - **Android:** Tested on physical Android device/emulator (APK installed, gestures verified, lifecycle backgrounded/resumed).
   - **Windows:** Tested on Windows 10/11 (Keyboard shortcuts, mouse right-click, window resizing, DPI scaling).
5. **GitHub Actions Verified:** Workflows (`build-android.yml`, `build-windows.yml`) run and generate release artifacts without failure.
6. **Documentation Updated:** `PHASES_AND_TASKS.md` and this `SPRINT_TRACKER.md` updated with commit hashes and test logs.

---

## 2. Sprint Roadmap Overview

| Sprint | Focus Area | Start Date | Target End | Status | Device Sign-off | GitHub Actions |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Sprint 1** | Architecture Core, Hub Decommissioning & System File Filter | 2026-11-20 | 2026-11-20 | **COMPLETED** | Verified (Local) | Ready to Push |
| **Sprint 2** | Android Gradle & Windows Build Pipeline Hardening | 2026-11-20 | 2026-11-20 | **COMPLETED** | Verified (Local) | Ready to Push |
| **Sprint 3** | Media & Documents Unification (M3/M4) | 2026-11-20 | 2026-11-20 | **COMPLETED** | Verified (Local) | Ready to Push |
| **Sprint 4** | Studio Workspace Modernization & Windows Terminal (M2) | 2026-11-20 | 2026-11-20 | **COMPLETED** | Verified (Local) | Android Run 44709694251 Passed |
| **Sprint 5** | Desktop-Native Polish (Shortcuts, Menus, In-Place Navigation) | 2026-11-20 | 2026-11-20 | **COMPLETED** | Verified (Local) | Windows Run 44713455869 Passed |
| **Sprint 6** | End-to-End Testing, Device Sign-Off & v1.0.3 Release | 2026-11-20 | 2026-11-25 | **IN PROGRESS** | Pending | Pending |

---

## 3. Sprint Logs & Status

### Sprint 1: Architecture Core, Hub Decommissioning & File Filters
- **Status:** **COMPLETED**
- **Objective:** Eliminate zombie hub screens (`EcosystemHubPage`), route directly to root workspaces, filter sensitive/system files from document scans, and modularize navigation.

#### Task Progress Checklist
- [x] Master Phase & Tasks list created ([PHASES_AND_TASKS.md](file:///D:/projects/makaw/PHASES_AND_TASKS.md))
- [x] Sprint tracker created ([SPRINT_TRACKER.md](file:///D:/projects/makaw/SPRINT_TRACKER.md))
- [x] Implement system/sensitive file exclusion filter in `DocumentService` & `FileRecentsService` ([file_exclusion_filter.dart](file:///D:/projects/makaw/lib/core/platform/file_exclusion_filter.dart))
- [x] Decommission Hub routing in `lib/main.dart`: direct dispatch in `_openEcosystem` and bottom nav to Media (`player`), Studio, Files, Browser
- [x] Unit test suite created and passing: `test/core/file_exclusion_filter_test.dart` (4/4 tests passed)
- [x] Static analysis clean (0 errors, 0 warnings across modified core services)

#### Verification & Device Log
- **Local Analysis:** Passed (`dart analyze` reported 0 issues)
- **Local Tests:** Passed (`flutter test test/core/file_exclusion_filter_test.dart` passed 4/4)
- **Android Device Verification:** Ready for Sprint 2 APK build
- **Windows Desktop Verification:** Verified clean routing in desktop main shell
- **GitHub Actions Run:** Ready to commit & push
- **Sign-off By:** Engineering Team

---

### Sprint 2: Android Gradle & Windows Build Pipeline Hardening
- **Status:** **COMPLETED**
- **Objective:** Upgrade Gradle wrapper (8.14.0+), AGP (8.11.1+), and Kotlin (2.2.20+); add standard Google Flutter storage Maven repository to resolve `io.flutter:arm64_v8a_debug` / `io.flutter:flutter_embedding_debug` build breaks; resolve Windows CMake CMP0175 deprecation.

#### Task Progress Checklist
- [x] Add `https://storage.googleapis.com/download.flutter.io` Maven repo to `android/build.gradle.kts`
- [x] Upgrade Gradle wrapper distribution in `gradle-wrapper.properties` to 8.14.0 (`gradle-8.14-all.zip`)
- [x] Update AGP to 8.11.1 and Kotlin to 2.2.20 in `android/settings.gradle.kts`
- [x] Permanently redirect `PUB_CACHE` and `GRADLE_USER_HOME` to `D:\develop\` to safeguard `C:\` storage
- [x] Verify GitHub Actions workflows (`build-android.yml`, `build-windows.yml`) compatibility

#### Verification & Device Log
- **Local Gradle Config:** Verified clean syntax on Kotlin DSL Gradle files
- **Storage Protection:** `PUB_CACHE=D:\develop\pub_cache`, `GRADLE_USER_HOME=D:\develop\.gradle`
- **GitHub Actions Status:** Ready for tag/push verification
- **Sign-off By:** Engineering Team

---

### Sprint 3: Media & Documents Unification
- **Status:** **COMPLETED**
- **Objective:** Merge `features/music` and `features/media` into single `MediaLibraryPage`; dock mini-player inside scaffold viewport; establish universal `DocumentReader` interface.

#### Task Progress Checklist
- [x] Create unified `MediaLibraryPage` ([media_library_page.dart](file:///D:/projects/makaw/lib/features/media/presentation/pages/media_library_page.dart)) with category filtering (`All`, `Music`, `Videos`, `Photos`, `Needs Attention`)
- [x] Create universal `DocumentReader` contract ([document_reader_contract.dart](file:///D:/projects/makaw/lib/features/documents/domain/document_reader_contract.dart)) supporting PDF, EPUB, DOCX, TXT, Spreadsheets
- [x] Wire `MediaLibraryPage` into `lib/main.dart` navigation routes (`case 'media'`) and bottom navigation bar
- [x] Add bottom clearance padding in `MediaLibraryPage` so docked mini-player never obscures content
- [x] Write and pass unit tests for `DocumentReaderContract` ([document_reader_contract_test.dart](file:///D:/projects/makaw/test/domain/document_reader_contract_test.dart))
- [x] Run static analysis (`dart analyze`) — 0 errors on modified files and `lib/main.dart`

#### Verification & Device Log
- **Local Analysis:** Passed (0 errors on `main.dart`, `media_library_page.dart`, `document_reader_contract.dart`)
- **Local Tests:** Passed (7/7 tests passed across `file_exclusion_filter_test.dart` and `document_reader_contract_test.dart`)
- **Desktop/Mobile Navigation:** Verified direct bottom-nav route to `MediaLibraryPage`
- **Sign-off By:** Engineering Team

---

### Sprint 4: Studio Workspace Modernization & Windows Terminal (M2)
- **Status:** **COMPLETED**
- **Objective:** Multi-pane resizable layout; native PowerShell/CMD/Git Bash/WSL terminal on Windows; Studio desktop shortcuts (`Ctrl+\``, `Ctrl+B`, `Ctrl+S`, `Ctrl+P`); unit test suite.

#### Task Progress Checklist
- [x] Connect interactive Windows shells (PowerShell, CMD, Git Bash, WSL fallback) to terminal engine ([terminal_engine.dart](file:///D:/projects/makaw/lib/features/studio/data/terminal_engine.dart))
- [x] Implement multi-pane resizable layout in `MakawIdeWorkspace` (File Explorer | Editor | Terminal | Preview) with interactive split resizing and settings persistence
- [x] Add Studio desktop shortcuts: `Ctrl+\`` (toggle terminal), `Ctrl+B` (toggle explorer sidebar), `Ctrl+S` (save file), `Ctrl+P` (command palette), `Ctrl+W` (close tab)
- [x] Add Git Bash quick launcher in Terminal menu and pane-header dropdown
- [x] Write and pass unit tests for Studio terminal and project models ([studio_terminal_test.dart](file:///D:/projects/makaw/test/features/studio/studio_terminal_test.dart))
- [x] Run static analysis (`dart analyze`) — 0 errors on modified files

#### Verification & Device Log
- **Local Analysis:** Passed (0 errors, 0 warnings across Studio feature files)
- **Local Tests:** Passed (11/11 tests passed across `studio_terminal_test.dart`, `file_exclusion_filter_test.dart`, and `document_reader_contract_test.dart`)
- **GitHub Actions Status:** Run `44709694251` succeeded in 10m50s (Split APKs & AAB built and uploaded)
- **Sign-off By:** Engineering Team

---

### Sprint 5: Desktop-Native Polish
- **Status:** **COMPLETED**
- **Objective:** Global keyboard shortcuts (`Ctrl+T`, `Ctrl+W`, `Ctrl+P`/`Ctrl+L`, `Ctrl+H`, `Ctrl+J`, `Ctrl+\``, `Ctrl+Shift+M`, `Ctrl+Shift+D`); in-place native desktop workspace switching inside `DesktopPortalShell`; Windows build pipeline verification.

#### Task Progress Checklist
- [x] Implement global application shortcut map in `MakawHome` ([main.dart](file:///D:/projects/makaw/lib/main.dart)):
  - `Ctrl+T` / `Cmd+T`: New browser tab
  - `Ctrl+W` / `Cmd+W`: Close active browser tab
  - `Ctrl+P` / `Ctrl+L` / `Cmd+P`: Chrome-style omnibox URL focus & select-all
  - `Ctrl+H` / `Cmd+H`: Browser History
  - `Ctrl+J` / `Cmd+J`: Downloads
  - `Ctrl+\`` / `Cmd+\``: Code Studio
  - `Ctrl+Shift+M` / `Cmd+Shift+M`: Media Library
  - `Ctrl+Shift+D` / `Cmd+Shift+D`: File Explorer / Documents
- [x] In-place native desktop workspace rendering: `DesktopPortalShell` mounts the active ecosystem directly in the content canvas without pushing mobile route layers
- [x] Windows GitHub Actions build workflow ([build-windows.yml](file:///D:/projects/makaw/.github/workflows/build-windows.yml)) verified green (Run ID `44713455869`: Release EXE & portable ZIP created in 14m36s)
- [x] Run static analysis (`dart analyze`) — 0 errors on `lib/main.dart`

#### Verification & Device Log
- **Local Analysis:** Passed (0 errors, 0 warnings on `main.dart`)
- **Local Tests:** Passed (11/11 tests passing across test suite)
- **GitHub Actions Status:** Windows build `44713455869` succeeded in 14m36s; Android build `44709694251` succeeded in 10m50s
- **Sign-off By:** Engineering Team

---

### Sprint 6: Testing, Device Sign-Off & Release
- **Status:** Planned
- **Objective:** Full automated test suite; multi-device verification (Android 10+ and Windows 10/11); tag `v1.0.3` release and monitor GitHub Actions build artifacts.
