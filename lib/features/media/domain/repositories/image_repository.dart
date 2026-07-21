import '../entities/image_file_info.dart';

abstract class ImageRepository {
  List<ImageFileInfo> getAllImages();
  Map<String, List<ImageFileInfo>> getFolders();
  List<ImageFileInfo> getFavorites();
  bool isFavorite(int id);
  bool get isScanning;

  Future<void> scanAllImages();
  void toggleFavorite(int id);
  void moveToTrash(ImageFileInfo image);
  void restoreFromTrash(ImageFileInfo image);
  Future<void> loadFavorites();
  Future<void> loadTrash();
}
