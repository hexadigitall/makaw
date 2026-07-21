import 'dart:io';

class SongInfo {
  final int id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final int duration;
  final int albumId;
  final int size;

  SongInfo({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.filePath,
    this.duration = 0,
    this.albumId = -1,
    this.size = 0,
  });

  String get displayTitle =>
      title.isNotEmpty ? title : filePath.split(Platform.pathSeparator).last.split('.').first;
  String get displayArtist =>
      artist.isNotEmpty && artist != '<unknown>' ? artist : 'Unknown Artist';
  String get displayAlbum =>
      album.isNotEmpty && album != '<unknown>' ? album : 'Unknown Album';
  String get fileName => filePath.split(Platform.pathSeparator).last;

  SongInfo copyWith({
    int? id,
    String? title,
    String? artist,
    String? album,
    String? filePath,
    int? duration,
    int? albumId,
    int? size,
  }) {
    return SongInfo(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      filePath: filePath ?? this.filePath,
      duration: duration ?? this.duration,
      albumId: albumId ?? this.albumId,
      size: size ?? this.size,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'filePath': filePath,
    'duration': duration,
    'albumId': albumId,
    'size': size,
  };

  static SongInfo fromJson(Map<String, dynamic> j) => SongInfo(
    id: j['id'] ?? 0,
    title: j['title'] ?? '',
    artist: j['artist'] ?? '',
    album: j['album'] ?? '',
    filePath: j['filePath'] ?? '',
    duration: j['duration'] ?? 0,
    albumId: j['albumId'] ?? -1,
    size: j['size'] ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongInfo && id == other.id && filePath == other.filePath;

  @override
  int get hashCode => Object.hash(id, filePath);

  @override
  String toString() => 'SongInfo(id: $id, title: $displayTitle, artist: $displayArtist)';
}
