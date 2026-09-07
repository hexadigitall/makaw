import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/services/device_file_browser.dart';

/// Full-device File Explorer for the Files / Documents ecosystem.
///
/// Starts at a "quick access" home showing common storage roots (Downloads,
/// Documents, Pictures, Music, …) plus the raw device root. Tapping any entry
/// drills into the full directory tree and lists **all** file types (not just
/// documents). Uses Android All-Files-Access (MANAGE_EXTERNAL_STORAGE).
class FoldersPage extends StatefulWidget {
  final void Function(String filePath) openFile;
  const FoldersPage({super.key, required this.openFile});

  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  // Stack of directories we've drilled into. When empty → quick-access home.
  final List<String> _pathStack = [];
  List<DeviceEntry> _entries = [];
  bool _loading = false;
  String? _error;
  bool _permissionGranted = true;

  bool get _isHome => _pathStack.isEmpty;

  String get _currentPath => _isHome ? '/' : _pathStack.last;

  static const _kDark = Color(0xFF0F0F1A);
  static const _kAccent = Color(0xFF818CF8);
  static const _kCard = Color(0xFF1A1A2E);

  @override
  void initState() {
    super.initState();
    _ensurePermission();
  }

  Future<void> _ensurePermission() async {
    final ok = await DeviceFileBrowser.ensureManageStoragePermission();
    if (mounted) setState(() => _permissionGranted = ok);
    if (ok) _load(_currentPath);
  }

  void _go(String path) {
    _pathStack.add(path);
    _load(path);
  }

  void _back() {
    if (_pathStack.isEmpty) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    setState(() => _pathStack.removeLast());
    _load(_currentPath);
  }

  void _load(String path) {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Defer file IO to avoid holding the frame; a short await keeps it smooth.
    Future.microtask(() {
      List<DeviceEntry> entries;
      try {
        entries = DeviceFileBrowser.listDirectory(path);
      } catch (e) {
        if (mounted) setState(() {
          _loading = false;
          _error = 'Cannot read $path';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      appBar: AppBar(
        backgroundColor: _kDark,
        title: Text(
          _isHome ? 'File Explorer' : _displayName(_currentPath),
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _back,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => _load(_currentPath),
          ),
        ],
      ),
      body: _isHome ? _buildHome() : _buildDirectory(),
    );
  }

  // ─── Quick-access home ────────────────────────────────────────────────────

  Widget _buildHome() {
    if (!_permissionGranted) {
      return _buildPermissionBanner();
    }
    final roots = DeviceFileBrowser.quickAccessRoots();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Icon(Icons.storage, color: _kAccent, size: 18),
            const SizedBox(width: 8),
            const Text('Quick access', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        for (final r in roots) _buildRootTile(r),
        const SizedBox(height: 12),
        const Divider(color: Color(0xFF2A2A40)),
        const SizedBox(height: 4),
        const Text('Tip: tap "Device root" to browse the entire filesystem, including system directories.',
            style: TextStyle(color: Color(0xFF666680), fontSize: 12)),
      ],
    );
  }

  Widget _buildPermissionBanner() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_off, size: 56, color: Color(0xFF666680)),
            const SizedBox(height: 16),
            const Text('Full file access required',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Enable "All files access" to browse the whole device.',
                style: TextStyle(color: Color(0xFF666680), fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _ensurePermission,
              style: FilledButton.styleFrom(backgroundColor: _kAccent),
              icon: const Icon(Icons.shield),
              label: const Text('Grant access'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRootTile(QuickAccessRoot r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => _go(r.path),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _rootColor(r.kind).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(_rootIcon(r.kind), color: _rootColor(r.kind), size: 24),
          ),
          title: Text(r.label, style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text(r.path, style: const TextStyle(color: Color(0xFF666680), fontSize: 11), overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFF666680)),
        ),
      ),
    );
  }

  IconData _rootIcon(IconKind k) {
    switch (k) {
      case IconKind.home: return Icons.home;
      case IconKind.download: return Icons.download;
      case IconKind.doc: return Icons.description;
      case IconKind.picture: return Icons.photo;
      case IconKind.music: return Icons.music_note;
      case IconKind.video: return Icons.movie;
      case IconKind.android: return Icons.android;
      case IconKind.root: return Icons.storage;
    }
  }

  Color _rootColor(IconKind k) {
    switch (k) {
      case IconKind.home: return const Color(0xFF38BDF8);
      case IconKind.download: return const Color(0xFFFB923C);
      case IconKind.doc: return const Color(0xFFFBBF24);
      case IconKind.picture: return const Color(0xFF38BDF8);
      case IconKind.music: return const Color(0xFFF472B6);
      case IconKind.video: return const Color(0xFFF87171);
      case IconKind.android: return const Color(0xFF22D3EE);
      case IconKind.root: return const Color(0xFF34D399);
    }
  }

  // ─── Directory listing ────────────────────────────────────────────────────

  Widget _buildDirectory() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error != null) return _buildError(_error!);
    if (_entries.isEmpty) {
      return const Center(child: Text('Folder is empty', style: TextStyle(color: Color(0xFF666680))));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _entries.length,
      itemBuilder: (_, i) => _buildEntry(_entries[i]),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 48),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(color: Color(0xFF666680), fontSize: 13)),
          const SizedBox(height: 8),
          Text('You may need all-files access to read this location.',
              style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _ensurePermission, style: FilledButton.styleFrom(backgroundColor: _kAccent), child: const Text('Grant access')),
        ],
      ),
    );
  }

  Widget _buildEntry(DeviceEntry e) {
    if (e.isDirectory) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: _kCard,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: () => _go(e.path),
            leading: const Icon(Icons.folder, color: Color(0xFF818CF8), size: 24),
            title: Text(e.name, style: const TextStyle(color: Colors.white, fontSize: 14), overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right, color: Color(0xFF666680)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => widget.openFile(e.path),
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: _fileColor(e.ext).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(_fileIcon(e.ext), color: _fileColor(e.ext), size: 20),
          ),
          title: Text(e.name, style: const TextStyle(color: Colors.white, fontSize: 14), overflow: TextOverflow.ellipsis),
          subtitle: Text(e.sizeLabel, style: const TextStyle(color: Color(0xFF666680), fontSize: 11)),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.share, color: Color(0xFF666680), size: 20),
            onSelected: (v) {
              if (v == 'share') Share.shareXFiles([XFile(e.path)]);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share, color: Colors.white70), title: Text('Share', style: TextStyle(color: Colors.white)))),
            ],
          ),
        ),
      ),
    );
  }

  IconData _fileIcon(String ext) {
    const video = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'wmv', '3gp', 'm4v'};
    const audio = {'mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'wma', 'opus'};
    const img = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'};
    const docs = {'pdf', 'epub', 'doc', 'docx', 'odt', 'rtf', 'pages'};
    const code = {'dart', 'js', 'ts', 'py', 'java', 'kt', 'c', 'cpp', 'h', 'go', 'rs', 'json', 'xml', 'yaml', 'yml', 'ini', 'cfg', 'html', 'htm', 'css', 'sh', 'sql'};
    if (video.contains(ext)) return Icons.movie;
    if (audio.contains(ext)) return Icons.music_note;
    if (img.contains(ext)) return Icons.image;
    if (docs.contains(ext)) return Icons.description;
    if (code.contains(ext)) return Icons.code;
    if (ext == 'apk') return Icons.android;
    if (ext == 'zip' || ext == 'rar' || ext == '7z' || ext == 'tar' || ext == 'gz') return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color _fileColor(String ext) {
    const video = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'wmv', '3gp', 'm4v'};
    const audio = {'mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'wma', 'opus'};
    const img = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'};
    const docs = {'pdf', 'epub', 'doc', 'docx', 'odt', 'rtf', 'pages'};
    const code = {'dart', 'js', 'ts', 'py', 'java', 'kt', 'c', 'cpp', 'h', 'go', 'rs', 'json', 'xml', 'yaml', 'yml', 'ini', 'cfg', 'html', 'htm', 'css', 'sh', 'sql'};
    if (video.contains(ext)) return const Color(0xFFF87171);
    if (audio.contains(ext)) return const Color(0xFFF472B6);
    if (img.contains(ext)) return const Color(0xFF38BDF8);
    if (docs.contains(ext)) return const Color(0xFFFBBF24);
    if (code.contains(ext)) return const Color(0xFF22D3EE);
    if (ext == 'apk') return const Color(0xFF34D399);
    if (ext == 'zip' || ext == 'rar' || ext == '7z' || ext == 'tar' || ext == 'gz') return const Color(0xFFFB923C);
    return const Color(0xFF94A3B8);
  }

  String _displayName(String path) {
    if (path == '/' || path == r'\') return 'Device root';
    final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.last : path;
  }
}