import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralized service for audio album artwork and video thumbnail extraction.
class MediaThumbnailService {
  MediaThumbnailService._();
  static final MediaThumbnailService instance = MediaThumbnailService._();

  static const _channel = MethodChannel('com.hexadigitall.makaw/metadata');
  final Map<String, Uint8List?> _cache = {};
  final Set<String> _inFlight = {};

  /// Retrieves album artwork bytes (for audio) or frame thumbnail bytes (for video).
  Future<Uint8List?> getThumbnail(String filePath, {bool isVideo = false}) async {
    if (filePath.isEmpty) return null;
    if (_cache.containsKey(filePath)) {
      return _cache[filePath];
    }
    if (_inFlight.contains(filePath)) return null;
    _inFlight.add(filePath);

    try {
      if (Platform.isAndroid) {
        final method = isVideo ? 'extractVideoThumbnail' : 'extractArtwork';
        final bytes = await _channel.invokeMethod<Uint8List>(method, {'path': filePath});
        _cache[filePath] = bytes;
        return bytes;
      }
    } catch (_) {
    } finally {
      _inFlight.remove(filePath);
    }
    _cache[filePath] = null;
    return null;
  }

  void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }
}

/// Unified Widget to render media artwork (album art or video thumbnail)
/// with smooth fallback to themed icons and zero blank tiles.
class MediaArtworkWidget extends StatefulWidget {
  final String filePath;
  final bool isVideo;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final Widget? fallback;
  final IconData? fallbackIcon;
  final Color? fallbackColor;
  final Color? iconColor;

  const MediaArtworkWidget({
    super.key,
    required this.filePath,
    this.isVideo = false,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.fallback,
    this.fallbackIcon,
    this.fallbackColor,
    this.iconColor,
  });

  @override
  State<MediaArtworkWidget> createState() => _MediaArtworkWidgetState();
}

class _MediaArtworkWidgetState extends State<MediaArtworkWidget> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant MediaArtworkWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath || oldWidget.isVideo != widget.isVideo) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final bytes = await MediaThumbnailService.instance.getThumbnail(
      widget.filePath,
      isVideo: widget.isVideo,
    );
    if (mounted) {
      setState(() {
        _bytes = bytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(8);
    final fallbackBg = widget.fallbackColor ?? const Color(0xFF1E293B);
    final iconCol = widget.iconColor ?? (widget.isVideo ? const Color(0xFF6366F1) : const Color(0xFFF87171));
    final icon = widget.fallbackIcon ?? (widget.isVideo ? Icons.videocam_rounded : Icons.music_note_rounded);

    Widget content;
    final fallbackWidget = widget.fallback ?? _buildFallback(fallbackBg, icon, iconCol);
    if (_bytes != null && _bytes!.isNotEmpty) {
      content = Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => fallbackWidget,
      );
    } else {
      content = fallbackWidget;
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: content,
      ),
    );
  }

  Widget _buildFallback(Color bg, IconData icon, Color iconColor) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: bg,
      child: Center(
        child: Icon(
          icon,
          color: iconColor.withValues(alpha: 0.8),
          size: (widget.width != null && widget.width! < 60) ? 22 : 32,
        ),
      ),
    );
  }
}
