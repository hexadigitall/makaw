import '../entities/news_item.dart';
import '../entities/news_category.dart';

abstract class NewsRepository {
  List<NewsCategory> getCategories();
  List<NewsItem>? cachedItems(String categoryName);
  List<NewsCategory> getOrderedCategories();

  Future<void> init();
  Future<void> ensureLocationReady();
  Future<List<NewsItem>> fetch(String categoryName);
  Future<void> refreshCategory(String categoryName);
  Future<void> refreshAll();
  Future<void> forceRefreshAll();
  void recordTap(String categoryName);
  Future<void> loadTaps();
  void dispose();
}
