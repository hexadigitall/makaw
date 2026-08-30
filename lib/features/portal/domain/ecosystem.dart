import 'package:flutter/material.dart';

/// A tool within an ecosystem.
class EcosystemTool {
  final String view;
  final String label;
  final IconData icon;
  final Color accent;
  const EcosystemTool(this.view, this.label, this.icon, this.accent);
}

/// An ecosystem hub composed of tools.
class Ecosystem {
  final String id;
  final String name;
  final IconData icon;
  final Color accent;
  final List<EcosystemTool> tools;
  const Ecosystem(this.id, this.name, this.icon, this.accent, this.tools);
}

/// The Makaw ecosystem registry.
///
/// Each ecosystem maps to a hub screen; its tools open within the ecosystem.
class Ecosystems {
  static const Ecosystem codeStudio = Ecosystem(
    'code_studio',
    'Code Studio',
    Icons.code_rounded,
    Color(0xFF818CF8),
    [
      EcosystemTool('studio', 'Code Studio (IDE)', Icons.code_rounded, Color(0xFF818CF8)),
      EcosystemTool('terminal', 'Terminal', Icons.terminal_rounded, Color(0xFF22D3EE)),
      EcosystemTool('projects', 'Projects', Icons.folder_rounded, Color(0xFFFBBF24)),
      EcosystemTool('git', 'Git', Icons.account_tree_rounded, Color(0xFFF472B6)),
      EcosystemTool('cloud', 'Cloud', Icons.cloud_rounded, Color(0xFF60A5FA)),
    ],
  );

  static const Ecosystem terminal = Ecosystem(
    'terminal',
    'Terminal',
    Icons.terminal_rounded,
    Color(0xFF22D3EE),
    [
      EcosystemTool('terminal', 'Terminal', Icons.terminal_rounded, Color(0xFF22D3EE)),
    ],
  );

  static const Ecosystem media = Ecosystem(
    'media',
    'Media Hub',
    Icons.video_collection_outlined,
    Color(0xFFF87171),
    [
      EcosystemTool('music', 'Music', Icons.music_note_rounded, Color(0xFFF472B6)),
      EcosystemTool('player', 'Video Player', Icons.play_circle_rounded, Color(0xFFF87171)),
      EcosystemTool('images', 'Gallery', Icons.photo_library_rounded, Color(0xFF38BDF8)),
      EcosystemTool('sniffer', 'Media Sniffer', Icons.wifi_tethering_rounded, Color(0xFF22D3EE)),
      EcosystemTool('lyrics', 'Lyrics', Icons.lyrics_rounded, Color(0xFFF472B6)),
      EcosystemTool('subtitles', 'Subtitles', Icons.subtitles_rounded, Color(0xFFF87171)),
    ],
  );

  static const Ecosystem documents = Ecosystem(
    'documents',
    'Documents',
    Icons.description_rounded,
    Color(0xFFFBBF24),
    [
      EcosystemTool('documents', 'Document Reader', Icons.edit_document, Color(0xFFFBBF24)),
      EcosystemTool('files', 'File Explorer', Icons.folder_open_rounded, Color(0xFF34D399)),
    ],
  );

  static const Ecosystem browser = Ecosystem(
    'browser',
    'Browser Hub',
    Icons.language_rounded,
    Color(0xFF00A7C2),
    [
      EcosystemTool('browser', 'Browser', Icons.language_rounded, Color(0xFF00A7C2)),
      EcosystemTool('history', 'History', Icons.history_rounded, Color(0xFF94A3B8)),
      EcosystemTool('downloads', 'Downloads', Icons.download_rounded, Color(0xFFFB923C)),
      EcosystemTool('bookmarks', 'Bookmarks', Icons.bookmarks_rounded, Color(0xFFFBBF24)),
      EcosystemTool('passwords', 'Passwords', Icons.password_rounded, Color(0xFFF472B6)),
    ],
  );

  static const Ecosystem cloud = Ecosystem(
    'cloud',
    'Cloud',
    Icons.cloud_rounded,
    Color(0xFF60A5FA),
    [
      EcosystemTool('cloud', 'Cloud Sync', Icons.cloud_sync_rounded, Color(0xFF60A5FA)),
    ],
  );

  static const Ecosystem files = Ecosystem(
    'files',
    'Files Hub',
    Icons.folder_open_rounded,
    Color(0xFF34D399),
    [
      EcosystemTool('files', 'File Explorer', Icons.folder_open_rounded, Color(0xFF34D399)),
      EcosystemTool('documents', 'Documents', Icons.edit_document, Color(0xFFFBBF24)),
      EcosystemTool('downloads', 'Downloads', Icons.download_rounded, Color(0xFFFB923C)),
    ],
  );

  static const Ecosystem settings = Ecosystem(
    'settings',
    'Settings',
    Icons.settings_rounded,
    Color(0xFF94A3B8),
    [
      EcosystemTool('settings', 'Settings', Icons.settings_rounded, Color(0xFF94A3B8)),
      EcosystemTool('cloud', 'Cloud Sync', Icons.cloud_sync_rounded, Color(0xFF60A5FA)),
    ],
  );

  static const List<Ecosystem> all = [
    codeStudio,
    terminal,
    media,
    documents,
    browser,
    cloud,
    files,
    settings,
  ];
}
