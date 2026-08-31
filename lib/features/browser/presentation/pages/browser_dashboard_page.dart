import 'package:flutter/material.dart';
import '../../domain/entities/recent_page_item.dart';

/// Browser Dashboard (Browser Ecosystem Home).
///
/// A modern new-tab / ecosystem-home for the Browser ecosystem. The omnibox
/// acts strictly as an idle search/web input (never mirrors the active tab URL);
/// tapping it focuses the keyboard and triggers web suggestions via
/// [onSearchFocused]. The dashboard surfaces browser actions (New Tab /
/// Bookmarks / History / Downloads / Passwords / Settings), an AI assistant
/// banner, and a Recent Pages list bound to real browsing history.
class BrowserDashboardPage extends StatefulWidget {
  final VoidCallback onBackToMakawHome;
  final VoidCallback onNewTab;
  final VoidCallback onOpenBookmarks;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenDownloads;
  final VoidCallback onOpenPasswords;
  final VoidCallback onOpenSettings;
  final VoidCallback onAskAiAboutPage;
  final Function(String queryOrUrl) onSearchOrNavigate;
  final VoidCallback onOpenQrScanner;
  final VoidCallback onToggleShield;
  final VoidCallback onSearchFocused;
  final List<RecentPageItem> recentPages;

  const BrowserDashboardPage({
    super.key,
    required this.onBackToMakawHome,
    required this.onNewTab,
    required this.onOpenBookmarks,
    required this.onOpenHistory,
    required this.onOpenDownloads,
    required this.onOpenPasswords,
    required this.onOpenSettings,
    required this.onAskAiAboutPage,
    required this.onSearchOrNavigate,
    required this.onOpenQrScanner,
    required this.onToggleShield,
    this.onSearchFocused = _noop,
    this.recentPages = const [],
  }) : super();

  static void _noop() {}

  @override
  State<BrowserDashboardPage> createState() => _BrowserDashboardPageState();
}

class _BrowserDashboardPageState extends State<BrowserDashboardPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Chrome-style URL/query formatting shared with the New Tab + browsing hive.
  static String _formatQueryOrUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.contains('.') && !trimmed.contains(' ')) {
      return 'https://$trimmed';
    }
    return 'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}';
  }

  void _submit() {
    final formatted = _formatQueryOrUrl(_searchController.text);
    _searchController.clear();
    _focusNode.unfocus();
    if (formatted.isNotEmpty) widget.onSearchOrNavigate(formatted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1120),
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: widget.onBackToMakawHome,
            tooltip: 'Back',
          ),
        ),
        title: Row(
          children: const [
            Icon(Icons.language_rounded, color: Color(0xFF00A7C2), size: 22),
            SizedBox(width: 8),
            Text('Browser Hub', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: widget.onBackToMakawHome,
            icon: const Icon(Icons.home_rounded, color: Color(0xFF60A5FA), size: 20),
            label: const Text('Makaw Home', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12),

              // 1. Centered Makaw Brand Wordmark
              const Text(
                'Makaw',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),

              // 2. Clean, Idle Omnibox Bar
              _buildBrowserOmnibox(context),
              const SizedBox(height: 20),

              // 3. Browser Dashboard Box
              _buildBrowserDashboardGrid(context),
              const SizedBox(height: 16),

              // 4. AI Assistant Context Action
              _buildAiAssistantBanner(context),
              const SizedBox(height: 16),

              // 5. Recent Pages History List
              _buildRecentPagesSection(context, widget.recentPages),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Standard Chrome-style idle omnibox capsule. Stable controller/focus nodes
  /// live on the State so focus + submission work across rebuilds.
  Widget _buildBrowserOmnibox(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.search, color: Colors.white.withOpacity(0.4), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              onTap: widget.onSearchFocused,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Search Google or type a URL...',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.qr_code_scanner_rounded, color: Colors.white.withOpacity(0.6), size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: widget.onOpenQrScanner,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(Icons.shield_outlined, color: Colors.white.withOpacity(0.6), size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: widget.onToggleShield,
          ),
        ],
      ),
    );
  }

  Widget _buildBrowserDashboardGrid(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Text('🚀', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 8),
                  Text(
                    'Browser Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: widget.onBackToMakawHome,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Back to Makaw Home',
                    style: TextStyle(
                      color: Color(0xFF60A5FA),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 2x3 Action Grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 14,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
            children: [
              _buildToolButton(
                icon: Icons.add,
                label: 'New Tab',
                onTap: widget.onNewTab,
              ),
              _buildToolButton(
                icon: Icons.star_outline_rounded,
                label: 'Bookmarks',
                onTap: widget.onOpenBookmarks,
              ),
              _buildToolButton(
                icon: Icons.history_rounded,
                label: 'History',
                onTap: widget.onOpenHistory,
              ),
              _buildToolButton(
                icon: Icons.download_rounded,
                label: 'Downloads',
                onTap: widget.onOpenDownloads,
              ),
              _buildToolButton(
                icon: Icons.key_outlined,
                label: 'Passwords',
                onTap: widget.onOpenPasswords,
              ),
              _buildToolButton(
                icon: Icons.folder_outlined,
                label: 'Settings',
                onTap: widget.onOpenSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF60A5FA), size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiAssistantBanner(BuildContext context) {
    return InkWell(
      onTap: widget.onAskAiAboutPage,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI Assistant',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Ask AI about this Page',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentPagesSection(BuildContext context, List<RecentPageItem> pages) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Pages',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          if (pages.isEmpty)
            Text(
              'No pages visited yet. Start browsing to see recent pages here.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 12,
              ),
            )
          else
            ...pages.map(
              (page) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => widget.onSearchOrNavigate(page.url),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF243247),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF334155),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            page.title.isNotEmpty ? page.title[0].toUpperCase() : '🌐',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            page.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}