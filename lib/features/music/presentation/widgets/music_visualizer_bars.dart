import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated dancing audio equalizer bars that rhythmically bounce
/// when audio playback is active, and smoothly rest when paused.
class MusicVisualizerBars extends StatefulWidget {
  final bool isPlaying;
  final Color? color;
  final double height;
  final double barWidth;
  final double spacing;
  final int barCount;

  const MusicVisualizerBars({
    super.key,
    required this.isPlaying,
    this.color,
    this.height = 16.0,
    this.barWidth = 3.0,
    this.spacing = 2.0,
    this.barCount = 4,
  });

  @override
  State<MusicVisualizerBars> createState() => _MusicVisualizerBarsState();
}

class _MusicVisualizerBarsState extends State<MusicVisualizerBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(MusicVisualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        if (!_controller.isAnimating) _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barColor = widget.color ?? const Color(0xFF818CF8);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value * 2 * math.pi;

          return SizedBox(
            height: widget.height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(widget.barCount, (index) {
                // Stagger frequencies & phase shifts for realistic spectrum motion
                double scale;
                if (!widget.isPlaying) {
                  scale = 0.22;
                } else {
                  final phase = index * (math.pi / 2.5);
                  final speedMult = (index % 2 == 0) ? 1.0 : 1.4;
                  final raw = (math.sin(t * speedMult + phase) + 1.0) / 2.0;
                  scale = 0.25 + (raw * 0.75);
                }

                final currentBarHeight = (widget.height * scale).clamp(2.5, widget.height);

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
                  child: Container(
                    width: widget.barWidth,
                    height: currentBarHeight,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(widget.barWidth / 2),
                      boxShadow: widget.isPlaying
                          ? [
                              BoxShadow(
                                color: barColor.withValues(alpha: 0.35),
                                blurRadius: 4,
                                spreadRadius: 0.5,
                              )
                            ]
                          : null,
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}
