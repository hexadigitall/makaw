import 'package:flutter/foundation.dart';

/// Central state coordinator tracking player visibility across Makaw.
///
/// Core rule:
/// The Floating music player should only show on screens where the
/// Mainplayer or miniplayer shouldn't show.
///
/// Screens with Mainplayer or Miniplayer (Category A):
/// - Makaw Home: Miniplayer (inline widget player)
/// - Media Library: Miniplayer (docked bottom bar)
/// - Makaw Music: Miniplayer (docked bottom bar) or Mainplayer (Now Playing)
/// - Playlist detail: Miniplayer (docked bottom bar)
/// - Video Player: Mainplayer (full video player)
///
/// Screens where neither should show (Category B):
/// - Browser, Files, Studio, Terminal, Settings, Downloads, History, Viewers.
class GlobalPlayerState extends ChangeNotifier {
  static final GlobalPlayerState instance = GlobalPlayerState._();
  GlobalPlayerState._();

  bool _isHome = true;
  bool get isHome => _isHome;

  bool _inFullPlayer = false;
  bool get inFullPlayer => _inFullPlayer;

  final List<String> _toolRoutes = [];
  List<String> get toolRoutes => List.unmodifiable(_toolRoutes);

  void pushToolRoute(String route) {
    _toolRoutes.add(route);
    notifyListeners();
  }

  void popToolRoute(String route) {
    _toolRoutes.remove(route);
    notifyListeners();
  }

  void update({required bool isHome, required bool inFullPlayer}) {
    if (_isHome != isHome || _inFullPlayer != inFullPlayer) {
      _isHome = isHome;
      _inFullPlayer = inFullPlayer;
      notifyListeners();
    }
  }

  /// Whether the currently visible screen is one where a Mainplayer or Miniplayer
  /// is shown.
  bool get isScreenWithPlayer {
    if (_inFullPlayer) return true;
    if (_toolRoutes.isNotEmpty) {
      final top = _toolRoutes.last;
      return top == 'media' ||
          top == 'music' ||
          top == 'player' ||
          top == 'video_player' ||
          top == 'playlist';
    }
    return _isHome;
  }
}
