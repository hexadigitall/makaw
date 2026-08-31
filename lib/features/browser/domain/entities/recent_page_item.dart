/// A recently visited page shown on the Browser Dashboard's Recent Pages
/// section. Bound to the app's history store in production.
class RecentPageItem {
  final String title;
  final String url;
  final DateTime visitedAt;

  const RecentPageItem({
    required this.title,
    required this.url,
    required this.visitedAt,
  });
}
