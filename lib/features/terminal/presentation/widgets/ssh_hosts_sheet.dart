import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/makaw_toast.dart';
import '../../data/ssh_vault_service.dart';
import '../../domain/terminal_models.dart';

/// Modal bottom sheet for managing encrypted SSH Hosts, in-app Ed25519 key
/// generation, `tmux` persistence, and 1-tap remote shell launch.
class SshHostsSheet extends StatefulWidget {
  final SshVaultService vault;
  final void Function(SshHostProfile host) onConnect;
  final void Function(SshHostProfile host)? onBrowseSftp;

  const SshHostsSheet({
    super.key,
    required this.vault,
    required this.onConnect,
    this.onBrowseSftp,
  });

  @override
  State<SshHostsSheet> createState() => _SshHostsSheetState();
}

class _SshHostsSheetState extends State<SshHostsSheet> {
  List<SshHostProfile> _hosts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final list = await widget.vault.loadHosts();
    if (mounted) {
      setState(() {
        _hosts = list;
        _loading = false;
      });
    }
  }

  Future<void> _openEditor([SshHostProfile? existing]) async {
    final saved = await showModalBottomSheet<SshHostProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SshHostEditorSheet(
        vault: widget.vault,
        existing: existing,
      ),
    );
    if (saved != null) {
      await _refresh();
    }
  }

  Future<void> _deleteHost(SshHostProfile host) async {
    await widget.vault.removeHost(host.id);
    await _refresh();
    if (mounted) {
      MakawToast.info(context, 'Removed SSH host ${host.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.dns_rounded, color: Color(0xFF38BDF8), size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SSH Hosts & Key Vault',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Pure-Dart SSH2 + encrypted key storage · works on Android & Desktop',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Host', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: const Color(0xFF090D16),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_hosts.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.router_outlined, color: Color(0xFF38BDF8), size: 28),
                    SizedBox(height: 8),
                    Text(
                      'No remote servers or workstations saved yet',
                      style: TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Add your VPS, Raspberry Pi, cloud VM, or Desktop PC to code and run tests remotely.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _hosts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final h = _hosts[idx];
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF38BDF8).withOpacity(0.16),
                          child: Icon(
                            h.authMethod == 'key' ? Icons.vpn_key : Icons.terminal,
                            color: const Color(0xFF38BDF8),
                            size: 18,
                          ),
                        ),
                        title: Text(
                          h.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${h.displayTarget} · ${h.authMethod}${h.autoTmux ? ' · tmux:${h.tmuxSession}' : ''}',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: Color(0xFF94A3B8), size: 18),
                              tooltip: 'Edit',
                              onPressed: () => _openEditor(h),
                            ),
                            if (widget.onBrowseSftp != null)
                              IconButton(
                                icon: const Icon(Icons.folder_shared_outlined,
                                    color: Color(0xFF38BDF8), size: 18),
                                tooltip: 'Browse SFTP Files',
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  widget.onBrowseSftp!(h);
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Color(0xFFF87171), size: 18),
                              tooltip: 'Delete',
                              onPressed: () => _deleteHost(h),
                            ),
                            FilledButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.onConnect(h);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                              ),
                              child: const Text('Connect',
                                  style: TextStyle(
                                      fontSize: 11.5, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onConnect(h);
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SshHostEditorSheet extends StatefulWidget {
  final SshVaultService vault;
  final SshHostProfile? existing;

  const _SshHostEditorSheet({required this.vault, this.existing});

  @override
  State<_SshHostEditorSheet> createState() => _SshHostEditorSheetState();
}

class _SshHostEditorSheetState extends State<_SshHostEditorSheet> {
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController(text: 'ubuntu');
  final _pwCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _passphraseCtrl = TextEditingController();
  final _dirCtrl = TextEditingController();
  final _tmuxCtrl = TextEditingController(text: 'makaw');

  String _authMethod = 'password';
  bool _autoTmux = false;
  String? _generatedPublicKey;
  String? _fingerprint;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _hostCtrl.text = e.host;
      _portCtrl.text = '${e.port}';
      _userCtrl.text = e.username;
      _authMethod = e.authMethod;
      _autoTmux = e.autoTmux;
      _tmuxCtrl.text = e.tmuxSession;
      _dirCtrl.text = e.defaultRemoteDir;
      widget.vault.readSecrets(e.id).then((sec) {
        if (!mounted) return;
        setState(() {
          if (sec.password != null) _pwCtrl.text = sec.password!;
          if (sec.privateKeyPem != null) _keyCtrl.text = sec.privateKeyPem!;
          if (sec.passphrase != null) _passphraseCtrl.text = sec.passphrase!;
        });
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _pwCtrl.dispose();
    _keyCtrl.dispose();
    _passphraseCtrl.dispose();
    _dirCtrl.dispose();
    _tmuxCtrl.dispose();
    super.dispose();
  }

  void _generateKey() {
    final user = _userCtrl.text.trim().isEmpty ? 'makaw' : _userCtrl.text.trim();
    final id = SshVaultService.generateEd25519KeyPair(comment: '$user@makaw');
    setState(() {
      _authMethod = 'key';
      _keyCtrl.text = id.privateKeyPem;
      _generatedPublicKey = id.publicKeyOpenSsh;
      _fingerprint = id.sha256Fingerprint;
    });
    MakawToast.success(context, 'Ed25519 keypair generated — copy the public key to authorized_keys');
  }

  Future<void> _save() async {
    final hostText = _hostCtrl.text.trim();
    if (hostText.isEmpty) {
      MakawToast.warning(context, 'Enter a hostname or IP address');
      return;
    }
    setState(() => _saving = true);
    final profile = SshHostProfile(
      id: widget.existing?.id ?? '',
      name: _nameCtrl.text.trim(),
      host: hostText,
      port: int.tryParse(_portCtrl.text.trim()) ?? 22,
      username: _userCtrl.text.trim(),
      authMethod: _authMethod,
      autoTmux: _autoTmux,
      tmuxSession: _tmuxCtrl.text.trim(),
      defaultRemoteDir: _dirCtrl.text.trim(),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    final saved = await widget.vault.saveHost(
      profile,
      password: _pwCtrl.text,
      privateKeyPem: _keyCtrl.text,
      passphrase: _passphraseCtrl.text,
    );
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null ? 'Add SSH Host' : 'Edit SSH Host',
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _field(_nameCtrl, 'Label', hint: 'e.g. Prod VPS / Home Workstation'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _field(_hostCtrl, 'Host / IP', hint: '192.168.1.40'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: _field(_portCtrl, 'Port',
                      keyboardType: TextInputType.number),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field(_userCtrl, 'Username', hint: 'ubuntu')),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(_dirCtrl, 'Start Dir (optional)',
                      hint: '~/projects'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Password'),
                  selected: _authMethod == 'password',
                  onSelected: (_) => setState(() => _authMethod = 'password'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('SSH Key (Ed25519/RSA)'),
                  selected: _authMethod == 'key',
                  onSelected: (_) => setState(() => _authMethod = 'key'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_authMethod == 'password')
              _field(_pwCtrl, 'Password (encrypted in Key Vault)',
                  obscure: true, hint: 'Leave blank to prompt each connect')
            else ...[
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _generateKey,
                    icon: const Icon(Icons.auto_awesome, size: 15),
                    label: const Text('Generate Ed25519 Keypair',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              if (_generatedPublicKey != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090D16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF10B981).withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _fingerprint ?? 'Public Key',
                            style: const TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: _generatedPublicKey!));
                              MakawToast.success(context, 'Public key copied');
                            },
                            icon: const Icon(Icons.copy, size: 14),
                            label: const Text('Copy .pub',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                      Text(
                        _generatedPublicKey!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10.5,
                            fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _field(_keyCtrl, 'Private Key PEM',
                  maxLines: 3, hint: '-----BEGIN OPENSSH PRIVATE KEY-----'),
              const SizedBox(height: 8),
              _field(_passphraseCtrl, 'Key Passphrase (optional)', obscure: true),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autoTmux,
              onChanged: (v) => setState(() => _autoTmux = v),
              title: const Text('tmux Session Survival',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: const Text(
                'Auto-attach tmux session so builds survive cellular/Wi-Fi drops',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
            ),
            if (_autoTmux)
              _field(_tmuxCtrl, 'tmux Session Name', hint: 'makaw'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  foregroundColor: const Color(0xFF090D16),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  _saving ? 'Encrypting & Saving...' : 'Save SSH Host',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    bool obscure = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        isDense: true,
      ),
    );
  }
}
