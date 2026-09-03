import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../browser/data/services/password_service.dart';

class PasswordsPage extends StatefulWidget {
  const PasswordsPage({super.key});

  @override
  State<PasswordsPage> createState() => _PasswordsPageState();
}

class _PasswordsPageState extends State<PasswordsPage> {
  static const _storage = FlutterSecureStorage();
  static const _pinKey = 'makaw_master_pin';

  List<PasswordEntry> _entries = [];
  bool _isLoading = true;
  bool _locked = true;
  bool _showPasswords = false;
  String _query = '';
  final _pinController = TextEditingController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkLock();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkLock() async {
    final pin = await _storage.read(key: _pinKey);
    if (pin == null) {
      // First run: ask to set up a master PIN.
      if (mounted) {
        setState(() => _isLoading = false);
        _showCreatePinDialog();
      }
    } else {
      _locked = true;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCreatePinDialog() async {
    final ctl = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Create a master PIN', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Text(
          'Set a 4-digit PIN to protect saved passwords.',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctl.clear();
              if (ctx.mounted) Navigator.of(ctx).pop();
              setState(() => _locked = false);
              _load();
            },
            child: const Text('Skip', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          TextButton(
            onPressed: () async {
              final pin = ctl.text.trim();
              if (pin.length < 4) {
                _toast('PIN must be at least 4 digits');
                return;
              }
              await _storage.write(key: _pinKey, value: pin);
              ctl.clear();
              if (ctx.mounted) Navigator.of(ctx).pop();
              setState(() => _locked = false);
              await _load();
            },
            child: const Text('Set PIN', style: TextStyle(color: Color(0xFFF472B6))),
          ),
        ],
      ),
    );
  }

  void _showUnlockDialog() {
    final ctl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Enter master PIN', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: '••••', hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          TextButton(
            onPressed: () async {
              final pin = await _storage.read(key: _pinKey);
              if (ctl.text.trim() == pin) {
                if (ctx.mounted) Navigator.of(ctx).pop();
                setState(() => _locked = false);
                await _load();
              } else {
                _toast('Incorrect PIN');
              }
            },
            child: const Text('Unlock', style: TextStyle(color: Color(0xFFF472B6))),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    if (_locked) return;
    setState(() => _isLoading = true);
    var items = await passwordService.getAll();
    final q = _query.trim();
    if (q.isNotEmpty) {
      items = items.where((e) =>
          e.domain.contains(q) || e.username.contains(q)).toList();
    }
    if (mounted) setState(() {
      _entries = items;
      _isLoading = false;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2), backgroundColor: const Color(0xFF334155)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _locked
            ? const Text('Passwords', style: TextStyle(color: Colors.white, fontSize: 17))
            : TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Search passwords',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, color: Colors.white38, size: 22),
                  prefixIconConstraints: BoxConstraints(minWidth: 40),
                ),
                onChanged: (v) {
                  _query = v.trim();
                  _load();
                },
              ),
        actions: [
          if (_locked)
            IconButton(
              icon: const Icon(Icons.lock_open, color: Color(0xFFF472B6)),
              tooltip: 'Unlock',
              onPressed: _showUnlockDialog,
            )
          else ...[
            if (_query.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () {
                  _searchController.clear();
                  _query = '';
                  _load();
                },
              ),
            IconButton(
              icon: Icon(_showPasswords ? Icons.visibility_off : Icons.visibility, color: Colors.white70),
              tooltip: _showPasswords ? 'Hide passwords' : 'Show passwords',
              onPressed: () => setState(() => _showPasswords = !_showPasswords),
            ),
            IconButton(
              icon: const Icon(Icons.add, color: Color(0xFFF472B6)),
              tooltip: 'Add password',
              onPressed: _showAddDialog,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF472B6)))
          : _locked
              ? _buildLockedState()
              : _entries.isEmpty
                  ? _buildEmptyState()
                  : _buildList(),
    );
  }

  Widget _buildLockedState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 72, color: Colors.white24),
          const SizedBox(height: 20),
          const Text('Passwords are locked', style: TextStyle(color: Colors.white70, fontSize: 17)),
          const SizedBox(height: 8),
          const Text('Enter your PIN to view saved passwords',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF472B6)),
            onPressed: _showUnlockDialog,
            icon: const Icon(Icons.lock_open),
            label: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.password, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            _query.isNotEmpty ? 'No results' : 'No saved passwords',
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text('Saved login credentials will appear here',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _entries.length,
      itemBuilder: (_, i) {
        final e = _entries[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF1E293B),
            child: Text(
              e.domain.isNotEmpty ? e.domain[0].toUpperCase() : '?',
              style: const TextStyle(color: Color(0xFFF472B6), fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(e.domain, style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text(
            '${e.username}  •  ${_showPasswords ? e.password : '••••••••'}',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white38, size: 18),
            onPressed: () => _showEntrySheet(e),
          ),
          onTap: () => _showEntrySheet(e),
        );
      },
    );
  }

  void _showAddDialog() {
    final domainCtl = TextEditingController();
    final userCtl = TextEditingController();
    final passCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Add password', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: domainCtl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Domain', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: userCtl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Username', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passCtl,
              style: const TextStyle(color: Colors.white),
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          TextButton(
            onPressed: () async {
              final domain = domainCtl.text.trim();
              final user = userCtl.text.trim();
              final pass = passCtl.text.trim();
              if (domain.isNotEmpty && user.isNotEmpty && pass.isNotEmpty) {
                await passwordService.save('https://$domain', user, pass);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _load();
            },
            child: const Text('Save', style: TextStyle(color: Color(0xFFF472B6))),
          ),
        ],
      ),
    );
  }

  void _showEntrySheet(PasswordEntry e) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(e.domain,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            _actionTile(Icons.content_copy, 'Copy username', () {
              Clipboard.setData(ClipboardData(text: e.username));
              Navigator.of(ctx).pop();
              _toast('Username copied');
            }),
            _actionTile(Icons.lock_outline, 'Copy password', () {
              Clipboard.setData(ClipboardData(text: e.password));
              Navigator.of(ctx).pop();
              _toast('Password copied');
            }),
            _actionTile(Icons.edit_outlined, 'Edit', () {
              Navigator.of(ctx).pop();
              _showEditDialog(e);
            }),
            _actionTile(Icons.delete_outline, 'Delete', () async {
              await passwordService.delete(e.id);
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _load();
            }, color: const Color(0xFFF87171)),
          ],
        ),
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.white70, size: 22),
      title: Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 14)),
      onTap: onTap,
      dense: true,
    );
  }

  void _showEditDialog(PasswordEntry e) {
    final domainCtl = TextEditingController(text: e.domain);
    final userCtl = TextEditingController(text: e.username);
    final passCtl = TextEditingController(text: e.password);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Edit password', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: domainCtl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Domain', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: userCtl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Username', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passCtl,
              style: const TextStyle(color: Colors.white),
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          TextButton(
            onPressed: () async {
              final domain = domainCtl.text.trim();
              final user = userCtl.text.trim();
              final pass = passCtl.text.trim();
              if (domain.isNotEmpty && user.isNotEmpty && pass.isNotEmpty) {
                await passwordService.delete(e.id);
                await passwordService.save('https://$domain', user, pass);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _load();
            },
            child: const Text('Save', style: TextStyle(color: Color(0xFFF472B6))),
          ),
        ],
      ),
    );
  }
}
