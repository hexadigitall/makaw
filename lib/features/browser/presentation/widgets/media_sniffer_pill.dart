import 'package:flutter/material.dart';

/// Floating pill shown while a page is loaded when audio/video streams are
/// detected in the DOM. Tapping it opens the media download surface.
class MediaSnifferPill extends StatelessWidget {
  final int mediaCount;
  final VoidCallback onTap;

  const MediaSnifferPill({
    Key? key,
    required this.mediaCount,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download_for_offline_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              '$mediaCount ${mediaCount == 1 ? 'Media' : 'Media files'}',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}