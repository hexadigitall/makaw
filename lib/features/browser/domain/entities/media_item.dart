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

  MediaFormat({
    required this.label,
    required this.url,
    this.mimeType = '',
    this.height,
    this.bitrate,
  });

  MediaFormat copyWith({
    String? label,
    String? url,
    String? mimeType,
    int? height,
    int? bitrate,
  }) {
    return MediaFormat(
      label: label ?? this.label,
      url: url ?? this.url,
      mimeType: mimeType ?? this.mimeType,
      height: height ?? this.height,
      bitrate: bitrate ?? this.bitrate,
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'url': url,
    'mimeType': mimeType,
    'height': height,
    'bitrate': bitrate,
  };

  factory MediaFormat.fromJson(Map<String, dynamic> json) => MediaFormat(
    label: json['label'] as String,
    url: json['url'] as String,
    mimeType: json['mimeType'] as String? ?? '',
    height: json['height'] as int?,
    bitrate: json['bitrate'] as int?,
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
