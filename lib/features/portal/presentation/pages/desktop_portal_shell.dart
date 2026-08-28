import 'package:flutter/material.dart';
import '../../domain/ecosystem.dart';

/// Desktop-only Root Portal shell.
///
/// A collapsible far-left main menu that starts collapsed to a slim icon rail
/// (with the Makaw logo at the top). The collapse toggle expands it into a
/// labelled drawer; in both states the menu *pushes* the content area to the
/// right rather than overlaying it. This menu exists only on the Root Portal —
/// ecosystem screens use a plain "Home" affordance instead, and tool pages use
/// "Back to {Ecosystem} Hub".
class DesktopPortalShell extends StatefulWidget {
  final Widget child;
  final void Function(String ecosystemId) onOpenEcosystem;
  final void Function() onGoHome;

  const DesktopPortalShell({
    super.key,
    required this.child,
    required this.onOpenEcosystem,
    required this.onGoHome,
  });

  @override
  State<DesktopPortalShell> createState() => _DesktopPortalShellState();
}

class _DesktopPortalShellState extends State<DesktopPortalShell> {
  bool _expanded = false;

  static const double _collapsedWidth = 72;
  static const double _expandedWidth = 240;

  List<Ecosystem> get _ecosystems => Ecosystems.all;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final width = _expanded ? _expandedWidth : _collapsedWidth;
    return Row(
      children: [
        // Collapsible main menu (pushes content, never overlays).
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: width,
          height: double.infinity,
          color: const Color(0xFF0B1120),
          child: _expanded ? _buildExpandedMenu() : _buildCollapsedMenu(),
        ),
        VerticalDivider(width: 1, thickness: 1, color: Colors.white.withOpacity(0.06)),
        Expanded(child: widget.child),
      ],
    );
  }

  Widget _buildCollapsedMenu() {
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildLogoButton(iconOnly: true),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final e in _ecosystems) _buildCollapsedItem(e),
            ],
          ),
        ),
        _buildToggleButton(expanded: false),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildExpandedMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildLogoButton(iconOnly: false),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'ECOSYSTEMS',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final e in _ecosystems) _buildExpandedItem(e),
            ],
          ),
        ),
        _buildToggleButton(expanded: true),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildLogoButton({required bool iconOnly}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: widget.onGoHome,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 8, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/makaw_logo_28.png', width: 32, height: 32, fit: BoxFit.contain),
            if (!iconOnly) ...[
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Makaw',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsedItem(Ecosystem e) {
    return Tooltip(
      message: e.name,
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onOpenEcosystem(e.id),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Icon(e.icon, color: Colors.white54, size: 22)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedItem(Ecosystem e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onOpenEcosystem(e.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(e.icon, color: Colors.white54, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton({required bool expanded}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(expanded ? Icons.menu_open : Icons.menu, color: Colors.white38, size: 20),
            if (expanded) ...[
              const SizedBox(width: 8),
              Text('Collapse', style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}
