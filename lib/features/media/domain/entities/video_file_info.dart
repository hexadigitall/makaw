class VideoFileInfo {
  final int id;
  final String filePath;
  final String fileName;
  final String folder;
  final DateTime? dateTime;
  final int fileSize;

  VideoFileInfo({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.folder,
    this.dateTime,
    required this.fileSize,
  });

  VideoFileInfo copyWith({
    int? id,
    String? filePath,
    String? fileName,
    String? folder,
    DateTime? dateTime,
    int? fileSize,
  }) {
    return VideoFileInfo(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      folder: folder ?? this.folder,
      dateTime: dateTime ?? this.dateTime,
      fileSize: fileSize ?? this.fileSize,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'fileName': fileName,
    'folder': folder,
    'dateTime': dateTime?.toIso8601String(),
    'fileSize': fileSize,
  };

  factory VideoFileInfo.fromJson(Map<String, dynamic> json) => VideoFileInfo(
    id: json['id'] as int,
    filePath: json['filePath'] as String,
    fileName: json['fileName'] as String,
    folder: json['folder'] as String,
    dateTime: json['dateTime'] != null ? DateTime.parse(json['dateTime'] as String) : null,
    fileSize: json['fileSize'] as int,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoFileInfo &&
          id == other.id &&
          filePath == other.filePath &&
          fileName == other.fileName &&
          folder == other.folder &&
          dateTime == other.dateTime &&
          fileSize == other.fileSize;

  @override
  int get hashCode =>
      Object.hash(id, filePath, fileName, folder, dateTime, fileSize);

  @override
  String toString() =>
      'VideoFileInfo(id: $id, fileName: $fileName, folder: $folder)';
}
