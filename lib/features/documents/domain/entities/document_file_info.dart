class DocumentFileInfo {
  final int id;
  final String filePath;
  final String fileName;
  final String folder;
  final DateTime? dateTime;
  final int fileSize;
  final String category;

  DocumentFileInfo({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.folder,
    this.dateTime,
    required this.fileSize,
    required this.category,
  });

  DocumentFileInfo copyWith({
    int? id,
    String? filePath,
    String? fileName,
    String? folder,
    DateTime? dateTime,
    int? fileSize,
    String? category,
  }) {
    return DocumentFileInfo(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      folder: folder ?? this.folder,
      dateTime: dateTime ?? this.dateTime,
      fileSize: fileSize ?? this.fileSize,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'fileName': fileName,
    'folder': folder,
    'dateTime': dateTime?.toIso8601String(),
    'fileSize': fileSize,
    'category': category,
  };

  factory DocumentFileInfo.fromJson(Map<String, dynamic> json) => DocumentFileInfo(
    id: json['id'] as int,
    filePath: json['filePath'] as String,
    fileName: json['fileName'] as String,
    folder: json['folder'] as String,
    dateTime: json['dateTime'] != null ? DateTime.parse(json['dateTime'] as String) : null,
    fileSize: json['fileSize'] as int,
    category: json['category'] as String,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentFileInfo &&
          id == other.id &&
          filePath == other.filePath &&
          fileName == other.fileName &&
          folder == other.folder &&
          dateTime == other.dateTime &&
          fileSize == other.fileSize &&
          category == other.category;

  @override
  int get hashCode =>
      Object.hash(id, filePath, fileName, folder, dateTime, fileSize, category);

  @override
  String toString() =>
      'DocumentFileInfo(id: $id, fileName: $fileName, category: $category)';
}
