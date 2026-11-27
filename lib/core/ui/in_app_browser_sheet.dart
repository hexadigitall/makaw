import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import 'makaw_toast.dart';

/// Shared helper for extracting & opening external/video links directly inside an
/// in-app browser sheet without losing the caller's reader/viewer state.
class MakawExternalLinks {
  MakawExternalLinks._();

  static final RegExp _urlRegex = RegExp(
    r'''https?://[^\s<>"'\)\]]+''',
    caseSensitive: false,
  );

  /// Extracts unique clean HTTP(S) URLs from plain text (emails, calendar
  /// descriptions, slide bullet points, markdown notes).
  static List<String> extractUrls(String text, {int limit = 12}) {
    if (text.isEmpty) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final m in _urlRegex.allMatches(text)) {
      var u = m.group(0) ?? '';
      while (u.isNotEmpty &&
          (u.endsWith('.') ||
              u.endsWith(',') ||
              u.endsWith(';') ||
              u.endsWith(')') ||
              u.endsWith(']'))) {
        u = u.substring(0, u.length - 1);
      }
      if (u.length > 8 && seen.add(u)) {
        out.add(u);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  static bool isVideoLikeUrl(String rawUrl) {
    final lower = rawUrl.toLowerCase();
    return RegExp(r'\.(mp4|m4v|webm|mov|mkv|m3u8)(\?|$)').hasMatch(lower) ||
        lower.contains('youtube.com/') ||
        lower.contains('youtu.be/') ||
        lower.contains('vimeo.com/') ||
        lower.contains('dailymotion.com/') ||
        lower.contains('twitch.tv/');
  }

  /// Handles `http://` / `https://` links inside any Makaw reader via an in-app
  /// overlay browser that supports inline video playback (`<video>`, YouTube,
  /// streams) while preserving the underlying book/document position. Non-HTTP
  /// actionable schemes (`mailto:`, `tel:`) delegate cleanly to `url_launcher`.
  static Future<void> open(
    BuildContext context,
    String rawUrl, {
    String? sourceTitle,
  }) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('mailto:') ||
        lower.startsWith('tel:') ||
        lower.startsWith('sms:')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) {
          MakawToast.warning(context, 'Could not open link handler for $trimmed');
        }
      }
      return;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      if (context.mounted) {
        MakawToast.warning(context, 'Unsupported link scheme: $trimmed');
      }
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF090D16),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _MakawInAppBrowserSheet(
        initialUrl: trimmed,
        sourceTitle: sourceTitle,
      ),
    );
  }
}

/// Reusable horizontal bar of clickable HTTP/video link pills extracted from
/// plain-text documents (Emails, Calendar invites, Slides).
class MakawExtractedLinksBar extends StatelessWidget {
  final String text;
  final String? sourceTitle;

  const MakawExtractedLinksBar({
    super.key,
    required this.text,
    this.sourceTitle,
  });

  @override
  Widget build(BuildContext context) {
    final urls = MakawExternalLinks.extractUrls(text);
    if (urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final url in urls)
            ActionChip(
              backgroundColor: const Color(0xFF1E293B),
              side: BorderSide(
                color: (MakawExternalLinks.isVideoLikeUrl(url)
                        ? const Color(0xFF34D399)
                        : const Color(0xFF38BDF8))
                    .withValues(alpha: 0.45),
              ),
              avatar: Icon(
                MakawExternalLinks.isVideoLikeUrl(url)
                    ? Icons.play_circle_fill_rounded
                    : Icons.open_in_browser_rounded,
                size: 16,
                color: MakawExternalLinks.isVideoLikeUrl(url)
                    ? const Color(0xFF34D399)
                    : const Color(0xFF38BDF8),
              ),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  url.replaceFirst(RegExp(r'^https?://'), ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5),
                ),
              ),
              onPressed: () =>
                  MakawExternalLinks.open(context, url, sourceTitle: sourceTitle),
            ),
        ],
      ),
    );
  }
}

class _MakawInAppBrowserSheet extends StatefulWidget {
  final String initialUrl;
  final String? sourceTitle;

  const _MakawInAppBrowserSheet({
    required this.initialUrl,
    this.sourceTitle,
  });

  @override
  State<_MakawInAppBrowserSheet> createState() =>
      _MakawInAppBrowserSheetState();
}

class _MakawInAppBrowserSheetState extends State<_MakawInAppBrowserSheet> {
  InAppWebViewController? _ctrl;
  late String _currentUrl = widget.initialUrl;
  String _pageTitle = '';
  double _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;

  Future<void> _syncNavState() async {
    final ctrl = _ctrl;
    if (ctrl == null || !mounted) return;
    final back = await ctrl.canGoBack();
    final fwd = await ctrl.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = back;
        _canGoForward = fwd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.90;
    final isVideo = MakawExternalLinks.isVideoLikeUrl(_currentUrl);
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: 'Return to reader',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isVideo
                                ? Icons.play_circle_fill_rounded
                                : Icons.public_rounded,
                            size: 14,
                            color: isVideo
                                ? const Color(0xFF34D399)
                                : const Color(0xFF38BDF8),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _pageTitle.isNotEmpty
                                  ? _pageTitle
                                  : (widget.sourceTitle != null
                                      ? 'In-Reader Browser · ${widget.sourceTitle}'
                                      : 'In-Reader Browser'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _currentUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: _canGoBack ? Colors.white : Colors.white24),
                  tooltip: 'Back',
                  onPressed: _canGoBack ? () => _ctrl?.goBack() : null,
                ),
                IconButton(
                  icon: Icon(Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: _canGoForward ? Colors.white : Colors.white24),
                  tooltip: 'Forward',
                  onPressed: _canGoForward ? () => _ctrl?.goForward() : null,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded,
                      size: 19, color: Colors.white70),
                  tooltip: 'Reload',
                  onPressed: () => _ctrl?.reload(),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded,
                      size: 18, color: Colors.white70),
                  tooltip: 'Copy URL',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _currentUrl));
                    MakawToast.success(context, 'Link copied');
                  },
                ),
              ],
            ),
          ),
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2.5,
              backgroundColor: const Color(0xFF0F172A),
              color: const Color(0xFF38BDF8),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                allowsBackForwardNavigationGestures: true,
                useWideViewPort: true,
                loadWithOverviewMode: true,
                supportZoom: true,
                builtInZoomControls: true,
                displayZoomControls: false,
              ),
              onWebViewCreated: (ctrl) => _ctrl = ctrl,
              onLoadStart: (_, url) {
                if (url != null && mounted) {
                  setState(() => _currentUrl = url.toString());
                }
                _syncNavState();
              },
              onLoadStop: (ctrl, url) async {
                final title = await ctrl.getTitle();
                if (!mounted) return;
                setState(() {
                  if (url != null) _currentUrl = url.toString();
                  if (title != null && title.isNotEmpty) _pageTitle = title;
                });
                _syncNavState();
              },
              onProgressChanged: (_, p) {
                if (mounted) setState(() => _progress = p / 100.0);
              },
            ),
          ),
        ],
      ),
    );
  }
}
