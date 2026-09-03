import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/browser_error_view.dart';
import '../widgets/media_sniffer_pill.dart';

/// Active Web Browsing Lifecycle chrome.
///
/// Renders the Loading / Loaded / Error states on top of the browser viewport:
/// - a 2.5px thin progress bar during Loading,
/// - a [BrowserErrorView] fallback canvas on network/DNS/SSL failures,
/// - the [MediaSnifferPill] when audio/video streams are detected, and
/// - a bottom command dock (back / forward / home / tabs / menu).
///
/// The host owns the actual `InAppWebView` instances (multi-tab engine) and
/// supplies the live viewport via [child].
class BrowserActivePage extends StatefulWidget {
  final Widget child;

  final double progress; // 0..1
  final bool isLoading;
  final bool hasError;
  final String failedUrl;
  final String errorMessage;
  final int mediaCount;
  final int tabCount;
  final bool canGoBack;
  final bool canGoForward;

  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onHome; // -> Browser Dashboard
  final VoidCallback onTabs;
  final VoidCallback onMenu;
  final bool showDock;

  final VoidCallback onStop;
  final VoidCallback onReload;
  final VoidCallback onMediaTap;

  const BrowserActivePage({
    Key? key,
    required this.child,
    this.progress = 0,
    this.isLoading = false,
    this.hasError = false,
    this.failedUrl = '',
    this.errorMessage = '',
    this.mediaCount = 0,
    this.tabCount = 0,
    this.showDock = true,
    this.canGoBack = false,
    this.canGoForward = false,
    required this.onBack,
    required this.onForward,
    required this.onHome,
    required this.onTabs,
    required this.onMenu,
    required this.onStop,
    required this.onReload,
    required this.onMediaTap,
  }) : super(key: key);

  @override
  State<BrowserActivePage> createState() => _BrowserActivePageState();
}

class _BrowserActivePageState extends State<BrowserActivePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pillController;

  bool get _showProgressBar =>
      widget.isLoading && widget.progress > 0 && widget.progress < 1;

  @override
  void initState() {
    super.initState();
    _pillController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.mediaCount > 0 ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(BrowserActivePage old) {
    super.didUpdateWidget(old);
    if (widget.mediaCount > 0 && old.mediaCount == 0) {
      _pillController.forward(from: 0);
    } else if (widget.mediaCount == 0 && old.mediaCount > 0) {
      _pillController.reverse();
    }
  }

  @override
  void dispose() {
    _pillController.dispose();
    super.dispose();
  }

  Widget _buildStopOrReload() {
    final loading =
        widget.isLoading && widget.progress > 0 && widget.progress < 1;
    final showStop = loading && !widget.hasError;
    return _ActionButton(
      icon: showStop ? Icons.close_rounded : Icons.refresh_rounded,
      color: const Color(0xFF94A3B8),
      onPressed: showStop ? widget.onStop : widget.onReload,
    );
  }

  Widget _buildBottomDock() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          _ActionButton(
            icon: Icons.arrow_back_ios_new_rounded,
            color: widget.canGoBack
                ? Colors.white70
                : Colors.white24,
            onPressed: widget.canGoBack ? widget.onBack : null,
          ),
          _ActionButton(
            icon: Icons.arrow_forward_ios_rounded,
            color: widget.canGoForward
                ? Colors.white70
                : Colors.white24,
            onPressed: widget.canGoForward ? widget.onForward : null,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            icon: Icons.home_outlined,
            color: Colors.white70,
            onPressed: widget.onHome,
          ),
          Expanded(
            child: Center(
              child: InkWell(
                onTap: widget.onTabs,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.apps_rounded,
                          size: 18, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.tabCount}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildStopOrReload(),
          _ActionButton(
            icon: Icons.more_horiz,
            color: Colors.white70,
            onPressed: widget.onMenu,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF0F172A),
          height: 2.5,
          width: double.infinity,
          child: Stack(
            children: [
              if (_showProgressBar)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: math.min(1.0, widget.progress),
                    child: const ColoredBox(
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: widget.child),
              if (widget.hasError)
                Positioned.fill(
                  child: BrowserErrorView(
                    failedUrl: widget.failedUrl,
                    errorMessage: widget.errorMessage,
                    onRetry: widget.onReload,
                  ),
                ),
              if (widget.mediaCount > 0)
                Positioned(
                  left: 16,
                  bottom: 10,
                  child: FadeTransition(
                    opacity: _pillController,
                    child: MediaSnifferPill(
                      mediaCount: widget.mediaCount,
                      onTap: widget.onMediaTap,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.showDock) _buildBottomDock(),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color, size: 22),
      onPressed: onPressed,
    );
  }
}