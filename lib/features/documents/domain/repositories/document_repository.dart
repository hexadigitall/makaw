import '../entities/document_file_info.dart';

abstract class DocumentRepository {
  List<DocumentFileInfo> getAllDocuments();
  Map<String, List<DocumentFileInfo>> getByCategory();
  Map<String, List<DocumentFileInfo>> getFolders();
  List<DocumentFileInfo> getFavorites();
  bool isFavorite(int id);
  bool get isScanning;

  Future<void> scanAllDocuments();
  void toggleFavorite(int id);
  Future<void> loadFavorites();
}
