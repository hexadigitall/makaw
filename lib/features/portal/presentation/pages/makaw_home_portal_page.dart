import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../../core/widgets/adaptive_container.dart';
import '../../domain/launcher_item.dart';

class MakawHomePortalPage extends StatelessWidget {
  final Function(String route) onNavigate;
  final void Function(String ecosystemId) onOpenEcosystem;
  final VoidCallback onOpenQrScanner;
  final VoidCallback onToggleIncognito;
  final VoidCallback onOpenAiAssistant;
  final VoidCallback onOpenSearch;

  const MakawHomePortalPage({
    Key? key,
    required this.onNavigate,
    required this.onOpenEcosystem,
    required this.onOpenQrScanner,
    required this.onToggleIncognito,
    required this.onOpenAiAssistant,
    required this.onOpenSearch,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return AdaptiveContainer(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.isMobile(context) ? 20 : 32,
          vertical: Responsive.isMobile(context) ? 16 : 24,
        ),
        child: Responsive.isDesktop(context)
            ? _buildDesktopLayout(context)
            : _buildMobileLayout(context),
      ),
    );
  }

  // ─── Desktop / Tablet layout: two-column, centered, wide ─────────────────
  Widget _buildDesktopLayout(BuildContext context) {
    final isWide = Responsive.isDesktop(context);
    final searchWidth = isWide ? Responsive.desktopMax * 0.55 : Responsive.desktopMax * 0.7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        // 1. Brand Identity Header
        Row(
          children: [
            const Text(
              'Makaw',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 44,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: const Text(
                'Command Center',
                style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Browse · Build · Create — one hub for the entire Makaw ecosystem.',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
        ),
        const SizedBox(height: 28),

        // 2. Universal Search & Command Palette
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: searchWidth),
          child: _buildUniversalSearchBar(context),
        ),
        const SizedBox(height: 28),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main column: Launcher Hub + AI banner
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLauncherHub(context, desktopColumns: isWide ? 4 : 3),
                  const SizedBox(height: 20),
                  _buildAiAssistantBanner(context),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Sidebar: Recent Activity + highlights
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRecentActivitySection(),
                  const SizedBox(height: 20),
                  _buildFeatureHighlights(context),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ─── Mobile layout: single column per spec ───────────────────────────────
  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 12),

        // 1. Center Wordmark
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

        // 2. Universal Search & Command Palette
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Search & Command Palette',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 8),

        _buildUniversalSearchBar(context),
        const SizedBox(height: 20),

        // 3. Launcher Hub Card
        _buildLauncherHub(context),
        const SizedBox(height: 16),

        // 4. AI Assistant Banner (Gradient Action Pill)
        _buildAiAssistantBanner(context),
        const SizedBox(height: 16),

        // 5. Recent Activity Card
        _buildRecentActivitySection(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildUniversalSearchBar(BuildContext context) {
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onOpenSearch,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: Responsive.isDesktop(context) ? 56 : 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              const Icon(Icons.travel_explore, color: Colors.white54, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search tools, files, and folders...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withOpacity(0.38), fontSize: 14),
                ),
              ),
              Icon(Icons.search, color: Colors.white.withOpacity(0.6), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLauncherHub(BuildContext context, {int? desktopColumns}) {
    final launcherItems = _launcherItems(context);
    final isDesktop = Responsive.isDesktop(context);
    final columns = isDesktop ? (desktopColumns ?? 3) : 3;
    final tileSize = isDesktop ? 64.0 : 52.0;
    final iconSize = isDesktop ? 28.0 : 24.0;
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
          Row(
            children: [
              Text('🚀', style: TextStyle(fontSize: isDesktop ? 18 : 14)),
              const SizedBox(width: 8),
              Text(
                'Launcher Hub',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isDesktop ? 17 : 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: columns,
            mainAxisSpacing: 20,
            crossAxisSpacing: 16,
            childAspectRatio: 1.0,
            children: launcherItems.map((item) => _buildGridTile(context, item, tileSize, iconSize)).toList(),
          ),
        ],
      ),
    );
  }

  List<LauncherItem> _launcherItems(BuildContext context) {
    return [
      LauncherItem(
        title: 'Code Studio',
        icon: Icons.code_rounded,
        accentColor: const Color(0xFF818CF8),
        onTap: () => onOpenEcosystem('code_studio'),
      ),
      LauncherItem(
        title: 'Terminal',
        icon: Icons.terminal_rounded,
        accentColor: const Color(0xFF22D3EE),
        onTap: () => onOpenEcosystem('terminal'),
      ),
      LauncherItem(
        title: 'Documents',
        icon: Icons.edit_document,
        accentColor: const Color(0xFFFBBF24),
        onTap: () => onOpenEcosystem('documents'),
      ),
      LauncherItem(
        title: 'Media Hub',
        icon: Icons.video_collection_outlined,
        accentColor: const Color(0xFFF87171),
        onTap: () => onOpenEcosystem('media'),
      ),
      LauncherItem(
        title: 'Web Browser',
        icon: Icons.language_rounded,
        accentColor: const Color(0xFF00A7C2),
        onTap: () => onOpenEcosystem('browser'),
      ),
      LauncherItem(
        title: 'File Explorer',
        icon: Icons.folder_outlined,
        accentColor: const Color(0xFF34D399),
        onTap: () => onOpenEcosystem('files'),
      ),
    ];
  }

  Widget _buildGridTile(BuildContext context, LauncherItem item, double tileSize, double iconSize) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: tileSize,
            height: tileSize,
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(item.icon, color: item.accentColor, size: iconSize),
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white70,
              fontSize: Responsive.isDesktop(context) ? 13 : 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiAssistantBanner(BuildContext context) {
    return InkWell(
      onTap: onOpenAiAssistant,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: Responsive.isDesktop(context) ? 72 : 64,
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
                    'Powered by Gemini',
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

  Widget _buildRecentActivitySection() {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Activity',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(Icons.settings_outlined, color: Colors.white.withOpacity(0.4), size: 18),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'No recent activity',
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildFeatureHighlights(BuildContext context) {
    final highlights = [
      (Icons.bolt, 'Fast browsing', 'Blazing ad & tracker blocking'),
      (Icons.security, 'Stealth mode', 'One-tap incognito browsing'),
      (Icons.cloud_queue, 'Cloud sync', 'Projects & snippets everywhere'),
    ];
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
            'Why Makaw',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...highlights.map((h) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(h.$1, color: const Color(0xFF38BDF8), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.$2, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(h.$3, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
