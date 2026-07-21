class Playlist {
  final String name;
  final List<int> songIds;

  Playlist({required this.name, required this.songIds});

  Playlist copyWith({String? name, List<int>? songIds}) => Playlist(
    name: name ?? this.name,
    songIds: songIds ?? List.from(this.songIds),
  );

  Map<String, dynamic> toJson() => {'name': name, 'songIds': songIds};

  static Playlist fromJson(Map<String, dynamic> j) =>
      Playlist(name: j['name'] ?? '', songIds: List<int>.from(j['songIds'] ?? []));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Playlist && name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'Playlist(name: $name, songs: ${songIds.length})';
}
