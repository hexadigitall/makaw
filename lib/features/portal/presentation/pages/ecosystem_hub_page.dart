import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive.dart';
import '../../domain/ecosystem.dart';

class EcosystemHubPage extends StatelessWidget {
  final Ecosystem ecosystem;
  final void Function(EcosystemTool tool) onOpenTool;
  final void Function() onGoHome;
  final bool isDesktopShell;
  final VoidCallback? onSearch;
  final Widget? recentActivity;
  final List<Widget> auxSections;

  const EcosystemHubPage({
    super.key,
    required this.ecosystem,
    required this.onOpenTool,
    required this.onGoHome,
    this.isDesktopShell = false,
    this.onSearch,
    this.recentActivity,
    this.auxSections = const [],
  });

  static const _quickActions = <String, List<_QuickAction>>{
    'code_studio': [
      _QuickAction(Icons.add_rounded, 'New File', Color(0xFF818CF8), 'studio'),
      _QuickAction(Icons.terminal_rounded, 'Terminal', Color(0xFF22D3EE), 'terminal'),
      _QuickAction(Icons.folder_rounded, 'Projects', Color(0xFFFBBF24), 'projects'),
    ],
    'media': [
      _QuickAction(Icons.music_note_rounded, 'Music', Color(0xFFF472B6), 'music'),
      _QuickAction(Icons.photo_library_rounded, 'Gallery', Color(0xFF38BDF8), 'images'),
      _QuickAction(Icons.wifi_tethering_rounded, 'Sniffer', Color(0xFF22D3EE), 'sniffer'),
    ],
    'documents': [
      // Redundant with the Document Reader / File Explorer tools — quick
      // actions for the Documents ecosystem are replaced by Recent Activity.
    ],
    'files': [
      _QuickAction(Icons.folder_open_rounded, 'Open Folder', Color(0xFF34D399), 'files'),
      _QuickAction(Icons.download_rounded, 'Downloads', Color(0xFFFB923C), 'downloads'),
    ],
  };

  List<_QuickAction> get _actions => _quickActions[ecosystem.id] ?? [];

  @override
  Widget build(BuildContext context) {
    final isDesktop = isDesktopShell || Responsive.isDesktop(context);
    final columns = isDesktop
        ? Responsive.gridColumns(context).clamp(3, 5)
        : 2;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1120),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: ecosystem.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(ecosystem.icon, color: ecosystem.accent, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                ecosystem.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? Responsive.desktopMax : double.infinity,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (onSearch != null) ...[
                    _buildSearchBar(),
                    const SizedBox(height: 16),
                  ],
                  for (final section in auxSections) ...[
                    section,
                    const SizedBox(height: 20),
                    _buildSectionDivider(),
                    const SizedBox(height: 16),
                  ],
                  if (_actions.isNotEmpty) ...[
                    _buildQuickActionsSection(isDesktop),
                    const SizedBox(height: 20),
                    _buildSectionDivider(),
                    const SizedBox(height: 16),
                  ],
                  _buildToolsSection(columns, isDesktop),
                  if (recentActivity != null) ...[
                    const SizedBox(height: 20),
                    _buildSectionDivider(),
                    const SizedBox(height: 16),
                    recentActivity!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onSearch,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search, color: ecosystem.accent.withOpacity(0.9), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search ${ecosystem.name} tools, files & folders...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.keyboard_arrow_right, color: Colors.white38, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionDivider() {
    return Container(height: 1, color: Colors.white.withOpacity(0.06));
  }

  Widget _buildQuickActionsSection(bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QUICK ACTIONS',
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _actions.map((action) {
            return Material(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () {
                  final tool = ecosystem.tools
                      .where((t) => t.view == action.view)
                      .firstOrNull;
                  if (tool != null) onOpenTool(tool);
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(action.icon, color: action.color, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        action.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildToolsSection(int columns, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TOOLS',
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ecosystem.tools.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: isDesktop ? 1.3 : 1.15,
          ),
          itemBuilder: (context, i) {
            final tool = ecosystem.tools[i];
            return _buildToolCard(context, tool, isDesktop);
          },
        ),
      ],
    );
  }

  Widget _buildToolCard(BuildContext context, EcosystemTool tool, bool isDesktop) {
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => onOpenTool(tool),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: isDesktop ? 48 : 42,
                height: isDesktop ? 48 : 42,
                decoration: BoxDecoration(
                  color: tool.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(tool.icon, color: tool.accent, size: isDesktop ? 24 : 20),
              ),
              const SizedBox(height: 10),
              Text(
                tool.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final String view;

  const _QuickAction(this.icon, this.label, this.color, this.view);
}
