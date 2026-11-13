import 'dart:ui';

import 'package:flutter/material.dart';

/// Reusable glassmorphism surface for sidebars, floating menus, command
/// palettes and top navigation bars.
///
/// Applies a [BackdropFilter] blur over whatever is behind it plus a subtle
/// translucent brand tint and hairline border, so panels read as premium
/// floating layers instead of flat cards.
class MakawGlassSurface extends StatelessWidget {
  final Widget child;

  /// Backdrop blur sigma in px.
  final double blur;

  /// Opacity of the [tint] base color.
  final double opacity;

  /// Corner radius applied to both the clip and the container.
  final double radius;

  final EdgeInsetsGeometry padding;

  /// Base color blended behind the content at [opacity].
  final Color tint;

  const MakawGlassSurface({
    super.key,
    required this.child,
    this.blur = 12.0,
    this.opacity = 0.6,
    this.radius = 0.0,
    this.padding = EdgeInsets.zero,
    this.tint = const Color(0xFF0F172A),
  });

  @override
  Widget build(BuildContext context) {
    final border = Border.all(color: Colors.white.withValues(alpha: 0.08));
    final radii = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: radii,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: opacity),
            border: radius > 0 ? border : null,
            borderRadius: radii,
          ),
          child: child,
        ),
      ),
    );
  }
}