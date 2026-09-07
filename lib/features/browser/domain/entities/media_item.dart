class MediaItem {
  final String url;
  final String type;
  final String title;
  final List<MediaFormat> formats;

  /// For HLS/DASH streams: the resolved chunk/segment URLs (after manifest
  /// parsing), used for direct downloading / ffmpeg stitching.
  final List<String>? segments;

  MediaItem({
    required this.url,
    required this.type,
    this.title = '',
    this.formats = const [],
    this.segments,
  });

  MediaItem copyWith({
    String? url,
    String? type,
    String? title,
    List<MediaFormat>? formats,
  }) {
    return MediaItem(
      url: url ?? this.url,
      type: type ?? this.type,
      title: title ?? this.title,
      formats: formats ?? this.formats,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'type': type,
    'title': title,
    'formats': formats.map((f) => f.toJson()).toList(),
  };

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
    url: json['url'] as String,
    type: json['type'] as String,
    title: json['title'] as String? ?? '',
    formats: (json['formats'] as List<dynamic>?)
            ?.map((e) => MediaFormat.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaItem && url == other.url && type == other.type && title == other.title;

  @override
  int get hashCode => Object.hash(url, type, title);

  @override
  String toString() => 'MediaItem(url: $url, type: $type, title: $title)';
}

class MediaFormat {
  final String label;
  final String url;
  final String mimeType;
  final int? height;
  final int? bitrate;

  /// True when [url] points to a streaming manifest (HLS .m3u8 / DASH .mpd)
  /// rather than a directly-downloadable media file.
  final bool isStream;

  /// The manifest URL that owns this format (identical to [url] for streams).
  final String? manifestUrl;

  /// Number of segments discovered inside the manifest (HLS/DASH).
  final int? segmentCount;

  /// Media chunk/segment URLs resolved from the manifest, used for
  /// direct download / ffmpeg stitching.
  final List<String>? segments;

  /// Response Content-Type observed on the network for this URL.
  final String? contentType;

  /// Observed Content-Length header (may be null for chunks).
  final int? sizeBytes;

  MediaFormat({
    required this.label,
    required this.url,
    this.mimeType = '',
    this.height,
    this.bitrate,
    this.isStream = false,
    this.manifestUrl,
    this.segmentCount,
    this.segments,
    this.contentType,
    this.sizeBytes,
  });

  MediaFormat copyWith({
    String? label,
    String? url,
    String? mimeType,
    int? height,
    int? bitrate,
    bool? isStream,
    String? manifestUrl,
    int? segmentCount,
    List<String>? segments,
    String? contentType,
    int? sizeBytes,
  }) {
    return MediaFormat(
      label: label ?? this.label,
      url: url ?? this.url,
      mimeType: mimeType ?? this.mimeType,
      height: height ?? this.height,
      bitrate: bitrate ?? this.bitrate,
      isStream: isStream ?? this.isStream,
      manifestUrl: manifestUrl ?? this.manifestUrl,
      segmentCount: segmentCount ?? this.segmentCount,
      segments: segments ?? this.segments,
      contentType: contentType ?? this.contentType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'url': url,
    'mimeType': mimeType,
    'height': height,
    'bitrate': bitrate,
    'isStream': isStream,
    'manifestUrl': manifestUrl,
    'segmentCount': segmentCount,
    'segments': segments,
    'contentType': contentType,
    'sizeBytes': sizeBytes,
  };

  factory MediaFormat.fromJson(Map<String, dynamic> json) => MediaFormat(
    label: json['label'] as String,
    url: json['url'] as String,
    mimeType: json['mimeType'] as String? ?? '',
    height: json['height'] as int?,
    bitrate: json['bitrate'] as int?,
    isStream: json['isStream'] as bool? ?? false,
    manifestUrl: json['manifestUrl'] as String?,
    segmentCount: json['segmentCount'] as int?,
    segments: (json['segments'] as List<dynamic>?)?.cast<String>(),
    contentType: json['contentType'] as String?,
    sizeBytes: json['sizeBytes'] as int?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaFormat && label == other.label && url == other.url;

  @override
  int get hashCode => Object.hash(label, url);

  @override
  String toString() => 'MediaFormat(label: $label, mimeType: $mimeType)';
}
