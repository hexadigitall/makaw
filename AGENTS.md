# Makaw Project Agent Instructions (`AGENTS.md`)
**Project:** Makaw (Hybrid Browser, Creative Studio & Media Platform)  
**Workspace Root:** `D:\projects\makaw`  
**Governing PRD:** Build-Ready PRD v1.0 (Nov 14, 2026)  

---

## 1. Storage & Machine Constraints (CRITICAL)
- **Primary Disk:** Drive `D:\` MUST be used for all operations, caches, and artifacts.
- **Avoid Drive `C:\`:** Drive `C:\` has low storage capacity. **NEVER** write caches, build outputs, or temp files to `C:\`.
- **Package & Build Caches:**
  - `PUB_CACHE` must always point to `D:\develop\pub_cache`.
  - `GRADLE_USER_HOME` must always point to `D:\develop\.gradle`.
- **Terminal Execution:** When running `flutter test` or `flutter analyze`, use `--no-pub` where applicable to avoid redundant network re-fetching.

---

## 2. Architecture & Design Principles (Non-Negotiable)

### A. One App, Five Systems
Makaw consists strictly of five core systems. Never create or resurrect intermediate Hub launcher screens:
1. **Home**: Dashboard showing real **Continue** and **Recent** activity, global search, and quick actions.
2. **Browser**: Direct session restore / New Tab Page, Omnibox, tabs, native streaming AI assistant (`ai_chat_page.dart`), ad blocker.
3. **Media**: Single unified **Media Library** (Music | Video | Photos) with docked Mini-Player and full-screen players.
4. **Documents**: Universal **Document Reader** contract for PDF, EPUB, DOCX, TXT, and Spreadsheets.
5. **Studio**: Unified IDE workspace with Editor, native Terminal (PowerShell/CMD on Windows), and Git integration.

### B. Desktop is Native, Not Stretched Mobile
- **Desktop Layout:** Sidebar + Main Content + Inspector (3 panes), resizable splitters, and top menu bar.
- **Keyboard-First:** Mandatory global shortcuts: `Ctrl+P` (Quick Open), `Ctrl+T` (New Tab), `Ctrl+W` (Close Tab), `Ctrl+\`` (Toggle Terminal), `Ctrl+S` (Save).
- **Mouse Complete:** Full mouse right-click context menus across files, tabs, and code editor.
- **Window State:** Window dimensions, position, and maximize state must persist across restarts.

### C. Clean Architecture
- `Presentation`: UI widgets and platform shells (Mobile / Desktop).
- `Application`: Use cases and business orchestrations.
- `Domain`: Pure entities and repository contracts (Zero Flutter UI dependencies).
- `Data`: SQLite (`makaw.db`), indexer, tags, network adapters.

### D. Security & Privacy
- **File Exclusion:** Always route file scanning and recent history through `FileExclusionFilter` to exclude OS metadata (`desktop.ini`, `thumbs.db`, `.DS_Store`) and credentials (`*password*.csv`, `.env`, `.pem`, `.key`).

---

## 3. Sprint & Task Tracking
- Track overall roadmap and work packages in [PHASES_AND_TASKS.md](file:///D:/projects/makaw/PHASES_AND_TASKS.md).
- Track active sprint status, Definition of Done, test verification, and device sign-offs in [SPRINT_TRACKER.md](file:///D:/projects/makaw/SPRINT_TRACKER.md).
- When a task or sprint is finished, update both tracking documents immediately.
