import 'package:flutter/material.dart';

class LauncherItem {
  final String title;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  const LauncherItem({
    required this.title,
    required this.icon,
    this.accentColor = const Color(0xFF64B5F6),
    required this.onTap,
  });
}
