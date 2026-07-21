import 'package:flutter/material.dart';

extension ThemeColors on BuildContext {
  Color get primaryText => Theme.of(this).colorScheme.onSurface;
  Color get mutedText => Theme.of(this).colorScheme.onSurface.withValues(alpha: 0.6);
  Color get surfaceColor => Theme.of(this).colorScheme.surface;
  Color get cardBg => Theme.of(this).cardColor;
  Color get scaffoldBg => Theme.of(this).scaffoldBackgroundColor;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
