/// Universal Document Reader Contract.
///
/// Implements PRD Section 5 & Milestone M4:
/// "Documents Hub > Document Reader > File Explorer -> One Library + One Reader
/// One reader contract for all formats (PDF, EPUB, DOCX, TXT, Spreadsheets)."
library;

enum DocumentFormat {
  pdf,
  epub,
  docx,
  txt,
  sheet,
  other;

  static DocumentFormat fromExtension(String ext) {
    final clean = ext.replaceAll('.', '').toLowerCase();
    switch (clean) {
      case 'pdf':
        return DocumentFormat.pdf;
      case 'epub':
        return DocumentFormat.epub;
      case 'doc':
      case 'docx':
      case 'odt':
      case 'rtf':
        return DocumentFormat.docx;
      case 'txt':
      case 'md':
      case 'log':
      case 'ini':
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
        return DocumentFormat.txt;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return DocumentFormat.sheet;
      default:
        return DocumentFormat.other;
    }
  }
}

enum ReaderTheme {
  light,
  dark,
  sepia;
}

/// Reading progress and state for persistence and continuous resume.
class DocumentReadingState {
  final String filePath;
  final String title;
  final DocumentFormat format;
  final int currentPage;
  final int totalPages;
  final double scrollProgress; // 0.0 to 1.0
  final DateTime lastRead;
  final ReaderTheme theme;
  final double fontSize;
  final List<int> bookmarks;

  const DocumentReadingState({
    required this.filePath,
    required this.title,
    required this.format,
    this.currentPage = 1,
    this.totalPages = 1,
    this.scrollProgress = 0.0,
    required this.lastRead,
    this.theme = ReaderTheme.dark,
    this.fontSize = 16.0,
    this.bookmarks = const [],
  });

  Map<String, dynamic> toMap() => {
    'file_path': filePath,
    'title': title,
    'format': format.name,
    'current_page': currentPage,
    'total_pages': totalPages,
    'scroll_progress': scrollProgress,
    'last_read': lastRead.toIso8601String(),
    'theme': theme.name,
    'font_size': fontSize,
    'bookmarks': bookmarks.join(','),
  };

  factory DocumentReadingState.fromMap(Map<String, dynamic> map) {
    return DocumentReadingState(
      filePath: map['file_path'] as String,
      title: (map['title'] as String?) ?? '',
      format: DocumentFormat.values.firstWhere(
        (f) => f.name == map['format'],
        orElse: () => DocumentFormat.other,
      ),
      currentPage: (map['current_page'] as int?) ?? 1,
      totalPages: (map['total_pages'] as int?) ?? 1,
      scrollProgress: ((map['scroll_progress'] as num?) ?? 0.0).toDouble(),
      lastRead: DateTime.tryParse(map['last_read'] as String? ?? '') ?? DateTime.now(),
      theme: ReaderTheme.values.firstWhere(
        (t) => t.name == map['theme'],
        orElse: () => ReaderTheme.dark,
      ),
      fontSize: ((map['font_size'] as num?) ?? 16.0).toDouble(),
      bookmarks: (map['bookmarks'] as String?)
              ?.split(',')
              .where((s) => s.isNotEmpty)
              .map((s) => int.tryParse(s) ?? 0)
              .toList() ??
          [],
    );
  }

  DocumentReadingState copyWith({
    int? currentPage,
    int? totalPages,
    double? scrollProgress,
    DateTime? lastRead,
    ReaderTheme? theme,
    double? fontSize,
    List<int>? bookmarks,
  }) {
    return DocumentReadingState(
      filePath: filePath,
      title: title,
      format: format,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      scrollProgress: scrollProgress ?? this.scrollProgress,
      lastRead: lastRead ?? this.lastRead,
      theme: theme ?? this.theme,
      fontSize: fontSize ?? this.fontSize,
      bookmarks: bookmarks ?? this.bookmarks,
    );
  }
}
