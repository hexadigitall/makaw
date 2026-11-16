import 'package:flutter/material.dart';

/// A single "continue where you left off" or "recent" entry on the Home
/// dashboard. Built by the host from real app state so Home never shows a
/// fabricated or dead card.
class HomeActivityItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const HomeActivityItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });
}
