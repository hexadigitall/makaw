import 'package:flutter/material.dart';

/// Clean fallback canvas shown in place of the webview on DNS failures,
/// connection drops, or SSL handshake timeouts.
class BrowserErrorView extends StatelessWidget {
  final String failedUrl;
  final String errorMessage;
  final VoidCallback onRetry;

  const BrowserErrorView({
    Key? key,
    required this.failedUrl,
    required this.errorMessage,
    required this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(32),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(36),
            ),
            child: const Icon(Icons.wifi_off_rounded, size: 36, color: Colors.white38),
          ),
          const SizedBox(height: 20),
          const Text(
            'This site can\u2019t be reached',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            failedUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Text(
            errorMessage.isNotEmpty ? errorMessage : 'Check your network connection or DNS settings.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18, color: Colors.black),
            label: const Text('Try Again', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}