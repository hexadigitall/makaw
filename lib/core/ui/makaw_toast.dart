import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum MakawToastKind { info, success, warning, error }

enum MakawToastPosition { top, bottom }

/// Seasoned, floating obsidian toast system for Makaw.
///
/// Renders cleanly on the root [Overlay] (superseding any active toast so
/// notifications never queue/overlap) with semantic accents, optional action
/// button, swipe-to-dismiss, and a live countdown hairline. Falls back
/// gracefully to [ScaffoldMessenger] if no [Overlay] is mounted in widget tests.
class MakawToast {
  static OverlayEntry? _activeEntry;
  static Timer? _dismissTimer;

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    try {
      _activeEntry?.remove();
    } catch (_) {}
    _activeEntry = null;
  }

  static void info(
    BuildContext context,
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    MakawToastPosition position = MakawToastPosition.top,
    Duration duration = const Duration(milliseconds: 2400),
  }) =>
      show(
        context,
        message,
        title: title,
        kind: MakawToastKind.info,
        actionLabel: actionLabel,
        onAction: onAction,
        position: position,
        duration: duration,
      );

  static void success(
    BuildContext context,
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    MakawToastPosition position = MakawToastPosition.top,
    Duration duration = const Duration(milliseconds: 2400),
  }) =>
      show(
        context,
        message,
        title: title,
        kind: MakawToastKind.success,
        actionLabel: actionLabel,
        onAction: onAction,
        position: position,
        duration: duration,
      );

  static void warning(
    BuildContext context,
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    MakawToastPosition position = MakawToastPosition.top,
    Duration duration = const Duration(milliseconds: 2800),
  }) =>
      show(
        context,
        message,
        title: title,
        kind: MakawToastKind.warning,
        actionLabel: actionLabel,
        onAction: onAction,
        position: position,
        duration: duration,
      );

  static void error(
    BuildContext context,
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    MakawToastPosition position = MakawToastPosition.top,
    Duration duration = const Duration(milliseconds: 3200),
  }) =>
      show(
        context,
        message,
        title: title,
        kind: MakawToastKind.error,
        actionLabel: actionLabel,
        onAction: onAction,
        position: position,
        duration: duration,
      );

  static void show(
    BuildContext context,
    String message, {
    String? title,
    MakawToastKind kind = MakawToastKind.info,
    String? actionLabel,
    VoidCallback? onAction,
    MakawToastPosition position = MakawToastPosition.top,
    Duration duration = const Duration(milliseconds: 2400),
  }) {
    if (!context.mounted) return;
    if (kind == MakawToastKind.error || kind == MakawToastKind.warning) {
      HapticFeedback.lightImpact();
    } else if (kind == MakawToastKind.success) {
      HapticFeedback.selectionClick();
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13)),
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF141928),
        ),
      );
      return;
    }

    dismiss();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _MakawToastHost(
        message: message,
        title: title,
        kind: kind,
        actionLabel: actionLabel,
        onAction: onAction,
        position: position,
        duration: duration,
        onDismissed: () {
          if (_activeEntry == entry) {
            dismiss();
          }
        },
      ),
    );
    _activeEntry = entry;
    overlay.insert(entry);
    _dismissTimer = Timer(duration, () {
      if (_activeEntry == entry) dismiss();
    });
  }
}

class _MakawToastHost extends StatefulWidget {
  final String message;
  final String? title;
  final MakawToastKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final MakawToastPosition position;
  final Duration duration;
  final VoidCallback onDismissed;

  const _MakawToastHost({
    required this.message,
    this.title,
    required this.kind,
    this.actionLabel,
    this.onAction,
    required this.position,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_MakawToastHost> createState() => _MakawToastHostState();
}

class _MakawToastHostState extends State<_MakawToastHost> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(0, widget.position == MakawToastPosition.top ? -0.35 : 0.35),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutBack));

  @override
  void initState() {
    super.initState();
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  (Color accent, IconData icon) get _style => switch (widget.kind) {
        MakawToastKind.success => (const Color(0xFF10B981), Icons.check_circle_rounded),
        MakawToastKind.warning => (const Color(0xFFF59E0B), Icons.warning_amber_rounded),
        MakawToastKind.error => (const Color(0xFFF43F5E), Icons.error_outline_rounded),
        MakawToastKind.info => (const Color(0xFF818CF8), Icons.auto_awesome_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final (accent, icon) = _style;
    final topPad = mq.padding.top + 12;
    final bottomPad = mq.padding.bottom + mq.viewInsets.bottom + 24;

    return Positioned(
      top: widget.position == MakawToastPosition.top ? topPad : null,
      bottom: widget.position == MakawToastPosition.bottom ? bottomPad : null,
      left: 16,
      right: 16,
      child: IgnorePointer(
        ignoring: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Dismissible(
              key: UniqueKey(),
              direction: widget.position == MakawToastPosition.top
                  ? DismissDirection.up
                  : DismissDirection.down,
              onDismissed: (_) => widget.onDismissed(),
              child: SlideTransition(
                position: _slide,
                child: FadeTransition(
                  opacity: _fade,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xF0141928),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: accent.withValues(alpha: 0.42), width: 1.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.48),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: accent.withValues(alpha: 0.14),
                            blurRadius: 14,
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(icon, color: accent, size: 18),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (widget.title != null && widget.title!.isNotEmpty)
                                        Text(
                                          widget.title!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      Text(
                                        widget.message,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.92),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.actionLabel != null && widget.onAction != null)
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      backgroundColor: accent.withValues(alpha: 0.18),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () {
                                      widget.onAction?.call();
                                      widget.onDismissed();
                                    },
                                    child: Text(
                                      widget.actionLabel!,
                                      style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                const SizedBox(width: 2),
                                InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: widget.onDismissed,
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.45), size: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 1.0, end: 0.0),
                            duration: widget.duration,
                            builder: (_, v, __) => LinearProgressIndicator(
                              value: v,
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                              color: accent.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
