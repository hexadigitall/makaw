import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A configured remote/SSH host the IDE can connect to.
class RemoteHost {
  final String name;
  final String host;
  final String user;
  final String port;

  const RemoteHost({
    required this.name,
    required this.host,
    required this.user,
    this.port = '22',
  });

  String get target => '$user@$host';

  Map<String, dynamic> toJson() =>
      {'name': name, 'host': host, 'user': user, 'port': port};

  factory RemoteHost.fromJson(Map<String, dynamic> json) => RemoteHost(
        name: json['name'] as String? ?? '',
        host: json['host'] as String? ?? '',
        user: json['user'] as String? ?? '',
        port: json['port'] as String? ?? '22',
      );
}

/// Persisted IDE configuration (Git identity, GitHub token, remote hosts,
/// recent folders). Stored on this device via [SharedPreferences] so it
/// survives app restarts.
class IdeSettings {
  String gitName;
  String gitEmail;
  String githubToken;

  /// The most recently opened folders, most recent first.
  List<String> recentFolders;

  /// Remote/SSH hosts configured in the Integrations dialog.
  List<RemoteHost> remoteHosts;

  /// Default WSL distro to use for the integrated terminal.
  String wslDistro;

  bool dockerEnabled;

  // Panel layout state persisted between sessions.
  double leftPanelWidth;
  double terminalHeightFraction;
  double previewWidth;
  bool showLeftPanel;
  bool showTerminal;
  bool showPreview;

  // Movable-panel placement + sizes (VS Code style).
  bool terminalOnBottom;
  bool previewOnBottom;
  double terminalSideWidth;
  double bottomAreaFraction;
  double bottomShareTerminal;

  IdeSettings({
    this.gitName = '',
    this.gitEmail = '',
    this.githubToken = '',
    List<String>? recentFolders,
    List<RemoteHost>? remoteHosts,
    this.wslDistro = '',
    this.dockerEnabled = true,
    this.leftPanelWidth = 260,
    this.terminalHeightFraction = 0.3,
    this.previewWidth = 360,
    this.showLeftPanel = true,
    this.showTerminal = true,
    this.showPreview = true,
    this.terminalOnBottom = true,
    this.previewOnBottom = false,
    this.terminalSideWidth = 300,
    this.bottomAreaFraction = 0.3,
    this.bottomShareTerminal = 0.5,
  })  : recentFolders = recentFolders ?? [],
        remoteHosts = remoteHosts ?? [];

  bool get hasGitIdentity => gitName.isNotEmpty && gitEmail.isNotEmpty;

  /// Records [path] as a recent folder (deduped, capped at 10).
  void rememberFolder(String path) {
    recentFolders.removeWhere((p) => p == path);
    recentFolders.insert(0, path);
    if (recentFolders.length > 10) {
      recentFolders.removeRange(10, recentFolders.length);
    }
  }

  Map<String, dynamic> toJson() => {
        'gitName': gitName,
        'gitEmail': gitEmail,
        'githubToken': githubToken,
        'recentFolders': recentFolders,
        'remoteHosts': remoteHosts.map((h) => h.toJson()).toList(),
        'wslDistro': wslDistro,
        'dockerEnabled': dockerEnabled,
        'leftPanelWidth': leftPanelWidth,
        'terminalHeightFraction': terminalHeightFraction,
        'previewWidth': previewWidth,
        'showLeftPanel': showLeftPanel,
        'showTerminal': showTerminal,
        'showPreview': showPreview,
        'terminalOnBottom': terminalOnBottom,
        'previewOnBottom': previewOnBottom,
        'terminalSideWidth': terminalSideWidth,
        'bottomAreaFraction': bottomAreaFraction,
        'bottomShareTerminal': bottomShareTerminal,
      };

  factory IdeSettings.fromJson(Map<String, dynamic> json) => IdeSettings(
        gitName: json['gitName'] as String? ?? '',
        gitEmail: json['gitEmail'] as String? ?? '',
        githubToken: json['githubToken'] as String? ?? '',
        recentFolders: (json['recentFolders'] as List?)?.cast<String>() ?? [],
        remoteHosts: (json['remoteHosts'] as List?)
                ?.map((e) => RemoteHost.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        wslDistro: json['wslDistro'] as String? ?? '',
        dockerEnabled: json['dockerEnabled'] as bool? ?? true,
        leftPanelWidth: (json['leftPanelWidth'] as num?)?.toDouble() ?? 260,
        terminalHeightFraction:
            (json['terminalHeightFraction'] as num?)?.toDouble() ?? 0.3,
        previewWidth: (json['previewWidth'] as num?)?.toDouble() ?? 360,
        showLeftPanel: json['showLeftPanel'] as bool? ?? true,
        showTerminal: json['showTerminal'] as bool? ?? true,
        showPreview: json['showPreview'] as bool? ?? true,
        terminalOnBottom: json['terminalOnBottom'] as bool? ?? true,
        previewOnBottom: json['previewOnBottom'] as bool? ?? false,
        terminalSideWidth:
            (json['terminalSideWidth'] as num?)?.toDouble() ?? 300,
        bottomAreaFraction:
            (json['bottomAreaFraction'] as num?)?.toDouble() ?? 0.3,
        bottomShareTerminal:
            (json['bottomShareTerminal'] as num?)?.toDouble() ?? 0.5,
      );
}

/// Loads/saves [IdeSettings] via [SharedPreferences].
class IdeSettingsStore {
  static const _key = 'makaw_ide_settings_v1';

  static IdeSettings _cache = IdeSettings();

  static Future<IdeSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        _cache = IdeSettings.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      _cache = IdeSettings();
    }
    return _cache;
  }

  static Future<void> save(IdeSettings settings) async {
    _cache = settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(settings.toJson()));
    } catch (_) {}
  }
}