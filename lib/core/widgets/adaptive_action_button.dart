import 'package:flutter/material.dart';
import 'responsive.dart';

class AdaptiveActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final String? tooltip;
  final Color? color;
  final bool mini;

  const AdaptiveActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.tooltip,
    this.color,
    this.mini = false,
  });

  @override
  Widget build(BuildContext context) {
    if (Responsive.isDesktop(context)) {
      return Tooltip(
        message: tooltip ?? label,
        child: iconButton(
          context: context,
          onPressed: onPressed,
          icon: icon,
          label: label,
          color: color,
        ),
      );
    }

    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: tooltip ?? label,
      mini: mini,
      backgroundColor: color,
      child: Icon(icon),
    );
  }

  static Widget iconButton({
    required BuildContext context,
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class AdaptiveScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Widget? drawer;
  final Widget? endDrawer;
  final bool extendBody;

  const AdaptiveScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.drawer,
    this.endDrawer,
    this.extendBody = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    if (isDesktop) {
      return Scaffold(
        appBar: appBar,
        body: body,
        drawer: drawer,
        endDrawer: endDrawer,
        bottomNavigationBar: bottomNavigationBar,
      );
    }

    return Scaffold(
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      drawer: drawer,
      endDrawer: endDrawer,
      extendBody: extendBody,
    );
  }
}
