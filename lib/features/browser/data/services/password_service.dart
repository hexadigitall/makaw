import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PasswordEntry {
  final String id;
  final String url;
  final String domain;
  final String username;
  final String password;
  final DateTime createdAt;
  final DateTime updatedAt;

  PasswordEntry({
    required this.id,
    required this.url,
    required this.domain,
    required this.username,
    required this.password,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'url': url, 'domain': domain, 'username': username,
    'password': password, 'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory PasswordEntry.fromJson(Map<String, dynamic> json) => PasswordEntry(
    id: json['id'] as String,
    url: json['url'] as String,
    domain: json['domain'] as String,
    username: json['username'] as String,
    password: json['password'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

class PasswordService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final List<PasswordEntry> _cache = [];
  bool _loaded = false;

  static const _keyPrefix = 'makaw_pass_';

  Future<List<PasswordEntry>> getAll() async {
    if (!_loaded) await _loadAll();
    return List.unmodifiable(_cache);
  }

  Future<List<PasswordEntry>> getForUrl(String url) async {
    if (!_loaded) await _loadAll();
    final domain = _extractDomain(url);
    return _cache.where((e) => e.domain == domain || e.url == url).toList();
  }

  Future<void> save(String url, String username, String password) async {
    if (!_loaded) await _loadAll();
    final now = DateTime.now();
    final domain = _extractDomain(url);
    final existing = _cache.where((e) => e.domain == domain && e.username == username).toList();
    if (existing.isNotEmpty) {
      final entry = existing.first;
      _cache.remove(entry);
      _cache.add(PasswordEntry(
        id: entry.id, url: url, domain: domain,
        username: username, password: password,
        createdAt: entry.createdAt, updatedAt: now,
      ));
    } else {
      _cache.add(PasswordEntry(
        id: now.millisecondsSinceEpoch.toString(),
        url: url, domain: domain,
        username: username, password: password,
        createdAt: now, updatedAt: now,
      ));
    }
    await _persist();
  }

  Future<void> importPassword(String domain, String url, String username, String password) async {
    if (!_loaded) await _loadAll();
    final now = DateTime.now();
    _cache.add(PasswordEntry(
      id: now.millisecondsSinceEpoch.toString(),
      url: url, domain: domain,
      username: username, password: password,
      createdAt: now, updatedAt: now,
    ));
    await _persist();
  }

  Future<void> delete(String id) async {
    if (!_loaded) await _loadAll();
    _cache.removeWhere((e) => e.id == id);
    await _persist();
  }

  Future<void> _loadAll() async {
    _cache.clear();
    final allKeys = await _storage.readAll();
    for (final entry in allKeys.entries) {
      if (entry.key.startsWith(_keyPrefix)) {
        try {
          final json = jsonDecode(entry.value) as Map<String, dynamic>;
          _cache.add(PasswordEntry.fromJson(json));
        } catch (_) {}
      }
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    // Clear old entries
    final allKeys = await _storage.readAll();
    for (final key in allKeys.keys) {
      if (key.startsWith(_keyPrefix)) {
        await _storage.delete(key: key);
      }
    }
    // Write all current entries
    for (final entry in _cache) {
      await _storage.write(key: '$_keyPrefix${entry.id}', value: jsonEncode(entry.toJson()));
    }
  }

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }
}

final passwordService = PasswordService();
