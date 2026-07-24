# Makaw

A full-featured hybrid browser and creative studio for Android.

## Download

Get the latest release from [GitHub Releases](https://github.com/hexadigitall/makaw/releases).

- **Universal APK** — works on all Android 7+ devices
- **arm64 APK** — smaller, optimized for most modern phones

The app includes built-in update checking — you'll be prompted when a new version is available.

## Features

### Browser
- Chrome-grade tab system with recent tabs, tab tray, and session restore
- Ad / tracker / popup / malware blocking (EasyList + AdGuard filter lists)
- Anti-fingerprinting stealth mode (spoofed UA, WebGL, canvas, time zone, plugins)
- Google consent auto-dismiss (SOCS cookie pre-seeding, shield auto-click)
- Desktop site toggle
- Full history system with omnibox suggestion engine
- Bookmark manager
- Password manager with encryption

### Media
- Built-in video player with gesture controls (brightness, volume, seek, mute)
- Built-in music player with queue, shuffle, loop, sleep timer
- LRC lyrics display for music
- Screenshot / screen capture from video player
- Media session integration (notification controls, lock screen)

### Documents
- PDF viewer (render, reorder, export, merge, split)
- DOCX / ODT / RTF document viewer with inline rendering
- EPUB reader

### Developer Tools
- Code studio with syntax highlighting
- Terminal emulator
- Snippets manager
- Git integration

### Other
- Download manager with progress tracking
- QR / barcode scanner
- Cloud sync (Firebase)
- Dark / light theme
- Auto-update from GitHub releases

## Tech Stack

- **Flutter** (Dart) — UI framework
- **flutter_inappwebview** — Chromium-based web rendering
- **just_audio** — audio playback
- **video_player** — video playback
- **pdfrx** — PDF rendering
- **Firebase** — cloud sync, authentication
- **Kotlin** — native Android services (media session, volume/brightness control)

## Requirements

- Android 7.0 (API 24) or higher
- Internet connection for browsing and cloud features

## License

Developed by [Hexadigitall](https://github.com/hexadigitall).
