import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PasswordEntry {
  final String id;
  final String url;
  final String domain;
  final String username;
  final String password;
  final DateTime createdAt;

  PasswordEntry({
    required this.id,
    required this.url,
    required this.domain,
    required this.username,
    required this.password,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'domain': domain,
    'username': username,
    'password': password,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PasswordEntry.fromJson(Map<String, dynamic> json) => PasswordEntry(
    id: json['id'] as String,
    url: json['url'] as String,
    domain: json['domain'] as String,
    username: json['username'] as String,
    password: json['password'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  PasswordEntry copyWith({
    String? id, String? url, String? domain,
    String? username, String? password, DateTime? createdAt,
  }) => PasswordEntry(
    id: id ?? this.id,
    url: url ?? this.url,
    domain: domain ?? this.domain,
    username: username ?? this.username,
    password: password ?? this.password,
    createdAt: createdAt ?? this.createdAt,
  );
}

class PasswordManager {
  static const _storageKey = 'makaw_passwords';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  List<PasswordEntry> _cache = [];
  bool _loaded = false;

  Future<List<PasswordEntry>> _load() async {
    if (_loaded) return _cache;
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _cache = list.map((e) => PasswordEntry.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    _loaded = true;
    return _cache;
  }

  Future<void> _save() async {
    final raw = jsonEncode(_cache.map((e) => e.toJson()).toList());
    await _storage.write(key: _storageKey, value: raw);
  }

  Future<List<PasswordEntry>> getAll() => _load();

  Future<List<PasswordEntry>> getForUrl(String url) async {
    final entries = await _load();
    final domain = _extractDomain(url);
    return entries.where((e) => e.domain == domain).toList();
  }

  Future<void> save(String url, String username, String password) async {
    final entries = await _load();
    final domain = _extractDomain(url);
    final existing = entries.indexWhere((e) => e.domain == domain && e.username == username);
    final entry = PasswordEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      domain: domain,
      username: username,
      password: password,
      createdAt: DateTime.now(),
    );
    if (existing >= 0) {
      _cache[existing] = entry;
    } else {
      _cache.add(entry);
    }
    await _save();
  }

  Future<void> delete(String id) async {
    await _load();
    _cache.removeWhere((e) => e.id == id);
    await _save();
  }

  Future<void> update(PasswordEntry entry) async {
    await _load();
    final idx = _cache.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      _cache[idx] = entry;
      await _save();
    }
  }

  Future<void> importPassword(String domain, String url, String username, String password) async {
    await _load();
    final existing = _cache.indexWhere((e) => e.domain == domain && e.username == username);
    final entry = PasswordEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      domain: domain,
      username: username,
      password: password,
      createdAt: DateTime.now(),
    );
    if (existing >= 0) {
      _cache[existing] = entry;
    } else {
      _cache.add(entry);
    }
    await _save();
  }

  static String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }
}

final passwordManager = PasswordManager();
