import 'dart:convert';

/// Kind of ecosystem activity recorded in the unified activity feed.
class ActivityKind {
  static const String browser = 'browser';
  static const String document = 'document';
  static const String terminal = 'terminal';
  static const String project = 'project';
  static const String media = 'media';
  static const String file = 'file';
  static const String download = 'download';

  /// Sub-kinds for [media].
  static const String mediaMusic = 'music';
  static const String mediaVideo = 'video';

  static const List<String> all = [browser, document, terminal, project, media, file, download];
}

/// A single recorded activity entry in the unified recents feed.
///
/// Every ecosystem writes a lightweight [ActivityEntry] when a user does
/// something resume-worthy (browse a page, open a document, create a terminal
/// session, save a project, play media, open a file/folder). The Makaw Home
/// portal and the ecosystem hubs surface them as one-tap-resume cards.
class ActivityEntry {
  final int? id;

  /// One of [ActivityKind].
  final String kind;

  /// For [ActivityKind.media] — [ActivityKind.mediaMusic] or
  /// [ActivityKind.mediaVideo]. Null otherwise.
  final String? subtype;

  final String title;
  final String subtitle;

  /// Payload used to resume the activity (url, filePath, sessionId, projectName,
  /// media uri + position, etc.). JSON-encoded string in the DB, decoded here.
  final Map<String, dynamic> payload;

  final DateTime timestamp;

  const ActivityEntry({
    this.id,
    required this.kind,
    this.subtype,
    required this.title,
    this.subtitle = '',
    this.payload = const {},
    required this.timestamp,
  });

  String get payloadJson => jsonEncode(payload);

  String? get payloadString => payload['data'] as String?;

  ActivityEntry copyWith({int? id, DateTime? timestamp}) => ActivityEntry(
        id: id ?? this.id,
        kind: kind,
        subtype: subtype,
        title: title,
        subtitle: subtitle,
        payload: payload,
        timestamp: timestamp ?? this.timestamp,
      );

  factory ActivityEntry.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> payload = {};
    final raw = map['payload'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    DateTime ts;
    try {
      ts = DateTime.parse(map['timestamp'] as String? ?? '');
    } catch (_) {
      ts = DateTime.now();
    }
    return ActivityEntry(
      id: map['id'] as int?,
      kind: map['kind'] as String? ?? ActivityKind.browser,
      subtype: map['subtype'] as String?,
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      payload: payload,
      timestamp: ts,
    );
  }

  Map<String, dynamic> toMap({bool includeId = true}) => {
        if (includeId) 'id': id,
        'kind': kind,
        'subtype': subtype,
        'title': title,
        'subtitle': subtitle,
        'payload': payloadJson,
        'timestamp': timestamp.toIso8601String(),
      };
}
