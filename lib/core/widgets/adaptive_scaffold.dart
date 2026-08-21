import 'package:flutter/material.dart';
import 'responsive.dart';

class NavigationDestination {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  const NavigationDestination({required this.icon, this.selectedIcon, required this.label});
}

class MakawAdaptiveScaffold extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onDestinationSelected;
  final Widget body;
  final PreferredSizeWidget? mobileAppBar;
  final Widget? persistentMiniPlayer;
  final Widget? desktopTitleBar;
  final List<NavigationDestination> destinations;
  final Color backgroundColor;
  final Color? sidebarBackground;

  const MakawAdaptiveScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    required this.destinations,
    this.mobileAppBar,
    this.persistentMiniPlayer,
    this.desktopTitleBar,
    this.backgroundColor = const Color(0xFF0F0F1A),
    this.sidebarBackground,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    if (isDesktop) {
      return _buildDesktopLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final bg = sidebarBackground ?? const Color(0xFF1A1A2E);
    final selectedColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Row(
        children: [
          // Persistent NavigationRail sidebar
          Container(
            width: 72,
            decoration: BoxDecoration(color: bg),
            child: Column(
              children: [
                const SizedBox(height: 12),
                // App logo or title bar
                if (desktopTitleBar != null)
                  desktopTitleBar!
                else ...[
                  const Icon(Icons.flutter_dash, color: Colors.white, size: 28),
                  const SizedBox(height: 20),
                ],
                // Navigation destinations
                Expanded(
                  child: ListView.builder(
                    itemCount: destinations.length,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemBuilder: (ctx, i) {
                      final dest = destinations[i];
                      final isSelected = i == selectedIndex;
                      return _DesktopNavButton(
                        icon: dest.icon,
                        selectedIcon: dest.selectedIcon,
                        label: dest.label,
                        isSelected: isSelected,
                        selectedColor: selectedColor,
                        onTap: () => onDestinationSelected(i),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF2D2D2D)),
          // Viewport canvas
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    final bottomPadding = persistentMiniPlayer != null ? 130.0 : 0.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: mobileAppBar,
      body: Stack(
        children: [
          Positioned.fill(
            bottom: bottomPadding,
            child: body,
          ),
          if (persistentMiniPlayer != null)
            Positioned(
              left: 8,
              right: 8,
              bottom: 68,
              child: persistentMiniPlayer!,
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          border: Border(top: BorderSide(color: Color(0xFF2D2D2D), width: 0.5)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 56,
            child: Row(
              children: List.generate(destinations.length, (i) {
                final dest = destinations[i];
                final isSelected = i == selectedIndex;
                return Expanded(
                  child: _MobileNavButton(
                    icon: dest.icon,
                    selectedIcon: dest.selectedIcon,
                    label: dest.label,
                    isSelected: isSelected,
                    onTap: () => onDestinationSelected(i),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopNavButton extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _DesktopNavButton({
    required this.icon,
    this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? selectedColor : Colors.grey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? selectedColor.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isSelected ? (selectedIcon ?? icon) : icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(color: color, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileNavButton extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _MobileNavButton({
    required this.icon,
    this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? Theme.of(context).colorScheme.primary : Colors.grey;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isSelected ? (selectedIcon ?? icon) : icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 10), maxLines: 1),
        ],
      ),
    );
  }
}
