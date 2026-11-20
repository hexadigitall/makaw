# Architecture & PRD Specification Rules

- **Five Core Systems:** Home | Browser | Media | Documents | Studio.
- **Forbidden Patterns:**
  - Do not introduce intermediate "Hub" screens or duplicate navigation tiles.
  - Do not stretch mobile cards to fill desktop space; use 3-pane layouts and tables.
  - Do not position floating mini-players where they obscure bottom navigation or content; dock them into the viewport.
  - Do not duplicate databases; use the single unified `makaw.db` schema.
- **Persistence:**
  - Progress (video watch positions, reading pages, open tabs, active editor files) must be autosaved and resumed on next launch.
- **Clean Architecture:**
  - Presentation -> Application -> Domain <- Data.
  - Domain models must never import `flutter/material.dart` or UI dependencies.
