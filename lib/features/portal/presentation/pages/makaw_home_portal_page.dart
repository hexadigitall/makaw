import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../../core/widgets/adaptive_container.dart';
import '../../domain/launcher_item.dart';
import '../../domain/home_activity.dart';

/// The Makaw Home dashboard.
///
/// Home only surfaces real state: the top bar holds search + AI, then come
/// "Continue" and "Recent" lists built from actual app activity. When there is
/// nothing to show a section is omitted instead of rendering an empty card.
class MakawHomePortalPage extends StatelessWidget {
  final Function(String route) onNavigate;
  final void Function(String ecosystemId) onOpenEcosystem;
  final VoidCallback onOpenQrScanner;
  final VoidCallback onToggleIncognito;
  final VoidCallback onOpenAiAssistant;
  final VoidCallback onOpenSearch;
  final VoidCallback onNewTab;
  final List<HomeActivityItem> continueItems;
  final List<HomeActivityItem> recentItems;
  final VoidCallback? onClearContinue;
  final VoidCallback? onClearRecent;
  final void Function(HomeActivityItem item)? onDismissItem;
  final Widget? recentActivity;
  final Widget? playerWidget;
  final Widget? workspaceBar;

  const MakawHomePortalPage({
    Key? key,
    required this.onNavigate,
    required this.onOpenEcosystem,
    required this.onOpenQrScanner,
    required this.onToggleIncognito,
    required this.onOpenAiAssistant,
    required this.onOpenSearch,
    required this.onNewTab,
    this.continueItems = const [],
    this.recentItems = const [],
    this.onClearContinue,
    this.onClearRecent,
    this.onDismissItem,
    this.recentActivity,
    this.playerWidget,
    this.workspaceBar,
  }) : super(key: key);

  static const _bg = Color(0xFF0F172A);
  static const _surface = Color(0xFF1E293B);
  static const _surfaceHigh = Color(0xFF334155);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: AdaptiveContainer(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.isMobile(context) ? 16 : 32,
              vertical: Responsive.isMobile(context) ? 12 : 24,
            ),
            child: Responsive.isDesktop(context)
                ? _buildDesktopLayout(context)
                : _buildMobileLayout(context),
          ),
        ),
      ),
    );
  }

  // ─── Top bar: identity + search + AI ──────────────────────────────────────
  Widget _buildTopBar(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/makaw_logo_28.png',
            width: isDesktop ? 30 : 26,
            height: isDesktop ? 30 : 26,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Makaw',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: isDesktop ? 24 : 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: _buildUniversalSearchBar(context)),
        const SizedBox(width: 8),
        _TopBarAction(
          icon: Icons.auto_awesome,
          tooltip: 'AI Assistant',
          gradient: true,
          onTap: onOpenAiAssistant,
        ),
        const SizedBox(width: 4),
        _TopBarAction(
          icon: Icons.settings_outlined,
          tooltip: 'Settings',
          onTap: () => onNavigate('settings'),
        ),
      ],
    );
  }

  Widget _buildUniversalSearchBar(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onOpenSearch,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: Responsive.isDesktop(context) ? 44 : 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.white54, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Search tools, files, and folders',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.38), fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Desktop / tablet layout ──────────────────────────────────────────────
  Widget _buildDesktopLayout(BuildContext context) {
    final isWide = Responsive.isDesktop(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        _buildTopBar(context),
        const SizedBox(height: 20),
        Text(
          'Browse · Build · Create — one workspace for the entire Makaw ecosystem.',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
        ),
        const SizedBox(height: 22),
        if (continueItems.isNotEmpty) ...[
          _buildContinueSection(context, horizontal: true),
          const SizedBox(height: 20),
        ],
        if (playerWidget != null) ...[
          playerWidget!,
          const SizedBox(height: 20),
        ],
        _buildQuickActions(context),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: _buildLauncherHub(context, desktopColumns: isWide ? 4 : 3),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 3,
              child: recentItems.isNotEmpty
                  ? _buildRecentSection(context)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ─── Mobile layout ────────────────────────────────────────────────────────
  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopBar(context),
        const SizedBox(height: 18),
        if (continueItems.isNotEmpty) ...[
          _buildContinueSection(context),
          const SizedBox(height: 18),
        ],
        if (playerWidget != null) ...[
          playerWidget!,
          const SizedBox(height: 18),
        ],
        _buildQuickActions(context),
        const SizedBox(height: 16),
        _buildLauncherHub(context),
        if (recentItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildRecentSection(context),
        ],
        if (workspaceBar != null) ...[
          const SizedBox(height: 16),
          workspaceBar!,
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── Continue ─────────────────────────────────────────────────────────────
  Widget _buildContinueSection(BuildContext context, {bool horizontal = false}) {
    final items = continueItems.take(horizontal ? 3 : 2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Continue',
          icon: Icons.play_circle_outline,
          onClear: onClearContinue,
        ),
        const SizedBox(height: 10),
        if (horizontal)
          Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _ActivityTile(
                    item: items[i],
                    elevated: true,
                    onDismiss: items[i].onDismiss ?? (onDismissItem != null ? () => onDismissItem!(items[i]) : null),
                  ),
                ),
              ],
            ],
          )
        else
          Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _ActivityTile(
                  item: items[i],
                  elevated: true,
                  onDismiss: items[i].onDismiss ?? (onDismissItem != null ? () => onDismissItem!(items[i]) : null),
                ),
              ],
            ],
          ),
      ],
    );
  }

  // ─── Quick actions ────────────────────────────────────────────────────────
  Widget _buildQuickActions(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction('New Tab', Icons.add_rounded, const Color(0xFF38BDF8), onNewTab),
      _QuickAction('Search', Icons.travel_explore, const Color(0xFFA78BFA), onOpenSearch),
      _QuickAction('Files', Icons.folder_outlined, const Color(0xFF34D399), () => onNavigate('files')),
      _QuickAction('Media', Icons.play_arrow_rounded, const Color(0xFFF87171), () => onNavigate('media')),
    ];
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _QuickActionButton(action: actions[i])),
        ],
      ],
    );
  }

  // ─── Apps (launcher) ──────────────────────────────────────────────────────
  Widget _buildLauncherHub(BuildContext context, {int? desktopColumns}) {
    final launcherItems = _launcherItems(context);
    final isDesktop = Responsive.isDesktop(context);
    final columns = isDesktop ? (desktopColumns ?? 3) : 4;
    final tileSize = isDesktop ? 56.0 : 46.0;
    final iconSize = isDesktop ? 26.0 : 22.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'Apps', icon: Icons.apps_rounded),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 10,
            childAspectRatio: 0.92,
            children: launcherItems
                .map((item) => _buildGridTile(context, item, tileSize, iconSize))
                .toList(),
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
        title: 'Files',
        icon: Icons.folder_outlined,
        accentColor: const Color(0xFF34D399),
        onTap: () => onOpenEcosystem('files'),
      ),
      LauncherItem(
        title: 'History',
        icon: Icons.history_rounded,
        accentColor: const Color(0xFF94A3B8),
        onTap: () => onNavigate('history'),
      ),
      LauncherItem(
        title: 'Settings',
        icon: Icons.settings_outlined,
        accentColor: const Color(0xFF94A3B8),
        onTap: () => onNavigate('settings'),
      ),
    ];
  }

  Widget _buildGridTile(
      BuildContext context, LauncherItem item, double tileSize, double iconSize) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: tileSize,
            height: tileSize,
            decoration: BoxDecoration(
              color: _surfaceHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: item.accentColor, size: iconSize),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white70,
              fontSize: Responsive.isDesktop(context) ? 12 : 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Recent ───────────────────────────────────────────────────────────────
  Widget _buildRecentSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Recent',
            icon: Icons.history_rounded,
            onClear: onClearRecent,
          ),
          const SizedBox(height: 8),
          for (final item in recentItems.take(6))
            _ActivityTile(
              item: item,
              onDismiss: item.onDismiss ?? (onDismissItem != null ? () => onDismissItem!(item) : null),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onClear;
  const _SectionHeader({required this.title, required this.icon, this.onClear});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const Spacer(),
        if (onClear != null)
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.close, size: 12, color: Color(0xFF94A3B8)),
                  SizedBox(width: 3),
                  Text(
                    'Clear',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final HomeActivityItem item;
  final bool elevated;
  final VoidCallback? onDismiss;
  const _ActivityTile({required this.item, this.elevated = false, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final title = item.title.trim().isEmpty ? 'Untitled' : item.title;
    final dismissCallback = onDismiss ?? item.onDismiss;

    final tileContent = Container(
      padding: EdgeInsets.symmetric(
          horizontal: elevated ? 14 : 10, vertical: elevated ? 12 : 9),
      decoration: elevated
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            )
          : null,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: item.accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, size: 18, color: item.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8), fontSize: 11),
                ),
              ],
            ),
          ),
          if (dismissCallback != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: dismissCallback,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 13, color: Colors.white70),
              ),
            ),
          ] else ...[
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF64748B)),
          ],
        ],
      ),
    );

    final card = Material(
      color: elevated ? const Color(0xFF1E293B) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(14),
        child: tileContent,
      ),
    );

    if (dismissCallback == null) return card;

    return Dismissible(
      key: ValueKey('home_act_${item.id.isNotEmpty ? item.id : item.title}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.15,
        DismissDirection.endToStart: 0.15,
      },
      movementDuration: const Duration(milliseconds: 100),
      resizeDuration: const Duration(milliseconds: 80),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
      ),
      onDismissed: (_) => dismissCallback(),
      child: card,
    );
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(this.label, this.icon, this.color, this.onTap);
}

class _QuickActionButton extends StatelessWidget {
  final _QuickAction action;
  const _QuickActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 20, color: action.color),
              const SizedBox(height: 6),
              Text(
                action.label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBarAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool gradient;
  const _TopBarAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.gradient = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: gradient ? null : const Color(0xFF1E293B),
              gradient: gradient
                  ? const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)])
                  : null,
              border: gradient
                  ? null
                  : Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
