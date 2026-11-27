import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/platform/conditional_pty.dart';
import '../../../core/platform/file_exclusion_filter.dart';
import 'continuum_sync_service.dart';
import 'shell_discovery.dart';

/// Saved pairing credential for a Makaw Desktop Workstation Companion host.
class CompanionPairing {
  final String name;
  final String host;
  final int port;
  final String token;
  final String rootDir;

  const CompanionPairing({
    required this.name,
    required this.host,
    required this.port,
    required this.token,
    this.rootDir = '',
  });

  String get baseUrl => 'http://$host:$port';
  String get wsUrl => 'ws://$host:$port/v1/shell';

  String toPairingUri() => Uri(
        scheme: 'makaw-pair',
        host: host,
        port: port,
        queryParameters: {
          'token': token,
          if (name.isNotEmpty) 'name': name,
          if (rootDir.isNotEmpty) 'root': rootDir,
        },
      ).toString();

  static CompanionPairing? parsePairingUri(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return null;
    final uri = Uri.tryParse(clean);
    if (uri == null || uri.scheme != 'makaw-pair' || uri.host.isEmpty) {
      return null;
    }
    final tok = uri.queryParameters['token'] ?? '';
    if (tok.isEmpty) return null;
    return CompanionPairing(
      name: uri.queryParameters['name'] ?? uri.host,
      host: uri.host,
      port: uri.hasPort ? uri.port : 47791,
      token: tok,
      rootDir: uri.queryParameters['root'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'token': token,
        'rootDir': rootDir,
      };

  factory CompanionPairing.fromJson(Map<String, dynamic> j) => CompanionPairing(
        name: (j['name'] as String?) ?? '',
        host: (j['host'] as String?) ?? '',
        port: (j['port'] as num?)?.toInt() ?? 47791,
        token: (j['token'] as String?) ?? '',
        rootDir: (j['rootDir'] as String?) ?? '',
      );
}

/// Embedded HTTP + WebSocket Companion Server run on Makaw Desktop (or test
/// peers) sharing a strictly sandboxed local root directory guarded by
/// [FileExclusionFilter] + Bearer pairing token authentication.
class WorkstationCompanionHost {
  final String rootDir;
  final String token;
  HttpServer? _server;

  WorkstationCompanionHost({
    required this.rootDir,
    String? token,
  }) : token = token ?? _generateToken();

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;

  static String _generateToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<int> start({int preferredPort = 47791}) async {
    if (_server != null) return _server!.port;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort);
    } catch (_) {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server!.listen(_handleRequest);
    return _server!.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Resolves a candidate relative or absolute path strictly inside [rootDir].
  String? resolveSafePath(String requested) {
    final normRoot = p.normalize(Directory(rootDir).absolute.path);
    final raw = requested.trim().isEmpty ? '.' : requested.trim();
    final joined = p.isAbsolute(raw) ? raw : p.join(normRoot, raw);
    final normTarget = p.normalize(File(joined).absolute.path);
    if (normTarget != normRoot && !p.isWithin(normRoot, normTarget)) {
      return null;
    }
    if (normTarget != normRoot && FileExclusionFilter.shouldExclude(normTarget)) {
      return null;
    }
    return normTarget;
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      // Handle CORS/headers cleanly
      if (req.uri.path == '/v1/ping') {
        await _sendJson(req, 200, {
          'ok': true,
          'hostname': Platform.localHostname,
          'os': Platform.operatingSystem,
          'rootDir': rootDir,
        });
        return;
      }

      final auth = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
      final qsToken = req.uri.queryParameters['token'] ?? '';
      final bearer = auth.startsWith('Bearer ') ? auth.substring(7).trim() : '';
      if (bearer != token && qsToken != token) {
        await _sendJson(req, 401, {'error': 'Unauthorized'});
        return;
      }

      if (req.uri.path == '/v1/shell' &&
          WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        _serveWebSocketShell(ws);
        return;
      }

      if (req.uri.path == '/v1/fs/list') {
        final rel = req.uri.queryParameters['path'] ?? '.';
        final safe = resolveSafePath(rel);
        if (safe == null || !Directory(safe).existsSync()) {
          await _sendJson(req, 403, {'error': 'Forbidden or missing path'});
          return;
        }
        final entries = <Map<String, dynamic>>[];
        for (final e in Directory(safe).listSync()) {
          if (FileExclusionFilter.shouldExclude(e.path)) continue;
          final stat = e.statSync();
          entries.add({
            'name': p.basename(e.path),
            'path': p.relative(e.path, from: rootDir).replaceAll(r'\', '/'),
            'isDir': e is Directory,
            'size': stat.size,
          });
        }
        entries.sort((a, b) {
          final ad = a['isDir'] as bool;
          final bd = b['isDir'] as bool;
          if (ad != bd) return ad ? -1 : 1;
          return (a['name'] as String)
              .toLowerCase()
              .compareTo((b['name'] as String).toLowerCase());
        });
        await _sendJson(req, 200, {'path': safe, 'entries': entries});
        return;
      }

      if (req.uri.path == '/v1/fs/read') {
        final rel = req.uri.queryParameters['path'] ?? '';
        final safe = resolveSafePath(rel);
        if (safe == null || !File(safe).existsSync()) {
          await _sendJson(req, 404, {'error': 'Forbidden or file not found'});
          return;
        }
        final bytes = await File(safe).readAsBytes();
        await _sendJson(req, 200, {
          'path': rel,
          'content': utf8.decode(bytes, allowMalformed: true),
        });
        return;
      }

      if (req.uri.path == '/v1/fs/write' && req.method == 'POST') {
        final body = jsonDecode(await utf8.decoder.bind(req).join())
            as Map<String, dynamic>;
        final safe = resolveSafePath((body['path'] as String?) ?? '');
        if (safe == null) {
          await _sendJson(req, 403, {'error': 'Forbidden target path'});
          return;
        }
        await File(safe).parent.create(recursive: true);
        await File(safe).writeAsString((body['content'] as String?) ?? '');
        await _sendJson(req, 200, {'ok': true});
        return;
      }

      if (req.uri.path == '/v1/continuum') {
        final store = MakawContinuumSync();
        if (req.method == 'POST') {
          final body = jsonDecode(await utf8.decoder.bind(req).join())
              as Map<String, dynamic>;
          await store.saveLocalSnapshot(ContinuumSnapshot.fromJson(body));
          await _sendJson(req, 200, {'ok': true});
          return;
        }
        final snap = await store.loadLocalSnapshot();
        await _sendJson(req, 200, snap?.toJson() ?? {});
        return;
      }

      await _sendJson(req, 404, {'error': 'Not found'});
    } catch (e) {
      try {
        await _sendJson(req, 500, {'error': '$e'});
      } catch (_) {}
    }
  }

  void _serveWebSocketShell(WebSocket ws) {
    Pty? pty;
    try {
      final shells = Platform.isWindows
          ? (ShellDiscovery.findPwsh() ?? 'powershell.exe')
          : (Platform.environment['SHELL'] ?? '/bin/sh');
      pty = Pty.start(
        shells,
        arguments: Platform.isWindows ? const ['-NoLogo'] : const ['-i'],
        environment: {'TERM': 'xterm-256color'},
        workingDirectory: rootDir,
      );
      pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((chunk) {
        if (ws.readyState == WebSocket.open) {
          ws.add(chunk);
        }
      });
      pty.exitCode.then((_) => ws.close());
    } catch (e) {
      ws.add('\r\n[Workstation PTY unavailable: $e]\r\n');
    }

    ws.listen(
      (msg) {
        if (msg is String) {
          if (msg.startsWith('{"resize":')) {
            try {
              final j = jsonDecode(msg) as Map<String, dynamic>;
              final rows = (j['rows'] as num?)?.toInt() ?? 24;
              final cols = (j['cols'] as num?)?.toInt() ?? 80;
              pty?.resize(rows, cols);
            } catch (_) {}
            return;
          }
          pty?.write(utf8.encode(msg));
        }
      },
      onDone: () => pty?.kill(),
      onError: (_) => pty?.kill(),
    );
  }

  Future<void> _sendJson(
      HttpRequest req, int status, Map<String, dynamic> body) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }
}

/// Client used by Makaw Mobile / Tablet / Peer Desktop to connect to a paired
/// [WorkstationCompanionHost] over LAN / Wi-Fi / tunnel.
class WorkstationCompanionClient {
  static const _pairingsKey = 'makaw_companion_pairings_v1';

  static Future<List<CompanionPairing>> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pairingsKey);
      if (raw == null || raw.isEmpty) return const [];
      return (jsonDecode(raw) as List)
          .map((e) => CompanionPairing.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> savePairing(CompanionPairing p) async {
    final current = (await loadSaved()).toList();
    final updated = [
      p,
      ...current.where((x) => !(x.host == p.host && x.port == p.port)),
    ];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _pairingsKey, jsonEncode(updated.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> ping(CompanionPairing pairing) async {
    try {
      final resp = await http
          .get(Uri.parse('${pairing.baseUrl}/v1/ping'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<List<Map<String, dynamic>>> listRemoteDir(
    CompanionPairing pairing, {
    String path = '.',
  }) async {
    final uri = Uri.parse('${pairing.baseUrl}/v1/fs/list')
        .replace(queryParameters: {'path': path});
    final resp = await http.get(
      uri,
      headers: {'Authorization': 'Bearer ${pairing.token}'},
    ).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['entries'] as List).cast<Map<String, dynamic>>();
  }

  static Future<String> readRemoteFile(
    CompanionPairing pairing,
    String path,
  ) async {
    final uri = Uri.parse('${pairing.baseUrl}/v1/fs/read')
        .replace(queryParameters: {'path': path});
    final resp = await http.get(
      uri,
      headers: {'Authorization': 'Bearer ${pairing.token}'},
    ).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['content'] as String?) ?? '';
  }

  static Future<void> writeRemoteFile(
    CompanionPairing pairing,
    String path,
    String content,
  ) async {
    final resp = await http
        .post(
          Uri.parse('${pairing.baseUrl}/v1/fs/write'),
          headers: {
            'Authorization': 'Bearer ${pairing.token}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'path': path, 'content': content}),
        )
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode}: ${resp.body}');
    }
  }
}
