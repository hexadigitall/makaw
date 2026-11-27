import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/terminal_sessions_store.dart';
import '../domain/terminal_models.dart';
import 'ai_tool_vault_service.dart';
import 'project_runbook_service.dart';
import 'workstation_companion_service.dart';

/// Serializable non-secret state snapshot handed off continuously between
/// Makaw Desktop, Tablet, and Mobile devices ("Makaw Continuum").
class ContinuumSnapshot {
  final String deviceName;
  final String os;
  final DateTime updatedAt;
  final String activeCwd;
  final String handoffNote;
  final List<TerminalSessionMeta> sessions;
  final List<SshHostProfile> sshHosts;
  final List<RunbookCommand> customRunbooks;

  const ContinuumSnapshot({
    required this.deviceName,
    required this.os,
    required this.updatedAt,
    this.activeCwd = '',
    this.handoffNote = '',
    this.sessions = const [],
    this.sshHosts = const [],
    this.customRunbooks = const [],
  });

  Map<String, dynamic> toJson() => {
        'deviceName': deviceName,
        'os': os,
        'updatedAt': updatedAt.toIso8601String(),
        'activeCwd': activeCwd,
        'handoffNote': AiToolVaultService.redactSecrets(handoffNote),
        'sessions': sessions
            .map((s) => s
                .copyWith(
                    lastCommand: AiToolVaultService.redactSecrets(s.lastCommand))
                .toJson())
            .toList(),
        'sshHosts': sshHosts.map((h) => h.toJson()).toList(),
        'customRunbooks': customRunbooks.map((r) => r.toJson()).toList(),
      };

  factory ContinuumSnapshot.fromJson(Map<String, dynamic> j) => ContinuumSnapshot(
        deviceName: (j['deviceName'] as String?) ?? 'Makaw Device',
        os: (j['os'] as String?) ?? '',
        updatedAt:
            DateTime.tryParse((j['updatedAt'] as String?) ?? '') ?? DateTime.now(),
        activeCwd: (j['activeCwd'] as String?) ?? '',
        handoffNote: (j['handoffNote'] as String?) ?? '',
        sessions: (j['sessions'] as List? ?? const [])
            .map((e) => TerminalSessionMeta.fromJson(e as Map<String, dynamic>))
            .toList(),
        sshHosts: (j['sshHosts'] as List? ?? const [])
            .map((e) => SshHostProfile.fromJson(e as Map<String, dynamic>))
            .toList(),
        customRunbooks: (j['customRunbooks'] as List? ?? const [])
            .map((e) => RunbookCommand.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Manages Continuum snapshot capture, local persistence, LAN Companion push/pull,
/// and optional Firestore cloud delta sync (always redacting secrets cleanly).
class MakawContinuumSync {
  static const _localSnapKey = 'makaw_continuum_last_snapshot_v1';

  Future<ContinuumSnapshot?> loadLocalSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localSnapKey);
      if (raw == null || raw.isEmpty) return null;
      return ContinuumSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLocalSnapshot(ContinuumSnapshot snap) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localSnapKey, jsonEncode(snap.toJson()));
    } catch (_) {}
  }

  /// Captures current local Terminal state and saves it locally (and pushes
  /// optionally to a paired Workstation Companion & Firestore if configured).
  Future<ContinuumSnapshot> captureAndSync({
    required TerminalSessionsStore store,
    required List<SshHostProfile> sshHosts,
    String activeCwd = '',
    String handoffNote = '',
    CompanionPairing? companion,
    String? cloudSyncRoomId,
  }) async {
    final sessions = await store.load();
    final runbooks = await RunbookDetector.loadCustom();
    final snap = ContinuumSnapshot(
      deviceName: Platform.localHostname,
      os: Platform.operatingSystem,
      updatedAt: DateTime.now(),
      activeCwd: activeCwd,
      handoffNote: handoffNote,
      sessions: sessions.take(10).toList(),
      sshHosts: sshHosts,
      customRunbooks: runbooks,
    );
    await saveLocalSnapshot(snap);

    if (companion != null) {
      try {
        await http
            .post(
              Uri.parse('${companion.baseUrl}/v1/continuum'),
              headers: {
                'Authorization': 'Bearer ${companion.token}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(snap.toJson()),
            )
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }

    if (cloudSyncRoomId != null && cloudSyncRoomId.trim().isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('makaw_continuum')
            .doc(cloudSyncRoomId.trim())
            .set(snap.toJson());
      } catch (_) {}
    }
    return snap;
  }

  Future<ContinuumSnapshot?> pullSnapshot({
    CompanionPairing? companion,
    String? cloudSyncRoomId,
  }) async {
    if (companion != null) {
      try {
        final resp = await http.get(
          Uri.parse('${companion.baseUrl}/v1/continuum'),
          headers: {'Authorization': 'Bearer ${companion.token}'},
        ).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200 && resp.body.trim().length > 4) {
          final parsed = ContinuumSnapshot.fromJson(
              jsonDecode(resp.body) as Map<String, dynamic>);
          await saveLocalSnapshot(parsed);
          return parsed;
        }
      } catch (_) {}
    }

    if (cloudSyncRoomId != null && cloudSyncRoomId.trim().isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('makaw_continuum')
            .doc(cloudSyncRoomId.trim())
            .get();
        if (doc.exists && doc.data() != null) {
          final parsed = ContinuumSnapshot.fromJson(doc.data()!);
          await saveLocalSnapshot(parsed);
          return parsed;
        }
      } catch (_) {}
    }

    return loadLocalSnapshot();
  }
}
