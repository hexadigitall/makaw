class MediaItem {
  final String url;
  final String type;
  final String title;
  final List<MediaFormat> formats;

  MediaItem({
    required this.url,
    required this.type,
    this.title = '',
    this.formats = const [],
  });
}

class MediaFormat {
  final String label;
  final String url;
  final String mimeType;
  final int? height;
  final int? bitrate;

  MediaFormat({
    required this.label,
    required this.url,
    this.mimeType = '',
    this.height,
    this.bitrate,
  });
}
