import '../entities/song_info.dart';
import '../entities/playlist.dart';

abstract class MusicRepository {
  List<SongInfo> getAllSongs();
  List<Playlist> getPlaylists();
  List<SongInfo> getFavorites();
  bool isFavorite(int songId);
  bool get isScanning;
  String get scanError;

  Future<void> scanAllSongs();
  Future<void> init();
  void toggleFavorite(int songId);
  Future<void> loadFavorites();
  Future<void> loadPlaylists();
  void addToPlaylist(String name, int songId);
  void deletePlaylist(String name);
  Map<String, List<SongInfo>> getAlbums();
  Map<String, List<SongInfo>> getArtists();
}
