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
  slides,
  comic,
  pim,
  vector,
  other;

  static DocumentFormat fromExtension(String ext) {
    final clean = ext.replaceAll('.', '').toLowerCase();
    switch (clean) {
      case 'pdf':
      case 'pdfa':
      case 'pdfx':
      case 'pdfe':
      case 'pdfua':
      case 'xps':
      case 'oxps':
        return DocumentFormat.pdf;
      case 'epub':
      case 'mobi':
      case 'azw':
      case 'azw3':
      case 'azw4':
      case 'kfx':
      case 'fb2':
      case 'lit':
      case 'lrf':
      case 'lrx':
      case 'pdb':
      case 'prc':
      case 'tcr':
      case 'rb':
      case 'snb':
      case 'djvu':
        return DocumentFormat.epub;
      case 'cbz':
      case 'cbr':
      case 'cbt':
      case 'cba':
      case 'cb7':
        return DocumentFormat.comic;
      case 'doc':
      case 'docx':
      case 'docm':
      case 'dotx':
      case 'dotm':
      case 'dot':
      case 'odt':
      case 'ott':
      case 'fodt':
      case 'rtf':
      case 'pages':
      case 'hwp':
      case 'hwpx':
      case 'wpd':
      case 'wps':
      case 'wri':
      case 'lwp':
      case 'abw':
      case 'zabw':
      case 'kwd':
      case 'sdw':
      case 'sxw':
      case 'stw':
      case 'uot':
      case 'mcw':
      case 'mwd':
      case 'cwk':
      case 'pub':
      case 'indd':
      case 'idml':
      case 'qxp':
      case 'pmd':
      case 'scriv':
      case 'celtx':
      case 'one':
      case 'onepkg':
      case 'enex':
        return DocumentFormat.docx;
      case 'txt':
      case 'md':
      case 'markdown':
      case 'log':
      case 'ini':
      case 'cfg':
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'html':
      case 'htm':
      case 'xhtml':
      case 'mhtml':
      case 'mht':
      case 'xsl':
      case 'xslt':
      case 'tex':
      case 'latex':
      case 'bib':
      case 'rst':
      case 'adoc':
      case 'asciidoc':
      case 'org':
      case 'wiki':
      case 'mediawiki':
      case 'textile':
      case 'pod':
      case 'man':
      case 'roff':
      case 'troff':
      case 'groff':
      case 'docbook':
      case 'dita':
      case 'sgml':
      case 'fdx':
      case 'fountain':
      case 'fdf':
      case 'xfdf':
        return DocumentFormat.txt;
      case 'xls':
      case 'xlsx':
      case 'xlsm':
      case 'xlsb':
      case 'xltx':
      case 'xltm':
      case 'xlt':
      case 'ods':
      case 'ots':
      case 'fods':
      case 'csv':
      case 'tsv':
      case 'dif':
      case 'sylk':
      case 'slk':
      case 'wk1':
      case 'wk3':
      case 'wk4':
      case 'wks':
      case '123':
      case 'numbers':
      case 'gnumeric':
      case 'ksp':
      case 'sdc':
      case 'sxc':
      case 'stc':
      case 'uos':
      case 'qpw':
      case 'wb1':
      case 'wb2':
      case 'wb3':
        return DocumentFormat.sheet;
      case 'pptx':
      case 'ppt':
      case 'pptm':
      case 'potx':
      case 'potm':
      case 'pot':
      case 'ppsx':
      case 'ppsm':
      case 'pps':
      case 'odp':
      case 'otp':
      case 'fodp':
      case 'key':
      case 'sdd':
      case 'sxi':
      case 'sti':
      case 'uop':
        return DocumentFormat.slides;
      case 'eml':
      case 'msg':
      case 'mbox':
      case 'vcf':
      case 'ics':
      case 'oft':
        return DocumentFormat.pim;
      case 'svg':
      case 'vsdx':
      case 'vsd':
      case 'vsdm':
      case 'odg':
      case 'dwg':
      case 'dxf':
      case 'plt':
      case 'cgm':
      case 'wmf':
      case 'emf':
      case 'xar':
      case 'cdr':
      case 'ai':
      case 'ps':
      case 'eps':
        return DocumentFormat.vector;
      default:
        return DocumentFormat.other;
    }
  }
}

enum ReaderTheme {
  light,
  dark,
  sepia,
  highContrast;
}

enum ReadingStatus {
  unread,
  reading,
  finished;
}

/// Reading progress and state for persistence and continuous resume.
class DocumentReadingState {
  final String filePath;
  final String title;
  final DocumentFormat format;
  final int currentPage;
  final int totalPages;
  final double scrollProgress; // 0.0 to 1.0
  final double scrollOffset;
  final double zoomScale;
  final DateTime lastRead;
  final ReaderTheme theme;
  final double fontSize;
  final List<int> bookmarks;
  final ReadingStatus readingStatus;
  final bool isPinned;

  const DocumentReadingState({
    required this.filePath,
    required this.title,
    required this.format,
    this.currentPage = 1,
    this.totalPages = 1,
    this.scrollProgress = 0.0,
    this.scrollOffset = 0.0,
    this.zoomScale = 1.0,
    required this.lastRead,
    this.theme = ReaderTheme.dark,
    this.fontSize = 16.0,
    this.bookmarks = const [],
    this.readingStatus = ReadingStatus.unread,
    this.isPinned = false,
  });

  double get normalizedProgress {
    if (scrollProgress > 0.0) return scrollProgress.clamp(0.0, 1.0);
    if (totalPages > 1) return (currentPage / totalPages).clamp(0.0, 1.0);
    return readingStatus == ReadingStatus.finished ? 1.0 : 0.0;
  }

  Map<String, dynamic> toMap() => {
    'file_path': filePath,
    'title': title,
    'format': format.name,
    'current_page': currentPage,
    'total_pages': totalPages,
    'scroll_progress': scrollProgress,
    'scroll_offset': scrollOffset,
    'zoom_scale': zoomScale,
    'last_read': lastRead.toIso8601String(),
    'theme': theme.name,
    'font_size': fontSize,
    'bookmarks': bookmarks.join(','),
    'reading_status': readingStatus.name,
    'pinned': isPinned ? 1 : 0,
  };

  factory DocumentReadingState.fromMap(Map<String, dynamic> map) {
    final cp = (map['current_page'] as int?) ?? 1;
    final tp = (map['total_pages'] as int?) ?? 1;
    final sp = ((map['scroll_progress'] as num?) ?? 0.0).toDouble();
    final inferredStatus = (sp >= 0.98 || (tp > 1 && cp >= tp))
        ? ReadingStatus.finished
        : (sp > 0.0 || cp > 1)
            ? ReadingStatus.reading
            : ReadingStatus.unread;
    return DocumentReadingState(
      filePath: map['file_path'] as String,
      title: (map['title'] as String?) ?? '',
      format: DocumentFormat.values.firstWhere(
        (f) => f.name == map['format'],
        orElse: () => DocumentFormat.other,
      ),
      currentPage: cp,
      totalPages: tp,
      scrollProgress: sp,
      scrollOffset: ((map['scroll_offset'] as num?) ?? 0.0).toDouble(),
      zoomScale: ((map['zoom_scale'] as num?) ?? 1.0).toDouble(),
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
      readingStatus: ReadingStatus.values.firstWhere(
        (s) => s.name == map['reading_status'],
        orElse: () => inferredStatus,
      ),
      isPinned: (map['pinned'] as int? ?? 0) == 1,
    );
  }

  DocumentReadingState copyWith({
    int? currentPage,
    int? totalPages,
    double? scrollProgress,
    double? scrollOffset,
    double? zoomScale,
    DateTime? lastRead,
    ReaderTheme? theme,
    double? fontSize,
    List<int>? bookmarks,
    ReadingStatus? readingStatus,
    bool? isPinned,
  }) {
    return DocumentReadingState(
      filePath: filePath,
      title: title,
      format: format,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      scrollProgress: scrollProgress ?? this.scrollProgress,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      zoomScale: zoomScale ?? this.zoomScale,
      lastRead: lastRead ?? this.lastRead,
      theme: theme ?? this.theme,
      fontSize: fontSize ?? this.fontSize,
      bookmarks: bookmarks ?? this.bookmarks,
      readingStatus: readingStatus ?? this.readingStatus,
      isPinned: isPinned ?? this.isPinned,
    );
  }
}
