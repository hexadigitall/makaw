import '../entities/video_file_info.dart';

abstract class VideoRepository {
  List<VideoFileInfo> getAllVideos();
  Map<String, List<VideoFileInfo>> getFolders();
  List<VideoFileInfo> getFavorites();
  List<VideoFileInfo> getFavoritesByFolder();
  bool isFavorite(int id);
  bool get isScanning;

  Future<void> scanAllVideos();
  void toggleFavorite(int id);
  void toggleFavoriteFolder(String path);
  bool isFavoriteFolder(String path);
  int resumePosition(String filePath);
  bool hasResume(String filePath);
  void saveResume(String filePath, int positionMs, int durationMs);
  void clearResume(String filePath);
  Future<void> loadFavorites();
  Future<void> loadResumePositions();
  Future<void> loadPlaylists();
}
