import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/platform/platform_paths.dart';
import '../../../../core/storage/settings_service.dart';

/// App-wide Settings hub.
///
/// Reachable from the home launcher and the browser ecosystem. Unlike the
/// browser-only settings dialog, this is a standalone top-level tool covering
/// the whole app: theme, downloads (location incl. root/system paths), storage
/// & file access, and data management.
class SettingsPage extends StatefulWidget {
  final String themeMode;
  final ValueChanged<String> onThemeChanged;
  final void Function(String path)? onDownloadLocationChanged;
  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    this.onDownloadLocationChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _kDark = Color(0xFF0F172A);
  static const _kElev = Color(0xFF1E293B);
  static const _kAccent = Color(0xFF38BDF8);
  static const _kMuted = Color(0xFF94A3B8);

  String _downloadLocation = '';
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _loadDownloadLocation();
    _loadPermission();
  }

  Future<void> _loadDownloadLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final loc = prefs.getString('download_location') ?? '';
    if (mounted) setState(() => _downloadLocation = loc);
  }

  Future<void> _loadPermission() async {
    bool ok = true;
    if (Platform.isAndroid) {
      try {
        ok = await Permission.manageExternalStorage.isGranted;
      } catch (_) {
        ok = false;
      }
    }
    if (mounted) setState(() => _permissionGranted = ok);
  }

  Future<void> _saveDownloadLocation(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('download_location', path);
    if (mounted) setState(() => _downloadLocation = path);
    widget.onDownloadLocationChanged?.call(path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      appBar: AppBar(
        backgroundColor: _kElev,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('General'),
          _buildCard([
            _tile(
              icon: Icons.palette,
              title: 'Appearance',
              subtitle: _themeLabel(widget.themeMode),
              onTap: _showThemeDialog,
            ),
          ]),
          const SizedBox(height: 20),

          _sectionTitle('Downloads'),
          _buildCard([
            _tile(
              icon: Icons.folder,
              title: 'Download location',
              subtitle: _downloadLocation.isNotEmpty ? _downloadLocation : 'MakawDownloads (default)',
              onTap: _showDownloadLocationDialog,
            ),
          ]),
          const SizedBox(height: 20),

          _sectionTitle('Storage & File Access'),
          _buildCard([
            _tile(
              icon: Icons.shield,
              title: 'All files access',
              subtitle: _permissionGranted ? 'Granted' : 'Required to browse the whole device',
              trailing: Switch(
                value: _permissionGranted,
                activeColor: _kAccent,
                onChanged: (_) => _togglePermission(),
              ),
              onTap: _togglePermission,
            ),
          ]),
          const SizedBox(height: 20),

          _sectionTitle('Data'),
          _buildCard([
            _tile(icon: Icons.backup, title: 'Raw settings', subtitle: 'Manage stored key/value settings', onTap: _showRawSettings),
          ]),
          const SizedBox(height: 28),
          const Center(
            child: Text('Makaw · App preferences',
                style: TextStyle(color: Color(0xFF475569), fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String s) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(s, style: const TextStyle(color: _kAccent, fontSize: 13, fontWeight: FontWeight.w600)),
  );

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _kElev,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(children: children),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: _kMuted, size: 22),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Color(0xFF475569)),
      onTap: onTap,
    );
  }

  String _themeLabel(String mode) {
    switch (mode) {
      case 'light': return 'Light';
      case 'system': return 'System default';
      default: return 'Dark';
    }
  }

  void _showThemeDialog() {
    final options = [
      ('dark', 'Dark', Icons.dark_mode),
      ('light', 'Light', Icons.light_mode),
      ('system', 'System', Icons.brightness_auto),
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kElev,
        title: const Text('Appearance', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((o) {
            return RadioListTile<String>(
              value: o.$1,
              groupValue: widget.themeMode,
              activeColor: _kAccent,
              onChanged: (v) {
                if (v != null) widget.onThemeChanged(v);
                Navigator.of(ctx).pop();
              },
              title: Row(children: [
                Icon(o.$3, color: Colors.white70, size: 20),
                const SizedBox(width: 10),
                Text(o.$2, style: const TextStyle(color: Colors.white)),
              ]),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showDownloadLocationDialog() {
    final ctl = TextEditingController(text: _downloadLocation);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kElev,
        title: const Text('Download location', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Folder path',
                labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                hintText: PlatformPaths.defaultDownloadsHint().isEmpty ? '/storage/emulated/0/Download/Makaw' : PlatformPaths.defaultDownloadsHint(),
                hintStyle: const TextStyle(color: Color(0xFF475569)),
                border: const OutlineInputBorder(),
                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tip: enter any path including a system/root location (e.g. /sdcard/Makaw).',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose download folder');
              if (dir != null && dir.isNotEmpty && ctx.mounted) {
                ctl.text = dir;
              }
            },
            child: const Text('Browse…', style: TextStyle(color: _kAccent)),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          TextButton(
            onPressed: () async {
              final path = ctl.text.trim();
              if (path.isNotEmpty && ctx.mounted) {
                try {
                  await Directory(path).create(recursive: true);
                } catch (_) {}
                await _saveDownloadLocation(path);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Save', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      if (mounted) setState(() => _permissionGranted = status.isGranted);
    }
  }

  void _showRawSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _RawSettingsView()),
    );
  }
}

// ─── Raw key/value settings (power users) ──────────────────────────────────

class _RawSettingsView extends StatefulWidget {
  const _RawSettingsView();
  @override
  State<_RawSettingsView> createState() => _RawSettingsViewState();
}

class _RawSettingsViewState extends State<_RawSettingsView> {
  Map<String, String> _settings = {};
  bool _isLoading = true;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    SettingsService.changes.listen((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await SettingsService.all();
    if (mounted) setState(() {
      _settings = all;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim();
    final entries = _settings.entries
        .where((e) => q.isEmpty || e.key.contains(q) || e.value.contains(q))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Search settings',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, color: Colors.white38, size: 22),
            prefixIconConstraints: BoxConstraints(minWidth: 40),
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () {
                _searchController.clear();
                setState(() => _query = '');
              },
            ),
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF94A3B8)),
            tooltip: 'Add setting',
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF94A3B8)))
          : entries.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return ListTile(
                      leading: const Icon(Icons.settings, color: Color(0xFF94A3B8)),
                      title: Text(e.key, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: Text(
                        _truncate(e.value),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFF87171)),
                        onPressed: () async {
                          await SettingsService.remove(e.key);
                          await _load();
                        },
                      ),
                      onTap: () => _showEditDialog(e.key, e.value),
                    );
                  },
                ),
    );
  }

  String _truncate(String s) => s.length > 120 ? '${s.substring(0, 120)}…' : s;

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.settings_outlined, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            _query.isNotEmpty ? 'No results' : 'No settings yet',
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text('Settings are stored locally so apps can share them',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }

  void _showAddDialog() {
    final keyCtl = TextEditingController();
    final valCtl = TextEditingController();
    var type = 'string';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Add setting', style: TextStyle(color: Colors.white, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyCtl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Key', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: valCtl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Value', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: type,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Type', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
                items: const ['string', 'bool', 'int', 'double', 'list']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setDlg(() => type = v ?? 'string'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
            TextButton(
              onPressed: () async {
                final key = keyCtl.text.trim();
                final val = valCtl.text.trim();
                if (key.isNotEmpty) {
                  await _writeTyped(type, key, val);
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _load();
              },
              child: const Text('Save', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(String key, String value) {
    final valCtl = TextEditingController(text: value);
    var type = _inferType(key, value);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(key, style: const TextStyle(color: Colors.white, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: valCtl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Value', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: type,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Type', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
                items: const ['string', 'bool', 'int', 'double', 'list']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setDlg(() => type = v ?? 'string'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
            TextButton(
              onPressed: () async {
                await _writeTyped(type, key, valCtl.text.trim());
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _load();
              },
              child: const Text('Save', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
          ],
        ),
      ),
    );
  }

  String _inferType(String key, String value) {
    if (value == 'true' || value == 'false') return 'bool';
    if (int.tryParse(value) != null) return 'int';
    if (double.tryParse(value) != null) return 'double';
    if (value.startsWith('[') && value.endsWith(']')) return 'list';
    return 'string';
  }

  Future<void> _writeTyped(String type, String key, String val) async {
    switch (type) {
      case 'bool':
        await SettingsService.setBool(key, val == 'true' || val == '1');
      case 'int':
        await SettingsService.setInt(key, int.tryParse(val) ?? 0);
      case 'double':
        await SettingsService.setDouble(key, double.tryParse(val) ?? 0);
      case 'list':
        await SettingsService.setList(key, val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList());
      default:
        await SettingsService.setString(key, val);
    }
  }
}