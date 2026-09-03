import 'package:flutter/material.dart';
import '../../../../core/storage/settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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
