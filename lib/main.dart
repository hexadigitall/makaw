import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide ContentBlocker;
import 'package:url_launcher/url_launcher.dart';
import 'services/password_manager.dart';
import 'services/import_service.dart';
import 'services/news_feed_service.dart';
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
import 'package:xterm/xterm.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'services/content_blocker.dart';
import 'services/download_manager.dart';
import 'services/update_service.dart';
import 'services/media_notification_service.dart';
import 'widgets/news_feed_widget.dart';
import 'widgets/downloads_widget.dart';
import 'widgets/video_player_widget.dart';
import 'widgets/pdf_viewer_widget.dart';
import 'widgets/epub_viewer_widget.dart';
import 'widgets/music_player_widget.dart';
import 'widgets/image_viewer_widget.dart';
import 'services/music_player_service.dart';
import 'services/image_viewer_service.dart';
import 'services/video_player_service.dart';
import 'services/document_service.dart';
import 'widgets/document_widget.dart';

// ── Makaw Design Tokens ─────────────────────────────────────────────────────
const kIconBgColor = Color(0xFF2B3845);
const kAccentOrange = Color(0xFFD44D33);
const kAccentTeal = Color(0xFF00A7C2);


// ─── Models ───────────────────────────────────────────────────────────────────

enum ViewMode { home, newTab, typeView, browsing }

class ConflictPart {
  String ours = '';
  String theirs = '';
  bool inTheirs = false;
}

class BrowserTab {
  int id;
  String url;
  String title;
  bool incognito;
  BrowserTab({required this.id, required this.url, this.title = 'New Tab', this.incognito = false});
}

class MediaItem {
  final String url;
  final String type;
  final String title;
  final List<MediaFormat> formats;
  MediaItem({required this.url, required this.type, this.title = '', this.formats = const []});
}

class MediaFormat {
  final String label;
  final String url;
  final String mimeType;
  final int? height;
  final int? bitrate;
  MediaFormat({required this.label, required this.url, this.mimeType = '', this.height, this.bitrate});
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
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    print('FLUTTER ERROR: ${details.exception}');
    print('STACK: ${details.stack}');
  };
  await globalMusicService.init();
  await _initMediaNotification();
  runApp(MakawApp());
}

final MusicPlayerService globalMusicService = MusicPlayerService();
String audioServiceStatus = 'unknown';

const _systemChannel = MethodChannel('com.example.makaw_mobile/system');

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

class MakawApp extends StatefulWidget {
  const MakawApp({super.key});
  @override
  _MakawAppState createState() => _MakawAppState();
}

class _MakawAppState extends State<MakawApp> with WidgetsBindingObserver {
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

class MakawHome extends StatefulWidget {
  final String themeMode;
  final void Function(String mode)? onThemeChanged;
  const MakawHome({required this.themeMode, this.onThemeChanged});
  @override
  _MakawHomeState createState() => _MakawHomeState();
}

class _MakawHomeState extends State<MakawHome> {
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

  // Browser tabs
  List<BrowserTab> _browserTabs = [];
  int _activeBrowserTabId = 0;
  int _browserTabIdCounter = 0;

  final Map<int, InAppWebViewController> _tabWebviews = {};
  final Map<int, PullToRefreshController> _tabRefreshControllers = {};
  final Map<int, bool> _tabReady = {};
  final Map<int, int> _tabProgress = {};
  final Map<int, String> _pendingNavigationUrls = {};
  List<(String, String)> _shortcuts = [];
  bool _shortcutsLoaded = false;
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
  bool _ignoreUrlChanges = false;
  Timer? _suggestDebounce;
  int _historyPage = 0;
  static const int _historyPageSize = 50;

  bool _desktopSite = false;
  final TextEditingController _findController = TextEditingController();

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
      setState(() {
        _viewMode = ViewMode.typeView;
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
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)).then((_) {
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
      case 'history': return _buildFeatureScaffold('Browser History', Icons.history, _buildHistoryTab());
      case 'studio': return _buildFeatureScaffold('Code Studio', Icons.code, _buildStudioTab());
      case 'sniffer': return _buildFeatureScaffold('Media Sniffer', Icons.wifi_tethering, _buildSnifferTab());
      case 'snippets': return _buildFeatureScaffold('Snippets', Icons.content_paste, _buildSnippetsTab());
      case 'projects': return _buildFeatureScaffold('Projects', Icons.folder, _buildProjectsTab());
      case 'git': return _buildFeatureScaffold('Git', Icons.account_tree, _buildGitTab());
      case 'cloud': return _buildFeatureScaffold('Cloud Sync', Icons.cloud, _buildCloudTab());
      case 'terminal': return _buildFeatureScaffold('Terminal', Icons.terminal, _buildTerminalTab());
      case 'downloads': return _buildFeatureScaffold('Downloads', Icons.download, _buildDownloadsTab());
      case 'player': return VideoPlayerWidget(service: _videoService, onOpenMusic: () => _switchToView('music'), onHome: () => _switchToView('media'));
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
  final ContentBlocker _contentBlocker = ContentBlocker();
  late final DownloadManager _downloadManager;
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
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _searchController = TextEditingController();
    _terminalInputController = TextEditingController();
    _terminalFocusNode = FocusNode();
    _newsFeedService = NewsFeedService();
    _newsFeedService!.init();
    _newsFeedService!.ensureLocationReady();
    _urlController.addListener(_onUrlChanged);
    _urlFocusNode.addListener(_onUrlFocusChanged);
    _musicService.addListener(_onMusicChanged);

    // Defer heavy init to after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadSavedSession();
      setState(() => _ready = true);
      _newsFeedService!.loadTaps();
      _loadShortcuts();
      _initDownloadDir();
      _musicService.loadPlaylists();
      _musicService.loadFavorites();
      _requestNotificationPermission();
      _imageService.loadFavorites();
      _imageService.loadTrash();
      // _imageService.scanAllImages(); // disabled — hangs on this device
      _videoService.loadFavorites();
      _videoService.loadPlaylists();
      _videoService.loadResumePositions();
      _videoService.scanAllVideos();
      _documentService.loadFavorites();
      // _documentService.scanAllDocuments(); // disabled — hangs on this device
      _downloadManager = DownloadManager(
        dio: Dio(BaseOptions(
          connectTimeout: Duration(seconds: 15),
          receiveTimeout: Duration(seconds: 60),
          sendTimeout: Duration(seconds: 30),
        )),
        getDownloadDir: _defaultDownloadDir,
        showNotification: _showToast,
        onComplete: null,
      );
      _updateService = UpdateService(
        updateUrl: 'https://your-org.github.io/makaw/update.json',
        dio: Dio(),
      );
      CookieManager.instance().deleteAllCookies().catchError((_) {});
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
    const channel = MethodChannel('com.example.makaw_mobile/intent');
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
    } else if (mimeType.contains('msword') || mimeType.contains('openxmlformats') || path.endsWith('.doc') || path.endsWith('.docx')) {
      OpenFilex.open(path);
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
      version: 2,
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
            UNIQUE(url)
          )
        ''');
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
      },
    );
    _loadProjects();
    _loadHistory();
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
            final id = DateTime.now().microsecondsSinceEpoch + _browserTabs.length;
            _browserTabs.add(BrowserTab(id: id, url: t['url'] as String? ?? '', title: t['title'] as String? ?? '', incognito: t['incognito'] as bool? ?? false));
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
  }

  Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    final tabsJson = jsonEncode(_browserTabs.map((t) => {
      'url': t.url,
      'title': t.title,
      'incognito': t.incognito,
    }).toList());
    await prefs.setString('saved_tabs', tabsJson);
    await prefs.setInt('active_tab_id', _activeBrowserTabId);
  }

  // ─── Terminal ───────────────────────────────────────────────────────────────

  void _startPty() {
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

  InAppWebViewController? get _activeWebview =>
      _tabWebviews[_activeBrowserTabId];

  void _createBrowserTab({bool incognito = false}) {
    final id = ++_browserTabIdCounter;
    setState(() {
      _browserTabs.add(BrowserTab(id: id, url: '', incognito: incognito));
      _activeBrowserTabId = id;
      _viewMode = ViewMode.newTab;
    });
    _urlController.clear();
    _syncUrlController();
    _saveSession();
  }

  void _showBrowsingView() {
    setState(() {
      _viewMode = ViewMode.typeView;
    });
  }

  void _switchBrowserTab(int id) {
    _urlFocusNode.unfocus();
    setState(() {
      _activeBrowserTabId = id;
      final tab = _browserTabs.firstWhere((t) => t.id == id, orElse: () => _browserTabs.first);
      _viewMode = tab.url.isEmpty ? ViewMode.newTab : ViewMode.browsing;
    });
    _syncUrlController();
  }

  void _closeBrowserTab(int id) {
    final idx = _browserTabs.indexWhere((t) => t.id == id);
    setState(() {
      _browserTabs.removeWhere((t) => t.id == id);
      _tabWebviews.remove(id);
      _tabReady.remove(id);
      _tabProgress.remove(id);
      _tabRefreshControllers.remove(id);
      if (_browserTabs.isEmpty) {
        _goHome();
        _activeBrowserTabId = 0;
      } else if (_activeBrowserTabId == id) {
        final next = _browserTabs[idx > 0 ? idx - 1 : 0];
        _activeBrowserTabId = next.id;
      }
    });
    _syncUrlController();
    _saveSession();
  }

  void _onBrowserNavigation(String url) {
    final tab = _browserTabs.firstWhere((t) => t.id == _activeBrowserTabId, orElse: () => _browserTabs.first);
    if (tab.url == url && tab.url.isNotEmpty) return;
    tab.url = url;
    tab.title = url;
    _suggestDebounce?.cancel();
    _ignoreUrlChanges = true;
    if (!_showHomeScreen) _urlController.text = url;
    _ignoreUrlChanges = false;
    _addHistoryEntry(url, tab.title);
    _saveSession();
    setState(() {
      _viewMode = ViewMode.browsing;
      _urlSuggestions = [];
      _searchSuggestions = [];
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
    });
  }

  void _addHistoryEntry(String url, String title) {
    _browserHistory.removeWhere((e) => e['url'] == url);
    _browserHistory.insert(0, <String, dynamic>{'url': url, 'title': title, 'time': DateTime.now().toIso8601String()});
    if (_browserHistory.length > 500) _browserHistory.removeRange(500, _browserHistory.length);
    _db?.insert('history', {
      'url': url,
      'title': title,
      'time': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace).catchError((_) {});
  }

  void _navigateToUrl(String raw) {
    String url;
    if (raw.contains(' ') || (!raw.contains('.') && !raw.contains('://'))) {
      url = 'https://www.google.com/search?q=${Uri.encodeComponent(raw)}';
    } else {
      url = raw.startsWith('http://') || raw.startsWith('https://') ? raw : 'https://$raw';
    }

    _suggestDebounce?.cancel();
    final id = ++_browserTabIdCounter;
    _ignoreUrlChanges = true;
    _urlController.text = url;
    _ignoreUrlChanges = false;
    setState(() {
      _browserTabs.add(BrowserTab(id: id, url: url, incognito: false));
      _activeBrowserTabId = id;
      _viewMode = ViewMode.browsing;
      _urlSuggestions = [];
      _searchSuggestions = [];
    });
    _addHistoryEntry(url, url);
    _saveSession();
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
      // No tabs exist — create a new tab via _navigateToUrl
      _navigateToUrl(raw);
      return;
    }
    final tab = _browserTabs.firstWhere((t) => t.id == _activeBrowserTabId, orElse: () => _browserTabs.first);
    tab.url = url;
    tab.title = url;
    setState(() {
      _viewMode = ViewMode.browsing;
      _urlSuggestions = [];
      _searchSuggestions = [];
    });
    _addHistoryEntry(url, url);
    _saveSession();
    final c = _activeWebview;
    if (c != null) {
      c.loadUrl(urlRequest: URLRequest(url: WebUri(url)))
          .catchError((_) {});
    } else {
      _pendingNavigationUrls[_activeBrowserTabId] = url;
    }
  }

  void _showTabSwitcher() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TabTrayPage(
          tabs: _browserTabs,
          activeTabId: _activeBrowserTabId,
          onSwitchTab: (id) {
            _switchBrowserTab(id);
          },
          onCloseTab: (id) {
            _closeBrowserTab(id);
          },
          onCreateTab: () {
            Navigator.of(context).pop();
            _createBrowserTab();
          },
          onCreateIncognitoTab: () {
            Navigator.of(context).pop();
            _createBrowserTab(incognito: true);
          },
        ),
        fullscreenDialog: true,
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
      builder: (ctx) => _MediaSnifferPage(
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF1E293B),
        content: Row(
          children: [
            SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8)),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Downloading update...', style: TextStyle(fontSize: 14))),
          ],
        ),
      ),
    );

    final path = await _updateService.downloadApk(
      info,
      onProgress: (received, total) {},
    );

    if (mounted) Navigator.of(context).pop();

    if (!mounted) return;
    if (path == null) {
      scaffold.showSnackBar(SnackBar(content: Text('Download failed')));
      return;
    }

    scaffold.showSnackBar(SnackBar(content: Text('Installing...')));
    final installed = await _updateService.installApk(path);
    if (!installed) {
      scaffold.showSnackBar(SnackBar(content: Text('Installation failed. Open the APK manually from downloads.')));
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
        userAgent: null,
      ));
    }
    c.reload();
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
    _urlFocusNode.removeListener(_onUrlFocusChanged);
    _musicService.removeListener(_onMusicChanged);
    _downloadManager.dispose();
    _updateService.cleanOldApks();
    _pty?.kill();
    _urlController.dispose();
    _searchController.dispose();
    _terminalInputController.dispose();
    _terminalFocusNode.dispose();
    _tabWebviews.clear();
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
    return DownloadsWidget(
      manager: _downloadManager,
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
    return _FolderVideoPlayerWidget(
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
                      builder: (_) => VideoPlayerWidget(service: _videoService, onOpenMusic: () => _switchToView('music'), onHome: () => _switchToView('media')),
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
                if (_urlFocusNode.hasFocus) {
                  _urlFocusNode.unfocus();
                  primaryFocus?.unfocus();
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
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => _buildMediaHubPage()));
        }
      },
      child: MusicPlayerWidget(
        service: _musicService,
        onOpenVideos: () {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => VideoPlayerWidget(service: _videoService, onOpenMusic: () => _switchToView('music'), onHome: () => _switchToView('media'))));
        },
        onOpenSettings: () {
          _showToast('Music settings coming soon');
        },
      ),
    );
  }

  Widget _buildImagePage() {
    return ImageViewerWidget(service: _imageService);
  }

  Widget _buildDocumentPage() {
    return DocumentWidget(
      service: _documentService,
      openFile: (path) => _openFile(path),
    );
  }

  Widget _buildFeatureScaffold(String title, IconData icon, Widget body, {bool backToMediaHub = false}) {
    return PopScope(
      canPop: !backToMediaHub,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && backToMediaHub) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => _buildMediaHubPage()));
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 20, color: kAccentTeal), SizedBox(width: 8), Text(title)]),
          backgroundColor: Theme.of(context).colorScheme.surface,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
            onPressed: backToMediaHub
                ? () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => _buildMediaHubPage()))
                : () => Navigator.of(context).pop(),
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

  // ─── Browser Header ──────────────────────────────────────────────────────────

  Widget _buildBrowserHeader() {
    final tabCount = _browserTabs.length;
    final isHome = _isMakawHome;
    final isNewTab = _isNewTabView;

    if (_viewMode == ViewMode.typeView) {
      return _buildTypeViewHeader();
    }

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          if (isHome)
            IconButton(
              icon: Icon(Icons.menu, color: Theme.of(context).colorScheme.onSurface),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            )
          else
            IconButton(
              icon: Icon(Icons.home_outlined, color: Theme.of(context).colorScheme.onSurface),
              onPressed: _goHome,
            ),
          if (_viewMode == ViewMode.browsing)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _viewMode = ViewMode.typeView;
                  });
                  _urlFocusNode.requestFocus();
                },
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 8),
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _urlController.text.isNotEmpty ? _urlController.text : 'Search or enter address',
                    style: TextStyle(
                      color: _urlController.text.isNotEmpty ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            )
          else
            Spacer(),
          if (_viewMode != ViewMode.newTab && _viewMode != ViewMode.home)
            _buildIncognitoBadge(),
          GestureDetector(
            onTap: _showTabSwitcher,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tab, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                  SizedBox(width: 4),
                  Text('$tabCount', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.more_horiz, color: Theme.of(context).colorScheme.onSurface),
            onPressed: _showEllipsisMenu,
          ),
        ],
      ),
    );
  }

  Widget _buildIncognitoBadge() {
    if (!_browserTabs.any((t) => t.incognito)) return SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(right: 4),
      child: Icon(Icons.visibility_off, size: 16, color: Color(0xFF7C3AED)),
    );
  }

  Widget _buildTypeViewHeader() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.only(left: 4, right: 4, top: 4, bottom: 6),
      child: Row(
        children: [
          // + icon for file attachment
          PopupMenuButton<String>(
            icon: Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.onSurface, size: 26),
            onSelected: (v) {
              if (v == 'tabs') _showTabSwitcher();
              else if (v == 'camera') _scanQRCode();
              else if (v == 'gallery') _pickFile();
              else if (v == 'files') _pickFile();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'tabs', child: ListTile(leading: Icon(Icons.tab, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)), title: Text('Tabs', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)), dense: true)),
              PopupMenuItem(value: 'camera', child: ListTile(leading: Icon(Icons.camera_alt, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)), title: Text('Camera', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)), dense: true)),
              PopupMenuItem(value: 'gallery', child: ListTile(leading: Icon(Icons.photo_library, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)), title: Text('Gallery', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)), dense: true)),
              PopupMenuItem(value: 'files', child: ListTile(leading: Icon(Icons.folder, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)), title: Text('Files', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)), dense: true)),
            ],
          ),
          Expanded(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _urlController,
                focusNode: _urlFocusNode,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search or enter address',
                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 16),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) _navigateInCurrentTab(v.trim());
                },
              ),
            ),
          ),
          SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.mic, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 22),
            onPressed: () => _showToast('Voice search'),
          ),
          IconButton(
            icon: Icon(Icons.qr_code_scanner, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 22),
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
                    _ellipsisItem(Icons.tab, 'New Tab', () { Navigator.of(ctx).pop(); Future.microtask(_createBrowserTab); }),
                    _ellipsisItem(Icons.visibility_off, 'New Incognito', () { Navigator.of(ctx).pop(); Future.microtask(() => _createBrowserTab(incognito: true)); }),
                    _ellipsisItem(Icons.folder, 'Add to Group', () { _showToast('Tab groups coming soon'); Navigator.of(ctx).pop(); }),
                    _ellipsisItem(Icons.history, 'History', () { Navigator.of(ctx).pop(); _switchToView('history'); }),
                    _ellipsisItem(Icons.delete_sweep, 'Delete Browsing Data', () {
                      _tabWebviews.forEach((_, c) {
                        CookieManager.instance().deleteAllCookies().catchError((_) {});
                        c.clearCache().catchError((_) {});
                      });
                      _showToast('Browsing data cleared');
                      Navigator.of(ctx).pop();
                    }),
                    _ellipsisItem(Icons.download, 'Downloads', () { Navigator.of(ctx).pop(); _switchToView('downloads'); }),
                    _ellipsisItem(Icons.bookmark, 'Bookmarks', () {
                      Navigator.of(ctx).pop();
                      _showBookmarksDialog();
                    }),
                    _ellipsisItem(Icons.recent_actors, 'Recent Tabs', () { _showToast('Recent tabs'); Navigator.of(ctx).pop(); }),
                    _ellipsisItem(Icons.share, 'Share', () {
                      final url = _urlController.text;
                      if (url.isNotEmpty) {
                        Share.share(url);
                      }
                      Navigator.of(ctx).pop();
                    }),
                    _ellipsisItem(Icons.search, 'Find in Page', () { _showFindInPage(); Navigator.of(ctx).pop(); }),
                    _ellipsisItem(Icons.translate, 'Translate', () { _showToast('Translate'); Navigator.of(ctx).pop(); }),
                    _ellipsisItem(Icons.text_snippet, 'Show Reading Mode', () { _showToast('Reading mode'); Navigator.of(ctx).pop(); }),
                    _ellipsisItem(Icons.add_to_home_screen, 'Add to Home screen', () { _showToast('Add to Home screen'); Navigator.of(ctx).pop(); }),
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
                    onTap: () { Navigator.of(ctx2).pop(); _navigateInCurrentTab(s.$2); },
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
    return Stack(
      children: [
        Column(
          children: [
            if (!_isFullscreen) _buildBrowserHeader(),
            if (!showHome && progress != null && progress > 0 && progress < 100)
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress / 100.0,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  valueColor: AlwaysStoppedAnimation(kAccentTeal),
                  minHeight: 2,
                ),
              ),
            Expanded(
              child: showHome ? _buildHomeContent() : _buildWebviewArea(),
            ),
            if (!showHome && _musicService.currentSong != null) _buildMiniMusicPlayer(),
          ],
        ),
        if (_viewMode == ViewMode.typeView)
          Positioned.fill(child: _buildTypeView()),
      ],
    );
  }

  Widget _buildWebviewArea() {
    Widget content;
    if (_activeBrowserTabId != 0 && _browserTabs.isNotEmpty) {
      final tab = _browserTabs.firstWhere(
        (t) => t.id == _activeBrowserTabId,
        orElse: () => _browserTabs.first,
      );
      content = SizedBox(
        key: ValueKey('wv_${tab.id}'),
        child: _buildWebview(tab),
      );
    } else if (_browserTabs.isNotEmpty) {
      content = Container(color: Theme.of(context).colorScheme.surface);
    } else {
      content = Center(child: Text('No tabs open', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))));
    }
    return Stack(
      children: [
        content,
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
    if (_showHomeScreen) _urlController.clear();
    return RefreshIndicator(
      onRefresh: _refreshNewsFeed,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: Column(
        children: [
          SizedBox(height: 24),
          Image.asset('assets/makaw_logo_48.png', width: 48, height: 48, fit: BoxFit.contain),
          SizedBox(height: 10),
          Text('Makaw Browser',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.3,
            )),
          SizedBox(height: 36),
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
                        onSubmitted: _navigateInCurrentTab,
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
              onNavigate: (url) => _navigateInCurrentTab(url),
              scrollController: _newsFeedScrollController,
            ),
          SizedBox(height: 24),
        ],
      ),
      ),
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
        if (url != null && url.isNotEmpty) _navigateInCurrentTab(url);
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
                    onTap: () => _navigateInCurrentTab(lastUrl),
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

  Widget _buildToggleTile(StateSetter setDlgState, ContentBlocker cb, String label, bool value, ValueChanged<bool> onChanged) {
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

    final goToMediaHub = () => Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => _buildMediaHubPage()),
    );

    if (['mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'wmv', '3gp'].contains(ext)) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DirectVideoPlayer(
          filePath: filePath,
          title: filePath.split('\\').last.split('/').last,
        ),
      ));
      return;
    }
    if (ext == 'pdf') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PdfViewerWidget(
          filePath: filePath,
          title: filePath.split('\\').last.split('/').last,
          onClose: goToMediaHub,
        ),
      ));
    } else if (ext == 'epub') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EpubReaderWidget(
          filePath: filePath,
          title: filePath.split('\\').last.split('/').last,
          onClose: goToMediaHub,
        ),
      ));
    } else if (['mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'wma', 'opus'].contains(ext)) {
      _playAudioFileFromIntent(filePath);
    } else if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].contains(ext)) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _buildImageViewer(filePath, goToMediaHub),
      ));
    } else if (['txt', 'md', 'json', 'xml', 'yaml', 'yml', 'ini', 'cfg', 'log', 'csv'].contains(ext)) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _buildTextViewer(filePath, goToMediaHub),
      ));
    } else if (['html', 'htm', 'xhtml'].contains(ext)) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _buildHtmlViewer(filePath, goToMediaHub),
      ));
    } else if (['doc', 'docx'].contains(ext)) {
      OpenFilex.open(filePath);
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

  Widget _buildTextViewer(String filePath, VoidCallback onBack) {
    final name = filePath.split('\\').last.split('/').last;
    return FutureBuilder<String>(
      future: File(filePath).readAsString(),
      builder: (ctx, snap) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(name, style: TextStyle(fontSize: 14)),
            backgroundColor: Theme.of(context).colorScheme.surface,
            leading: IconButton(icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface), onPressed: onBack),
          ),
          body: snap.hasData
              ? SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: SelectableText(
                    snap.data!,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontFamily: 'monospace'),
                  ),
                )
              : Center(child: CircularProgressIndicator(color: kAccentTeal)),
        );
      },
    );
  }

  Widget _buildHtmlViewer(String filePath, VoidCallback onBack) {
    final name = filePath.split('\\').last.split('/').last;
    final uri = Uri.file(filePath);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(name, style: TextStyle(fontSize: 14)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface), onPressed: onBack),
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(uri.toString())),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useWideViewPort: true,
          supportZoom: true,
        ),
      ),
    );
  }

  void _onUrlChanged() {
    if (_ignoreUrlChanges) return;
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      setState(() => _urlSuggestions = []);
      return;
    }
    final lower = text.toLowerCase();
    final results = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final h in _browserHistory) {
      if (results.length >= 8) break;
      final url = (h['url'] as String? ?? '').toLowerCase();
      final title = (h['title'] as String? ?? '').toLowerCase();
      if ((url.contains(lower) || title.contains(lower)) && seen.add(url)) {
        results.add(h);
      }
    }
    // Add matching shortcuts/bookmarks too
    for (final s in _shortcuts) {
      if (results.length >= 8) break;
      final label = s.$1.toLowerCase();
      final url = s.$2.toLowerCase();
      if ((label.contains(lower) || url.contains(lower)) && seen.add(url)) {
        results.add(<String, dynamic>{'url': s.$2, 'title': s.$1, 'time': ''});
      }
    }
    setState(() => _urlSuggestions = results);
    _fetchSearchSuggestions(text);
  }

  void _fetchSearchSuggestions(String query) {
    _suggestDebounce?.cancel();
    if (query.length < 2) { setState(() => _searchSuggestions = []); return; }
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
        if (mounted) setState(() => _searchSuggestions = suggestions);
      } catch (_) {}
    });
  }

  // ─── Browsing View ─────────────────────────────────────────────────────────

  Widget _buildSuggestionItem(String display, String url, IconData icon) {
    return InkWell(
      onTap: () => _navigateInCurrentTab(url),
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
    return Column(
      children: [
        if (_urlSuggestions.isNotEmpty || _searchSuggestions.isNotEmpty)
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  if (_searchSuggestions.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Search suggestions', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    ..._searchSuggestions.take(5).map((s) => ListTile(
                      dense: true,
                      leading: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
                      title: Text(s, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                      onTap: () => _navigateInCurrentTab(s),
                    )),
                  ],
                  if (_urlSuggestions.isNotEmpty) ...[
                    if (_searchSuggestions.isNotEmpty) Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
                    ..._urlSuggestions.take(5).map((s) {
                      final url = s['url'] as String? ?? '';
                      final title = s['title'] as String? ?? '';
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.language, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
                        title: Text(title.isNotEmpty ? title : url, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                        onTap: () => _navigateInCurrentTab(url),
                      );
                    }),
                  ],
                ],
              ),
            ),
          )
        else
          Expanded(child: SizedBox.shrink()),
      ],
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

  Widget _buildWebview(BrowserTab tab) {
    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      supportZoom: true,
      cacheEnabled: true,
      cacheMode: CacheMode.LOAD_DEFAULT,
      domStorageEnabled: true,
      databaseEnabled: true,
      allowFileAccess: true,
    );

    return InAppWebView(
      key: ValueKey('webview_${tab.id}'),
      initialSettings: settings,
      initialUrlRequest: tab.url.isNotEmpty ? URLRequest(url: WebUri(tab.url)) : null,
      pullToRefreshController: _tabRefreshControllers.putIfAbsent(tab.id, () => PullToRefreshController(
        settings: PullToRefreshSettings(color: kAccentTeal),
        onRefresh: () {
          _tabWebviews[tab.id]?.reload();
        },
      )),
      onWebViewCreated: (ctrl) {
        _tabWebviews[tab.id] = ctrl;
        _tabReady[tab.id] = true;

        if (_pendingNavigationUrls.containsKey(tab.id) && tab.id == _activeBrowserTabId) {
          final url = _pendingNavigationUrls.remove(tab.id)!;
          ctrl.loadUrl(urlRequest: URLRequest(url: WebUri(url)))
              .catchError((e) => _showToast('Nav error: $e'));
        }

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
            final tabId = tab.id;
            final data = args.isNotEmpty && args[0] is List ? List<Map<String, dynamic>>.from(args[0]) : [];
            final list = _tabMedia.putIfAbsent(tabId, () => []);
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
              } else if (['pdf','epub','doc','docx','xls','xlsx','ppt','pptx','txt','csv'].contains(ext)) {
                type = 'document';
              } else {
                type = 'other';
              }
              final list = _tabMedia.putIfAbsent(_activeBrowserTabId, () => []);
              final exists = list.any((m) => m.url == url);
              if (!exists) {
                list.add(MediaItem(url: url, type: type, title: filename));
                if (_activeBrowserTabId == tab.id) setState(() {});
              }
            }
          } catch (_) {}
        });
        ctrl.addJavaScriptHandler(handlerName: 'popupBlocked', callback: (args) {
          final url = args.isNotEmpty ? args[0] as String : '';
          _showToast('Popup blocked: ${url.isNotEmpty ? url.split('/').last : 'unknown'}');
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
        if (_contentBlocker.shouldBlockUrl(url)) {
          return NavigationActionPolicy.CANCEL;
        }
        final ext = url.split('?')[0].split('#')[0].split('.').last.toLowerCase();
        final binaryExts = ['zip','rar','7z','tar','gz','apk','exe','msi','iso','img','dmg','deb','rpm','bin'];
        if (url.startsWith('http') && binaryExts.contains(ext)) {
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onLoadStart: (ctrl, url) {
        print('WEBVIEW_DEBUG: onLoadStart tab=${tab.id} url=$url');
        if (tab.id == _activeBrowserTabId) {
          _tabProgress[tab.id] = 0;
          _pendingMedia.clear();
          setState(() {});
          _onBrowserNavigation(url.toString());
        }
      },
      onLoadStop: (ctrl, url) {
        print('WEBVIEW_DEBUG: onLoadStop tab=${tab.id} url=$url');
        _tabRefreshControllers[tab.id]?.endRefreshing();
        _tabProgress[tab.id] = 100;
        if (tab.id == _activeBrowserTabId) {
          setState(() {
            _urlSuggestions = [];
            _searchSuggestions = [];
          });
        }
        if (tab.id == _activeBrowserTabId) {
          final cbScript = _contentBlocker.fullUserScript;
          if (cbScript.isNotEmpty) {
            ctrl.evaluateJavascript(source: cbScript).catchError((_) {});
          }
          _injectPasswordScripts(ctrl, url.toString());
          _injectFilePickerScript(ctrl);
          _injectMediaSnifferScript(ctrl);
          _injectDownloadInterceptorScript(ctrl);
        }
      },
      onProgressChanged: (ctrl, progress) {
        if (progress % 25 == 0) print('WEBVIEW_DEBUG: onProgressChanged tab=${tab.id} progress=$progress');
        _tabProgress[tab.id] = progress;
        if (tab.id == _activeBrowserTabId) setState(() {});
      },
      onReceivedError: (ctrl, request, error) {
        print('WEBVIEW_DEBUG: onReceivedError tab=${tab.id} url=${request.url} desc=${error.description} type=${error.type}');
        if (tab.id == _activeBrowserTabId && (request.isForMainFrame ?? false)) {
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
    final entries = await passwordManager.getForUrl(url);
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
  var docExts = ['pdf','epub','doc','docx','xls','xlsx','ppt','pptx','txt','csv'];
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
              passwordManager.save(
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
    final entries = await passwordManager.getAll();
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
                                for (final e in fixedEntries) { await passwordManager.delete(e.id); }
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
                                      await passwordManager.delete(entry.id);
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
      builder: (ctx) => _QrScannerPage(
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

// ─── Media Sniffer Page Widget ───────────────────────────────────────────

class _MediaSnifferPage extends StatefulWidget {
  final List<MediaItem> items;
  final void Function(MediaItem) onDownload;
  final void Function(List<MediaItem>) onDownloadAll;
  final VoidCallback onClear;
  final void Function(MediaItem, String) onRename;
  final void Function(String) showToast;

  const _MediaSnifferPage({
    required this.items,
    required this.onDownload,
    required this.onDownloadAll,
    required this.onClear,
    required this.onRename,
    required this.showToast,
  });

  @override
  State<_MediaSnifferPage> createState() => _MediaSnifferPageState();
}

class _MediaSnifferPageState extends State<_MediaSnifferPage> {
  bool _selectMode = false;
  late List<bool> _selected;
  late List<MediaItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
    _selected = List.filled(_items.length, false);
  }

  int get _selectedCount => _selected.where((s) => s).length;

  List<MediaItem> _sections(String type) =>
      _items.where((m) => m.type == type).toList();

  IconData _typeIcon(String type) {
    switch (type) {
      case 'video': return Icons.videocam;
      case 'image': return Icons.image;
      case 'audio': return Icons.music_note;
      case 'document': return Icons.description;
      default: return Icons.insert_drive_file;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'video': return const Color(0xFF818CF8);
      case 'image': return const Color(0xFF34D399);
      case 'audio': return const Color(0xFFFBBF24);
      case 'document': return const Color(0xFFF87171);
      default: return const Color(0xFF94A3B8);
    }
  }

  String _sectionLabel(String type) {
    switch (type) {
      case 'video': return 'Videos';
      case 'image': return 'Images';
      case 'document': return 'Documents';
      case 'audio': return 'Audio';
      default: return 'Other';
    }
  }

  IconData _sectionIcon(String type) {
    switch (type) {
      case 'video': return Icons.videocam;
      case 'image': return Icons.image;
      case 'document': return Icons.description;
      case 'audio': return Icons.music_note;
      default: return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sectionTypes = ['video', 'image', 'document', 'audio'];
    final availableTypes = sectionTypes.where((t) => _sections(t).isNotEmpty).toList();

    return Container(
      height: MediaQuery.of(context).size.height,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // ── Header ──
          Container(
            padding: EdgeInsets.fromLTRB(4, MediaQuery.of(context).padding.top + 4, 4, 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: Theme.of(context).cardColor, width: 0.5)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                if (_selectMode) ...[
                  Text('$_selectedCount Selected', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w600)),
                  Spacer(),
                  TextButton(
                    onPressed: _selectedCount == 0 ? null : () {
                      final toDelete = <MediaItem>[];
                      for (int i = _items.length - 1; i >= 0; i--) {
                        if (_selected[i]) toDelete.add(_items[i]);
                      }
                      widget.onDownloadAll(toDelete);
                      setState(() {
                        for (final item in toDelete) _items.remove(item);
                        _selected = List.filled(_items.length, false);
                        _selectMode = false;
                      });
                    },
                    child: Text('Delete', style: TextStyle(color: Colors.red, fontSize: 14)),
                  ),
                  SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.onSurface),
                    onPressed: () {
                      setState(() {
                        _selected.fillRange(0, _selected.length, false);
                        _selectMode = false;
                      });
                    },
                    tooltip: 'Refresh',
                  ),
                ] else ...[
                  Text('Media Sniffer', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
                  Spacer(),
                  TextButton(
                    onPressed: () {
                      widget.onClear();
                      Navigator.of(context).pop();
                    },
                    child: Text('Clear', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 14)),
                  ),
                  SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                    onSelected: (v) {
                      if (v == 'select') setState(() => _selectMode = true);
                      if (v == 'select_all') {
                        setState(() {
                          _selectMode = true;
                          _selected.fillRange(0, _selected.length, true);
                        });
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'select', child: Text('Select', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                      PopupMenuItem(value: 'select_all', child: Text('Select All', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // ── Content ──
          Expanded(
            child: _items.isEmpty
                ? Center(child: Text('No media found', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))))
                : ListView(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final type in availableTypes) ...[
                        // Section header
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Row(
                            children: [
                              Icon(_sectionIcon(type), size: 16, color: _typeColor(type)),
                              SizedBox(width: 6),
                              Text(_sectionLabel(type), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
                              Spacer(),
                              Text('${_sections(type).length}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12)),
                            ],
                          ),
                        ),
                        // Items
                        for (final item in _sections(type))
                          _buildMediaItem(context, item),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaItem(BuildContext context, MediaItem item) {
    final idx = _items.indexOf(item);
    final name = item.title.isNotEmpty ? item.title : item.url.split('/').last.split('?').first;
    final displayName = name.length > 45 ? '${name.substring(0, 45)}...' : name;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: _selectMode
          ? CheckboxListTile(
              dense: true,
              value: idx >= 0 && idx < _selected.length ? _selected[idx] : false,
              activeColor: kAccentTeal,
              checkColor: Colors.white,
              onChanged: (v) {
                if (idx < 0) return;
                setState(() => _selected[idx] = v ?? false);
              },
              secondary: Icon(_typeIcon(item.type), color: _typeColor(item.type), size: 22),
              title: Text(displayName, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
              subtitle: Text(item.url, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          : Padding(
              padding: EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_typeIcon(item.type), color: _typeColor(item.type), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w500)),
                            Text(item.url, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.edit, size: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                        onPressed: () => _showRenameDialog(context, item),
                        constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.all(4),
                        tooltip: 'Rename',
                      ),
                      IconButton(
                        icon: Icon(Icons.download, size: 18, color: kAccentTeal),
                        onPressed: () {
                          widget.onDownload(item);
                          widget.showToast('Added to downloads');
                        },
                        constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.all(4),
                        tooltip: 'Download',
                      ),
                    ],
                  ),
                  if (item.formats.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: item.formats.map((f) {
                        final selected = false;
                        return GestureDetector(
                          onTap: () {
                            widget.onDownload(MediaItem(url: f.url, type: item.type, title: item.title));
                            widget.showToast('Downloading ${f.label}');
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: selected ? kAccentTeal.withValues(alpha: 0.3) : Color(0xFF374151),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: selected ? kAccentTeal : Color(0xFF4B5563), width: 0.5),
                            ),
                            child: Text(f.label, style: TextStyle(fontSize: 11, color: selected ? kAccentTeal : Color(0xFF93C5FD))),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  void _showRenameDialog(BuildContext context, MediaItem item) {
    final ctl = TextEditingController(text: item.title.isNotEmpty ? item.title : item.url.split('/').last.split('?').first);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Rename', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Enter new name',
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)))),
          TextButton(
            onPressed: () {
              final newName = ctl.text.trim();
              if (newName.isNotEmpty) {
                widget.onRename(item, newName);
                setState(() {
                  final idx = _items.indexOf(item);
                  if (idx >= 0) _items[idx] = MediaItem(url: item.url, type: item.type, title: newName, formats: item.formats);
                });
              }
              Navigator.of(ctx).pop();
            },
            child: Text('Rename', style: TextStyle(color: kAccentTeal)),
          ),
        ],
      ),
    );
  }
}

// ─── QR Scanner Page Widget ───────────────────────────────────────────────

class _QrScannerPage extends StatefulWidget {
  final void Function(String) onScan;
  const _QrScannerPage({required this.onScan});

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  late final MobileScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Scan Code', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            errorBuilder: (ctx, error) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 48),
                    SizedBox(height: 12),
                    Text('Camera not available', style: TextStyle(color: Colors.white, fontSize: 16)),
                    SizedBox(height: 4),
                    Text('$error', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        await _controller.start();
                      },
                      child: Text('Retry'),
                    ),
                  ],
                ),
              );
            },
            onDetect: (capture) {
              final barcode = capture.barcodes.firstOrNull;
              if (barcode == null || barcode.rawValue == null) return;
              final value = barcode.rawValue!;
              widget.onScan(value);
            },
          ),
        ],
      ),
    );
  }
}

// ─── Folder Video Player Widget ────────────────────────────────────────────

class _FolderVideoPlayerWidget extends StatefulWidget {
  final List<String> files;
  final VoidCallback? onClose;

  const _FolderVideoPlayerWidget({required this.files, this.onClose});

  @override
  State<_FolderVideoPlayerWidget> createState() => _FolderVideoPlayerWidgetState();
}

class _FolderVideoPlayerWidgetState extends State<_FolderVideoPlayerWidget> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final filePath = widget.files[_currentIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(filePath.split('\\').last.split('/').last, style: TextStyle(fontSize: 13)),
        backgroundColor: Colors.black87,
        actions: [
          if (_currentIndex > 0)
            IconButton(icon: Icon(Icons.skip_previous), onPressed: () => setState(() => _currentIndex--)),
          Text('${_currentIndex + 1}/${widget.files.length}', style: TextStyle(color: Colors.white54, fontSize: 12)),
          if (_currentIndex < widget.files.length - 1)
            IconButton(icon: Icon(Icons.skip_next), onPressed: () => setState(() => _currentIndex++)),
          if (widget.onClose != null)
            IconButton(icon: Icon(Icons.close), onPressed: widget.onClose),
        ],
      ),
      body: DirectVideoPlayer(
        filePath: filePath,
        title: filePath.split('\\').last.split('/').last,
      ),
    );
  }
}

// ─── Tab Tray Page ────────────────────────────────────────────────────────

class _TabTrayPage extends StatefulWidget {
  final List<BrowserTab> tabs;
  final int activeTabId;
  final ValueChanged<int> onSwitchTab;
  final ValueChanged<int> onCloseTab;
  final VoidCallback onCreateTab;
  final VoidCallback? onCreateIncognitoTab;

  const _TabTrayPage({
    required this.tabs,
    required this.activeTabId,
    required this.onSwitchTab,
    required this.onCloseTab,
    required this.onCreateTab,
    this.onCreateIncognitoTab,
  });

  @override
  _TabTrayPageState createState() => _TabTrayPageState();
}

class _TabTrayPageState extends State<_TabTrayPage> {
  late List<BrowserTab> _tabs;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showIncognito = false;

  @override
  void initState() {
    super.initState();
    _tabs = List.from(widget.tabs);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _friendlyTitle(String url) {
    final u = url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'^www\.'), '');
    final idx = u.indexOf('/');
    return idx > 0 ? u.substring(0, idx) : u;
  }

  void _closeTab(int id) {
    final removed = _tabs.where((t) => t.id == id).toList();
    setState(() {
      _tabs.removeWhere((t) => t.id == id);
    });
    widget.onCloseTab(id);
  }

  List<BrowserTab> get _visibleTabs {
    final filtered = _tabs.where((t) => t.incognito == _showIncognito).toList();
    if (_searchQuery.isEmpty) return filtered;
    return filtered.where((t) {
      final title = (t.title.isNotEmpty ? t.title : t.url).toLowerCase();
      final url = t.url.toLowerCase();
      return title.contains(_searchQuery) || url.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kAccentTeal = isDark ? const Color(0xFF14B8A6) : const Color(0xFF0D9488);
    final kIconBgColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final kIncognitoPurple = const Color(0xFF7C3AED);

    final hasIncognitoTabs = _tabs.any((t) => t.incognito);
    final regularCount = _tabs.where((t) => !t.incognito).length;
    final incognitoCount = _tabs.where((t) => t.incognito).length;
    final visible = _visibleTabs;
    final isEmptyState = visible.isEmpty;
    final count = _showIncognito ? incognitoCount : regularCount;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
        children: [
          // Header
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                // + button (farthest left)
                IconButton(
                  icon: Icon(Icons.add_circle_outline, color: kAccentTeal, size: 28),
                  onPressed: widget.onCreateTab,
                  splashRadius: 20,
                ),
                Spacer(),
                // Tab icon (center)
                GestureDetector(
                  onTap: () => setState(() => _showIncognito = false),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _showIncognito ? Theme.of(context).cardColor : kAccentTeal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _showIncognito ? Theme.of(context).colorScheme.onSurface.withOpacity(0.3) : kAccentTeal.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tab, size: 18, color: _showIncognito ? Theme.of(context).colorScheme.onSurface.withOpacity(0.6) : kAccentTeal),
                        SizedBox(width: 4),
                        Text('$regularCount', style: TextStyle(color: _showIncognito ? Theme.of(context).colorScheme.onSurface.withOpacity(0.6) : kAccentTeal, fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                // Incognito icon (only if incognito tabs exist)
                if (hasIncognitoTabs) ...[
                  SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() => _showIncognito = true),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: _showIncognito ? kIncognitoPurple.withOpacity(0.15) : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _showIncognito ? kIncognitoPurple.withOpacity(0.3) : Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_off, size: 16, color: _showIncognito ? kIncognitoPurple : Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                          SizedBox(width: 4),
                          Text('$incognitoCount', style: TextStyle(color: _showIncognito ? kIncognitoPurple : Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
                Spacer(),
                // Inverted ellipsis (farthest right)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz, color: Theme.of(context).colorScheme.onSurface),
                  onSelected: (v) {
                    switch (v) {
                      case 'new_tab':
                        Navigator.of(context).pop();
                        widget.onCreateTab();
                      case 'new_incognito':
                        Navigator.of(context).pop();
                        widget.onCreateIncognitoTab?.call();
                      case 'close_all':
                        final toClose = _tabs.where((t) => t.incognito == _showIncognito).toList();
                        for (final tab in toClose) widget.onCloseTab(tab.id);
                        setState(() => _tabs.removeWhere((t) => toClose.any((tc) => tc.id == t.id)));
                      case 'select_tabs':
                        Navigator.of(context).pop();
                      case 'delete_data':
                        Navigator.of(context).pop();
                      case 'settings':
                        Navigator.of(context).pop();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'new_tab', child: Row(children: [Icon(Icons.add, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)), SizedBox(width: 12), Text('New tab', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))])),
                    PopupMenuItem(value: 'new_incognito', child: Row(children: [Icon(Icons.visibility_off, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)), SizedBox(width: 12), Text('New Incognito tab', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))])),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'close_all', child: Row(children: [Icon(Icons.close, size: 18, color: Colors.redAccent), SizedBox(width: 12), Text('Close all tabs', style: TextStyle(color: Colors.redAccent))])),
                    PopupMenuItem(value: 'select_tabs', child: Row(children: [Icon(Icons.checklist, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)), SizedBox(width: 12), Text('Select tabs', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))])),
                    PopupMenuItem(value: 'delete_data', child: Row(children: [Icon(Icons.delete_sweep_outlined, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)), SizedBox(width: 12), Text('Delete browsing data', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))])),
                    PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)), SizedBox(width: 12), Text('Settings', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))])),
                  ],
                ),
              ],
            ),
          ),
          // Search bar
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search your tabs',
                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 20),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ),
          Expanded(
            child: isEmptyState
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_showIncognito ? Icons.visibility_off : Icons.tab, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4), size: 48),
                      SizedBox(height: 12),
                      Text(_searchQuery.isNotEmpty ? 'No matching tabs' : 'No ${_showIncognito ? 'incognito ' : ''}tabs', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final tab = visible[i];
                    final isActive = tab.id == widget.activeTabId;
                    final isNewTab = tab.url.isEmpty || tab.url == 'about:blank';
                    final displayUrl = isNewTab ? '' : tab.url;
                    final displayTitle = isNewTab ? 'New Tab' : tab.title;
                    final domain = _friendlyTitle(displayUrl);
                    return Dismissible(
                      key: ValueKey('tab_${tab.id}'),
                      direction: DismissDirection.horizontal,
                      background: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.delete_outline, color: Colors.white, size: 28),
                      ),
                      onDismissed: (_) => _closeTab(tab.id),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            widget.onSwitchTab(tab.id);
                            Navigator.of(context).pop();
                          },
                          child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: isActive ? Border.all(color: kAccentTeal, width: 2) : null,
                          ),
                          child: Column(
                            children: [
                              // Card header: icon + title + close
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(isActive ? 10 : 12)),
                                ),
                                child: Row(
                                  children: [
                                    isNewTab
                                      ? Container(
                                          width: 20, height: 20,
                                          child: Icon(Icons.public, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                                        )
                                      : Container(
                                          width: 20, height: 20,
                                          decoration: BoxDecoration(
                                            color: kIconBgColor,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              domain.isNotEmpty ? domain[0].toUpperCase() : '?',
                                              style: TextStyle(color: kAccentTeal, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        displayTitle.length > 14 ? '${displayTitle.substring(0, 14)}...' : displayTitle,
                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 11),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _closeTab(tab.id),
                                      child: Container(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Card body: snapshot placeholder
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(isActive ? 10 : 12)),
                                  ),
                                  child: Center(
                                    child: isNewTab
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 32, height: 32,
                                              decoration: BoxDecoration(
                                                color: Colors.black,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Center(
                                                child: Text('M', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                            SizedBox(height: 6),
                                            Text('New Tab', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 10)),
                                          ],
                                        )
                                      : Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 48, height: 48,
                                              decoration: BoxDecoration(
                                                color: kIconBgColor,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  domain.isNotEmpty ? domain[0].toUpperCase() : '?',
                                                  style: TextStyle(color: kAccentTeal, fontSize: 22, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 6),
                                            Text(domain,
                                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 11),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ));
                  },
                ),
          ),
        ],
        ),
      ),
    );
  }
}
