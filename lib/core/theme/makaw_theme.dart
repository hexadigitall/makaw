import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Makaw token-driven design system root.
///
/// Mirrors the Makaw dark-slate / electric-blue brand on top of the shadcn_ui
/// component language so every [ShadButton], [ShadCard], [ShadInput] and
/// [ShadBadge] shares the same premium, developer-tool aesthetic.
class MakawTheme {
  MakawTheme._();

  /// Makaw Deep Slate background with Electric Blue primary accents.
  ///
  /// `border`/`input` use a subtle 10% white so surfaces separate with
  /// precision instead of heavy gray outlines.
  static ShadThemeData get darkTheme {
    return ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadSlateColorScheme.dark(
        background: Color(0xFF0B1121),
        foreground: Color(0xFFF8FAFC),
        card: Color(0xFF16213A),
        cardForeground: Color(0xFFF8FAFC),
        popover: Color(0xFF111C33),
        popoverForeground: Color(0xFFF8FAFC),
        primary: Color(0xFF38BDF8),
        primaryForeground: Color(0xFF06121F),
        secondary: Color(0xFF1E293B),
        secondaryForeground: Color(0xFFF8FAFC),
        muted: Color(0xFF1E293B),
        mutedForeground: Color(0xFF94A3B8),
        accent: Color(0xFF1E293B),
        accentForeground: Color(0xFFF8FAFC),
        destructive: Color(0xFFEF4444),
        destructiveForeground: Color(0xFFF8FAFC),
        border: Color(0x1AFFFFFF),
        input: Color(0x1AFFFFFF),
        ring: Color(0xFF38BDF8),
        selection: Color(0xFF2B5A83),
      ),
      textTheme: ShadTextTheme(family: 'Outfit'),
      radius: const BorderRadius.all(Radius.circular(10)),
      cardTheme: const ShadCardTheme(
        radius: BorderRadius.all(Radius.circular(16)),
        padding: EdgeInsets.all(16),
      ),
    );
  }
}