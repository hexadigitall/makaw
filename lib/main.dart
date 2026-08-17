import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'features/browser/data/services/password_service.dart';
import 'features/browser/data/services/import_service.dart';
import 'features/browser/data/services/ad_blocker_service.dart';
import 'features/browser/data/services/suggestion_engine.dart';
import 'features/browser/data/models/suggestion_item.dart';
import 'features/viewer/presentation/pages/document_viewer_page.dart';
import 'features/history/data/history_service.dart';
import 'features/history/domain/history_item.dart';
import 'features/history/presentation/pages/makaw_history_page.dart';
import 'features/news/data/services/news_feed_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:git/git.dart';
import 'package:path/path.dart' as p;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:collection';
import 'dart:typed_data';
import 'package:xterm/xterm.dart';
import 'core/platform/conditional_pty.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'features/browser/data/services/content_blocker_service.dart';
import 'features/browser/presentation/providers/download_service.dart';
import 'core/services/update_service.dart';
import 'core/services/media_notification_service.dart';
import 'features/news/presentation/pages/news_feed_page.dart';
import 'features/media/presentation/pages/video_player_page.dart';
import 'features/pdf/presentation/pages/pdf_viewer_page.dart';
import 'features/viewer/presentation/pages/epub_viewer_page.dart';
import 'features/viewer/presentation/pages/text_viewer_page.dart';
import 'features/viewer/presentation/pages/html_viewer_page.dart';
import 'features/music/presentation/pages/music_player_page.dart';
import 'features/media/presentation/pages/image_viewer_page.dart';
import 'features/music/data/services/music_player_service.dart';
import 'features/media/data/services/image_viewer_service.dart';
import 'features/media/data/services/video_player_service.dart';
import 'features/documents/data/services/document_service.dart';
import 'features/documents/presentation/pages/document_page.dart';
import 'features/browser/domain/entities/entities.dart';
import 'features/browser/presentation/pages/tab_tray_page.dart';
import 'features/browser/presentation/pages/qr_scanner_page.dart';
import 'features/viewer/presentation/pages/folder_video_player_page.dart';
import 'features/browser/presentation/providers/download_manager_provider.dart';
import 'app/providers/service_providers.dart';
import 'features/browser/presentation/pages/media_sniffer_page.dart';
import 'features/browser/presentation/widgets/downloads_widget.dart' as feature;

// ── Makaw Design Tokens ─────────────────────────────────────────────────────
const kIconBgColor = Color(0xFF2B3845);
const kAccentOrange = Color(0xFFD44D33);
const kAccentTeal = Color(0xFF00A7C2);

const kIncognitoBg = Color(0xFF202124);
const kIncognitoSurface = Color(0xFF2B2C2F);
const kIncognitoInput = Color(0xFF3C4043);
const kIncognitoAccent = Color(0xFFA8C7FA);
const kIncognitoPurple = Color(0xFF7C3AED);


// ─── Models ───────────────────────────────────────────────────────────────────

enum ViewMode { home, newTab, typeView, browsing }

class ConflictPart {
  String ours = '';
  String theirs = '';
  bool inTheirs = false;
}

class EditorFile {
  int id;
  String name;
  String content;
  String language;
  bool dirty;
  EditorFile({required this.id, required this.name, required this.content, this.language = 'javascript', this.dirty = false});
}

// ─── App ──────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch Flutter framework errors (widget build/layout/paint failures)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    print('FLUTTER ERROR: ${details.exception}');
    print('STACK: ${details.stack}');
  };

  // Catch unhandled async errors and platform errors (network failures,
  // file I/O, codec errors, corrupt media — prevents OS kill)
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    print('PLATFORM ERROR: $error');
    print('STACK: $stack');
    return true; // handled — prevents app process crash
  };

  await globalMusicService.init();
  await _initMediaNotification();
  runApp(ProviderScope(child: MakawApp()));
}

final MusicPlayerService globalMusicService = MusicPlayerService();
String audioServiceStatus = 'unknown';

const _systemChannel = MethodChannel('com.hexadigitall.makaw/system');

Future<void> _moveTaskToBack() async {
  try {
    await _systemChannel.invokeMethod('moveTaskToBack');
  } catch (_) {}
}

Future<void> _initMediaNotification() async {
  try {
    final notif = MediaNotificationService.instance;
    await notif.init();
    audioServiceStatus = 'notif: ${notif.channelImportance}';
    globalMusicService.notificationStatus = 'channel: ${notif.channelImportance}';

    notif.onPlay = () {
      globalMusicService.player.play();
      globalMusicService.notifyNowPlaying();
    };
    notif.onPause = () {
      globalMusicService.player.pause();
      globalMusicService.notifyNowPlaying();
    };
    notif.onNext = () => globalMusicService.nextSong();
    notif.onPrevious = () => globalMusicService.previousSong();
    notif.onSeek = (pos) => globalMusicService.player.seek(pos);

    globalMusicService.onNowPlaying = () {
      final song = globalMusicService.currentSong;
      if (song != null) {
        notif.show(
          title: song.displayTitle,
          artist: song.displayArtist,
          isPlaying: globalMusicService.isPlaying,
          position: globalMusicService.position,
          duration: globalMusicService.duration,
        );
      }
    };
  } catch (e) {
    audioServiceStatus = 'error';
    globalMusicService.notificationStatus = 'init error: $e';
    print('MediaNotification init failed: $e');
  }
}

Future<void> _requestNotificationPermission() async {
  if (await Permission.notification.status.isDenied) {
    await Permission.notification.request();
  }
}

class MakawApp extends ConsumerStatefulWidget {
  const MakawApp({super.key});
  @override
  ConsumerState<MakawApp> createState() => _MakawAppState();
}

class _MakawAppState extends ConsumerState<MakawApp> with WidgetsBindingObserver {
  String _themeMode = 'system';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateSystemUi(_effectiveBrightness());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (_themeMode == 'system') {
      _updateSystemUi(_effectiveBrightness());
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      MediaNotificationService.instance.hide();
    }
  }

  Brightness _effectiveBrightness() {
    if (_themeMode == 'light') return Brightness.light;
    if (_themeMode == 'dark') return Brightness.dark;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }

  void setThemeMode(String mode) {
    setState(() => _themeMode = mode);
    _updateSystemUi(_effectiveBrightness());
  }

  void _updateSystemUi(Brightness brightness) {
    final navColor = brightness == Brightness.light ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor: navColor,
      systemNavigationBarIconBrightness: brightness == Brightness.light ? Brightness.dark : Brightness.light,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: brightness == Brightness.light ? Brightness.dark : Brightness.light,
    ));
    // Also set via platform channel for MIUI compatibility
    try {
      _systemChannel.invokeMethod('setNavigationBarColor', {'color': navColor.value});
    } catch (_) {}
  }

  ThemeMode get _themeModeValue {
    if (_themeMode == 'light') return ThemeMode.light;
    if (_themeMode == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Makaw',
      debugShowCheckedModeBanner: false,
      themeMode: _themeModeValue,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: Color(0xFFF1F5F9),
        primaryColor: Color(0xFFE2E8F0),
        colorScheme: ColorScheme.light(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF818CF8),
          surface: Color(0xFFFFFFFF),
        ),
        cardColor: Color(0xFFF8FAFC),
        appBarTheme: AppBarTheme(backgroundColor: Color(0xFFE2E8F0), foregroundColor: Color(0xFF0F172A)),
        textTheme: TextTheme(bodyMedium: TextStyle(color: Color(0xFF1E293B))),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Color(0xFF0F172A),
        primaryColor: Color(0xFF1E293B),
        colorScheme: ColorScheme.dark(
          primary: Color(0xFF818CF8),
          secondary: Color(0xFF6366F1),
          surface: Color(0xFF1E293B),
        ),
        cardColor: Color(0xFF334155),
        appBarTheme: AppBarTheme(backgroundColor: Color(0xFF1E293B)),
      ),
      home: MakawHome(themeMode: _themeMode, onThemeChanged: setThemeMode),
    );
  }
}

// ─── Home ─────────────────────────────────────────────────────────────────────

class MakawHome extends ConsumerStatefulWidget {
  final String themeMode;
  final void Function(String mode)? onThemeChanged;
  const MakawHome({required this.themeMode, this.onThemeChanged});
  @override
  ConsumerState<MakawHome> createState() => _MakawHomeState();
}

class _MakawHomeState extends ConsumerState<MakawHome> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _currentView = 'browser';
  ViewMode _viewMode = ViewMode.home;
  bool get _showHomeScreen => _viewMode == ViewMode.home || _viewMode == ViewMode.newTab;
  bool get _isMakawHome => _viewMode == ViewMode.home;
  bool get _isNewTabView => _viewMode == ViewMode.newTab;
  bool _showMediaHub = false;
  bool _ready = false;
  InAppWebViewController? _monacoController;
  Database? _db;
  String _currentProject = 'untitled';
  String _currentLang = 'javascript';
  String _projectPath = '';
  List<Map<String, dynamic>> _projects = [];
  String _gitOutput = '';
  List<String> _branches = [];
  String _currentBranch = '';
  List<String> _conflictedFiles = [];
  String _snippetSearch = '';
  List<Map<String, String>> _snippets = [];

  late final Terminal _terminal = Terminal(maxLines: 10000);
  final TerminalController _terminalController = TerminalController();
  late final TextEditingController _terminalInputController;
  late final FocusNode _terminalFocusNode;
  final FocusNode _urlFocusNode = FocusNode();
  Pty? _pty;

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: [drive.DriveApi.driveFileScope]);

  // Browser tabs — single WebView recycling
  List<BrowserTab> _browserTabs = [];
  int _activeBrowserTabId = 0;
  int _browserTabIdCounter = 0;

  final Map<int, InAppWebViewController> _tabControllers = {};
  PullToRefreshController? _pullToRefreshController;
  final Map<int, int> _tabProgress = {};
  final Map<int, Uint8List?> _tabSnapshots = {};
  List<(String, String)> _shortcuts = [];
  bool _shortcutsLoaded = false;
  bool _homeInitialized = false;
  bool _typeViewFromHome = false;
  bool _isWebViewLoading = false;
  DateTime? _lastPopupToast;
  bool _showPasswordDialog = false;
  String _pendingPasswordUrl = '';
  String _pendingPasswordUsername = '';
  String _pendingPasswordPassword = '';
  late final TextEditingController _urlController;
  late final TextEditingController _searchController;

  // Browser history
  List<Map<String, dynamic>> _browserHistory = [];
  List<Map<String, dynamic>> _urlSuggestions = [];
  List<String> _searchSuggestions = [];
  List<SuggestionItem> _suggestions = [];
  bool _ignoreUrlChanges = false;
  Timer? _suggestDebounce;
  int _historyPage = 0;
  static const int _historyPageSize = 50;

  bool _desktopSite = false;
  final TextEditingController _findController = TextEditingController();
  final List<Map<String, String>> _recentTabs = [];
  static const int _maxRecentTabs = 20;

  NewsFeedService? _newsFeedService;
  final GlobalKey<NewsFeedWidgetState> _newsFeedKey = GlobalKey<NewsFeedWidgetState>();
  final ScrollController _newsFeedScrollController = ScrollController();

  Future<void> _refreshNewsFeed() async {
    if (_newsFeedService == null) return;
    final state = _newsFeedKey.currentState;
    if (state != null) {
      await state.refresh();
    }
  }
  MusicPlayerService _musicService = globalMusicService;
  ImageViewerService _imageService = ImageViewerService();

  // Navigation
  void _onUrlFocusChanged() {
    if (_urlFocusNode.hasFocus && _viewMode != ViewMode.typeView) {
      final rawUrl = _urlController.text;
      final clean = _cleanDisplayUrl(rawUrl);
      _typeViewFromHome = _showHomeScreen;
      _ignoreUrlChanges = true;
      if (clean.isNotEmpty) _urlController.text = clean;
      _ignoreUrlChanges = false;
      setState(() { _viewMode = ViewMode.typeView; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _urlController.selection = TextSelection(baseOffset: 0, extentOffset: _urlController.text.length);
      });
    }
  }

  void _switchToView(String view) {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
    if (view == 'browser') {
      setState(() => _currentView = view);
    } else {
      final page = _buildFeaturePage(view);
      if (page != null) {
        final wasBrowsing = !_showHomeScreen;
        Navigator.of(context).push(PageRouteBuilder(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: Duration(milliseconds: 200),
          reverseTransitionDuration: Duration(milliseconds: 150),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        )).then((_) {
          if (mounted) {
            _urlController.clear();
            setState(() {
              _viewMode = wasBrowsing ? ViewMode.browsing : ViewMode.home;
            });
            if (wasBrowsing) _syncUrlController();
          }
        });
      }
    }
  }

  Widget? _buildFeaturePage(String view) {
    switch (view) {
      case 'history': return MakawHistoryPage(onNavigate: (url) => _navigateInCurrentTab(url));
      case 'studio': return _buildFeatureScaffold('Code Studio', Icons.code, _buildStudioTab());
      case 'sniffer': return _buildFeatureScaffold('Media Sniffer', Icons.wifi_tethering, _buildSnifferTab());
      case 'snippets': return _buildFeatureScaffold('Snippets', Icons.content_paste, _buildSnippetsTab());
      case 'projects': return _buildFeatureScaffold('Projects', Icons.folder, _buildProjectsTab());
      case 'git': return _buildFeatureScaffold('Git', Icons.account_tree, _buildGitTab());
      case 'cloud': return _buildFeatureScaffold('Cloud Sync', Icons.cloud, _buildCloudTab());
      case 'terminal': return _buildFeatureScaffold('Terminal', Icons.terminal, _buildTerminalTab());
      case 'downloads': return _buildFeatureScaffold('Downloads', Icons.download, _buildDownloadsTab());
      case 'player': return VideoPlayerWidget(onOpenMusic: () => _switchToView('music'), onHome: () => Navigator.of(context).pop());
      case 'music': return _buildMusicPlayerPage();
      case 'media': return _buildMediaHubPage();
      case 'images': return _buildImagePage();
      case 'documents': return _buildDocumentPage();
      default: return null;
    }
  }

  // Media sniffer — per-tab
  final Map<int, List<MediaItem>> _tabMedia = {};
  List<MediaItem> get _pendingMedia => _tabMedia.putIfAbsent(_activeBrowserTabId, () => []);

  // Editor file tabs
  List<EditorFile> _openFiles = [];
  int _activeFileId = 0;
  int _fileIdCounter = 0;

  // Content blocker & download manager
  final ContentBlockerService _contentBlocker = ContentBlockerService();
  final AdBlockerService _adBlocker = AdBlockerService();
  late final DownloadService _downloadManager;
  late final UpdateService _updateService;
  String? _playVideoUrl;
  String? _playVideoTitle;
  VideoPlayerService _videoService = VideoPlayerService();
  DocumentService _documentService = DocumentService();
  bool _isFullscreen = false;
  String? _pendingOpenFilePath;
  String? _pendingOpenMimeType = '';

  // VPN / Proxy
  bool _vpnEnabled = false;
  String _proxyHost = '';
  int _proxyPort = 1080;
  bool _proxyUseAuth = false;
  String _proxyUsername = '';
  String _proxyPassword = '';

  Future<void> _loadProxySettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _vpnEnabled = prefs.getBool('vpn_enabled') ?? false;
      _proxyHost = prefs.getString('proxy_host') ?? '';
      _proxyPort = prefs.getInt('proxy_port') ?? 1080;
      _proxyUseAuth = prefs.getBool('proxy_use_auth') ?? false;
      _proxyUsername = prefs.getString('proxy_username') ?? '';
      _proxyPassword = prefs.getString('proxy_password') ?? '';
    });
    if (_vpnEnabled && _proxyHost.isNotEmpty) {
      _applyProxy();
    }
  }

  Future<void> _saveProxySettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vpn_enabled', _vpnEnabled);
    await prefs.setString('proxy_host', _proxyHost);
    await prefs.setInt('proxy_port', _proxyPort);
    await prefs.setBool('proxy_use_auth', _proxyUseAuth);
    await prefs.setString('proxy_username', _proxyUsername);
    await prefs.setString('proxy_password', _proxyPassword);
  }

  Future<void> _applyProxy() async {
    if (_proxyHost.isEmpty) return;
    try {
      final rules = <ProxyRule>[
        ProxyRule(
          url: 'socks://$_proxyHost:$_proxyPort',
        ),
      ];
      await ProxyController.instance().setProxyOverride(
        settings: ProxySettings(
          proxyRules: rules,
          bypassSimpleHostnames: true,
        ),
      );
    } catch (e) {
      print('Proxy error: $e');
    }
  }

  Future<void> _clearProxy() async {
    try {
      await ProxyController.instance().clearProxyOverride();
    } catch (e) {
      print('Clear proxy error: $e');
    }
  }

  void _toggleProxy() {
    showDialog(
      context: context,
      builder: (ctx) {
        final hostCtrl = TextEditingController(text: _proxyHost);
        final portCtrl = TextEditingController(text: '$_proxyPort');
        final userCtrl = TextEditingController(text: _proxyUsername);
        final passCtrl = TextEditingController(text: _proxyPassword);
        bool useAuth = _proxyUseAuth;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Row(
                children: [
                  Icon(Icons.vpn_lock, color: _vpnEnabled ? Colors.greenAccent : Colors.white54, size: 26),
                  SizedBox(width: 8),
                  Text(_vpnEnabled ? 'VPN: Connected' : 'VPN: Disabled', style: TextStyle(color: Colors.white, fontSize: 17)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: Text('Enable Proxy', style: TextStyle(color: Colors.white, fontSize: 15)),
                      value: _vpnEnabled,
                      activeColor: Colors.greenAccent,
                      onChanged: (v) => setState(() => _vpnEnabled = v),
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: hostCtrl,
                      style: TextStyle(color: Colors.white, fontSize: 15),
                      decoration: InputDecoration(
                        labelText: 'Proxy Host',
                        hintText: '127.0.0.1',
                        labelStyle: TextStyle(color: Colors.white54, fontSize: 15),
                        hintStyle: TextStyle(color: Colors.white30, fontSize: 15),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                      ),
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: portCtrl,
                      style: TextStyle(color: Colors.white, fontSize: 15),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Port',
                        hintText: '1080',
                        labelStyle: TextStyle(color: Colors.white54, fontSize: 15),
                        hintStyle: TextStyle(color: Colors.white30, fontSize: 15),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                      ),
                    ),
                    SizedBox(height: 8),
                    SwitchListTile(
                      title: Text('Require Authentication', style: TextStyle(color: Colors.white, fontSize: 15)),
                      value: useAuth,
                      activeColor: Colors.greenAccent,
                      onChanged: (v) => setDialogState(() => useAuth = v),
                    ),
                    if (useAuth) ...[
                      SizedBox(height: 8),
                      TextField(
                        controller: userCtrl,
                        style: TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          labelText: 'Username',
                          labelStyle: TextStyle(color: Colors.white54, fontSize: 15),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                        ),
                      ),
                      SizedBox(height: 8),
                      TextField(
                        controller: passCtrl,
                        style: TextStyle(color: Colors.white, fontSize: 15),
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: TextStyle(color: Colors.white54, fontSize: 15),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent.shade700),
                  onPressed: () {
                    setState(() {
                      _proxyHost = hostCtrl.text.trim();
                      _proxyPort = int.tryParse(portCtrl.text.trim()) ?? 1080;
                      _proxyUseAuth = useAuth;
                      _proxyUsername = userCtrl.text.trim();
                      _proxyPassword = passCtrl.text.trim();
                    });
                    if (_vpnEnabled && _proxyHost.isNotEmpty) {
                      _applyProxy();
                    } else {
                      _clearProxy();
                    }
                    Navigator.pop(ctx);
                  },
                  child: Text('Apply', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => _saveProxySettings());
  }

  // AI
  String _aiApiKey = '';
  GenerativeModel? _aiModel;
  final List<Map<String, String>> _aiMessages = [];
  bool _aiLoading = false;

  static const List<String> LANG_OPTIONS = ['javascript', 'dart', 'python', 'html', 'css', 'typescript', 'json'];

  static const Map<String, String> BOILERPLATES = {
    'javascript': '// Makaw JS\nconsole.log("Hello from Makaw!");\n',
    'dart': 'void main() {\n  print("Hello from Makaw!");\n}\n',
    'python': '# Makaw Python\nprint("Hello from Makaw!")\n',
    'html': '<!DOCTYPE html>\n<html>\n<head><title>Makaw</title></head>\n<body>\n  <h1>Hello Makaw!</h1>\n</body>\n</html>\n',
    'css': '/* Makaw CSS */\nbody {\n  background: #0f172a;\n  color: #e2e8f0;\n}\n',
    'typescript': '// Makaw TypeScript\nconst greeting: string = "Hello from Makaw!";\nconsole.log(greeting);\n',
    'json': '{\n  "app": "Makaw",\n  "version": "1.0.0"\n}\n',
  };

  void _onMusicChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveSession();
    }
    if (state == AppLifecycleState.resumed) {
      // Do NOT re-initialize shortcuts, feeds, or services — they persist in memory
    }
    if (state == AppLifecycleState.detached) {
      _saveSession();
      MediaNotificationService.instance.hide();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _urlController = TextEditingController();
    _searchController = TextEditingController();
    _terminalInputController = TextEditingController();
    _terminalFocusNode = FocusNode();
    _newsFeedService = NewsFeedService();
    _urlController.addListener(_onUrlChanged);
    _urlFocusNode.addListener(_onUrlFocusChanged);
    _musicService.addListener(_onMusicChanged);

    // Defer heavy init to after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_homeInitialized) return;
      _homeInitialized = true;
      await _newsFeedService!.init();
      await _newsFeedService!.ensureLocationReady();
      _newsFeedService!.loadTaps();
      await _loadSavedSession();
      await _loadShortcuts();
      setState(() => _ready = true);
      _initDownloadDir();
      _musicService.loadPlaylists();
      _musicService.loadFavorites();
      ref.read(musicPlayerServiceProvider.notifier).state = _musicService;
      _requestNotificationPermission();
      _imageService.loadFavorites();
      _imageService.loadTrash();
      ref.read(imageViewerServiceProvider.notifier).state = _imageService;
      // _imageService.scanAllImages(); // disabled — hangs on this device
      _videoService.loadFavorites();
      _videoService.loadPlaylists();
      _videoService.loadResumePositions();
      _videoService.scanAllVideos();
      ref.read(videoPlayerServiceProvider.notifier).state = _videoService;
      _documentService.loadFavorites();
      ref.read(documentServiceProvider.notifier).state = _documentService;
      _documentService.scanAllDocuments(); // runs in background isolate — no UI freeze
      _downloadManager = DownloadService(
        dio: Dio(BaseOptions(
          connectTimeout: Duration(seconds: 15),
          receiveTimeout: Duration(seconds: 60),
          sendTimeout: Duration(seconds: 30),
        )),
        getDownloadDir: _defaultDownloadDir,
        showNotification: _showToast,
        onComplete: null,
      );
      ref.read(downloadServiceProvider.notifier).state = _downloadManager;
      _adBlocker.onBlacklistUpdated = () {
        // Push new contentBlocker rules to all existing tabs
        final rules = _adBlocker.getContentBlockerRules();
        for (final entry in _tabControllers.entries) {
          entry.value.setSettings(settings: InAppWebViewSettings(
            contentBlockers: rules,
          ));
        }
      };
      _adBlocker.updateBlacklist(); // fire-and-forget: fetch EasyList + AdGuard filter lists
      _updateService = UpdateService(
        repoOwner: 'hexadigitall',
        repoName: 'makaw',
        dio: Dio(),
      );
      _initDb();
      _initSnippets();
      _checkUpdatesOnStartup();
      _requestPermissions();
      _loadAiKey();
      _setupIntentChannel();
      _loadProxySettings();
    });
  }

  void _setupIntentChannel() {
    const channel = MethodChannel('com.hexadigitall.makaw/intent');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onNewIntent') {
        final data = call.arguments as Map?;
        _handleIncomingIntent(data);
      }
      return null;
    });
    // Handle initial intent that launched the app
    channel.invokeMethod('getInitialIntent').then((result) {
      if (result is Map) _handleIncomingIntent(result);
    }).catchError((_) {});
  }

  void _handleIncomingIntent(Map? data) {
    if (data == null) return;
    final action = data['action'] as String? ?? '';
    final filePath = data['filePath'] as String? ?? '';
    final uri = data['uri'] as String? ?? '';
    final mimeType = data['mimeType'] as String? ?? '';

    if (action == 'OPEN_PLAYER') {
      globalMusicService.setShowNowPlaying(true);
      return;
    }

    if (action != 'android.intent.action.VIEW' || (filePath.isEmpty && uri.isEmpty)) return;

    setState(() {
      _pendingOpenFilePath = filePath.isNotEmpty ? filePath : uri;
      _pendingOpenMimeType = mimeType;
    });
    _openPendingFile();
  }

  void _openPendingFile() {
    final path = _pendingOpenFilePath;
    final mimeType = _pendingOpenMimeType ?? '';
    if (path == null || path.isEmpty) return;
    setState(() => _pendingOpenFilePath = null);

    if (mimeType.contains('pdf') || path.endsWith('.pdf')) {
      _openFile(path);
    } else if (mimeType.contains('epub') || path.endsWith('.epub')) {
      _openFile(path);
    } else if (mimeType.contains('audio') || ['mp3','wav','aac','flac','ogg','m4a','wma','opus'].any((e) => path.endsWith('.$e'))) {
      _playAudioFileFromIntent(path);
    } else if (mimeType.contains('video') || ['mp4','mkv','webm','avi','mov','flv','wmv','3gp'].any((e) => path.endsWith('.$e'))) {
      _openFile(path);
    } else if (mimeType.contains('image') || ['jpg','jpeg','png','gif','webp','bmp','svg'].any((e) => path.endsWith('.$e'))) {
      _openFile(path);
    } else if (mimeType.contains('html') || ['html','htm','xhtml'].any((e) => path.endsWith('.$e'))) {
      _openFile(path);
    } else if (mimeType.contains('text') || ['txt','md','json','xml','yaml','yml','ini','log','csv'].any((e) => path.endsWith('.$e'))) {
      _openFile(path);
    } else if (mimeType.contains('msword') || mimeType.contains('openxmlformats') || path.endsWith('.doc') || path.endsWith('.docx') || path.endsWith('.odt') || path.endsWith('.rtf') || path.endsWith('.pages')) {
      _openFile(path);
    } else {
      OpenFilex.open(path);
    }
  }

  Future<void> _checkUpdatesOnStartup() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    final result = await _updateService.checkForUpdate();
    if (!mounted) return;
    if (result.result == UpdateCheckResult.available && result.info != null) {
      _showUpdateDialog(result.info!);
    }
  }

  Future<void> _requestPermissions() async {
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;

    // Request manage external storage first (separate dialog)
    if (Platform.isAndroid) {
      final sdk = int.tryParse(Platform.operatingSystemVersion.split(' ').first) ?? 0;
      if (sdk >= 30) {
        final status = await Permission.manageExternalStorage.status;
        if (status.isDenied) {
          await Permission.manageExternalStorage.request();
        }
      }
    }

    // Batch request remaining permissions (shows a single system dialog on Android 13+)
    if (!mounted) return;
    final batch = <Permission>[
      Permission.camera,
      Permission.audio,
      Permission.videos,
      Permission.photos,
    ];
    final toRequest = <Permission>[];
    for (final p in batch) {
      if (await p.status.isDenied || await p.status.isRestricted) {
        toRequest.add(p);
      }
    }
    if (toRequest.isNotEmpty) {
      await toRequest.request();
    }
  }

  Future<void> _requestFileAccess() async {
    if (Platform.isAndroid) {
      final sdk = int.tryParse(Platform.operatingSystemVersion.split(' ').first) ?? 0;
      if (sdk >= 30) {
        final status = await Permission.manageExternalStorage.status;
        if (status.isGranted) {
          _showToast('Storage access already granted');
          return;
        }
        final result = await Permission.manageExternalStorage.request();
        if (result.isGranted) {
          _showToast('Storage access granted');
        } else if (result.isPermanentlyDenied) {
          _showToast('Open Settings to grant All Files access');
          openAppSettings();
        } else {
          _showToast('Storage access denied');
        }
      } else {
        final status = await Permission.storage.request();
        if (status.isGranted) {
          _showToast('Storage access granted');
        } else {
          _showToast('Storage access denied');
        }
      }
    } else {
      _showToast('File access not needed on this platform');
    }
  }

  void _initBrowserTab() {
    if (_browserTabs.isNotEmpty) return;
    final id = ++_browserTabIdCounter;
      _browserTabs.add(BrowserTab(id: id, url: ''));
    _activeBrowserTabId = id;
  }

  Future<void> _loadShortcuts() async {
    if (_shortcutsLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('browser_shortcuts');
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _shortcuts = list.map((e) {
          final arr = e as List;
          return (arr[0] as String, arr[1] as String);
        }).toList();
      }
    } catch (_) {}
    if (_shortcuts.isEmpty) {
      _shortcuts = [
        ('jw.org', 'https://jw.org'),
        ('YouTube', 'https://youtube.com'),
        ('Facebook', 'https://facebook.com'),
        ('Instagram', 'https://instagram.com'),
        ('X', 'https://x.com'),
        ('Amazon', 'https://amazon.com'),
        ('ChatGPT', 'https://chatgpt.com'),
        ('Wikipedia', 'https://wikipedia.org'),
        ('WhatsApp', 'https://whatsapp.com'),
        ('Gmail', 'https://mail.google.com'),
        ('Google', 'https://google.com'),
        ('Booking', 'https://booking.com'),
        ('Weather', 'https://accuweather.com'),
        ('o2tvseries', 'https://o2tvseries.com'),
        ('Nkiri', 'https://thenkiri.com'),
        ('Hexadigitall', 'https://hexadigitall.com'),
      ];
    }
    _shortcutsLoaded = true;
  }

  Future<void> _saveShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_shortcuts.map((e) => [e.$1, e.$2]).toList());
    await prefs.setString('browser_shortcuts', raw);
    _exportAppData();
  }

  bool _isCurrentPageBookmarked() {
    final url = _urlController.text.trim();
    return url.isNotEmpty && _shortcuts.any((s) => s.$2 == url);
  }

  void _toggleBookmarkForCurrentPage() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (_isCurrentPageBookmarked()) {
      _shortcuts.removeWhere((s) => s.$2 == url);
      _saveShortcuts();
      _showToast('Bookmark removed');
      setState(() {});
    } else {
      _showAddBookmarkDialog(url);
    }
  }

  void _showAddBookmarkDialog(String url) {
    final titleCtl = TextEditingController(text: url.split('/').last.split('?').first.replaceAll(RegExp(r'[-_]'), ' ') );
    final urlCtl = TextEditingController(text: url);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Add Bookmark', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtl,
              style: TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Name', labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kAccentTeal)),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: urlCtl,
              style: TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'URL', labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kAccentTeal)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAccentTeal),
            onPressed: () {
              final name = titleCtl.text.trim();
              final u = urlCtl.text.trim();
              if (name.isNotEmpty && u.isNotEmpty) {
                _shortcuts.removeWhere((s) => s.$2 == u);
                _shortcuts.insert(0, (name, u));
                _saveShortcuts();
                _showToast('Bookmark added');
                setState(() {});
              }
              Navigator.of(ctx).pop();
            },
            child: Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _initSnippets() {
    _snippets = [
      {'name': 'Flutter StatelessWidget', 'code': 'class MyWidget extends StatelessWidget {\n  @override\n  Widget build(BuildContext context) {\n    return Container();\n  }\n}'},
      {'name': 'Flutter StatefulWidget', 'code': 'class MyWidget extends StatefulWidget {\n  @override\n  _MyWidgetState createState() => _MyWidgetState();\n}\n\nclass _MyWidgetState extends State<MyWidget> {\n  @override\n  Widget build(BuildContext context) {\n    return Container();\n  }\n}'},
      {'name': 'JS Fetch GET', 'code': 'fetch("/api/data")\n  .then(r => r.json())\n  .then(data => console.log(data))\n  .catch(err => console.error(err));'},
      {'name': 'JS Arrow Function', 'code': 'const fn = (args) => {\n  return args;\n};'},
      {'name': 'Python Flask Route', 'code': '@app.route("/api", methods=["GET"])\ndef api():\n    return jsonify({"message": "Hello"})'},
      {'name': 'CSS Flex Center', 'code': '.container {\n  display: flex;\n  justify-content: center;\n  align-items: center;\n}'},
      {'name': 'HTML5 Boilerplate', 'code': '<!DOCTYPE html>\n<html lang="en">\n<head>\n  <meta charset="UTF-8">\n  <meta name="viewport" content="width=device-width, initial-scale=1.0">\n  <title>Document</title>\n</head>\n<body>\n\n</body>\n</html>'},
    ];
  }

  String detectLanguage(String name) {
    final ext = p.extension(name).replaceAll('.', '').toLowerCase();
    final map = {
      'dart': 'dart', 'py': 'python', 'js': 'javascript', 'ts': 'typescript',
      'html': 'html', 'htm': 'html', 'css': 'css', 'json': 'json',
      'yaml': 'yaml', 'yml': 'yaml', 'md': 'markdown', 'xml': 'html',
      'txt': 'plaintext', 'c': 'c', 'cpp': 'cpp', 'h': 'c', 'java': 'java',
      'rb': 'ruby', 'go': 'go', 'rs': 'rust', 'sh': 'shell', 'sql': 'sql',
    };
    return map[ext] ?? 'javascript';
  }

  // ─── DB ─────────────────────────────────────────────────────────────────────

  Future<void> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    _projectPath = p.join(dir.path, 'makaw_projects');
    await Directory(_projectPath).create(recursive: true);

    _db = await openDatabase(
      p.join(dir.path, 'makaw.db'),
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE projects (
            id INTEGER PRIMARY KEY,
            name TEXT,
            content TEXT,
            language TEXT,
            path TEXT,
            updated_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            title TEXT,
            time TEXT NOT NULL,
            favicon_url TEXT,
            UNIQUE(url)
          )
        ''');
        await db.execute('CREATE INDEX idx_history_time ON history(time DESC)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              url TEXT NOT NULL,
              title TEXT,
              time TEXT NOT NULL,
              UNIQUE(url)
            )
          ''');
        }
        if (oldVersion < 3) {
          try {
            await db.execute('ALTER TABLE history ADD COLUMN favicon_url TEXT');
          } catch (_) {}
          try {
            await db.execute('CREATE INDEX IF NOT EXISTS idx_history_time ON history(time DESC)');
          } catch (_) {}
        }
      },
    );
    HistoryService.init(_db!);
    _preseedGoogleConsentCookies();
    _loadProjects();
    _loadHistory();
    HistoryService.pruneOldEntries().catchError((_) {});
  }

  Future<void> _preseedGoogleConsentCookies() async {
    try {
      final cm = CookieManager.instance();
      final existing = await cm.getCookies(url: WebUri('https://www.google.com'));
      final hasSOCS = existing.any((c) => c.name == 'SOCS');
      if (!hasSOCS) {
        await cm.setCookie(
          url: WebUri('https://www.google.com'),
          name: 'SOCS',
          value: 'CAISHAgBEhJnd3NfMjAyNDA0MTYtMF9SQzEgGgJlbiAEGgIgAQ',
          domain: '.google.com',
          path: '/',
          isSecure: true,
        );
      }
    } catch (_) {}
  }

  Future<void> _loadProjects() async {
    final data = await _db!.query('projects', orderBy: 'updated_at DESC');
    setState(() => _projects = data);
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await _db!.query('history', orderBy: 'time DESC', limit: 500);
      setState(() {
        _browserHistory = rows.map<Map<String, dynamic>>((r) => <String, dynamic>{
          'url': r['url'] as String? ?? '',
          'title': r['title'] as String? ?? '',
          'time': r['time'] as String? ?? '',
        }).toList();
      });
    } catch (_) {}
  }

  Future<void> _loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final tabsJson = prefs.getString('saved_tabs');
    if (tabsJson != null) {
      try {
        final tabs = jsonDecode(tabsJson) as List;
        if (tabs.isNotEmpty) {
          _browserTabs.clear();
          for (final t in tabs) {
            final isIncognito = t['incognito'] as bool? ?? false;
            if (isIncognito) continue;
            final id = DateTime.now().microsecondsSinceEpoch + _browserTabs.length;
            _browserTabs.add(BrowserTab(
              id: id,
              url: t['url'] as String? ?? '',
              title: t['title'] as String? ?? '',
              incognito: false,
              historyStack: (t['historyStack'] as List<dynamic>?)?.cast<String>() ?? [],
              historyIndex: t['historyIndex'] as int? ?? 0,
            ));
            setState(() {});
          }
          if (_browserTabs.isNotEmpty) {
            final activeId = prefs.getInt('active_tab_id');
            if (activeId != null) {
              final idx = _browserTabs.indexWhere((t) => t.id == activeId);
              _activeBrowserTabId = idx >= 0 ? activeId : _browserTabs.first.id;
            } else {
              _activeBrowserTabId = _browserTabs.first.id;
            }
          }
        }
      } catch (_) {}
    }
    if (_browserTabs.isEmpty) {
      _initBrowserTab();
    }
  }

  Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTabs = _browserTabs.where((t) => !t.incognito).toList();
    final tabsJson = jsonEncode(savedTabs.map((t) => {
      'url': t.url,
      'title': t.title,
      'incognito': t.incognito,
      'historyStack': t.historyStack,
      'historyIndex': t.historyIndex,
    }).toList());
    await prefs.setString('saved_tabs', tabsJson);
    final activeTab = _activeTab;
    await prefs.setInt('active_tab_id', activeTab.incognito ? (savedTabs.isNotEmpty ? savedTabs.first.id : 0) : _activeBrowserTabId);
  }

  // ─── Terminal ───────────────────────────────────────────────────────────────

  void _startPty() {
    if (kIsWeb) return;
    if (_pty != null) return;
    _pty = Pty.start(
      Platform.isAndroid ? 'sh' : 'bash',
      arguments: Platform.isAndroid ? ['-c', 'cd /storage/emulated/0 && sh'] : [],
      environment: {'TERM': 'xterm-256color'},
      workingDirectory: _projectPath,
    );
    _pty!.output.cast<List<int>>().transform(const Utf8Decoder()).listen(_terminal.write);
    _pty!.exitCode.then((code) => _terminal.write('Process exited: $code\n'));
    _terminal.onOutput = (data) {
      _pty!.write(const Utf8Encoder().convert(data));
    };
  }

  // ─── Browser Tabs ───────────────────────────────────────────────────────────

  BrowserTab get _activeBrowserTab =>
      _browserTabs.isNotEmpty ? _browserTabs.firstWhere((t) => t.id == _activeBrowserTabId, orElse: () => _browserTabs.first) : BrowserTab(id: 0, url: '');

  InAppWebViewController? get _activeWebview => _tabControllers[_activeBrowserTabId];

  BrowserTab get _activeTab =>
      _browserTabs.isNotEmpty
          ? _browserTabs.firstWhere((t) => t.id == _activeBrowserTabId, orElse: () => _browserTabs.first)
          : BrowserTab(id: 0, url: '');

  void _warmUpDns(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) {
        InternetAddress.lookup(uri.host).catchError((_) {});
      }
    } catch (_) {}
  }

  void _createBrowserTab({bool incognito = false, String? url}) {
    final id = ++_browserTabIdCounter;
    final tab = BrowserTab(id: id, url: url ?? '', incognito: incognito, title: incognito ? 'Incognito' : 'New Tab');
    setState(() {
      _browserTabs.add(tab);
      _activeBrowserTabId = id;
      _tabProgress[id] = 0;
      _viewMode = url != null && url.isNotEmpty ? ViewMode.browsing : ViewMode.newTab;
    });
    _urlController.clear();
    _syncUrlController();
    _saveSession();
  }


  Future<void> _captureCurrentTabSnapshot() async {
    final c = _activeWebview;
    if (c == null) return;
    final tab = _activeTab;
    if (tab.incognito || tab.url.isEmpty) return;
    try {
      final data = await c.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
          compressFormat: CompressFormat.JPEG,
          quality: 80,
        ),
      );
      if (data != null) {
        _tabSnapshots[tab.id] = data;
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/tab_snapshots/${tab.id}.jpg');
        await file.create(recursive: true);
        await file.writeAsBytes(data);
        final idx = _browserTabs.indexWhere((t) => t.id == tab.id);
        if (idx >= 0) _browserTabs[idx].snapshotPath = file.path;
      }
    } catch (_) {}
  }

  void _showBrowsingView() {
    setState(() {
      _viewMode = ViewMode.typeView;
    });
  }

  Future<void> _switchBrowserTab(int id) async {
    if (id == _activeBrowserTabId) {
      final tab = _browserTabs.firstWhere((t) => t.id == id, orElse: () => _browserTabs.first);
      if (!tab.isEmpty && _showHomeScreen) {
        setState(() { _viewMode = ViewMode.browsing; });
        _syncUrlController();
      }
      return;
    }
    _urlFocusNode.unfocus();
    _captureCurrentTabSnapshot();
    final tab = _browserTabs.firstWhere((t) => t.id == id, orElse: () => _browserTabs.first);
    setState(() {
      _activeBrowserTabId = id;
      if (!tab.isEmpty) {
        _viewMode = ViewMode.browsing;
      } else {
        _viewMode = ViewMode.newTab;
      }
    });
    _syncUrlController();
  }

  void _closeBrowserTab(int id) {
    final idx = _browserTabs.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      final tab = _browserTabs[idx];
      if (tab.url.isNotEmpty && !tab.incognito) {
        _recentTabs.removeWhere((t) => t['url'] == tab.url);
        _recentTabs.insert(0, {'url': tab.url, 'title': tab.title});
        if (_recentTabs.length > _maxRecentTabs) _recentTabs.removeLast();
      }
    }
    _tabSnapshots.remove(id);
    _tabProgress.remove(id);
    _tabControllers.remove(id);
    setState(() {
      _browserTabs.removeWhere((t) => t.id == id);
      if (_browserTabs.isEmpty) {
        _goHome();
        _activeBrowserTabId = 0;
      } else if (_activeBrowserTabId == id) {
        final next = _browserTabs[idx > 0 ? idx - 1 : 0];
        _activeBrowserTabId = next.id;
        _viewMode = !next.isEmpty ? ViewMode.browsing : ViewMode.newTab;
      }
    });
    _syncUrlController();
    _saveSession();
  }

  void _onBrowserNavigation(String url) {
    if (url.isEmpty || url == 'about:blank') return;
    final tab = _activeTab;
    if (tab.url == url && tab.url.isNotEmpty) return;
    tab.url = url;
    tab.title = url;
    tab.pushHistory(url);
    _suggestDebounce?.cancel();
    _ignoreUrlChanges = true;
    if (!_showHomeScreen) _urlController.text = url;
    _ignoreUrlChanges = false;
    _addHistoryEntry(url, url);
    _saveSession();
    setState(() {
      _viewMode = ViewMode.browsing;
      _urlSuggestions = [];
      _searchSuggestions = [];
      _suggestions = [];
    });
  }

  void _syncUrlController() {
    if (_browserTabs.isEmpty) { _urlController.text = ''; return; }
    final tab = _browserTabs.firstWhere((t) => t.id == _activeBrowserTabId, orElse: () => _browserTabs.first);
    _suggestDebounce?.cancel();
    _ignoreUrlChanges = true;
    if (!_showHomeScreen) {
      _urlController.text = tab.url.isEmpty ? '' : tab.url;
    }
    _ignoreUrlChanges = false;
    setState(() {
      _urlSuggestions = [];
      _searchSuggestions = [];
      _suggestions = [];
    });
  }

  void _addHistoryEntry(String url, String title) {
    if (_activeTab.incognito) return;
    final existing = _browserHistory.indexWhere((e) => e['url'] == url);
    if (existing >= 0) {
      final entry = _browserHistory.removeAt(existing);
      final count = (entry['visit_count'] as int? ?? 1) + 1;
      entry['time'] = DateTime.now().toIso8601String();
      entry['visit_count'] = count;
      _browserHistory.insert(0, entry);
    } else {
      _browserHistory.insert(0, <String, dynamic>{'url': url, 'title': title, 'time': DateTime.now().toIso8601String(), 'visit_count': 1});
    }
    if (_browserHistory.length > 500) _browserHistory.removeRange(500, _browserHistory.length);
    HistoryService.addEntry(HistoryItem(
      url: url,
      title: title,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    )).catchError((_) {});
  }

  void _updateHistoryTitle(String url, String title) {
    final idx = _browserHistory.indexWhere((e) => e['url'] == url);
    if (idx >= 0) _browserHistory[idx]['title'] = title;
    HistoryService.updateTitle(url, title).catchError((_) {});
  }

  void _navigateToUrl(String raw) {
    String url;
    if (raw.contains(' ') || (!raw.contains('.') && !raw.contains('://'))) {
      url = 'https://www.google.com/search?q=${Uri.encodeComponent(raw)}';
    } else {
      url = raw.startsWith('http://') || raw.startsWith('https://') ? raw : 'https://$raw';
    }

    _suggestDebounce?.cancel();
    _warmUpDns(url);
    if (_browserTabs.isEmpty) {
      final id = ++_browserTabIdCounter;
      final tab = BrowserTab(id: id, url: url, incognito: false);
      tab.pushHistory(url);
      _ignoreUrlChanges = true;
      _urlController.text = url;
      _ignoreUrlChanges = false;
      setState(() {
        _browserTabs.add(tab);
        _activeBrowserTabId = id;
        _viewMode = ViewMode.browsing;
        _urlSuggestions = [];
        _searchSuggestions = [];
        _suggestions = [];
      });
    } else {
      final tab = _activeTab;
      tab.url = url;
      tab.title = url;
      tab.pushHistory(url);
      _ignoreUrlChanges = true;
      _urlController.text = url;
      _ignoreUrlChanges = false;
      setState(() {
        _viewMode = ViewMode.browsing;
        _urlSuggestions = [];
        _searchSuggestions = [];
        _suggestions = [];
      });
    }
    _addHistoryEntry(url, url);
    _saveSession();
    final c = _activeWebview;
    if (c != null) {
      c.loadUrl(urlRequest: URLRequest(url: WebUri(url))).catchError((_) {});
    }
  }

  void _typeViewNavigate(String raw) {
    if (_typeViewFromHome) {
      _navigateOrOpenNewTab(raw);
    } else {
      _navigateInCurrentTab(raw);
    }
  }

  void _navigateInCurrentTab(String raw) {
    String url;
    if (raw.contains(' ') || (!raw.contains('.') && !raw.contains('://'))) {
      url = 'https://www.google.com/search?q=${Uri.encodeComponent(raw)}';
    } else {
      url = raw.startsWith('http://') || raw.startsWith('https://') ? raw : 'https://$raw';
    }
    _suggestDebounce?.cancel();
    _urlFocusNode.unfocus();
    _ignoreUrlChanges = true;
    _urlController.text = url;
    _ignoreUrlChanges = false;
    if (_browserTabs.isEmpty) {
      _navigateOrOpenNewTab(raw);
      return;
    }
    final tab = _activeTab;
    tab.url = url;
    tab.title = url;
    tab.pushHistory(url);
    _warmUpDns(url);
    setState(() {
      _viewMode = ViewMode.browsing;
      _urlSuggestions = [];
      _searchSuggestions = [];
      _suggestions = [];
    });
    _addHistoryEntry(url, url);
    _saveSession();
    final c = _activeWebview;
    if (c != null) {
      c.loadUrl(urlRequest: URLRequest(url: WebUri(url))).catchError((_) {});
    }
  }

  void _navigateOrOpenNewTab(String raw) {
    String url;
    if (raw.contains(' ') || (!raw.contains('.') && !raw.contains('://'))) {
      url = 'https://www.google.com/search?q=${Uri.encodeComponent(raw)}';
    } else {
      url = raw.startsWith('http://') || raw.startsWith('https://') ? raw : 'https://$raw';
    }

    if (_browserTabs.isEmpty) {
      _createBrowserTab(url: url);
      final tab = _activeTab;
      tab.pushHistory(url);
      _suggestDebounce?.cancel();
      _urlFocusNode.unfocus();
      _ignoreUrlChanges = true;
      _urlController.text = url;
      _ignoreUrlChanges = false;
      _warmUpDns(url);
      setState(() {
        _viewMode = ViewMode.browsing;
        _urlSuggestions = [];
        _searchSuggestions = [];
      });
      _addHistoryEntry(url, url);
      _saveSession();
      return;
    }

    final tab = _activeTab;
    final isNtp = tab.url.isEmpty || tab.url == 'about:blank';

    if (isNtp) {
      tab.url = url;
      tab.title = url;
      tab.pushHistory(url);
      _suggestDebounce?.cancel();
      _urlFocusNode.unfocus();
      _ignoreUrlChanges = true;
      _urlController.text = url;
      _ignoreUrlChanges = false;
      _warmUpDns(url);
      setState(() {
        _viewMode = ViewMode.browsing;
        _urlSuggestions = [];
        _searchSuggestions = [];
      });
      _addHistoryEntry(url, url);
      _saveSession();
      final c = _activeWebview;
      if (c != null) {
        c.loadUrl(urlRequest: URLRequest(url: WebUri(url))).catchError((_) {});
      }
    } else {
      _createBrowserTab(url: url);
      final newTab = _activeTab;
      newTab.pushHistory(url);
      _suggestDebounce?.cancel();
      _urlFocusNode.unfocus();
      _ignoreUrlChanges = true;
      _urlController.text = url;
      _ignoreUrlChanges = false;
      _warmUpDns(url);
      setState(() {
        _viewMode = ViewMode.browsing;
        _urlSuggestions = [];
        _searchSuggestions = [];
      });
      _addHistoryEntry(url, url);
      _saveSession();
    }
  }

  Future<void> _showTabSwitcher() async {
    await _captureCurrentTabSnapshot();
    if (!mounted) return;
    if (_browserTabs.isEmpty) {
      _createBrowserTab();
      return;
    }
    final activeTab = _browserTabs.firstWhere(
      (t) => t.id == _activeBrowserTabId,
      orElse: () => _browserTabs.first,
    );
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => TabTrayPage(
          tabs: _browserTabs,
          activeTabId: _activeBrowserTabId,
          snapshots: _tabSnapshots,
          initialIsIncognito: activeTab.incognito,
          onSwitchTab: (id) {
            _switchBrowserTab(id);
          },
          onCloseTab: (id) {
            _closeBrowserTab(id);
          },
          onCreateTab: () {
            _createBrowserTab();
            Navigator.of(context).pop();
          },
          onCreateIncognitoTab: () {
            _createBrowserTab(incognito: true);
            Navigator.of(context).pop();
          },
        ),
        transitionDuration: Duration(milliseconds: 200),
        reverseTransitionDuration: Duration(milliseconds: 150),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(begin: Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  // ─── Media Sniffer ──────────────────────────────────────────────────────────

  void _onMediaDetected(String url, String type) {
    setState(() {
      _pendingMedia.add(MediaItem(url: url, type: type));
    });
  }

  void _showMediaSnifferPage() {
    if (_pendingMedia.isEmpty) return;
    final items = List<MediaItem>.from(_pendingMedia);

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      isScrollControlled: true,
      isDismissible: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(0))),
      builder: (ctx) => MediaSnifferPage(
        items: items,
        showToast: _showToast,
        onDownload: (item) {
          _downloadManager.enqueue(item.url, filename: item.url.split('/').last.split('?').first);
          setState(() {});
        },
        onDownloadAll: (items) {
          for (final item in items) {
            _downloadManager.enqueue(item.url, filename: item.url.split('/').last.split('?').first);
            _pendingMedia.removeWhere((m) => m.url == item.url);
          }
          _showToast('Downloading ${items.length} item(s)');
          setState(() {});
        },
        onClear: () {
          _pendingMedia.clear();
          setState(() {});
        },
        onRename: (oldItem, newName) {
          final idx = _pendingMedia.indexWhere((m) => m.url == oldItem.url);
          if (idx >= 0) {
            final old = _pendingMedia[idx];
            _pendingMedia[idx] = MediaItem(url: old.url, type: old.type, title: newName, formats: old.formats);
            setState(() {});
          }
        },
      ),
    );
  }

  // ─── Theme ───────────────────────────────────────────────────────────────────

  void _cycleTheme() {
    final modes = ['dark', 'light', 'system'];
    final idx = modes.indexOf(widget.themeMode);
    final newMode = modes[(idx + 1) % modes.length];
    widget.onThemeChanged?.call(newMode);
    _exportAppData();
  }

  // ─── Updates ─────────────────────────────────────────────────────────────────

  Future<void> _checkForUpdatesManual() async {
    _showToast('Checking for updates...');
    final result = await _updateService.checkForUpdate();
    if (!mounted) return;
    switch (result.result) {
      case UpdateCheckResult.available:
        _showUpdateDialog(result.info!);
      case UpdateCheckResult.upToDate:
        _showToast('Already up to date');
      case UpdateCheckResult.error:
        _showToast('Update check failed: ${result.error}');
    }
  }

  void _showUpdateDialog(UpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: !info.mandatory,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF1E293B),
        title: Row(
          children: [
            Icon(Icons.system_update, color: Color(0xFF818CF8)),
            SizedBox(width: 8),
            Expanded(child: Text('Update Available', style: TextStyle(fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${info.versionName} (build ${info.versionCode})',
                style: TextStyle(fontWeight: FontWeight.bold)),
            if (info.releaseNotes.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(info.releaseNotes, style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
            SizedBox(height: 12),
            if (info.mandatory)
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red, size: 16),
                    SizedBox(width: 6),
                    Expanded(child: Text('This update is required to continue using the app.',
                        style: TextStyle(color: Colors.red[200], fontSize: 12))),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          if (!info.mandatory)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Later', style: TextStyle(color: Colors.grey)),
            ),
          ElevatedButton.icon(
            icon: Icon(Icons.download, size: 16),
            label: Text('Update'),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAndInstallUpdate(info);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF818CF8),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstallUpdate(UpdateInfo info) async {
    final scaffold = ScaffoldMessenger.of(context);
    double progress = 0;
    final progressController = StreamController<double>.broadcast();

    final dialogCtx = showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          progressController.stream.listen((p) {
            if (ctx.mounted) {
              setDialogState(() => progress = p);
            }
          });
          return AlertDialog(
            backgroundColor: Color(0xFF1E293B),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF818CF8),
                        value: progress > 0 ? progress : null,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        progress > 0
                            ? 'Downloading ${(progress * 100).toInt()}%...'
                            : 'Downloading update...',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                if (progress > 0) ...[
                  SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[800],
                    color: Color(0xFF818CF8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );

    final path = await _updateService.downloadApk(
      info,
      onProgress: (received, total) {
        if (total > 0) {
          final p = (received / total).clamp(0.0, 1.0);
          progressController.add(p);
        }
      },
    );

    await progressController.close();
    if (mounted) Navigator.of(context).pop();

    if (!mounted) return;
    if (path == null) {
      scaffold.showSnackBar(SnackBar(content: Text('Download failed')));
      return;
    }

    scaffold.showSnackBar(SnackBar(content: Text('Installing...')));
    final installed = await _updateService.installApk(path);
    if (!installed) {
      scaffold.showSnackBar(SnackBar(
        content: Text('Tap the notification or open the APK from downloads to install.'),
        duration: Duration(seconds: 5),
      ));
    }
  }

  // ─── Editor ──────────────────────────────────────────────────────────────────

  void _openFileInEditor(String name, String content, {String? language}) {
    final existing = _openFiles.indexWhere((f) => f.name == name);
    if (existing >= 0) {
      setState(() => _activeFileId = _openFiles[existing].id);
      _loadFileInMonaco(_openFiles[existing]);
      return;
    }
    final id = ++_fileIdCounter;
    final file = EditorFile(id: id, name: name, content: content, language: language ?? detectLanguage(name));
    setState(() {
      _openFiles.add(file);
      _activeFileId = id;
    });
    _loadFileInMonaco(file);
  }

  void _loadFileInMonaco(EditorFile file) {
    final escaped = file.content.replaceAll('\\', '\\\\').replaceAll('`', '\\`').replaceAll(r'$', r'\$');
    _monacoController?.evaluateJavascript(source: '''
      window.editor.getModel().setValue(`$escaped`);
      monaco.editor.setModelLanguage(window.editor.getModel(), '${file.language}');
    ''');
  }

  void _closeEditorFile(int id) {
    if (_openFiles.length <= 1) return;
    final idx = _openFiles.indexWhere((f) => f.id == id);
    setState(() {
      _openFiles.removeWhere((f) => f.id == id);
      if (_activeFileId == id) {
        final next = _openFiles[idx > 0 ? idx - 1 : 0];
        _activeFileId = next.id;
        _loadFileInMonaco(next);
      }
    });
  }

  Future<void> _saveProject() async {
    final code = await _monacoController?.evaluateJavascript(source: "window.editor.getValue()");
    final ext = _currentLang == 'dart' ? 'dart' : _currentLang == 'python' ? 'py' : _currentLang == 'typescript' ? 'ts' : _currentLang;
    final path = p.join(_projectPath, '$_currentProject.$ext');
    await File(path).writeAsString(code ?? '');
    await _db!.insert('projects', {
      'name': _currentProject,
      'content': code,
      'language': _currentLang,
      'path': path,
      'updated_at': DateTime.now().toIso8601String()
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Mark file clean
    final af = _openFiles.where((f) => f.id == _activeFileId);
    if (af.isNotEmpty) af.first.dirty = false;

    _loadProjects();
    _showToast('Saved');
  }

  Future<void> _runPreview() async {
    final code = await _monacoController?.evaluateJavascript(source: "window.editor.getValue()");
    String html = code ?? '';
    if (_currentLang == 'javascript' || _currentLang == 'typescript') {
      html = '<!DOCTYPE html><html><body><script type="module">$html</script></body></html>';
    } else if (_currentLang == 'css') {
      html = '<!DOCTYPE html><html><head><style>$html</style></head><body><h1>CSS Preview</h1></body></html>';
    } else if (_currentLang == 'dart') {
      html = '<!DOCTYPE html><html><body><pre>$html</pre></body></html>';
    }
    final uri = Uri.dataFromString(html, mimeType: 'text/html', encoding: utf8);
    await _activeWebview?.loadUrl(urlRequest: URLRequest(url: WebUri(uri.toString())));
    _switchToView('browser');
  }

  Future<void> _formatCode() async {
    await _monacoController?.evaluateJavascript(source: "window.editor.getAction('editor.action.formatDocument').run()");
    _showToast('Formatted');
  }

  // ─── Git Functions ──────────────────────────────────────────────────────────

  Future<void> _gitStatus() async {
    try {
      final git = await GitDir.fromExisting(_projectPath);
      final result = await git.runCommand(['status', '--porcelain']);
      setState(() => _gitOutput = result.stdout.toString());
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitLog() async {
    try {
      final git = await GitDir.fromExisting(_projectPath);
      final result = await git.runCommand(['log', '--oneline', '-10']);
      setState(() => _gitOutput = result.stdout.toString());
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitDiff() async {
    try {
      final git = await GitDir.fromExisting(_projectPath);
      final result = await git.runCommand(['diff']);
      setState(() => _gitOutput = result.stdout.toString());
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitCommit() async {
    try {
      final git = await GitDir.fromExisting(_projectPath);
      await git.runCommand(['add', '.']);
      await git.runCommand(['commit', '-m', 'Update from Makaw Mobile']);
      setState(() => _gitOutput = 'Committed');
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _refreshBranches() async {
    try {
      final git = await GitDir.fromExisting(_projectPath);
      final result = await git.runCommand(['branch']);
      final branches = result.stdout.toString().split('\n').where((b) => b.isNotEmpty).map((b) => b.trim().replaceAll('* ', '')).toList();
      final current = branches.firstWhere((b) => result.stdout.toString().contains('* $b'), orElse: () => '');
      setState(() {
        _branches = branches.cast<String>();
        _currentBranch = current;
      });
    } catch (e) {}
  }

  Future<void> _gitCheckout(String branch) async {
    try {
      final git = await GitDir.fromExisting(_projectPath);
      await git.runCommand(['checkout', branch]);
      _refreshBranches();
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitCreateBranch() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New Branch'),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: 'Branch name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final git = await GitDir.fromExisting(_projectPath);
      await git.runCommand(['branch', name]);
      setState(() => _gitOutput = 'Created branch $name');
      _refreshBranches();
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitStash() async {
    try {
      final git = await GitDir.fromExisting(_projectPath);
      await git.runCommand(['stash']);
      setState(() => _gitOutput = 'Stashed');
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitStashPop() async {
    try {
      final git = await GitDir.fromExisting(_projectPath);
      await git.runCommand(['stash', 'pop']);
      setState(() => _gitOutput = 'Stash popped');
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitPush() async {
    try {
      final git = await GitDir.fromExisting(_projectPath);
      await git.runCommand(['push']);
      setState(() => _gitOutput = 'Pushed');
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitPull() async {
    try {
      final git = await GitDir.fromExisting(_projectPath);
      await git.runCommand(['pull']);
      setState(() => _gitOutput = 'Pulled');
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitFetch() async {
    try {
      final git = await GitDir.fromExisting(_projectPath);
      await git.runCommand(['fetch']);
      setState(() => _gitOutput = 'Fetched');
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitAddRemote() async {
    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController(text: 'origin');
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Remote'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: InputDecoration(labelText: 'Name', hintText: 'origin')),
          TextField(controller: urlCtrl, decoration: InputDecoration(labelText: 'URL', hintText: 'https://...')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, urlCtrl.text), child: Text('Add')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      final git = await GitDir.fromExisting(_projectPath);
      await git.runCommand(['remote', 'add', nameCtrl.text, url]);
      setState(() => _gitOutput = 'Added remote ${nameCtrl.text}');
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitTag() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New Tag'),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: 'v1.0.0')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final git = await GitDir.fromExisting(_projectPath);
      await git.runCommand(['tag', name]);
      setState(() => _gitOutput = 'Created tag $name');
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset Hard?'),
        content: Text('This will discard all uncommitted changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Reset'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red)),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final git = await GitDir.fromExisting(_projectPath);
      await git.runCommand(['reset', '--hard']);
      setState(() => _gitOutput = 'Reset hard');
    } catch (e) {
      setState(() => _gitOutput = 'Error: $e');
    }
  }

  Future<void> _gitMerge(String branch) async {
    try {
      final git = await GitDir.fromExisting(_projectPath);
      await git.runCommand(['merge', branch]);
      setState(() => _gitOutput = 'Merged $branch');
      _refreshBranches();
    } catch (e) {
      if (e.toString().contains('CONFLICT')) {
        final git = await GitDir.fromExisting(_projectPath);
        final status = await git.runCommand(['status', '--porcelain']);
        final conflicts = status.stdout.toString().split('\n').where((l) => l.startsWith('UU ')).map((l) => l.substring(3)).toList();
        setState(() {
          _conflictedFiles = conflicts;
          _gitOutput = 'Merge conflicts in: ${conflicts.join(', ')}';
        });
        _showConflictResolver(conflicts.first);
      } else {
        setState(() => _gitOutput = 'Error: $e');
      }
    }
  }

  Future<void> _showConflictResolver(String file) async {
    final filePath = p.join(_projectPath, file);
    final content = await File(filePath).readAsString();
    final parts = _parseConflictMarkers(content);
    if (parts.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.all(10),
        child: Container(
          height: MediaQuery.of(ctx).size.height * 0.9,
          child: Column(
            children: [
              AppBar(title: Text('Resolve: $file'), automaticallyImplyLeading: false, actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: TextStyle(color: Colors.white)))
              ]),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildConflictEditor('Ours', parts[0].ours, file, true)),
                    Expanded(child: _buildConflictEditor('Theirs', parts[0].theirs, file, false)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConflictEditor(String side, String content, String file, bool isOurs) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          color: Color(0xFF1E293B),
          child: Text(side, style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: InAppWebView(
            initialData: InAppWebViewInitialData(data: _monacoConflictHtml(content, isOurs ? 'javascript' : 'typescript')),
            onWebViewCreated: (c) async {
              await Future.delayed(Duration(milliseconds: 500));
            },
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: isOurs ? Colors.green : Colors.blue),
          onPressed: () async {
            await File(p.join(_projectPath, file)).writeAsString(content);
            final git = await GitDir.fromExisting(_projectPath);
            await git.runCommand(['add', file]);
            Navigator.pop(context);
            _checkRemainingConflicts();
          },
          child: Text('Accept $side'),
        ),
      ],
    );
  }

  List<ConflictPart> _parseConflictMarkers(String content) {
    final lines = content.split('\n');
    final parts = <ConflictPart>[];
    ConflictPart? current;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('<<<<<<<')) {
        current = ConflictPart();
      } else if (lines[i].startsWith('=======')) {
        current?.inTheirs = true;
      } else if (lines[i].startsWith('>>>>>>>')) {
        if (current != null) parts.add(current);
        current = null;
      } else if (current != null) {
        if (current.inTheirs) current.theirs += lines[i] + '\n';
        else current.ours += lines[i] + '\n';
      }
    }
    return parts;
  }

  Future<void> _checkRemainingConflicts() async {
    final git = await GitDir.fromExisting(_projectPath);
    final status = await git.runCommand(['status', '--porcelain']);
    final remaining = status.stdout.toString().split('\n').where((l) => l.startsWith('UU ')).toList();
    if (remaining.isEmpty) {
      setState(() => _gitOutput = 'All conflicts resolved. Commit to complete merge.');
    }
  }

  // ─── Cloud Sync: Google Drive ──────────────────────────────────────────────

  Future<void> _backupToDrive() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return;
      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) return;
      final driveApi = drive.DriveApi(authClient);

      final dbFile = File(p.join((await getApplicationDocumentsDirectory()).path, 'makaw.db'));
      final media = drive.Media(dbFile.openRead(), dbFile.lengthSync());
      final driveFile = drive.File()..name = 'makaw.db';

      await driveApi.files.create(driveFile, uploadMedia: media);
      _showToast('Backed up to Google Drive');
    } catch (e) {
      setState(() => _gitOutput = 'Drive error: $e');
    }
  }

  Future<void> _restoreFromDrive() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return;
      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) return;
      final driveApi = drive.DriveApi(authClient);

      final files = await driveApi.files.list(q: "name='makaw.db'");
      if (files.files?.isEmpty ?? true) {
        _showToast('No backup found');
        return;
      }

      final fileId = files.files!.first.id!;
      final media = await driveApi.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final dbPath = p.join((await getApplicationDocumentsDirectory()).path, 'makaw.db');
      final outFile = File(dbPath);
      final sink = outFile.openWrite();
      await media.stream.pipe(sink);
      await sink.close();

      await _initDb();
      _showToast('Restored from Google Drive');
    } catch (e) {
      setState(() => _gitOutput = 'Restore error: $e');
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  String _cachedDownloadDir = '';
  String _downloadLocation = '';
  String _defaultDownloadDir() => _downloadLocation.isNotEmpty ? _downloadLocation : _cachedDownloadDir;

  /// Returns a path on public external storage that survives uninstall/reinstall.
  /// Falls back to app-specific external storage, then documents dir.
  Future<String> _getPublicStoragePath(String subfolder) async {
    // Try public Downloads folder (survives uninstall with MANAGE_EXTERNAL_STORAGE)
    if (Platform.isAndroid) {
      for (final base in ['/storage/emulated/0/Download', '/sdcard/Download', '/storage/emulated/0/Downloads']) {
        final dir = Directory('$base/Makaw');
        try {
          await dir.create(recursive: true);
          if (await dir.exists()) {
            return p.join(dir.path, subfolder);
          }
        } catch (_) {}
      }
    }
    // Fallback: app-external storage (will NOT survive uninstall)
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final dir = Directory(p.join(ext.path, 'Makaw'));
        await dir.create(recursive: true);
        return p.join(dir.path, subfolder);
      }
    } catch (_) {}
    // Final fallback: documents directory
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(dir.path, 'Makaw'));
    await d.create(recursive: true);
    return p.join(d.path, subfolder);
  }

  Future<void> _initDownloadDir() async {
    final prefs = await SharedPreferences.getInstance();
    _downloadLocation = prefs.getString('download_location') ?? '';
    if (_downloadLocation.isNotEmpty && await Directory(_downloadLocation).exists()) {
      _cachedDownloadDir = _downloadLocation;
    } else {
      _cachedDownloadDir = await _getPublicStoragePath('MakawDownloads');
      final d = Directory(_cachedDownloadDir);
      if (!await d.exists()) await d.create(recursive: true);
    }
    await _importAppData();
  }

  /// Export all user data to JSON file in the public Makaw folder.
  Future<void> _exportAppData() async {
    try {
      final dataDir = await _getPublicStoragePath('');
      final file = File(p.join(dataDir, 'makaw_data.json'));
      final data = {
        'shortcuts': _shortcuts.map((s) => [s.$1, s.$2]).toList(),
        'history': _browserHistory,
        'themeMode': widget.themeMode,
        'downloadLocation': _downloadLocation,
        'exportedAt': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  /// Import all user data from JSON file in the public Makaw folder.
  Future<void> _importAppData() async {
    try {
      final dataDir = await _getPublicStoragePath('');
      final file = File(p.join(dataDir, 'makaw_data.json'));
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['shortcuts'] is List && (_shortcuts.isEmpty || !_shortcutsLoaded)) {
        _shortcuts = (data['shortcuts'] as List).map((e) {
          final arr = e as List;
          return (arr[0] as String, arr[1] as String);
        }).toList();
        _shortcutsLoaded = true;
      }
      if (data['history'] is List && _browserHistory.isEmpty) {
        _browserHistory.addAll((data['history'] as List).cast<Map<String, dynamic>>());
      }
      if (data['themeMode'] is String) {
        widget.onThemeChanged?.call(data['themeMode'] as String);
      }
    } catch (_) {}
  }

  Future<void> _reloadCurrentPage() async {
    final c = _activeWebview;
    if (c == null) return;
    c.reload();
  }

  void _showFindInPage() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Find in Page', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _findController,
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Search...',
            hintStyle: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6)),
            filled: true,
            fillColor: Theme.of(ctx).cardColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
          onSubmitted: (q) {
            if (q.isNotEmpty) {
              _activeWebview?.findAllAsync(find: q);
            }
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6)))),
        ],
      ),
    );
  }

  void _applyDesktopSite(bool enable) {
    final c = _activeWebview;
    if (c == null) return;
    if (enable) {
      c.setSettings(settings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      ));
    } else {
      c.setSettings(settings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: _stealthUA,
      ));
    }
    c.reload();
  }

  void _showRecentTabs() {
    if (_recentTabs.isEmpty) {
      _showToast('No recent tabs');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.only(top: 8),
              width: 32, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('Recent Tabs', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _recentTabs.length,
                itemBuilder: (_, i) {
                  final tab = _recentTabs[i];
                  return ListTile(
                    leading: Icon(Icons.history, color: Colors.white54, size: 20),
                    title: Text(tab['title'] ?? tab['url']!, style: TextStyle(color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(tab['url']!, style: TextStyle(color: Colors.white54, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.pop(ctx);
                      _createBrowserTab(url: tab['url']);
                    },
                    trailing: IconButton(
                      icon: Icon(Icons.close, color: Colors.white38, size: 16),
                      onPressed: () => setState(() => _recentTabs.removeAt(i)),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showReadingMode() async {
    final url = _activeTab.url;
    if (url.isEmpty || url == 'about:blank') {
      _showToast('No page to read');
      return;
    }
    final c = _activeWebview;
    if (c == null) return;
    _showToast('Extracting content...');
    try {
      final result = await c.evaluateJavascript(source: r'''
        (function() {
          var content = '';
          var title = document.title || '';
          var article = document.querySelector('article, [role="article"], .post-content, .article-content, .entry-content, main, .content');
          if (article) {
            content = article.innerHTML;
          } else {
            var paragraphs = document.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, blockquote, pre');
            var texts = [];
            paragraphs.forEach(function(p) {
              var text = p.innerText.trim();
              if (text.length > 20) texts.push('<p>' + text + '</p>');
            });
            content = texts.join('\n');
          }
          if (!content || content.length < 50) {
            content = '<p>' + (document.body ? document.body.innerText : '').substring(0, 10000) + '</p>';
          }
          return JSON.stringify({title: title, content: content});
        })();
      ''');
      if (result != null) {
        final data = jsonDecode(result.toString());
        final title = data['title'] ?? 'Reading Mode';
        final htmlBody = data['content'] ?? '';
        final html = '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{background:#0F172A;color:#E2E8F0;font-family:-apple-system,BlinkMacSystemFont,sans-serif;font-size:18px;line-height:1.8;padding:24px;max-width:800px;margin:0 auto}
h1,h2,h3{color:#F8FAFC;margin:1em 0 0.5em}p{margin:0.6em 0}a{color:#38BDF8}img{max-width:100%;border-radius:8px}
blockquote{border-left:3px solid #38BDF8;padding:8px 16px;margin:12px 0;background:rgba(56,189,248,0.05)}
pre{background:#1E293B;padding:12px;border-radius:8px;overflow-x:auto}
</style></head><body><h1 style="font-size:1.5em">$title</h1>$htmlBody</body></html>''';
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/reading_mode.html');
        await tempFile.writeAsString(html);
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => HtmlViewerPage(filePath: tempFile.path, title: 'Reading Mode'),
          ));
        }
      }
    } catch (e) {
      _showToast('Failed to extract content');
    }
  }

  void _addToHomeScreen() async {
    final url = _activeTab.url;
    final title = _activeTab.title.isNotEmpty ? _activeTab.title : url;
    if (url.isEmpty || url == 'about:blank') {
      _showToast('No page to add');
      return;
    }
    Share.share('$title\n$url', subject: title);
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlFocusNode.removeListener(_onUrlFocusChanged);
    _musicService.removeListener(_onMusicChanged);
    _downloadManager.dispose();
    _updateService.cleanOldApks();
    _pty?.kill();
    _urlController.dispose();
    _searchController.dispose();
    _terminalInputController.dispose();
    _terminalFocusNode.dispose();
    _tabControllers.clear();
    _tabSnapshots.clear();
    super.dispose();
  }

  String _monacoConflictHtml(String content, String lang) {
    final esc = content.replaceAll('`', '\\`');
    return '''
      <!DOCTYPE html><html><head><meta charset="utf-8">
      <script src="https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs/loader.min.js"></script>
      <style>html,body,#container{width:100%;height:100%;margin:0;padding:0;overflow:hidden;}</style>
      </head><body><div id="container"></div>
      <script>
        require.config({ paths: { 'vs': 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs' }});
        require(['vs/editor/editor.main'], function () {
          window.editor = monaco.editor.create(document.getElementById('container'), {
            value: `$esc`,
            language: '$lang',
            theme: 'vs-dark',
            readOnly: true,
            minimap: {enabled: false}
          });
        });
      </script></body></html>
    ''';
  }

  String _monacoHtml() {
    return '''
      <!DOCTYPE html><html><head><meta charset="utf-8">
      <script src="https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs/loader.min.js"></script>
      <style>html,body,#container{width:100%;height:100%;margin:0;padding:0;overflow:hidden;}</style>
      </head><body><div id="container"></div>
      <script>
        require.config({ paths: { 'vs': 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs' }});
        require(['vs/editor/editor.main'], function () {
          window.editor = monaco.editor.create(document.getElementById('container'), {
            value: '// Welcome to Makaw Mobile\\nconsole.log("Hello from Makaw!");',
            language: 'javascript',
            theme: '${widget.themeMode == "light" ? "vs" : "vs-dark"}',
            automaticLayout: true,
            minimap: {enabled: true},
            fontSize: 14,
            wordWrap: 'on',
            formatOnPaste: true,
            formatOnType: true,
            quickSuggestions: true,
            suggestOnTriggerCharacters: true,
            renderWhitespace: 'selection',
            fontLigatures: true
          });
          window.editor.getModel().onDidChangeContent(function() {
            window.flutter_inappwebview.callHandler('editorChanged');
          });
        });
      </script></body></html>
    ''';
  }

  // ─── Downloads Tab ──────────────────────────────────────────────────────────

  Widget _buildDownloadsTab() {
    return feature.DownloadsWidget(
      onOpenDownload: (url, filename, savePath) {
        if (savePath != null && savePath.isNotEmpty) {
          _openFile(savePath);
        } else {
          setState(() {
            _playVideoUrl = url;
            _playVideoTitle = filename;
          });
          _switchToView('player');
        }
      },
    );
  }

  // ─── Player Tab ─────────────────────────────────────────────────────────────

  Widget _buildPlayerTab() {
    if (_videoBrowserItems.isEmpty && !_videoBrowserLoading) {
      _loadVideoBrowserDir(_getStorageRoot());
    }

    if (_playVideoUrl != null) {
      // Show full-screen player immediately by pushing a new page
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DirectVideoPlayer(
              url: _playVideoUrl,
              title: _playVideoTitle ?? 'Video',
              onDownload: _playVideoUrl != null ? () {
                final url = _playVideoUrl!;
                final filename = url.split('/').last.split('?').first;
                _downloadManager.enqueue(url, filename: filename.isNotEmpty ? filename : 'video_${DateTime.now().millisecondsSinceEpoch}.mp4');
                _showToast('Downloading: $filename');
              } : null,
            ),
          )).then((_) {
            setState(() { _playVideoUrl = null; _playVideoTitle = null; });
          });
        }
      });
      // Show nothing while navigating
      return SizedBox.shrink();
    }

    return Column(
      children: [
        // Top bar with path breadcrumb
        Container(
          color: Theme.of(context).colorScheme.surface,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.videocam, color: Color(0xFF818CF8), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => _loadVideoBrowserDir(_getStorageRoot()),
                  child: Text(
                    _videoBrowserPath.replaceAll(_getStorageRoot(), '~').replaceAll('/', ' / '),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              SizedBox(width: 4),
              if (_videoBrowserPath != _getStorageRoot())
                IconButton(
                  icon: Icon(Icons.arrow_upward, color: Color(0xFF818CF8), size: 20),
                  onPressed: () {
                    final parent = p.dirname(_videoBrowserPath);
                    if (parent != _videoBrowserPath) _loadVideoBrowserDir(parent);
                  },
                  tooltip: 'Go up',
                ),
              IconButton(
                icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
                onPressed: () => _loadVideoBrowserDir(),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Theme.of(context).cardColor),
        Expanded(
          child: _videoBrowserLoading
              ? Center(child: CircularProgressIndicator(color: Color(0xFF818CF8)))
              : _videoBrowserItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.video_file, size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('Nothing here', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _videoBrowserItems.length,
                      itemBuilder: (ctx, i) {
                        final entity = _videoBrowserItems[i];
                        final isDir = entity is Directory;
                        final name = entity.path.split('\\').last.split('/').last;
                        final ext = name.split('.').last.toLowerCase();
                        final isVideo = !isDir && ['mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'wmv', '3gp'].contains(ext);

                        if (!isDir && !isVideo) return SizedBox.shrink();

                        return ListTile(
                          leading: Icon(
                            isDir ? Icons.folder : Icons.videocam,
                            color: isDir ? Color(0xFFFBBF24) : Color(0xFF818CF8),
                            size: 20,
                          ),
                          title: Text(name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
                          onTap: () {
                            if (isDir) {
                              _loadVideoBrowserDir(entity.path);
                            } else if (isVideo) {
                              setState(() {
                                _playVideoUrl = entity.path;
                                _playVideoTitle = name;
                              });
                            }
                          },
                          dense: true,
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ─── Folder Video Player ────────────────────────────────────────────────────

  Widget _buildFolderVideoPlayer(List<String> files) {
    return FolderVideoPlayerWidget(
      files: files,
      onClose: () => Navigator.of(context).pop(),
    );
  }

  // ─── Music Player Tab ──────────────────────────────────────────────────────

  // Video file browser state
  String _videoBrowserPath = '/storage/emulated/0/';
  List<FileSystemEntity> _videoBrowserItems = [];
  bool _videoBrowserLoading = false;

  String _getStorageRoot() => Platform.isAndroid ? '/storage/emulated/0/' : '/';

  Future<void> _loadVideoBrowserDir([String? path]) async {
    setState(() => _videoBrowserLoading = true);
    if (path != null) _videoBrowserPath = path;
    try {
      final dir = Directory(_videoBrowserPath);
      if (await dir.exists()) {
        final entities = await dir.list().toList();
        entities.sort((a, b) {
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });
        setState(() => _videoBrowserItems = entities);
      } else {
        setState(() => _videoBrowserItems = []);
      }
    } catch (_) {
      setState(() => _videoBrowserItems = []);
    }
    setState(() => _videoBrowserLoading = false);
  }

  // ─── Media Hub ───────────────────────────────────────────────────────────────

  Widget _buildMediaHubPage() {
    final nowPlaying = _musicService.currentSong != null;
    final hasVideoUrl = _playVideoUrl != null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.movie, size: 20, color: kAccentTeal), SizedBox(width: 8), Text('Media Hub')]),
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface), onPressed: _goToMakawHome),
        actions: [
          IconButton(
            icon: Icon(Icons.system_update, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
            onPressed: () => _checkForUpdatesManual(),
            tooltip: 'Check for updates',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            // Continue playing section
            if (nowPlaying || hasVideoUrl) ...[
              Text('Continue Playing', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              if (nowPlaying)
                _buildMediaCard(
                  icon: Icons.music_note,
                  iconColor: kAccentTeal,
                  title: _musicService.currentSong?.displayTitle ?? 'Unknown',
                  subtitle: 'Music Player',
                  onTap: () => _switchToView('music'),
                ),
              SizedBox(height: 8),
              if (hasVideoUrl)
                _buildMediaCard(
                  icon: Icons.videocam,
                  iconColor: Color(0xFF818CF8),
                  title: _playVideoTitle ?? 'Video',
                  subtitle: 'Video Player',
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => VideoPlayerWidget(onOpenMusic: () { Navigator.of(context).pop(); _switchToView('music'); }, onHome: () => Navigator.of(context).pop()),
                    ));
                  },
                ),
              SizedBox(height: 20),
            ],
            // Browse section
            Text('Browse', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            _buildMediaCard(
              icon: Icons.music_note, iconColor: kAccentTeal,
              title: 'Music Player', subtitle: 'Browse and play audio files',
              onTap: () => _switchToView('music'),
            ),
            SizedBox(height: 8),
            _buildMediaCard(
              icon: Icons.videocam, iconColor: Color(0xFF818CF8),
              title: 'Video Player', subtitle: 'Browse and watch video files',
              onTap: () => _switchToView('player'),
            ),
            SizedBox(height: 8),
            _buildMediaCard(
              icon: Icons.image, iconColor: Color(0xFF34D399),
              title: 'Image Viewer', subtitle: 'View images from your device',
              onTap: () => _switchToView('images'),
            ),
            SizedBox(height: 8),
            _buildMediaCard(
              icon: Icons.description, iconColor: Color(0xFFF87171),
              title: 'Documents', subtitle: 'PDF, EPUB, DOCX, TXT and more',
              onTap: () => _switchToView('documents'),
            ),
            SizedBox(height: 20),
            // Go to browser
            Text('Actions', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            _buildMediaCard(
              icon: Icons.language, iconColor: kAccentTeal,
              title: 'Go to Makaw Home', subtitle: 'Return to the app home screen',
              onTap: _goToMakawHome,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaCard({required IconData icon, required Color iconColor, required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w500)),
                  SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
          ],
        ),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/makaw_logo_64.png', width: 64, height: 64, fit: BoxFit.contain),
              SizedBox(height: 20),
              CircularProgressIndicator(color: kAccentTeal),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: _viewMode == ViewMode.home ? _buildDrawer(context) : null,
      body: Stack(
        children: [
          PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              if (_currentView == 'browser') {
                if (_viewMode == ViewMode.typeView) {
                  _urlFocusNode.unfocus();
                  _suggestDebounce?.cancel();
                  if (_browserTabs.isEmpty) {
                    setState(() {
                      _viewMode = ViewMode.home;
                      _urlSuggestions = [];
                      _searchSuggestions = [];
                      _suggestions = [];
                    });
                    return;
                  }
                  final tab = _browserTabs.firstWhere((t) => t.id == _activeBrowserTabId, orElse: () => _browserTabs.first);
                  _ignoreUrlChanges = true;
                  if (!_showHomeScreen) {
                    _urlController.text = tab.url.isEmpty ? '' : tab.url;
                  }
                  _ignoreUrlChanges = false;
                  setState(() {
                    _viewMode = _typeViewFromHome ? ViewMode.home : ViewMode.browsing;
                    _urlSuggestions = [];
                    _searchSuggestions = [];
                  });
                  return;
                }
                final c = _activeWebview;
                if (c != null) {
                  final canGoBack = await c.canGoBack();
                  if (canGoBack) {
                    c.goBack();
                    return;
                  }
                }
                // No back history
                if (_showHomeScreen) {
                  _moveTaskToBack();
                  return;
                }
                _goHome();
                return;
              }
              if (context.mounted) Navigator.of(context).pop();
            },
            child: SafeArea(
              child: _currentView == 'browser' ? _buildBrowserContent() : SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMusicPlayer() {
    final song = _musicService.currentSong;
    if (song == null) return SizedBox.shrink();
    return GestureDetector(
      onTap: () => _switchToView('music'),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).cardColor, width: 1)),
        ),
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: kAccentTeal.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.music_note, color: kAccentTeal, size: 22),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.displayTitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(song.displayArtist, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              icon: Icon(_musicService.isPlaying ? Icons.pause : Icons.play_arrow, color: kAccentTeal, size: 26),
              onPressed: () => _musicService.togglePlayPause(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final items = [
      ('Browser', Icons.language, 'browser'),
      ('Code Studio', Icons.code, 'studio'),
      ('Terminal', Icons.terminal, 'terminal'),
      ('Media Hub', Icons.movie, 'media'),
      ('Media Sniffer', Icons.wifi_tethering, 'sniffer'),
      ('Video Player', Icons.videocam, 'player'),
      ('Music Player', Icons.music_note, 'music'),
      ('Image Viewer', Icons.photo_library, 'images'),
      ('Documents', Icons.description, 'documents'),
      ('Git', Icons.account_tree, 'git'),
      ('Downloads', Icons.download, 'downloads'),
      ('Snippets', Icons.content_paste, 'snippets'),
      ('Projects', Icons.folder, 'projects'),
      ('Cloud Sync', Icons.cloud, 'cloud'),
    ];
    return Drawer(
      child: SafeArea(
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kAccentTeal, kAccentOrange],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Image.asset('assets/makaw_logo_28.png', width: 40, height: 40, fit: BoxFit.contain),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Makaw', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('Code Studio', style: TextStyle(fontSize: 12, color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),
              ...items.map((item) {
                final label = item.$1;
                final icon = item.$2;
                final view = item.$3;
                final active = _currentView == view;
                return ListTile(
                  leading: Icon(icon, color: active ? kAccentTeal : Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                  title: Text(label, style: TextStyle(color: active ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                  selected: active,
                  selectedTileColor: Theme.of(context).colorScheme.surface,
                  onTap: () => _switchToView(view),
                );
              }),
              Divider(color: Theme.of(context).cardColor),
              ListTile(
                leading: Icon(Icons.system_update, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                title: Text('Check for Updates', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                onTap: () {
                  Navigator.of(context).pop();
                  _checkForUpdatesManual();
                },
              ),
              ListTile(
                leading: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                title: Text('About Makaw', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                onTap: () {
                  Navigator.of(context).pop();
                  _showAboutMakaw();
                },
              ),
              Divider(color: Theme.of(context).cardColor),
              ListTile(
                leading: Icon(widget.themeMode == 'system' ? Icons.brightness_auto : widget.themeMode == 'dark' ? Icons.dark_mode : Icons.light_mode, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                title: Text(widget.themeMode == 'system' ? 'System Theme' : widget.themeMode == 'dark' ? 'Dark Theme' : 'Light Theme', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                onTap: () {
                  Navigator.of(context).pop();
                  _cycleTheme();
                },
              ),
              ListTile(
                leading: Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                title: Text('AI Settings', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                subtitle: Text('Configure Gemini API', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 11)),
                onTap: () {
                  Navigator.of(context).pop();
                  _showAISettings();
                },
              ),
              ListTile(
                leading: Icon(Icons.storage, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                title: Text('Storage Access', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                subtitle: Text('Manage file permissions', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 11)),
                onTap: () {
                  Navigator.of(context).pop();
                  _requestFileAccess();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMusicPlayerPage() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop();
        }
      },
      child: MusicPlayerWidget(
        onOpenVideos: () {
          Navigator.of(context).pop();
          _switchToView('player');
        },
        onOpenSettings: () {
          _showToast('Music settings coming soon');
        },
      ),
    );
  }

  Widget _buildImagePage() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => _buildMediaHubPage()));
        }
      },
      child: ImageViewerWidget(),
    );
  }

  Widget _buildDocumentPage() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => _buildMediaHubPage()));
        }
      },
      child: DocumentWidget(
        openFile: (path) => _openFile(path),
      ),
    );
  }

  Widget _buildFeatureScaffold(String title, IconData icon, Widget body, {bool backToMediaHub = false}) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 20, color: kAccentTeal), SizedBox(width: 8), Text(title)]),
          backgroundColor: Theme.of(context).colorScheme.surface,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.system_update, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              onPressed: () => _checkForUpdatesManual(),
              tooltip: 'Check for updates',
            ),
            IconButton(
              icon: Icon(widget.themeMode == 'system' ? Icons.brightness_auto : widget.themeMode == 'dark' ? Icons.dark_mode : Icons.light_mode, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              onPressed: _cycleTheme,
              tooltip: 'Theme: ${widget.themeMode}',
            ),
          ],
        ),
        body: SafeArea(child: body),
      ),
    );
  }

  // ─── Studio Tab ─────────────────────────────────────────────────────────────

  Widget _buildStudioTab() {
    return Column(
      children: [
        // File tabs bar
        Container(
          height: 36,
          color: Theme.of(context).colorScheme.surface,
          child: _openFiles.isEmpty
              ? null
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _openFiles.length,
                  itemBuilder: (ctx, i) {
                    final f = _openFiles[i];
                    final active = f.id == _activeFileId;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _activeFileId = f.id);
                        _loadFileInMonaco(f);
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: active ? Color(0xFF818CF8) : Colors.transparent, width: 2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (f.dirty) Text('● ', style: TextStyle(color: Colors.yellow, fontSize: 12)),
                            Text(f.name, style: TextStyle(fontSize: 12, color: active ? Colors.white : Colors.grey)),
                            SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _closeEditorFile(f.id),
                              child: Icon(Icons.close, size: 14, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        // Toolbar
        Container(
          color: Color(0xFF1E293B),
          padding: EdgeInsets.all(6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(hintText: 'Project name', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                  controller: TextEditingController(text: _currentProject),
                  onChanged: (v) => _currentProject = v,
                ),
              ),
              SizedBox(width: 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: Color(0xFF334155),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButton<String>(
                  value: _currentLang,
                  dropdownColor: Color(0xFF1E293B),
                  underline: SizedBox(),
                  style: TextStyle(fontSize: 12, color: Colors.white),
                  items: LANG_OPTIONS.map((l) => DropdownMenuItem(value: l, child: Text(l, style: TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) async {
                    setState(() => _currentLang = v!);
                    await _monacoController?.evaluateJavascript(source: "monaco.editor.setModelLanguage(window.editor.getModel(), '$_currentLang')");
                  },
                ),
              ),
              SizedBox(width: 4),
              _iconBtn(Icons.save, 'Save', _saveProject),
              _iconBtn(Icons.play_arrow, 'Run', _runPreview),
              _iconBtn(Icons.format_align_left, 'Format', _formatCode),
              _iconBtn(Icons.add, 'New', _newFile),
            ],
          ),
        ),
        // Monaco editor
        Expanded(
          child: InAppWebView(
            initialData: InAppWebViewInitialData(data: _monacoHtml()),
            onWebViewCreated: (c) {
              _monacoController = c;
              c.addJavaScriptHandler(handlerName: 'editorChanged', callback: (_) {
                final af = _openFiles.where((f) => f.id == _activeFileId);
                if (af.isNotEmpty && !af.first.dirty) {
                  setState(() => af.first.dirty = true);
                }
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.all(4),
    );
  }

  void _newFile() {
    final controller = TextEditingController(text: 'untitled.dart');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New File'),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: 'filename.dart')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final lang = detectLanguage(name);
              final boilerplate = BOILERPLATES[lang] ?? '';
              _openFileInEditor(name, boilerplate, language: lang);
              _currentLang = lang;
            },
            child: Text('Create'),
          ),
        ],
      ),
    );
  }

  bool get _isIncognitoActive {
    final tab = _activeTab;
    return tab.incognito;
  }

  int get _currentModeTabCount {
    if (_isIncognitoActive) {
      return _browserTabs.where((t) => t.incognito).length;
    }
    return _browserTabs.where((t) => !t.incognito).length;
  }

  // ─── Browser Header ──────────────────────────────────────────────────────────

  Widget _buildBrowserHeader() {
    final tabCount = _currentModeTabCount;
    final inc = _isIncognitoActive;
    final isHome = _isMakawHome;

    if (_viewMode == ViewMode.typeView) {
      return _buildTypeViewHeader();
    }

    final headerBg = inc ? kIncognitoBg : Theme.of(context).colorScheme.surface;
    final iconColor = inc ? Colors.white70 : Theme.of(context).colorScheme.onSurface;
    final urlBarBg = inc ? kIncognitoInput : Theme.of(context).cardColor;
    final urlTextColor = inc ? Colors.white70 : Theme.of(context).colorScheme.onSurface;
    final urlHintColor = inc ? Colors.white38 : Theme.of(context).colorScheme.onSurface.withOpacity(0.6);

    return Container(
      color: headerBg,
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          if (isHome && !inc)
            IconButton(
              icon: Icon(Icons.menu, color: iconColor),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            )
          else
            IconButton(
              icon: Icon(inc ? Icons.visibility_off : Icons.home_outlined, color: iconColor),
              onPressed: _goHome,
            ),
          if (_viewMode == ViewMode.browsing)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  final clean = _cleanDisplayUrl(_urlController.text);
                  _typeViewFromHome = false;
                  _ignoreUrlChanges = true;
                  if (clean.isNotEmpty) _urlController.text = clean;
                  _ignoreUrlChanges = false;
                  setState(() { _viewMode = ViewMode.typeView; });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _urlFocusNode.requestFocus();
                    _urlController.selection = TextSelection(baseOffset: 0, extentOffset: _urlController.text.length);
                  });
                },
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 8),
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: urlBarBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      if (inc) ...[
                        Icon(Icons.visibility_off, size: 16, color: kIncognitoAccent),
                        SizedBox(width: 8),
                      ],
                      if (!inc && _urlController.text.isNotEmpty && _urlController.text.startsWith('https'))
                        Icon(Icons.lock_outline, size: 14, color: Colors.green),
                      Expanded(
                        child: Text(
                          _urlController.text.isNotEmpty ? _cleanDisplayUrl(_urlController.text) : (inc ? 'Search privately' : 'Search or enter address'),
                          style: TextStyle(
                            color: _urlController.text.isNotEmpty ? urlTextColor : urlHintColor,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Spacer(),
          GestureDetector(
            onTap: _showTabSwitcher,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: inc ? kIncognitoPurple.withValues(alpha: 0.15) : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: inc ? kIncognitoPurple.withValues(alpha: 0.5) : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    inc ? Icons.visibility_off : Icons.tab,
                    size: 18,
                    color: inc ? kIncognitoPurple : iconColor,
                  ),
                  SizedBox(width: 4),
                  Text(
                    '$tabCount',
                    style: TextStyle(
                      color: inc ? kIncognitoPurple : iconColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.more_horiz, color: iconColor),
            onPressed: _showEllipsisMenu,
          ),
        ],
      ),
    );
  }

  Widget _buildTypeViewHeader() {
    final inc = _isIncognitoActive;
    final headerBg = inc ? kIncognitoBg : Theme.of(context).colorScheme.surface;
    final iconColor = inc ? Colors.white70 : Theme.of(context).colorScheme.onSurface;
    final inputBg = inc ? kIncognitoInput : Theme.of(context).cardColor;
    final textColor = inc ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final hintColor = inc ? Colors.white38 : Theme.of(context).colorScheme.onSurface.withOpacity(0.6);

    return Container(
      color: headerBg,
      padding: EdgeInsets.only(left: 4, right: 4, top: 4, bottom: 6),
      child: Row(
        children: [
          PopupMenuButton<String>(
            icon: Icon(Icons.add_circle_outline, color: iconColor, size: 26),
            onSelected: (v) {
              if (v == 'tabs') _showTabSwitcher();
              else if (v == 'camera') _scanQRCode();
              else if (v == 'gallery') _pickFile();
              else if (v == 'files') _pickFile();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'tabs', child: ListTile(leading: Icon(Icons.tab, color: iconColor), title: Text('Tabs', style: TextStyle(color: textColor)), dense: true)),
              PopupMenuItem(value: 'camera', child: ListTile(leading: Icon(Icons.camera_alt, color: iconColor), title: Text('Camera', style: TextStyle(color: textColor)), dense: true)),
              PopupMenuItem(value: 'gallery', child: ListTile(leading: Icon(Icons.photo_library, color: iconColor), title: Text('Gallery', style: TextStyle(color: textColor)), dense: true)),
              PopupMenuItem(value: 'files', child: ListTile(leading: Icon(Icons.folder, color: iconColor), title: Text('Files', style: TextStyle(color: textColor)), dense: true)),
            ],
          ),
          Expanded(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _urlController,
                focusNode: _urlFocusNode,
                autofocus: true,
                style: TextStyle(color: textColor, fontSize: 16),
                decoration: InputDecoration(
                  hintText: inc ? 'Search privately' : 'Search or enter address',
                  hintStyle: TextStyle(color: hintColor, fontSize: 16),
                  prefixIcon: inc ? Padding(
                    padding: EdgeInsets.only(left: 12, right: 4),
                    child: Icon(Icons.visibility_off, size: 18, color: kIncognitoAccent),
                  ) : null,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) _typeViewNavigate(v.trim());
                },
              ),
            ),
          ),
          SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.mic, color: iconColor, size: 22),
            onPressed: () => _showToast('Voice search'),
          ),
          IconButton(
            icon: Icon(Icons.qr_code_scanner, color: iconColor, size: 22),
            onPressed: _scanQRCode,
          ),
        ],
      ),
    );
  }

  void _pickFile() {
    FilePicker.platform.pickFiles().then((result) {
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path != null) _navigateInCurrentTab(path);
      }
    });
  }

  void _showEllipsisMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final bookmarked = _isCurrentPageBookmarked();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header action icons
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(bottom: BorderSide(color: Theme.of(context).cardColor, width: 1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ellipsisAction(Icons.arrow_forward, 'Forward', () { _activeWebview?.goForward(); Navigator.of(ctx).pop(); }),
                    _ellipsisAction(bookmarked ? Icons.star : Icons.star_border, 'Bookmark', () { _toggleBookmarkForCurrentPage(); Navigator.of(ctx).pop(); }),
                    _ellipsisAction(Icons.download, 'Download', () { _showToast('Download page'); Navigator.of(ctx).pop(); }),
                    _ellipsisAction(Icons.info_outline, 'Info', () { _showToast('Page info'); Navigator.of(ctx).pop(); }),
                    _ellipsisAction(Icons.refresh, 'Refresh', () { _reloadCurrentPage(); Navigator.of(ctx).pop(); }),
                  ],
                ),
              ),
              // Body menu list
              Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(vertical: 4),
                  children: [
                    _ellipsisItem(Icons.tab, 'New Tab', () { Navigator.of(ctx).pop(); Future.microtask(() => _createBrowserTab(incognito: _isIncognitoActive)); }),
                    _ellipsisItem(Icons.visibility_off, 'New Incognito', () { Navigator.of(ctx).pop(); Future.microtask(() => _createBrowserTab(incognito: true)); }),
                    _ellipsisItem(Icons.folder, 'Add to Group', () { _showToast('Tab groups coming soon'); Navigator.of(ctx).pop(); }),
                    _ellipsisItem(Icons.history, 'History', () { Navigator.of(ctx).pop(); _switchToView('history'); }),
                    _ellipsisItem(Icons.delete_sweep, 'Delete Browsing Data', () {
                      Navigator.of(ctx).pop();
                      _showClearBrowsingDataDialog();
                    }),
                    _ellipsisItem(Icons.download, 'Downloads', () { Navigator.of(ctx).pop(); _switchToView('downloads'); }),
                    _ellipsisItem(Icons.bookmark, 'Bookmarks', () {
                      Navigator.of(ctx).pop();
                      _showBookmarksDialog();
                    }),
                    _ellipsisItem(Icons.recent_actors, 'Recent Tabs', () { Navigator.of(ctx).pop(); _showRecentTabs(); }),
                    _ellipsisItem(Icons.share, 'Share', () {
                      final url = _activeTab.url;
                      if (url.isNotEmpty) Share.share(url);
                      Navigator.of(ctx).pop();
                    }),
                    _ellipsisItem(Icons.search, 'Find in Page', () { _showFindInPage(); Navigator.of(ctx).pop(); }),
                    _ellipsisItem(Icons.translate, 'Translate', () {
                      final url = _activeTab.url;
                      Navigator.of(ctx).pop();
                      if (url.isNotEmpty) _openFile('https://translate.google.com/translate?sl=auto&tl=en&u=${Uri.encodeComponent(url)}');
                    }),
                    _ellipsisItem(Icons.text_snippet, 'Show Reading Mode', () {
                      Navigator.of(ctx).pop();
                      _showReadingMode();
                    }),
                    _ellipsisItem(Icons.add_to_home_screen, 'Add to Home screen', () {
                      Navigator.of(ctx).pop();
                      _addToHomeScreen();
                    }),
                    // Desktop site checkbox
                    StatefulBuilder(
                      builder: (ctx2, setInnerState) {
                        final ds = _desktopSite;
                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.desktop_windows, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
                          title: Text('Desktop Site', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                          trailing: Switch(
                            value: ds,
                            activeColor: kAccentTeal,
                            onChanged: (v) {
                              setInnerState(() => _desktopSite = v);
                              _applyDesktopSite(v);
                            },
                          ),
                        );
                      },
                    ),
                    _ellipsisItem(Icons.settings, 'Settings', () { Navigator.of(ctx).pop(); _showBrowserSettings(); }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ellipsisAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Theme.of(context).colorScheme.onSurface, size: 22),
          ),
          SizedBox(height: 4),
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 10)),
        ],
      ),
    );
  }

  Widget _ellipsisItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
      title: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
      onTap: onTap,
    );
  }

  void _showClearBrowsingDataDialog() {
    bool clearHistory = true;
    bool clearCookies = false;
    bool clearCache = false;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              backgroundColor: Color(0xFF1E293B),
              title: Text('Clear Browsing Data', style: TextStyle(color: Colors.white, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    value: clearHistory,
                    onChanged: (v) => setDlgState(() => clearHistory = v ?? false),
                    title: Text('Browsing history', style: TextStyle(color: Colors.white, fontSize: 14)),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: kAccentTeal,
                  ),
                  CheckboxListTile(
                    value: clearCookies,
                    onChanged: (v) => setDlgState(() => clearCookies = v ?? false),
                    title: Text('Cookies and site data', style: TextStyle(color: Colors.white, fontSize: 14)),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: kAccentTeal,
                  ),
                  CheckboxListTile(
                    value: clearCache,
                    onChanged: (v) => setDlgState(() => clearCache = v ?? false),
                    title: Text('Cached images and files', style: TextStyle(color: Colors.white, fontSize: 14)),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: kAccentTeal,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    if (clearHistory) {
                      await HistoryService.clearAll();
                      setState(() => _browserHistory.clear());
                    }
                    if (clearCookies) {
                      CookieManager.instance().deleteAllCookies().catchError((_) {});
                    }
                    if (clearCache) {
                      _activeWebview?.clearCache().catchError((_) {});
                    }
                    _showToast('Browsing data cleared');
                  },
                  child: Text('Clear', style: TextStyle(color: Color(0xFFF87171))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showBookmarksDialog() {
    showDialog(
      context: context,
      builder: (ctx2) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Bookmarks', style: TextStyle(color: Colors.white)),
        content: _shortcuts.isEmpty
            ? Text('No bookmarks', style: TextStyle(color: Color(0xFF94A3B8)))
            : SizedBox(
                width: double.minPositive,
                child: ListView(
                  shrinkWrap: true,
                  children: _shortcuts.map((s) => ListTile(
                    title: Text(s.$1, style: TextStyle(color: Colors.white)),
                    subtitle: Text(s.$2, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    onTap: () { Navigator.of(ctx2).pop(); _navigateOrOpenNewTab(s.$2); },
                  )).toList(),
                ),
              ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx2).pop(), child: Text('Close', style: TextStyle(color: Color(0xFF94A3B8)))),
        ],
      ),
    );
  }

  // ─── Browser Content ──────────────────────────────────────────────────────

  Widget _buildBrowserContent() {
    final showHome = _showHomeScreen;
    final progress = _tabProgress[_activeBrowserTabId];
    final isTypeView = _viewMode == ViewMode.typeView;

    return Column(
      children: [
        if (!_isFullscreen) _buildBrowserHeader(),
        if (!showHome && !isTypeView && progress != null && progress > 0 && progress < 100)
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress / 100.0,
              backgroundColor: _isIncognitoActive ? kIncognitoBg : Theme.of(context).colorScheme.surface,
              valueColor: AlwaysStoppedAnimation(_isIncognitoActive ? kIncognitoPurple : kAccentTeal),
              minHeight: 2,
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              if (!showHome && !(isTypeView && _typeViewFromHome)) _buildWebviewArea(),
              if (showHome && !isTypeView) _buildHomeContent(),
              if (isTypeView) _buildTypeView(),
            ],
          ),
        ),
        if (!showHome && !isTypeView && _musicService.currentSong != null) _buildMiniMusicPlayer(),
      ],
    );
  }

  Widget _buildWebviewArea() {
    final activeIndex = _browserTabs.indexWhere((t) => t.id == _activeBrowserTabId);
    final activeTab = activeIndex >= 0 ? _browserTabs[activeIndex] : null;
    final isLoading = activeTab != null && (_tabProgress[activeTab.id] ?? 0) < 100;
    return Container(
      color: Color(0xFF0F172A),
      child: Stack(
        children: [
          if (_browserTabs.isNotEmpty && activeIndex >= 0)
            IndexedStack(
              index: activeIndex,
              children: _browserTabs.map((tab) => _buildTabWebView(tab)).toList(),
            ),
          if (isLoading)
            Container(
              color: Color(0xFF0F172A),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 28, height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: kAccentTeal,
                        value: (_tabProgress[activeTab!.id] ?? 0) / 100.0,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '${_tabProgress[activeTab.id] ?? 0}%',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          if (_isFullscreen)
            Positioned(
              top: 12,
              right: 16,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: Colors.black87,
                onPressed: () {
                  _activeWebview?.evaluateJavascript(source: 'document.exitFullscreen();');
                },
                child: Icon(Icons.fullscreen_exit, color: Colors.white, size: 20),
              ),
            ),
          if (_pendingMedia.isNotEmpty)
            Positioned(
              right: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: kAccentTeal,
                onPressed: _showMediaSnifferPage,
                child: Stack(
                  children: [
                    Icon(Icons.wifi_tethering, color: Colors.white),
                    Positioned(
                      right: 0, top: 0,
                      child: Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(color: kAccentOrange, shape: BoxShape.circle),
                        constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '${_pendingMedia.length}',
                          style: TextStyle(fontSize: 10, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _homeScreenKey = 0;
  void _goHome() {
    _homeScreenKey++;
    _urlController.clear();
    setState(() { _viewMode = ViewMode.home; });
  }

  void _goToMakawHome() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _switchToView('browser');
    _goHome();
  }

  // ─── Home Screen ───────────────────────────────────────────────────────────

  Widget _buildHomeContent() {
    if (_isIncognitoActive) return _buildIncognitoLandingPage();
    if (_showHomeScreen) _urlController.clear();
    return RefreshIndicator(
      onRefresh: _refreshNewsFeed,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: Column(
        children: [
          SizedBox(height: 16),
          Text('Makaw',
            style: TextStyle(
              fontFamily: 'Outfit',
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 42,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.5,
            )),
          SizedBox(height: 24),
          // Omnibox
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(32),
              ),
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335)],
                      ),
                    ),
                    child: Center(child: Text('G', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                      child: TextField(
                        controller: _urlController,
                        focusNode: _urlFocusNode,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 17),
                        decoration: InputDecoration(
                          hintText: 'Search or enter address',
                          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 17),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        onSubmitted: _navigateOrOpenNewTab,
                      ),
                  ),
                  SizedBox(width: 14),
                  GestureDetector(
                    onTap: _scanQRCode,
                    child: Icon(Icons.qr_code_scanner, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 26),
                  ),
                  SizedBox(width: 12),
                  Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 26),
                ],
              ),
            ),
          ),
          SizedBox(height: 20),
          // Shortcuts Grid
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
              ),
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              child: _buildShortcutsGrid(),
            ),
          ),
          SizedBox(height: 20),
          // AI assistant
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: _showAIChat,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4285F4), Color(0xFF9B59B6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI Assistant', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                        Text('Powered by Gemini', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                    Spacer(),
                    Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 14),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 20),
          // ─── Media Players on Home ─────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _switchToView('music'),
                    child: Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.music_note, color: Color(0xFF818CF8), size: 22),
                              SizedBox(width: 8),
                              Text('Music', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          SizedBox(height: 10),
                          if (_musicService.currentSong != null) ...[
                            Text(_musicService.currentSong!.displayTitle,
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                              overflow: TextOverflow.ellipsis, maxLines: 1),
                            Text(_musicService.currentSong!.displayArtist,
                              style: TextStyle(color: Color(0xFF666680), fontSize: 11),
                              overflow: TextOverflow.ellipsis, maxLines: 1),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.skip_previous, color: Color(0xFF818CF8), size: 18),
                                  constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _musicService.previousSong(),
                                ),
                                IconButton(
                                  icon: Icon(
                                    _musicService.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                    color: Color(0xFF818CF8), size: 24,
                                  ),
                                  constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _musicService.togglePlayPause(),
                                ),
                                IconButton(
                                  icon: Icon(Icons.skip_next, color: Color(0xFF818CF8), size: 18),
                                  constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _musicService.nextSong(),
                                ),
                              ],
                            ),
                          ] else ...[
                            Text('No music playing',
                              style: TextStyle(color: Color(0xFF666680), fontSize: 12)),
                            SizedBox(height: 4),
                            Text('${_musicService.allSongs.length} songs',
                              style: TextStyle(color: Color(0xFF666680), fontSize: 11)),
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Color(0xFF818CF8).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('Open Player', style: TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _switchToView('player'),
                    child: Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.videocam, color: Color(0xFFF87171), size: 22),
                              SizedBox(width: 8),
                              Text('Videos', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          SizedBox(height: 10),
                          Text('${_videoService.allVideos.length} videos',
                            style: TextStyle(color: Color(0xFF666680), fontSize: 12)),
                          SizedBox(height: 4),
                          Text('${_videoService.folders.length} folders',
                            style: TextStyle(color: Color(0xFF666680), fontSize: 11)),
                          SizedBox(height: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Color(0xFFF87171).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('Open Player', style: TextStyle(color: Color(0xFFF87171), fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
          // News Feed
          if (_newsFeedService != null)
            NewsFeedWidget(
              key: _newsFeedKey,
              service: _newsFeedService!,
              onNavigate: (url) => _navigateOrOpenNewTab(url),
              scrollController: _newsFeedScrollController,
            ),
          SizedBox(height: 24),
        ],
      ),
      ),
    );
  }

  Widget _buildIncognitoLandingPage() {
    return Container(
      color: kIncognitoBg,
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: kIncognitoPurple.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.visibility_off, color: kIncognitoPurple, size: 40),
            ),
            SizedBox(height: 24),
            Text(
              'You\'re browsing privately',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Your activity won\'t be saved in this browser.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 36),
            // Omnibox
            GestureDetector(
              onTap: () {
                setState(() { _typeViewFromHome = true; _viewMode = ViewMode.typeView; });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _urlFocusNode.requestFocus();
                });
              },
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: kIncognitoInput,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: kIncognitoPurple.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.white54, size: 22),
                    SizedBox(width: 12),
                    Text(
                      'Search privately',
                      style: TextStyle(color: Colors.white38, fontSize: 16),
                    ),
                    Spacer(),
                    Icon(Icons.qr_code_scanner, color: Colors.white38, size: 22),
                  ],
                ),
              ),
            ),
            SizedBox(height: 40),
            // Privacy features
            _buildIncognitoFeature(Icons.history, 'Activity is erased', 'Tabs, history, and cookies are deleted when you close all incognito tabs'),
            SizedBox(height: 20),
            _buildIncognitoFeature(Icons.lock_outline, 'Safer connection', 'Pages you visit won\'t be saved to this device'),
          ],
        ),
      ),
    );
  }

  Widget _buildIncognitoFeature(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: kIncognitoPurple.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: kIncognitoAccent, size: 20),
        ),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
              SizedBox(height: 3),
              Text(subtitle, style: TextStyle(color: Colors.white38, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Shortcuts Grid ────────────────────────────────────────────────────────

  Widget _buildShortcutsGrid() {
    final items = List<(String, String)?>.of(_shortcuts);
    items.add(null);
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 4),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: 16),
        itemBuilder: (ctx, i) {
          final s = items[i];
          return s != null ? _buildShortcutItem(s.$1, s.$2) : _buildShortcutItem(null, null);
        },
      ),
    );
  }

  Widget _buildShortcutItem(String? label, String? url) {
    if (label == null) {
      return GestureDetector(
        onTap: _showEditShortcutsDialog,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: kIconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.edit_outlined, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 22),
            ),
            SizedBox(height: 6),
            Text('Edit', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12)),
          ],
        ),
      );
    }
    final domain = url != null ? Uri.tryParse(url)?.host ?? url : '';
    final faviconUrl = domain.isNotEmpty ? 'https://www.google.com/s2/favicons?domain=$domain&sz=64' : '';
    return GestureDetector(
      onTap: () {
        if (url != null && url.isNotEmpty) _navigateOrOpenNewTab(url);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: kIconBgColor,
              shape: BoxShape.circle,
            ),
                child: ClipOval(
                  child: faviconUrl.isNotEmpty
                      ? Image.network(faviconUrl, width: 52, height: 52,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(label != null && label.isNotEmpty ? label[0].toUpperCase() : '?',
                              style: TextStyle(color: kAccentTeal, fontSize: 20, fontWeight: FontWeight.bold)),
                          ),
                        )
                  : Center(
                      child: Text(label != null && label.isNotEmpty ? label[0].toUpperCase() : '?',
                        style: TextStyle(color: kAccentTeal, fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
            ),
          ),
          SizedBox(height: 6),
          Text(label!, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12)),
        ],
      ),
    );
  }

  // ─── Content Discovery ─────────────────────────────────────────────────────

  Future<void> _showEditShortcutsDialog() async {
    List<(String, String)>? result;
    await showDialog<List<(String, String)>>(
      context: context,
      builder: (ctx) {
        final list = List<(String, String)>.from(_shortcuts);
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text('Edit Shortcuts', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: double.maxFinite,
                child: list.isEmpty
                    ? Text('No shortcuts. Tap + to add one.', style: TextStyle(color: Color(0xFF94A3B8)))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final item = list[i];
                          return ListTile(
                            dense: true,
                            title: Text(item.$1, style: TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: Text(item.$2, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                              onPressed: () {
                                setDialogState(() => list.removeAt(i));
                              },
                            ),
                    );
                  },
                )
              ),
              actions: [
                TextButton.icon(
                  icon: Icon(Icons.add, color: kAccentTeal, size: 18),
                  label: Text('Add', style: TextStyle(color: kAccentTeal)),
                  onPressed: () => _showAddShortcutDialog(ctx, list, setDialogState),
                ),
                TextButton(
                  onPressed: () {
                    result = list;
                    Navigator.of(ctx).pop();
                  },
                  child: Text('Save', style: TextStyle(color: kAccentTeal)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      try {
        _shortcuts = result!;
        await _saveShortcuts();
        setState(() {});
      } catch (e) {
        _showToast('Failed to save shortcuts: $e');
      }
    }
  }

  Future<void> _showAddShortcutDialog(BuildContext parentCtx, List<(String, String)> list, StateSetter setDialogState) async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final added = await showDialog<bool>(
      context: parentCtx,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Add Shortcut', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kAccentTeal)),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: urlCtrl,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'URL',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kAccentTeal)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAccentTeal),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && urlCtrl.text.isNotEmpty) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (added == true) {
      setDialogState(() => list.add((nameCtrl.text, urlCtrl.text)));
    }
  }

  Widget _buildContentDiscovery() {
    final lastUrl = _activeBrowserTab.url;
    final hasContent = lastUrl != 'about:blank';
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text('Continue with your Tab',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          if (hasContent)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: kAccentTeal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.language, color: kAccentTeal, size: 28),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lastUrl.replaceAll(RegExp(r'^https?://'), '').split('/').first,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Text(lastUrl,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _typeViewNavigate(lastUrl),
                    child: Icon(Icons.arrow_forward_ios, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 16),
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.travel_explore, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 24),
                  SizedBox(width: 12),
                  Text('Start browsing to see your tabs here',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showBrowserSettings() {
    final cb = _contentBlocker;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlgState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text('Browser Settings', style: TextStyle(color: Colors.white, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('General', style: TextStyle(color: kAccentTeal, fontSize: 13, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.lock, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
                    title: Text('Passwords', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                    trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
                    onTap: () { Navigator.of(ctx2).pop(); _showPasswordSettings(); },
                  ),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.folder, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
                    title: Text('Download Location', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                    subtitle: Text(_downloadLocation.isNotEmpty ? _downloadLocation.split('/').last : 'MakawDownloads', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 11)),
                    trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
                    onTap: () async {
                      Navigator.of(ctx2).pop();
                      final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose download folder');
                      if (dir != null && dir.isNotEmpty) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('download_location', dir);
                        setState(() => _downloadLocation = dir);
                        _cachedDownloadDir = dir;
                        _showToast('Download location updated');
                      }
                    },
                  ),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.file_upload, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
                    title: Text('Import Data', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                    trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
                    onTap: () { Navigator.of(ctx2).pop(); _showImportDialog(); },
                  ),
                  SizedBox(height: 12),
                  Text('Content Blocking', style: TextStyle(color: kAccentTeal, fontSize: 13, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  _buildToggleTile(setDlgState, cb, 'Ad Blocking', cb.blockAds, (v) { cb.blockAds = v; setDlgState(() {}); }),
                  _buildToggleTile(setDlgState, cb, 'Tracker Blocking', cb.blockTrackers, (v) { cb.blockTrackers = v; setDlgState(() {}); }),
                  _buildToggleTile(setDlgState, cb, 'Popup / Pop-under Blocking', cb.blockPopups, (v) { cb.blockPopups = v; setDlgState(() {}); }),
                  _buildToggleTile(setDlgState, cb, 'Malware / Crypto-miner Blocking', cb.blockMalware, (v) { cb.blockMalware = v; setDlgState(() {}); }),
                  _buildToggleTile(setDlgState, cb, 'Annoyances (cookies, overlays)', cb.blockAnnoyances, (v) { cb.blockAnnoyances = v; setDlgState(() {}); }),
                  _buildToggleTile(setDlgState, cb, 'Block Notification Spam', cb.blockNotifications, (v) { cb.blockNotifications = v; setDlgState(() {}); }),
                  _buildToggleTile(setDlgState, cb, 'Tabnabbing Protection', cb.blockTabnabbing, (v) { cb.blockTabnabbing = v; setDlgState(() {}); }),
                  _buildToggleTile(setDlgState, cb, 'Clickjacking Protection', cb.blockClickjacking, (v) { cb.blockClickjacking = v; setDlgState(() {}); }),
                  _buildToggleTile(setDlgState, cb, 'History Hijack Protection', cb.blockHistoryHijack, (v) { cb.blockHistoryHijack = v; setDlgState(() {}); }),
                  _buildToggleTile(setDlgState, cb, 'Sticky Video Blocker', cb.blockStickyVideos, (v) { cb.blockStickyVideos = v; setDlgState(() {}); }),
                  _buildToggleTile(setDlgState, cb, 'Drive-by Download Protection', cb.blockDriveByDownloads, (v) { cb.blockDriveByDownloads = v; setDlgState(() {}); }),
                  _buildToggleTile(setDlgState, cb, 'CLS Prevention', cb.preventCls, (v) { cb.preventCls = v; setDlgState(() {}); }),
                  _buildToggleTile(setDlgState, cb, 'Typosquatting Protection', cb.protectTyposquatting, (v) { cb.protectTyposquatting = v; setDlgState(() {}); }),
                  SizedBox(height: 8),
                  Text('Changes take effect on next page load', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 11)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx2).pop(), child: Text('Done', style: TextStyle(color: kAccentTeal))),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToggleTile(StateSetter setDlgState, ContentBlockerService cb, String label, bool value, ValueChanged<bool> onChanged) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 4),
      title: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
      trailing: Switch(
        value: value,
        activeColor: kAccentTeal,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }

  void _showAboutMakaw() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/makaw_logo_28.png', width: 28, height: 28),
          SizedBox(width: 8),
          Text('Makaw', style: TextStyle(color: Colors.white)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Code Studio + Hybrid Browser', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            SizedBox(height: 12),
            Text('Version 1.0.0', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            SizedBox(height: 4),
            Text('Powered by Flutter, InAppWebView, Gemini', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            SizedBox(height: 12),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse('https://hexadigitall.com')),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Developed by ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  Text('Hexadigitall', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12, fontWeight: FontWeight.w600)),
                  SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 12, color: Color(0xFF818CF8)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Close', style: TextStyle(color: Color(0xFF94A3B8)))),
        ],
      ),
    );
  }

  // ─── File Opener ────────────────────────────────────────────────────────────

  void _playAudioFileFromIntent(String path) {
    final song = SongInfo(
      id: DateTime.now().microsecondsSinceEpoch,
      title: path.split(Platform.pathSeparator).last.split('.').first,
      artist: '',
      album: '',
      filePath: path,
      duration: 0,
    );
    _musicService.playSongInfo(song);
    _switchToView('music');
  }

  void _openFile(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();

    final goBack = () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    };

    Route fastRoute(Widget child) => PageRouteBuilder(
      pageBuilder: (_, __, ___) => child,
      transitionDuration: Duration(milliseconds: 200),
      reverseTransitionDuration: Duration(milliseconds: 150),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    );

    if (['mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'wmv', '3gp'].contains(ext)) {
      Navigator.of(context).push(fastRoute(DirectVideoPlayer(
        filePath: filePath,
        title: filePath.split('\\').last.split('/').last,
      )));
      return;
    }
    if (ext == 'pdf') {
      Navigator.of(context).push(fastRoute(MakawPdfViewerPage(
        filePath: filePath,
        title: filePath.split('\\').last.split('/').last,
        onClose: goBack,
      )));
    } else if (ext == 'epub') {
      Navigator.of(context).push(fastRoute(EpubReaderWidget(
        filePath: filePath,
        title: filePath.split('\\').last.split('/').last,
        onClose: goBack,
      )));
    } else if (['mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'wma', 'opus'].contains(ext)) {
      _playAudioFileFromIntent(filePath);
    } else if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].contains(ext)) {
      Navigator.of(context).push(fastRoute(_buildImageViewer(filePath, goBack)));
    } else if (['txt', 'md', 'json', 'xml', 'yaml', 'yml', 'ini', 'cfg', 'log', 'csv'].contains(ext)) {
      Navigator.of(context).push(fastRoute(TextViewerPage(filePath: filePath, title: filePath.split('\\').last.split('/').last, onClose: goBack)));
    } else if (['html', 'htm', 'xhtml'].contains(ext)) {
      Navigator.of(context).push(fastRoute(HtmlViewerPage(filePath: filePath, title: filePath.split('\\').last.split('/').last, onClose: goBack)));
    } else if (['doc', 'docx', 'odt', 'rtf', 'pages'].contains(ext)) {
      Navigator.of(context).push(fastRoute(DocumentViewerPage(filePath: filePath, title: filePath.split('\\').last.split('/').last, onClose: goBack)));
    } else {
      OpenFilex.open(filePath);
    }
  }

  Widget _buildImageViewer(String filePath, VoidCallback onBack) {
    final name = filePath.split('\\').last.split('/').last;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(name, style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.black87,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Colors.white), onPressed: onBack),
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(
          child: Image.file(File(filePath), fit: BoxFit.contain),
        ),
      ),
    );
  }

  void _onUrlChanged() {
    if (_ignoreUrlChanges) return;
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      setState(() { _suggestions = []; _urlSuggestions = []; _searchSuggestions = []; });
      return;
    }
    final results = SuggestionEngine.rank(
      query: text,
      history: _browserHistory,
      shortcuts: _shortcuts,
      searchSuggestions: _searchSuggestions,
      isIncognito: _isIncognitoActive,
    );
    setState(() => _suggestions = results);
    _fetchSearchSuggestions(text);
  }

  void _fetchSearchSuggestions(String query) {
    _suggestDebounce?.cancel();
    if (query.length < 2) { setState(() { _searchSuggestions = []; _suggestions = []; }); return; }
    _suggestDebounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        final uri = Uri.parse('https://suggestqueries.google.com/complete/search?client=firefox&q=${Uri.encodeComponent(query)}');
        final http = HttpClient();
        http.connectionTimeout = const Duration(seconds: 3);
        final req = await http.getUrl(uri);
        req.headers.set('User-Agent', 'Mozilla/5.0');
        final res = await req.close();
        if (res.statusCode != 200) { http.close(); return; }
        final body = await res.transform(utf8.decoder).join();
        http.close();
        final decoded = jsonDecode(body) as List;
        if (decoded.length < 2 || decoded[1] is! List) return;
        final suggestions = (decoded[1] as List).map((e) => e.toString()).where((s) => s.isNotEmpty).take(6).toList();
        if (mounted) {
          setState(() => _searchSuggestions = suggestions);
          final text = _urlController.text.trim();
          if (text.isNotEmpty) {
            final ranked = SuggestionEngine.rank(
              query: text,
              history: _browserHistory,
              shortcuts: _shortcuts,
              searchSuggestions: suggestions,
              isIncognito: _isIncognitoActive,
            );
            setState(() => _suggestions = ranked);
          }
        }
      } catch (_) {}
    });
  }

  // ─── Browsing View ─────────────────────────────────────────────────────────

  Widget _buildSuggestionItem(String display, String url, IconData icon) {
    return InkWell(
      onTap: () => _typeViewNavigate(url),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
            SizedBox(width: 14),
            Expanded(
              child: Text(display, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeView() {
    if (_suggestions.isEmpty) return SizedBox.shrink();
    final inc = _isIncognitoActive;
    final bgColor = inc ? kIncognitoBg : Theme.of(context).colorScheme.surface;
    final textColor = inc ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final subColor = inc ? Colors.white54 : Theme.of(context).colorScheme.onSurface.withOpacity(0.5);
    final dividerColor = inc ? Colors.white12 : Theme.of(context).colorScheme.onSurface.withOpacity(0.15);

    final historySuggestions = _suggestions.where((s) => s.source == SuggestionSource.history).toList();
    final bookmarkSuggestions = _suggestions.where((s) => s.source == SuggestionSource.bookmark).toList();
    final searchSuggestions = _suggestions.where((s) => s.source == SuggestionSource.search).toList();
    final tabSuggestions = _suggestions.where((s) => s.source == SuggestionSource.openTab).toList();

    return Container(
      color: bgColor,
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          if (searchSuggestions.isNotEmpty) ...[
            _sectionHeader('Search', textColor, subColor),
            ...searchSuggestions.map((s) => _suggestionTile(s, textColor, subColor)),
          ],
          if (historySuggestions.isNotEmpty) ...[
            if (searchSuggestions.isNotEmpty) Divider(color: dividerColor, height: 1),
            _sectionHeader('History', textColor, subColor),
            ...historySuggestions.map((s) => _suggestionTile(s, textColor, subColor)),
          ],
          if (bookmarkSuggestions.isNotEmpty) ...[
            if (searchSuggestions.isNotEmpty || historySuggestions.isNotEmpty) Divider(color: dividerColor, height: 1),
            _sectionHeader('Shortcuts', textColor, subColor),
            ...bookmarkSuggestions.map((s) => _suggestionTile(s, textColor, subColor)),
          ],
          if (tabSuggestions.isNotEmpty) ...[
            if (searchSuggestions.isNotEmpty || historySuggestions.isNotEmpty || bookmarkSuggestions.isNotEmpty) Divider(color: dividerColor, height: 1),
            _sectionHeader('Open Tabs', textColor, subColor),
            ...tabSuggestions.map((s) => _suggestionTile(s, textColor, subColor)),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, Color textColor, Color subColor) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Text(label.toUpperCase(), style: TextStyle(color: subColor, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    );
  }

  Widget _suggestionTile(SuggestionItem item, Color textColor, Color subColor) {
    final icon = item.source == SuggestionSource.search
        ? Icons.search
        : item.source == SuggestionSource.bookmark
            ? Icons.bookmark
            : item.source == SuggestionSource.openTab
                ? Icons.tab
                : Icons.history;
    final iconColor = item.source == SuggestionSource.bookmark
        ? kAccentTeal
        : item.source == SuggestionSource.search
            ? subColor
            : subColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _typeViewNavigate(item.url),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: (textColor == Colors.white ? Colors.white : Colors.black).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: item.source == SuggestionSource.history && item.googleFaviconUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          item.googleFaviconUrl,
                          width: 32, height: 32, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(icon, color: iconColor, size: 18),
                        ),
                      )
                    : Icon(icon, color: iconColor, size: 18),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayTitle,
                      style: TextStyle(color: textColor, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.source != SuggestionSource.search)
                      Text(
                        item.domain,
                        style: TextStyle(color: subColor, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrowsingView() {
    return SizedBox.shrink();
  }

  // ─── History Tab ────────────────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    if (_browserHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
            SizedBox(height: 16),
            Text('No browsing history', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 16)),
            SizedBox(height: 8),
            Text('Visit some websites to see history here',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search history',
              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 14),
              prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: EdgeInsets.symmetric(vertical: 10),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _browserHistory.length,
            itemBuilder: (_, i) {
              final entry = _browserHistory[i];
              final url = entry['url'] as String;
              final title = entry['title'] as String;
              final query = _searchController.text.toLowerCase();
              if (query.isNotEmpty && !url.toLowerCase().contains(query) && !title.toLowerCase().contains(query)) {
                return SizedBox.shrink();
              }
              return ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.public, color: kAccentTeal, size: 20),
                ),
                title: Text(title == 'about:blank' || title == url ? _friendlyTitle(url) : title,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_friendlyUrl(url),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: Icon(Icons.close, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                  onPressed: () {
                    setState(() => _browserHistory.removeAt(i));
                  },
                ),
                onTap: () {
                  _navigateInCurrentTab(url);
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _friendlyTitle(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  String _friendlyUrl(String url) {
    try {
      return url.replaceAll(RegExp(r'^https?://'), '').split('/').first;
    } catch (_) {
      return url;
    }
  }

  String _cleanDisplayUrl(String rawUrl) {
    if (rawUrl.isEmpty || rawUrl == 'about:blank' || rawUrl == 'makaw://newtab') return '';
    try {
      final uri = Uri.parse(rawUrl);
      if (uri.host.contains('google.') && uri.path.contains('/search')) {
        final query = uri.queryParameters['q'];
        if (query != null && query.isNotEmpty) return query;
      }
      return uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
    } catch (_) {
      return rawUrl;
    }
  }

  static const _stealthUA = 'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36';

  static final _blockedRedirectDomains = [
    'popads.net','popcash.net','exoclick.com','propellerads.com','adsterra.com',
    'hilltopads.com','clickadu.com','trafficjunky.com','juicyads.com','trafficfactory.com',
    'galaksion.com','monuanceli.com','surmounttemperbooklet.com','lievestcrasser.com',
    'responservbzh.icu','aclib.js','acscdn.com','d33f51dyacx7bd.cloudfront.net',
    'dpjf9a2rbjbvp.cloudfront.net','1xbet','bet9ja','betway','bet365',
    'casino.com','pornhub','xvideos','xhamster','redtube','youporn',
    'popunder','clickunder','adnxs.com','criteo.com','pubmatic.com',
    'outbrain.com','taboola.com','revcontent.com','mgid.com','spotx.tv',
    'smartadserver.com','rubiconproject.com','indexww.com','openx.net',
    'casalemedia.com','bidswitch.net','sharethrough.com','teads.tv',
    'connatix.com','moatads.com','doubleverify.com','iasds01.com',
  ];

  static final _blockedRedirectKeywords = [
    'casino','betting','gambling','slots','poker','blackjack',
    'porn','xxx','sex','nude','nsfw','adult',
    'popunder','clickunder','popads','popcash',
    'malware','phishing','keylogger','ransomware',
    'apkpure','apk-dl','download-app','install-app',
  ];

  static bool _isBlockedRedirect(String url) {
    final lower = url.toLowerCase();
    for (final d in _blockedRedirectDomains) {
      if (lower.contains(d)) return true;
    }
    for (final k in _blockedRedirectKeywords) {
      if (lower.contains(k)) return true;
    }
    return false;
  }

  String _googleConsentAutoDismissScript() => '''
(function(){
  function killConsentHaze() {
    try {
      var selectors = [
        'iframe[src*="consent.google"]',
        '#lb',
        '.SS20bd',
        'div[role="dialog"][aria-modal="true"]',
        '.GoogleConsentBanner',
        '#consent-bump',
        '[data-consent]',
        'div[class*="consent"]',
        'div[id*="consent"]'
      ];
      for (var i = 0; i < selectors.length; i++) {
        var els = document.querySelectorAll(selectors[i]);
        for (var j = 0; j < els.length; j++) {
          var el = els[j];
          var src = (el.src || '').toLowerCase();
          var cls = (el.className || '').toLowerCase();
          var id = (el.id || '').toLowerCase();
          if (src.indexOf('consent.google') >= 0 ||
              cls.indexOf('consent') >= 0 ||
              id.indexOf('consent') >= 0 ||
              id === 'lb') {
            el.remove();
          }
        }
      }
      if (document.body) {
        document.body.style.overflow = 'auto';
        document.body.style.position = 'static';
        document.documentElement.style.overflow = 'auto';
      }
    } catch(e) {}
  }
  killConsentHaze();
  if (document.body) {
    var obs = new MutationObserver(function(muts) {
      for (var i = 0; i < muts.length; i++) {
        var added = muts[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          var n = added[j];
          if (n.nodeType === 1) killConsentHaze();
        }
      }
    });
    obs.observe(document.body, { childList: true, subtree: true });
  }
  setTimeout(killConsentHaze, 500);
  setTimeout(killConsentHaze, 1500);
})();
''';

  String _antiTapjackScript() => '''
(function(){
  try {
    var loc = window.location.href.toLowerCase();
    var whitelist = ['consent.google','accounts.google','play.google','myaccount.google',
      'facebook.com/login','github.com','apple.com/signin','google.com'];
    for (var i = 0; i < whitelist.length; i++) {
      if (loc.indexOf(whitelist[i]) >= 0) return;
    }
  } catch(e) {}

  // 1. Anti-detection: hide automation flags (keep this - it's harmless)
  try { Object.defineProperty(navigator, 'webdriver', { get: () => undefined }); } catch(e) {}
  try { window.chrome = window.chrome || { runtime: {}, loadTimes: function(){}, csi: function(){} }; } catch(e) {}
  try {
    var origQuery = window.navigator.permissions.query;
    window.navigator.permissions.query = function(p) {
      return p.name === 'notifications' ?
        Promise.resolve({ state: Notification.permission }) :
        origQuery(p);
    };
  } catch(e) {}
  try { Object.defineProperty(navigator, 'plugins', { get: function(){ return [1,2,3,4,5]; } }); } catch(e) {}
  try { Object.defineProperty(navigator, 'languages', { get: function(){ return ['en-US','en']; } }); } catch(e) {}

  // 2. Block location.replace / location.assign redirects to known bad domains only
  try {
    var _blockedKw = ['casino','betting','gambling','slots','poker','porn','xxx','sex','nude','nsfw','adult','popunder','clickunder','popads','malware','phishing'];
    function _isBadRedirect(url) {
      if (!url || typeof url !== 'string') return false;
      var l = url.toLowerCase();
      for (var k = 0; k < _blockedKw.length; k++) {
        if (l.indexOf(_blockedKw[k]) >= 0) return true;
      }
      return false;
    }
    var origReplace = window.location.replace.bind(window.location);
    var origAssign = window.location.assign.bind(window.location);
    window.location.replace = function(url) {
      if (_isBadRedirect(url)) return;
      origReplace(url);
    };
    window.location.assign = function(url) {
      if (_isBadRedirect(url)) return;
      origAssign(url);
    };
  } catch(e) {}

  // NOTE: Do NOT override window.open — breaks OAuth, Google sign-in, popups needed by sites
  // NOTE: Do NOT strip target="_blank" — breaks GitHub, documentation sites, normal browsing
  // NOTE: Do NOT kill document.write — breaks some page loads and video players
  // NOTE: Do NOT aggressively remove overlays — breaks legitimate modals, consent dialogs, UI elements
})();
''';

  Widget _buildTabWebView(BrowserTab tab) {
    final settings = InAppWebViewSettings(
      userAgent: _stealthUA,
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      supportMultipleWindows: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowsPictureInPictureMediaPlayback: true,
      supportZoom: true,
      cacheEnabled: true,
      clearCache: false,
      clearSessionCache: false,
      thirdPartyCookiesEnabled: true,
      cacheMode: CacheMode.LOAD_DEFAULT,
      domStorageEnabled: true,
      databaseEnabled: true,
      allowFileAccess: true,
      useShouldInterceptRequest: true,
      preferredContentMode: UserPreferredContentMode.MOBILE,
      offscreenPreRaster: true,
      incognito: tab.incognito,
      useOnDownloadStart: true,
      contentBlockers: _adBlocker.getContentBlockerRules(),
    );

    _pullToRefreshController ??= PullToRefreshController(
      settings: PullToRefreshSettings(
        color: kAccentTeal,
        enabled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      onRefresh: () {
        _activeWebview?.reload();
      },
    );

    final initialUrl = tab.url.isNotEmpty ? tab.url : 'about:blank';

    return InAppWebView(
      key: tab.webViewKey,
      initialSettings: settings,
      initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
      initialUserScripts: UnmodifiableListView([
        UserScript(source: _googleConsentAutoDismissScript(), injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
        UserScript(source: _antiTapjackScript(), injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
      ]),
      pullToRefreshController: _pullToRefreshController,
      onCreateWindow: (ctrl, request) async {
        final targetUrl = request.request.url?.toString() ?? '';
        if (targetUrl.isEmpty || targetUrl == 'about:blank' || _isBlockedRedirect(targetUrl)) {
          return false;
        }
        _navigateOrOpenNewTab(targetUrl);
        return false;
      },
      onWebViewCreated: (ctrl) {
        _tabControllers[tab.id] = ctrl;

        ctrl.addJavaScriptHandler(handlerName: 'PasswordSaveChannel', callback: (args) {
          try {
            final data = args.isNotEmpty ? jsonDecode(args[0] as String) as Map : {};
            _pendingPasswordUrl = data['url'] ?? '';
            _pendingPasswordUsername = data['username'] ?? '';
            _pendingPasswordPassword = data['password'] ?? '';
            if (_pendingPasswordUrl.isNotEmpty && _pendingPasswordPassword.isNotEmpty) {
              _showSavePasswordDialog();
            }
          } catch (_) {}
        });

        ctrl.addJavaScriptHandler(handlerName: 'PasswordAutofillChannel', callback: (args) {
          try {
            final data = args.isNotEmpty ? jsonDecode(args[0] as String) as Map : {};
            final url = data['url'] as String? ?? '';
            final domain = data['domain'] as String? ?? '';
            if (domain.isNotEmpty) {
              _autofillPassword(ctrl, url, domain);
            }
          } catch (_) {}
        });

        ctrl.addJavaScriptHandler(handlerName: 'MakawMediaSnifferChannel', callback: (args) {
          try {
            final data = args.isNotEmpty && args[0] is List ? List<Map<String, dynamic>>.from(args[0]) : [];
            final list = _pendingMedia;
            for (final item in data) {
              final url = item['url'] as String? ?? '';
              final type = item['type'] as String? ?? '';
              final title = item['title'] as String? ?? '';
              final rawFormats = item['formats'] as List? ?? [];
              final formats = rawFormats.map((f) {
                final fm = f as Map<String, dynamic>;
                return MediaFormat(
                  label: fm['label'] as String? ?? '',
                  url: fm['url'] as String? ?? '',
                  mimeType: fm['mimeType'] as String? ?? '',
                  height: fm['height'] as int?,
                  bitrate: fm['bitrate'] as int?,
                );
              }).toList();
              if (url.isNotEmpty && type.isNotEmpty) {
                final exists = list.any((m) => m.url == url);
                if (!exists) {
                  list.add(MediaItem(url: url, type: type, title: title, formats: formats));
                }
              }
            }
            if (data.isNotEmpty) setState(() {});
          } catch (_) {}
        });
        ctrl.addJavaScriptHandler(handlerName: 'MakawFilePickerChannel', callback: (args) async {
          try {
            final data = args.isNotEmpty && args[0] is Map ? Map<String, dynamic>.from(args[0]) : {};
            final accept = (data['accept'] as String? ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            final multiple = data['multiple'] as bool? ?? false;
            final result = await FilePicker.platform.pickFiles(
              type: accept.isEmpty ? FileType.any : FileType.custom,
              allowedExtensions: accept.isEmpty ? null : accept.map((s) => s.replaceFirst('.', '')).toList(),
              allowMultiple: multiple,
              withData: true,
            );
            if (result != null && result.files.isNotEmpty) {
              return result.files.map((f) {
                final bytes = f.bytes ?? File(f.path!).readAsBytesSync();
                return {
                  'bytes': base64Encode(bytes),
                  'filename': f.name,
                  'mimeType': 'application/octet-stream',
                };
              }).toList();
            }
          } catch (e) {
            print('Makaw file picker error: $e');
          }
          return [];
        });
        ctrl.addJavaScriptHandler(handlerName: 'MakawDownloadChannel', callback: (args) {
          try {
            final data = args.isNotEmpty && args[0] is String ? jsonDecode(args[0] as String) as Map<String, dynamic> : {};
            final url = data['url'] as String? ?? '';
            final filename = data['filename'] as String? ?? '';
            if (url.isNotEmpty) {
              final ext = url.split('?')[0].split('#')[0].split('.').last.toLowerCase();
              String type;
              if (['mp4','webm','mkv','avi','mov','flv','wmv','m3u8','mpd','ts'].contains(ext)) {
                type = 'video';
              } else if (['mp3','wav','flac','ogg','aac','m4a','opus'].contains(ext)) {
                type = 'audio';
              } else if (['jpg','jpeg','png','gif','webp','bmp','svg','ico','avif'].contains(ext)) {
                type = 'image';
              } else if (['pdf','epub','doc','docx','odt','rtf','pages','xls','xlsx','ppt','pptx','txt','csv'].contains(ext)) {
                type = 'document';
              } else {
                type = 'other';
              }
              final list = _pendingMedia;
              final exists = list.any((m) => m.url == url);
              if (!exists) {
                list.add(MediaItem(url: url, type: type, title: filename));
                setState(() {});
              }
            }
          } catch (_) {}
        });
        ctrl.addJavaScriptHandler(handlerName: 'popupBlocked', callback: (args) {
          final now = DateTime.now();
          if (_lastPopupToast != null && now.difference(_lastPopupToast!) < const Duration(seconds: 3)) return;
          _lastPopupToast = now;
          final url = args.isNotEmpty ? args[0] as String : '';
          String label = 'Popup blocked';
          if (url.isNotEmpty) {
            try { label += ': ${Uri.parse(url).host}'; } catch (_) {}
          }
          _showToast(label);
        });
        ctrl.addJavaScriptHandler(handlerName: 'popUnderDetected', callback: (args) {
          _showToast('Pop-under attempt detected and blocked');
        });
        ctrl.addJavaScriptHandler(handlerName: 'typosquatWarning', callback: (args) {
          try {
            final data = args.isNotEmpty && args[0] is Map ? Map<String, dynamic>.from(args[0]) : {};
            final host = data['host'] as String? ?? '';
            final reason = data['reason'] as String? ?? '';
            if (host.isNotEmpty) {
              _showToast('Suspicious site: $host ($reason)');
            }
          } catch (_) {}
        });
      },
      shouldOverrideUrlLoading: (ctrl, navAction) async {
        final url = navAction.request.url.toString();
        // 1. Block non-http protocols (intent://, market://, etc.)
        if (!url.startsWith('http://') && !url.startsWith('https://')) {
          return NavigationActionPolicy.CANCEL;
        }
        // 2. Block known ad/tracker/malware domains
        if (_contentBlocker.shouldBlockUrl(url)) {
          return NavigationActionPolicy.CANCEL;
        }
        // 3. Block via dynamic blacklist (EasyList + AdGuard + hardcoded)
        if (_adBlocker.isBlocked(url)) {
          return NavigationActionPolicy.CANCEL;
        }
        // 4. Block redirect to ad/porn/betting domains
        if (_isBlockedRedirect(url)) {
          return NavigationActionPolicy.CANCEL;
        }
        // 5. Block ad redirect patterns (but allow legitimate tracking params like gclid/fbclid)
        final lowerUrl = url.toLowerCase();
        if (lowerUrl.contains('adurl=') || lowerUrl.contains('clickid=')) {
          return NavigationActionPolicy.CANCEL;
        }
        // 6. Block suspicious redirect params (but allow common OAuth and site flows)
        final _authWhitelist = ['accounts.google.com','facebook.com','github.com','apple.com','login.microsoftonline.com','auth0.com','okta.com','login.salesforce.com'];
        bool isWhitelisted = false;
        for (final w in _authWhitelist) {
          if (lowerUrl.contains(w)) { isWhitelisted = true; break; }
        }
        if (!isWhitelisted) {
          final redirectParams = ['?url=', '&url=', '?redirect=', '&redirect=', '?go=', '&go=', '?dest=', '&dest='];
          for (final p in redirectParams) {
            if (lowerUrl.contains(p)) {
              final idx = lowerUrl.indexOf(p);
              final afterParam = lowerUrl.substring(idx + p.length);
              if (_isBlockedRedirect(afterParam)) {
                return NavigationActionPolicy.CANCEL;
              }
            }
          }
        }
        return NavigationActionPolicy.ALLOW;
      },
      onLoadStart: (ctrl, url) {
        final urlStr = url.toString();
        final tabId = tab.id;
        _tabProgress[tabId] = 0;
        if (tabId == _activeBrowserTabId) {
          _pendingMedia.clear();
          if (urlStr != 'about:blank') _isWebViewLoading = true;
          if (urlStr == 'about:blank') return;
          _onBrowserNavigation(urlStr);
        }
        setState(() {});
      },
      onLoadStop: (ctrl, url) async {
        final urlStr = url.toString();
        final tabId = tab.id;
        _tabProgress[tabId] = 100;
        if (urlStr == 'about:blank') return;
        if (tabId == _activeBrowserTabId) {
          _pullToRefreshController?.endRefreshing();
          _isWebViewLoading = false;
          setState(() {
            _urlSuggestions = [];
            _searchSuggestions = [];
            _suggestions = [];
          });
        } else {
          setState(() {});
        }
        if (!tab.incognito) {
          try {
            final title = await ctrl.getTitle();
            if (title != null && title.isNotEmpty && title != 'about:blank') {
              _updateHistoryTitle(urlStr, title);
            }
          } catch (_) {}
        }
        final cbScript = _contentBlocker.fullUserScript;
        final urlLower = urlStr.toLowerCase();
        final skipBlocker = urlLower.contains('accounts.google') ||
            urlLower.contains('consent.google') ||
            urlLower.contains('play.google') ||
            urlLower.contains('myaccount.google') ||
            urlLower.contains('youtube.com/embed') ||
            urlLower.contains('github.com') ||
            urlLower.contains('facebook.com') ||
            urlLower.contains('apple.com') ||
            urlLower.contains('login.microsoftonline') ||
            urlLower.contains('discord.com') ||
            urlLower.contains('reddit.com') ||
            urlLower.contains('twitter.com') ||
            urlLower.contains('x.com') ||
            urlLower.contains('linkedin.com');
        if (!skipBlocker && cbScript.isNotEmpty) {
          ctrl.evaluateJavascript(source: cbScript).catchError((_) {});
        }
        _injectPasswordScripts(ctrl, url.toString());
        _injectFilePickerScript(ctrl);
        _injectMediaSnifferScript(ctrl);
        _injectDownloadInterceptorScript(ctrl);
        _injectMediaSessionBridge(ctrl);
      },
      onDownloadStartRequest: (ctrl, downloadStartRequest) async {
        final fileUrl = downloadStartRequest.url.toString();
        String filename = downloadStartRequest.suggestedFilename ?? '';
        if (filename.isEmpty) {
          final uriPath = downloadStartRequest.url.uriValue.path;
          filename = uriPath.split('/').lastWhere((s) => s.isNotEmpty, orElse: () => 'download');
        }
        if (!filename.contains('.')) {
          filename = '$filename.bin';
        }
        _downloadManager.enqueue(fileUrl, filename: filename);
        _showToast('Downloading: $filename');
      },
      onProgressChanged: (ctrl, progress) {
        _tabProgress[tab.id] = progress;
        if (tab.id == _activeBrowserTabId) setState(() {});
      },
      onReceivedError: (ctrl, request, error) {
        if ((request.isForMainFrame ?? false) && tab.id == _activeBrowserTabId) {
          _showToast('${error.description} (${error.type})');
          setState(() {});
        }
      },
      onReceivedServerTrustAuthRequest: (ctrl, challenge) async {
        return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
      },
      onPermissionRequest: (ctrl, request) async {
        for (final resource in request.resources) {
          if (resource == PermissionResourceType.MICROPHONE) {
            await Permission.microphone.request();
          } else if (resource == PermissionResourceType.CAMERA) {
            await Permission.camera.request();
          }
        }
        return PermissionResponse(action: PermissionResponseAction.GRANT);
      },
      onEnterFullscreen: (ctrl) {
        setState(() => _isFullscreen = true);
      },
      onExitFullscreen: (ctrl) {
        setState(() => _isFullscreen = false);
      },
    );
  }

  void _injectPasswordScripts(InAppWebViewController c, String url) {
    final escapedUrl = url.replaceAll("'", "\\'");
    c.evaluateJavascript(source: '''
(function() {
  if (window._makawPwdSave) return;
  window._makawPwdSave = true;
  document.addEventListener('submit', function(e) {
    var f = e.target;
    var pwd = f.querySelector('input[type="password"]');
    if (!pwd || !pwd.value) return;
    var user = f.querySelector('input[type="email"], input[name*="user"], input[name*="email"], input[name*="login"], input[type="text"]:not([type="hidden"])');
    PasswordSaveChannel.postMessage(JSON.stringify({
      username: user ? user.value : '',
      password: pwd.value,
      url: '$escapedUrl'
    }));
  });
})();
''').catchError((_) {});

    final domain = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? '';
    if (domain.isNotEmpty) {
      c.evaluateJavascript(source: '''
PasswordAutofillChannel.postMessage(JSON.stringify({
  url: '$escapedUrl',
  domain: '$domain'
}));
''').catchError((_) {});
    }
  }

  void _autofillPassword(InAppWebViewController c, String url, String domain) async {
    final entries = await passwordService.getForUrl(url);
    if (entries.isEmpty) return;
    final entry = entries.first;
    final escUser = entry.username.replaceAll("'", "\\'").replaceAll('\n', '\\n');
    final escPass = entry.password.replaceAll("'", "\\'").replaceAll('\n', '\\n');
    c.evaluateJavascript(source: '''
(function(u, p) {
  var pwd = document.querySelector('input[type="password"]');
  if (!pwd) return;
  var f = pwd.closest('form');
  if (!f) return;
  var user = f.querySelector('input[type="email"], input[name*="user"], input[name*="email"], input[name*="login"], input[type="text"]:not([type="hidden"])');
  if (user) { user.value = u; }
  pwd.value = p;
  })('$escUser', '$escPass');''').catchError((_) {});
  }

  void _injectFilePickerScript(InAppWebViewController c) {
    c.evaluateJavascript(source: '''
(function() {
  if (window._makawFilePicker) return;
  window._makawFilePicker = true;
  var _inputRef = null;
  document.addEventListener('click', async function(e) {
    var el = e.target;
    if (el.tagName !== 'INPUT' || el.type !== 'file') return;
    e.preventDefault();
    _inputRef = el;
    var accept = el.getAttribute('accept') || '';
    var multiple = el.hasAttribute('multiple');
    try {
      var result = await flutter_inappwebview.callHandler('MakawFilePickerChannel', {
        accept: accept,
        multiple: multiple
      });
      if (result && result.length > 0) {
        var dt = new DataTransfer();
        for (var i = 0; i < result.length; i++) {
          var fd = result[i];
          var bin = atob(fd.bytes);
          var buf = new Uint8Array(bin.length);
          for (var j = 0; j < bin.length; j++) buf[j] = bin.charCodeAt(j);
          var file = new File([buf], fd.filename, {type: fd.mimeType || 'application/octet-stream'});
          dt.items.add(file);
        }
        _inputRef.files = dt.files;
        _inputRef.dispatchEvent(new Event('change', {bubbles: true}));
      }
    } catch(e) {
      console.error('Makaw file picker error:', e);
    }
  });
})();
''').catchError((_) {});
  }

  void _injectMediaSnifferScript(InAppWebViewController c) {
    c.evaluateJavascript(source: '''
(function() {
  if (window._makawMediaSnifferIntervalIds) {
    window._makawMediaSnifferIntervalIds.forEach(clearInterval);
  }
  window._makawMediaSnifferIntervalIds = [];
  if (window._makawMediaSniffer) return;
  window._makawMediaSniffer = true;

  var knownQualities = ['2160p','4k','1440p','2k','1080p','full hd','hd','720p','480p','360p','240p','144p'];
  var videoExts = ['mp4','webm','mkv','avi','mov','flv','wmv','m3u8','mpd','ts'];
  var audioExts = ['mp3','wav','flac','ogg','aac','m4a','opus'];
  var imageExts = ['jpg','jpeg','png','gif','webp','bmp','svg','ico','avif'];
  var docExts = ['pdf','epub','doc','docx','odt','rtf','pages','xls','xlsx','ppt','pptx','txt','csv'];
  var allExts = videoExts.concat(audioExts).concat(imageExts).concat(docExts);

  function classifyExt(ext) {
    if (videoExts.indexOf(ext) >= 0) return 'video';
    if (audioExts.indexOf(ext) >= 0) return 'audio';
    if (imageExts.indexOf(ext) >= 0) return 'image';
    if (docExts.indexOf(ext) >= 0) return 'document';
    return 'other';
  }

  function isDownloadableUrl(url) {
    if (!url || !url.startsWith('http')) return false;
    var ext = url.split('?')[0].split('#')[0].split('.').pop().toLowerCase();
    return allExts.indexOf(ext) >= 0;
  }

  function extractTitle(src, el) {
    var t = (el && (el.getAttribute('title') || el.getAttribute('alt') || el.getAttribute('aria-label') || '')) || '';
    if (!t) {
      var fig = el && el.closest('figure');
      if (fig) t = (fig.querySelector('figcaption') || {}).innerText || '';
    }
    var link = el && el.closest('a');
    if (!t && link) t = link.getAttribute('download') || link.getAttribute('title') || '';
    if (!t) { t = src.split('/').pop().split('?')[0].split('#')[0] || ''; }
    return decodeURIComponent(t);
  }

  function guessQuality(src, videoEl) {
    var formats = [];
    var label = '';
    var lower = (src + ' ' + (videoEl ? videoEl.outerHTML : '')).toLowerCase();
    for (var i = 0; i < knownQualities.length; i++) {
      if (lower.indexOf(knownQualities[i]) >= 0) {
        label = knownQualities[i].charAt(0).toUpperCase() + knownQualities[i].slice(1);
        break;
      }
    }
    var h = videoEl ? videoEl.videoHeight : 0;
    if (!label && h > 0) {
      if (h >= 2160) label = '4K';
      else if (h >= 1440) label = '2K';
      else if (h >= 1080) label = '1080p';
      else if (h >= 720) label = '720p';
      else if (h >= 480) label = '480p';
      else if (h >= 360) label = '360p';
    }
    if (label || h > 0) {
      formats.push({label: label || h + 'p', url: src, mimeType: '', height: h, bitrate: 0});
    }
    return formats;
  }

  function tryParseHlsManifest(url) {
    return fetch(url, {method: 'HEAD', mode: 'cors'}).then(function(r) {
      if (!r.ok) return null;
      return fetch(url).then(function(res) { return res.text(); }).then(function(text) {
        var formats = [];
        var lines = text.split('\\n');
        var currentRes = '';
        for (var i = 0; i < lines.length; i++) {
          var l = lines[i].trim();
          if (l.indexOf('RESOLUTION=') >= 0) {
            var m = l.match(/RESOLUTION=(\\d+)x(\\d+)/);
            if (m) currentRes = m[2] + 'p';
          } else if (l.startsWith('http') && isDownloadableUrl(l)) {
            formats.push({label: currentRes || 'auto', url: l.startsWith('http') ? l : new URL(l, url).href, mimeType: 'application/vnd.apple.mpegurl', height: parseInt(currentRes) || 0, bitrate: 0});
            currentRes = '';
          } else if (l.indexOf('BANDWIDTH=') >= 0 && currentRes === '') {
            var b = l.match(/BANDWIDTH=(\\d+)/);
            if (b) currentRes = Math.round(parseInt(b[1]) / 1000) + 'k';
          }
        }
        return formats.length > 0 ? {url: url, formats: formats} : null;
      }).catch(function() { return null; });
    }).catch(function() { return null; });
  }

  function scanMedia() {
    var results = [];
    var seen = {};

    // 1. Scan <video> elements
    document.querySelectorAll('video').forEach(function(v) {
      var src = v.currentSrc || v.src || '';
      if (isDownloadableUrl(src) && !seen[src]) {
        seen[src] = true;
        results.push({url: src, type: 'video', title: extractTitle(src, v), formats: guessQuality(src, v)});
      }
      v.querySelectorAll('source').forEach(function(s) {
        if (isDownloadableUrl(s.src) && !seen[s.src]) {
          seen[s.src] = true;
          results.push({url: s.src, type: 'video', title: extractTitle(s.src, v), formats: guessQuality(s.src, v)});
        }
      });
    });

    // 2. Scan <audio> elements
    document.querySelectorAll('audio').forEach(function(a) {
      var src = a.currentSrc || a.src || '';
      if (isDownloadableUrl(src) && !seen[src]) {
        seen[src] = true;
        results.push({url: src, type: 'audio', title: extractTitle(src, a), formats: []});
      }
      a.querySelectorAll('source').forEach(function(s) {
        if (isDownloadableUrl(s.src) && !seen[s.src]) {
          seen[s.src] = true;
          results.push({url: s.src, type: 'audio', title: extractTitle(s.src, a), formats: []});
        }
      });
    });

    // 3. Scan <img> elements
    document.querySelectorAll('img').forEach(function(img) {
      var src = img.getAttribute('src') || img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || '';
      if (src && !seen[src]) {
        var ext = src.split('?')[0].split('#')[0].split('.').pop().toLowerCase();
        if (imageExts.indexOf(ext) >= 0 && src.startsWith('http')) {
          seen[src] = true;
          results.push({url: src, type: 'image', title: extractTitle(src, img), formats: []});
        }
      }
    });

    // 4. Scan <a> links for downloadable files
    document.querySelectorAll('a[href]').forEach(function(a) {
      var href = a.href;
      if (!href || !href.startsWith('http') || seen[href]) return;
      var ext = href.split('?')[0].split('#')[0].split('.').pop().toLowerCase();
      var type = classifyExt(ext);
      if (type !== 'other' && !seen[href]) {
        seen[href] = true;
        results.push({url: href, type: type, title: extractTitle(href, a), formats: []});
      }
    });

    // 5. HLS / DASH in attributes
    document.querySelectorAll('[src*=".m3u8"],[src*=".mpd"],[data-url*=".m3u8"],[data-url*=".mpd"],[href*=".m3u8"],[href*=".mpd"]').forEach(function(el) {
      var src = el.getAttribute('src') || el.getAttribute('data-url') || el.getAttribute('href') || '';
      if (isDownloadableUrl(src) && !seen[src]) {
        seen[src] = true;
        results.push({url: src, type: 'video', title: extractTitle(src, null), formats: []});
      }
    });

    // 6. JSON-LD VideoObject
    document.querySelectorAll('script[type="application/ld+json"]').forEach(function(s) {
      try {
        var data = JSON.parse(s.textContent);
        var videos = [];
        if (Array.isArray(data)) { data.forEach(function(d) { if (d['@type'] === 'VideoObject') videos.push(d); }); }
        else if (data['@type'] === 'VideoObject') videos.push(data);
        else if (data['@graph']) data['@graph'].forEach(function(g) { if (g['@type'] === 'VideoObject') videos.push(g); });
        videos.forEach(function(v) {
          var src = v.contentUrl || v.embedUrl || v.url || '';
          if (isDownloadableUrl(src) && !seen[src]) {
            seen[src] = true;
            results.push({url: src, type: 'video', title: v.name || v.description || '', formats: []});
          }
        });
      } catch(e) {}
    });

    // 7. Open Graph / Twitter meta
    var metaSrc = '';
    var meta = document.querySelector('meta[property="og:video:url"], meta[property="og:video"], meta[property="twitter:player:stream"], meta[property="og:image"], meta[property="twitter:image"]');
    if (meta) metaSrc = meta.getAttribute('content') || '';
    if (isDownloadableUrl(metaSrc) && !seen[metaSrc]) {
      seen[metaSrc] = true;
      results.push({url: metaSrc, type: metaSrc.match(/\\\\.(jpg|jpeg|png|gif|webp)/i) ? 'image' : 'video', title: extractTitle(metaSrc, null), formats: []});
    }

    // 8. Embed/iframe sources
    document.querySelectorAll('iframe[src]').forEach(function(f) {
      var src = f.src || '';
      if ((src.indexOf('youtube.com/embed/') >= 0 || src.indexOf('player.vimeo.com') >= 0 || src.indexOf('dailymotion.com/embed') >= 0) && !seen[src]) {
        seen[src] = true;
        results.push({url: src, type: 'video', title: f.getAttribute('title') || f.getAttribute('aria-label') || '', formats: []});
      }
    });

    // 9. Inline scripts for URLs
    document.querySelectorAll('script:not([src])').forEach(function(s) {
      var text = s.textContent || '';
      var urlMatches = text.match(/https?:\\\\/\\\\/[^\\\\"'\\\\s]+(?:mp4|webm|mkv|m3u8|mpd|jpg|jpeg|png|pdf)(?:[?#][^\\\\"'\\\\s]*)?/gi);
      if (urlMatches) {
        urlMatches.forEach(function(u) {
          u = u.replace(/\\\\u0026/g, '&').replace(/\\\\\//g, '/');
          if (isDownloadableUrl(u) && !seen[u]) {
            seen[u] = true;
            results.push({url: u, type: classifyExt(u.split('?')[0].split('.').pop().toLowerCase()), title: '', formats: []});
          }
        });
      }
    });

    // 10. Try fetching HLS/DASH manifests
    var manifestUrls = results.filter(function(r) { return r.url.indexOf('.m3u8') >= 0; });
    if (manifestUrls.length > 0) {
      manifestUrls.forEach(function(m) {
        tryParseHlsManifest(m.url).then(function(parsed) {
          if (parsed && parsed.formats && parsed.formats.length > 0) {
            m.formats = parsed.formats;
            flutter_inappwebview.callHandler('MakawMediaSnifferChannel', [m]);
          }
        });
      });
    }

    if (results.length > 0) {
      flutter_inappwebview.callHandler('MakawMediaSnifferChannel', results);
    }
  }

  scanMedia();
  window._makawMediaSnifferIntervalIds.push(setInterval(scanMedia, 4000));
  var origPushState = history.pushState;
  history.pushState = function() { origPushState.apply(this, arguments); setTimeout(scanMedia, 800); };
  window.addEventListener('popstate', function() { setTimeout(scanMedia, 800); });
})();
''').catchError((_) {});
  }

  void _injectDownloadInterceptorScript(InAppWebViewController c) {
    c.evaluateJavascript(source: '''
(function() {
  if (window._makawDownloadIntervalIds) {
    window._makawDownloadIntervalIds.forEach(clearInterval);
  }
  window._makawDownloadIntervalIds = [];
  if (window._makawDownloadInit) return;
  window._makawDownloadInit = true;

  var binaryExts = ['zip','rar','7z','tar','gz','apk','exe','msi','iso','img','dmg','deb','rpm'];

  function sendDownload(url, filename) {
    if (!url || url.startsWith('javascript:') || url.startsWith('about:')) return;
    flutter_inappwebview.callHandler('MakawDownloadChannel', JSON.stringify({url: url, filename: filename || ''}));
  }

  // Intercept <a download> and binary file links only
  document.addEventListener('click', function(e) {
    var a = e.target.closest('a[download]');
    if (a && a.href) {
      e.preventDefault();
      e.stopPropagation();
      sendDownload(a.href, a.download);
      return;
    }
    a = e.target.closest('a');
    if (!a || !a.href) return;
    var ext = a.href.split('?')[0].split('#')[0].split('.').pop().toLowerCase();
    if (binaryExts.indexOf(ext) >= 0 && a.href.startsWith('http')) {
      e.preventDefault();
      e.stopPropagation();
      sendDownload(a.href, a.href.split('/').pop().split('?')[0].split('#')[0]);
    }
  }, true);

  // Intercept blob URL downloads
  var origCreateObjectURL = window.URL.createObjectURL;
  window.URL.createObjectURL = function(obj) {
    var url = origCreateObjectURL.apply(this, arguments);
    _makawBlobUrls = _makawBlobUrls || [];
    _makawBlobUrls.push(url);
    return url;
  };

  // Intercept window.open only for binary files
  var origOpen = window.open;
  window.open = function(url, name, features) {
    var ext = (url || '').split('?')[0].split('.').pop().toLowerCase();
    if (binaryExts.indexOf(ext) >= 0 && url && url.startsWith('http')) {
      sendDownload(url, url.split('/').pop().split('?')[0]);
      return null;
    }
    return origOpen ? origOpen.apply(this, arguments) : null;
  };

  // Intercept fetch() for binary attachment downloads
  var origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function(input, init) {
      return origFetch.apply(this, arguments).then(function(response) {
        var url = typeof input === 'string' ? input : (input.url || '');
        var ctype = response.headers && response.headers.get ? response.headers.get('content-type') || '' : '';
        var cd = response.headers && response.headers.get ? response.headers.get('content-disposition') || '' : '';
        var isBinary = cd.indexOf('attachment') >= 0 || ctype.indexOf('octet-stream') >= 0;
        if (isBinary && url.startsWith('http')) {
          var fn = '';
          var match = cd.match(/filename="?([^"]+)"?/);
          if (match) fn = match[1];
          if (!fn) fn = url.split('/').pop().split('?')[0];
          sendDownload(url, fn);
        }
        return response;
      }).catch(function(e) { return origFetch.apply(this, arguments); });
    };
  }

  // Intercept XHR for binary downloads
  var origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function(body) {
    var xhr = this;
    xhr.addEventListener('load', function() {
      var url = xhr.responseURL || '';
      var ctype = xhr.getResponseHeader('content-type') || '';
      var cd = xhr.getResponseHeader('content-disposition') || '';
      var isBinary = cd.indexOf('attachment') >= 0 || ctype.indexOf('octet-stream') >= 0;
      if (isBinary && url.startsWith('http')) {
        var fn = '';
        var match = cd.match(/filename="?([^"]+)"?/);
        if (match) fn = match[1];
        if (!fn) fn = url.split('/').pop().split('?')[0];
        sendDownload(url, fn);
      }
    });
    return origSend.apply(this, arguments);
  };

  // Monitor for blob downloads
  window._makawDownloadIntervalIds.push(setInterval(function() {
    if (!_makawBlobUrls || !_makawBlobUrls.length) return;
    var anchors = document.querySelectorAll('a');
    for (var i = 0; i < anchors.length; i++) {
      var a = anchors[i];
      if (a.href && a.href.startsWith('blob:') && a.getAttribute('download')) {
        sendDownload(a.href, a.download || 'download');
        a.removeAttribute('download');
      }
    }
  }, 1000));

  // MutationObserver for dynamically created download links
  var observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(mut) {
      mut.addedNodes.forEach(function(node) {
        if (node.nodeType === 1) {
          if (node.tagName === 'A' && node.href && node.hasAttribute('download')) {
            sendDownload(node.href, node.getAttribute('download') || '');
          }
          node.querySelectorAll && node.querySelectorAll('a[download]').forEach(function(a) {
            if (a.href) sendDownload(a.href, a.download || '');
          });
        }
      });
    });
  });
  if (document.body) observer.observe(document.body, {childList: true, subtree: true});
})();
''').catchError((_) {});
  }

  void _injectMediaSessionBridge(InAppWebViewController c) {
    c.evaluateJavascript(source: '''
(function() {
  if (window._makawMediaSessionInit) return;
  window._makawMediaSessionInit = true;

  var lastUrl = '';

  function tryBridge() {
    try {
      var media = document.querySelector('video, audio');
      if (!media || media.paused) return;

      var now = location.href;
      var changed = (now !== lastUrl);
      lastUrl = now;

      if (!navigator.mediaSession) return;

      if (changed || !navigator.mediaSession.metadata) {
        var title = document.title || 'Makaw Web Player';
        var artist = location.hostname;
        var artworkUrl = 'https://www.google.com/s2/favicons?domain=' + location.hostname + '&sz=128';

        try {
          navigator.mediaSession.metadata = new MediaMetadata({
            title: title,
            artist: artist,
            artwork: [{ src: artworkUrl, sizes: '128x128', type: 'image/png' }]
          });
        } catch(e) {}

        try {
          navigator.mediaSession.setActionHandler('play', function() { media.play(); });
          navigator.mediaSession.setActionHandler('pause', function() { media.pause(); });
          navigator.mediaSession.setActionHandler('seekbackward', function() { media.currentTime = Math.max(0, media.currentTime - 10); });
          navigator.mediaSession.setActionHandler('seekforward', function() { media.currentTime = Math.min(media.duration, media.currentTime + 10); });
        } catch(e) {}

        try {
          navigator.mediaSession.setActionHandler('previoustrack', null);
          navigator.mediaSession.setActionHandler('nexttrack', null);
        } catch(e) {}

        try {
          navigator.mediaSession.setActionHandler('seekto', function(details) {
            if (details.seekTime != null) media.currentTime = details.seekTime;
          });
        } catch(e) {}
      }

      navigator.mediaSession.playbackState = media.paused ? 'paused' : 'playing';
    } catch(e) {}
  }

  media = document.querySelector('video, audio');
  if (media) {
    ['play','pause','loadedmetadata','ended','seeked','timeupdate'].forEach(function(evt) {
      media.addEventListener(evt, tryBridge, {passive: true});
    });
  }

  var obs = new MutationObserver(function() {
    var m = document.querySelector('video, audio');
    if (m && !m._makawBound) {
      m._makawBound = true;
      ['play','pause','loadedmetadata','ended','seeked','timeupdate'].forEach(function(evt) {
        m.addEventListener(evt, tryBridge, {passive: true});
      });
      tryBridge();
    }
  });
  if (document.body) obs.observe(document.body, {childList: true, subtree: true});
})();
''').catchError((_) {});
  }

  void _handleDownload(String url) {
    _downloadManager.enqueue(url);
    _showToast('Download added: ${url.split('/').last.length > 40 ? '...' : url.split('/').last}');
  }

  void _showSavePasswordDialog() {
    final domain = Uri.tryParse(_pendingPasswordUrl)?.host ?? _pendingPasswordUrl;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Save Password?', style: TextStyle(color: Colors.white)),
        content: Text('Save login for $domain?', style: TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _pendingPasswordUrl = '';
              _pendingPasswordUsername = '';
              _pendingPasswordPassword = '';
            },
            child: Text('Never', style: TextStyle(color: Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _pendingPasswordUrl = '';
              _pendingPasswordUsername = '';
              _pendingPasswordPassword = '';
            },
            child: Text('Not now', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF14B8A6)),
            onPressed: () {
              passwordService.save(
                _pendingPasswordUrl,
                _pendingPasswordUsername,
                _pendingPasswordPassword,
              );
              Navigator.of(ctx).pop();
              _pendingPasswordUrl = '';
              _pendingPasswordUsername = '';
              _pendingPasswordPassword = '';
              _showToast('Password saved');
            },
            child: Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showPasswordSettings() async {
    final entries = await passwordService.getAll();
    final fixedEntries = List<PasswordEntry>.from(entries);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (ctx, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Text('Saved Passwords', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          Spacer(),
                          if (fixedEntries.isNotEmpty)
                            TextButton(
                              onPressed: () async {
                                for (final e in fixedEntries) { await passwordService.delete(e.id); }
                                setSheetState(() { fixedEntries.clear(); });
                                _showToast('All passwords cleared');
                              },
                              child: Text('Clear All', style: TextStyle(color: Color(0xFFEF4444))),
                            ),
                          IconButton(
                            icon: Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    if (fixedEntries.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text('No saved passwords', style: TextStyle(color: Color(0xFF64748B))),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: fixedEntries.length,
                          itemBuilder: (ctx, i) {
                            final entry = fixedEntries[i];
                            return ListTile(
                              title: Text(entry.domain, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                              subtitle: Text(entry.username, style: TextStyle(color: Color(0xFF94A3B8))),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.copy, color: Color(0xFF94A3B8), size: 18),
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      _showToast('Password copied');
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                                    onPressed: () async {
                                      await passwordService.delete(entry.id);
                                      setSheetState(() {
                                        fixedEntries.removeAt(i);
                                      });
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                _showToast('Username: ${entry.username}');
                              },
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showImportDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Import Data', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _importButton(ctx, 'Import Bookmarks (HTML)', Icons.bookmark, () async {
              final result = await importService.pickAndImportBookmarks();
              if (ctx.mounted) Navigator.of(ctx).pop();
              _showToast(result.summary);
            }),
            SizedBox(height: 12),
            _importButton(ctx, 'Import Passwords (CSV)', Icons.lock, () async {
              final result = await importService.pickAndImportPasswords();
              if (ctx.mounted) Navigator.of(ctx).pop();
              _showToast(result.summary);
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
        ],
      ),
    );
  }

  Widget _importButton(BuildContext ctx, String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Color(0xFF334155)),
          padding: EdgeInsets.symmetric(vertical: 14),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
        onPressed: onTap,
      ),
    );
  }

  // ─── AI Chat ─────────────────────────────────────────────────────────────────

  Future<void> _loadAiKey() async {
    final prefs = await SharedPreferences.getInstance();
    _aiApiKey = prefs.getString('gemini_api_key') ?? '';
    if (_aiApiKey.isNotEmpty) {
      _aiModel = GenerativeModel(model: 'gemini-2.0-flash', apiKey: _aiApiKey);
    }
  }

  void _showAISettings() {
    final ctrl = TextEditingController(text: _aiApiKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('AI Settings', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter your Gemini API key to enable AI features.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Gemini API Key',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                isDense: true,
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF14B8A6)),
            onPressed: () async {
              final key = ctrl.text.trim();
              if (key.isEmpty) return;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('gemini_api_key', key);
              _aiApiKey = key;
              _aiModel = GenerativeModel(model: 'gemini-2.0-flash', apiKey: key);
              if (ctx.mounted) Navigator.of(ctx).pop();
              _showToast('AI configured');
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAIChat() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _buildAIChatPage(),
    ));
  }

  Widget _buildAIChatPage() {
    final msgCtrl = TextEditingController();
    final scrollCtrl = ScrollController();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, size: 20, color: kAccentTeal),
          SizedBox(width: 8),
          Text('AI Assistant'),
        ]),
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface), onPressed: () => Navigator.of(context).pop()),
        actions: [
          if (_aiMessages.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              onPressed: () => setState(() => _aiMessages.clear()),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _aiMessages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 48, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                        SizedBox(height: 12),
                        Text('Ask me anything', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 16)),
                        SizedBox(height: 4),
                        Text('Powered by Gemini', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12)),
                        if (_aiApiKey.isEmpty) ...[
                          SizedBox(height: 20),
                          TextButton.icon(
                            onPressed: () { Navigator.of(context).pop(); _showAISettings(); },
                            icon: Icon(Icons.settings, size: 16),
                            label: Text('Set API Key'),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    padding: EdgeInsets.all(12),
                    itemCount: _aiMessages.length,
                    itemBuilder: (_, i) {
                      final msg = _aiMessages[i];
                      final isUser = msg['role'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: EdgeInsets.only(bottom: 8),
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isUser ? kAccentTeal.withOpacity(0.2) : Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16).copyWith(
                              bottomRight: isUser ? Radius.zero : null,
                              bottomLeft: isUser ? null : Radius.zero,
                            ),
                          ),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                          child: Text(msg['text'] ?? '', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                        ),
                      );
                    },
                  ),
          ),
          if (_aiLoading)
            Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kAccentTeal)),
            ),
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: msgCtrl,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) _aiSendMessage(v.trim());
                      msgCtrl.clear();
                    },
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send_rounded, color: kAccentTeal),
                  onPressed: () {
                    if (msgCtrl.text.trim().isNotEmpty) {
                      _aiSendMessage(msgCtrl.text.trim());
                      msgCtrl.clear();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _aiSendMessage(String text) async {
    if (_aiApiKey.isEmpty) {
      _showToast('Set API key in Settings > AI Settings');
      return;
    }
    setState(() {
      _aiMessages.add({'role': 'user', 'text': text});
      _aiLoading = true;
    });
    try {
      _aiModel ??= GenerativeModel(model: 'gemini-2.0-flash', apiKey: _aiApiKey);
      final chat = _aiModel!.startChat();
      final content = Content.text(text);
      final response = await chat.sendMessage(content);
      setState(() {
        _aiMessages.add({'role': 'model', 'text': response.text ?? 'No response'});
        _aiLoading = false;
      });
    } catch (e) {
      setState(() {
        _aiMessages.add({'role': 'model', 'text': 'Error: $e'});
        _aiLoading = false;
      });
    }
  }

  // ─── QR Scanner ──────────────────────────────────────────────────────────────

  void _scanQRCode() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      _showToast('Camera permission denied');
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => QrScannerPage(
        onScan: (value) {
          Navigator.of(ctx).pop();
          if (value.startsWith('http://') || value.startsWith('https://')) {
            _navigateInCurrentTab(value);
          } else {
            _navigateInCurrentTab('https://www.google.com/search?q=${Uri.encodeComponent(value)}');
          }
        },
      ),
    ));
  }


  // ─── Sniffer Tab ────────────────────────────────────────────────────────────

  Widget _buildSnifferTab() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          color: Color(0xFF1E293B),
          child: Row(
            children: [
              Icon(Icons.wifi_tethering, color: Color(0xFF818CF8)),
              SizedBox(width: 8),
              Text('Media Detector', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Spacer(),
              if (_pendingMedia.isNotEmpty) ...[
                TextButton(
                  onPressed: _showMediaSnifferPage,
                  child: Text('Download All (${_pendingMedia.length})', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 8), minimumSize: Size(0, 28)),
                ),
                TextButton(
                  onPressed: () => setState(() => _pendingMedia.clear()),
                  child: Text('Clear', style: TextStyle(fontSize: 12, color: Colors.red)),
                  style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 8), minimumSize: Size(0, 28)),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _pendingMedia.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No media detected', style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 8),
                      Text('Browse sites with video/audio in the Browser tab', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _pendingMedia.length,
                  itemBuilder: (ctx, i) {
                    final item = _pendingMedia[i];
                    return Card(
                      color: Color(0xFF1E293B),
                      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(item.type == 'video' ? Icons.movie : item.type == 'audio' ? Icons.music_note : Icons.image, color: Color(0xFF818CF8), size: 18),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (item.title.isNotEmpty)
                                        Text(item.title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text(item.type.toUpperCase(), style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.play_arrow, size: 16, color: Colors.green),
                                      onPressed: () {
                                        setState(() {
                                          _playVideoUrl = item.url;
                                          _playVideoTitle = item.title.isNotEmpty ? item.title : item.url.split('/').last.split('?').first;
                                        });
                                        _switchToView('player');
                                      },
                                      tooltip: 'Play',
                                      constraints: BoxConstraints(minWidth: 24, minHeight: 24),
                                      padding: EdgeInsets.all(2),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.download, size: 16, color: Colors.cyan),
                                      onPressed: () {
                                        _downloadManager.enqueue(item.url, filename: item.url.split('/').last.split('?').first);
                                        _showToast('Added to downloads');
                                      },
                                      tooltip: 'Download original',
                                      constraints: BoxConstraints(minWidth: 24, minHeight: 24),
                                      padding: EdgeInsets.all(2),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (item.url.length > 60)
                              Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(item.url, style: TextStyle(fontSize: 9, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            if (item.formats.isNotEmpty) ...[
                              SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                children: item.formats.map((f) {
                                  return InkWell(
                                    onTap: () {
                                      _downloadManager.enqueue(f.url, filename: f.url.split('/').last.split('?').first);
                                      _showToast('Downloading ${f.label}');
                                    },
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Color(0xFF374151),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Color(0xFF4B5563), width: 0.5),
                                      ),
                                      child: Text(f.label, style: TextStyle(fontSize: 10, color: Color(0xFF93C5FD))),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── Snippets Tab ───────────────────────────────────────────────────────────

  Widget _buildSnippetsTab() {
    final filtered = _snippetSearch.isEmpty
        ? _snippets
        : _snippets.where((s) => s['name']!.toLowerCase().contains(_snippetSearch.toLowerCase())).toList();
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          color: Color(0xFF1E293B),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search snippets...',
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            onChanged: (v) => setState(() => _snippetSearch = v),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text('No snippets found', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final s = filtered[i];
                    return ListTile(
                      dense: true,
                      title: Text(s['name']!, style: TextStyle(fontSize: 13)),
                      trailing: Icon(Icons.content_paste, size: 16, color: Color(0xFF818CF8)),
                      onTap: () {
                        _openFileInEditor('snippet.dart', s['code'] ?? '');
                        _switchToView('studio');
                        _showToast('Snippet inserted');
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── Projects Tab ───────────────────────────────────────────────────────────

  Widget _buildProjectsTab() {
    return _projects.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_open, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('No saved projects', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 8),
                Text('Write code in Studio and tap Save', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          )
        : ListView.builder(
            itemCount: _projects.length,
            itemBuilder: (ctx, i) {
              final p = _projects[i];
              final name = p['name'] ?? 'untitled';
              final lang = p['language'] ?? 'javascript';
              final updated = p['updated_at'] ?? '';
              return Card(
                color: Color(0xFF1E293B),
                margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: Icon(Icons.insert_drive_file, color: Color(0xFF818CF8)),
                  title: Text(name, style: TextStyle(fontSize: 14)),
                  subtitle: Text('$lang  •  ${updated.toString().substring(0, 10)}', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: Icon(Icons.open_in_new, size: 16, color: Color(0xFF818CF8)),
                  onTap: () async {
                    setState(() {
                      _currentProject = name;
                      _currentLang = lang;
                    });
                    final content = p['content'] ?? '';
                    _openFileInEditor('$name.$lang', content, language: lang);
                    _switchToView('studio');
                  },
                ),
              );
            },
          );
  }

  // ─── Git Tab ────────────────────────────────────────────────────────────────

  Widget _buildGitTab() {
    return Padding(
      padding: EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: InputDecoration(labelText: 'Project Path', hintText: _projectPath, isDense: true),
            controller: TextEditingController(text: _projectPath),
            onChanged: (v) => _projectPath = v,
          ),
          SizedBox(height: 6),
          // Row 1: Basic ops
          Wrap(spacing: 4, runSpacing: 4, children: [
            _smallBtn('Init', () async { await GitDir.init(_projectPath); _refreshBranches(); }),
            _smallBtn('Status', _gitStatus),
            _smallBtn('Log', _gitLog),
            _smallBtn('Diff', _gitDiff),
            _smallBtn('Commit', _gitCommit),
            _smallBtn('Push', _gitPush),
            _smallBtn('Pull', _gitPull),
            _smallBtn('Fetch', _gitFetch),
          ]),
          SizedBox(height: 6),
          // Row 2: Advanced ops
          Wrap(spacing: 4, runSpacing: 4, children: [
            _smallBtn('Stash', _gitStash),
            _smallBtn('Stash Pop', _gitStashPop),
            _smallBtn('New Branch', _gitCreateBranch),
            _smallBtn('Tag', _gitTag),
            _smallBtn('Add Remote', _gitAddRemote),
            _smallBtn('Reset Hard', _gitReset),
          ]),
          SizedBox(height: 6),
          // Branch selector
          Row(children: [
            Expanded(child: DropdownButton<String>(
              value: _currentBranch.isEmpty ? null : _currentBranch,
              hint: Text('Branch', style: TextStyle(fontSize: 13)),
              isExpanded: true,
              style: TextStyle(fontSize: 13, color: Colors.white),
              dropdownColor: Color(0xFF1E293B),
              items: _branches.map((b) => DropdownMenuItem(value: b, child: Text(b, style: TextStyle(fontSize: 13)))).toList(),
              onChanged: (b) => _gitCheckout(b!),
            )),
            IconButton(icon: Icon(Icons.refresh, size: 18), onPressed: _refreshBranches),
          ]),
          _smallBtn('Merge Current Branch', () => _gitMerge(_currentBranch)),
          SizedBox(height: 6),
          // Conflicts
          if (_conflictedFiles.isNotEmpty)
            Container(
              padding: EdgeInsets.all(6),
              color: Colors.red[900],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CONFLICTS:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ..._conflictedFiles.map((f) => TextButton(
                    onPressed: () => _showConflictResolver(f),
                    child: Text(f, style: TextStyle(color: Colors.white, fontSize: 12)),
                  )),
                ],
              ),
            ),
          SizedBox(height: 6),
          // Output
          Text('Output:', style: TextStyle(color: Colors.grey, fontSize: 11)),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(color: Color(0xFF0F172A), border: Border.all(color: Color(0xFF334155))),
              child: SingleChildScrollView(
                child: SelectableText(_gitOutput, style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFFE2E8F0))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallBtn(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size(0, 28)),
      child: Text(label, style: TextStyle(fontSize: 11)),
    );
  }

  // ─── Cloud Tab ──────────────────────────────────────────────────────────────

  Widget _buildCloudTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.cloud, size: 48, color: Color(0xFF818CF8)),
          SizedBox(height: 12),
          Text('iCloud / Google Drive Sync', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          SizedBox(height: 24),
          _cloudBtn(Icons.cloud_upload, 'Backup to Google Drive', _backupToDrive, Color(0xFF818CF8)),
          SizedBox(height: 12),
          _cloudBtn(Icons.cloud_download, 'Restore from Google Drive', _restoreFromDrive, Color(0xFF6366F1)),
          SizedBox(height: 24),
          Text(
            'Note: On iOS, the makaw.db file can be stored in iCloud Drive for automatic sync between devices.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _cloudBtn(IconData icon, String label, VoidCallback onPressed, Color color) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  // ─── Terminal Tab ───────────────────────────────────────────────────────────

  Widget _buildTerminalTab() {
    if (kIsWeb) {
      return Container(
        decoration: BoxDecoration(color: Color(0xFF0F172A)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.terminal, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text('Terminal is not available on web', style: TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
        ),
      );
    }
    _startPty();
    return Container(
      decoration: BoxDecoration(color: Color(0xFF0F172A)),
      child: Column(
        children: [
          Expanded(
            child: TerminalView(
              _terminal,
              controller: _terminalController,
              theme: TerminalThemes.defaultTheme,
              autofocus: true,
            ),
          ),
          Container(
            color: Color(0xFF1E293B),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 16, color: Colors.grey),
                SizedBox(width: 8),
                Text('Terminal', style: TextStyle(color: Colors.grey, fontSize: 12)),
                Spacer(),
                _iconBtn(Icons.block, 'Ctrl+C', () => _pty?.write(utf8.encode('\x03'))),
                SizedBox(width: 4),
                _iconBtn(Icons.stop, 'Ctrl+D', () => _pty?.write(utf8.encode('\x04'))),
                SizedBox(width: 4),
                _iconBtn(Icons.refresh, 'Clear', () { _terminal.eraseDisplay(); _terminal.eraseScrollbackOnly(); }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── QR Scanner Page Widget ───────────────────────────────────────────────

// QrScannerPage moved to features/browser/presentation/pages/qr_scanner_page.dart

// ─── Tab Tray Page ────────────────────────────────────────────────────────

// TabTrayPage moved to features/browser/presentation/pages/tab_tray_page.dart
