import 'package:flutter/material.dart';

/// A small icon with a guaranteed minimum tap target.
///
/// A raw icon inside a [GestureDetector]/[InkWell] only responds where the
/// glyph is painted (~12-16px), which is nearly impossible to hit. This wraps
/// the icon in a fixed-size tappable box (default 36x36) while keeping the
/// *visual* icon small, and paints ink when a [Material] ancestor exists.
class TappableIcon extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final Color color;
  final VoidCallback? onTap;
  final String? tooltip;
  final double target;

  const TappableIcon({
    super.key,
    required this.icon,
    this.iconSize = 18,
    this.color = Colors.white70,
    this.onTap,
    this.tooltip,
    this.target = 36,
  });

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: target,
      height: target,
      child: Icon(icon, size: iconSize, color: color),
    );
    Widget content = button;
    if (onTap == null) return content;
    // InkWell needs a Material; many of these icons sit in plain Stacks/rows
    // over dark backgrounds, so provide a transparent one when absent.
    content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(target / 2),
        child: button,
      ),
    );
    if (tooltip != null) {
      content = Tooltip(message: tooltip!, child: content);
    }
    return content;
  }
}