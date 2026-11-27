/// Pure-Dart registry for all document formats supported by Makaw Documents.
///
/// Maps ~145 document extensions into 7 semantic [DocumentFamily] groups,
/// 4 honest [DocumentRenderTier] engines, and concrete [DocumentViewerKind]
/// routes while keeping legacy category keys (`pdf`, `epub`, `doc`, `text`,
/// `html`, `xls`, `code`, `slides`, `comic`, `pim`, `vector`) intact.
library;

enum DocumentFamily {
  booksComics('books', 'Books & Comics', 'Books'),
  docsNotes('docs', 'Docs & Notes', 'Docs'),
  sheetsData('sheets', 'Sheets & Data', 'Sheets'),
  slides('slides', 'Presentations', 'Slides'),
  markupTech('markup', 'Markup & Tech', 'Markup'),
  mailPim('pim', 'Mail & PIM', 'Mail & PIM'),
  vectorCad('vector', 'Vector & CAD', 'Vector');

  final String id;
  final String label;
  final String shortLabel;
  const DocumentFamily(this.id, this.label, this.shortLabel);
}

enum DocumentRenderTier {
  native('Native Engine'),
  structuredContainer('Structured Parser'),
  recoveryMetadata('Metadata / Recovery'),
  externalFallback('External Viewer');

  final String label;
  const DocumentRenderTier(this.label);
}

enum DocumentViewerKind {
  pdf,
  epub,
  comic,
  richDoc,
  spreadsheet,
  presentation,
  textMarkup,
  html,
  pim,
  vectorCad,
  recoveryCard,
}

class DocumentFormatSpec {
  final String ext;
  final DocumentFamily family;
  final String categoryKey;
  final String label;
  final DocumentRenderTier tier;
  final DocumentViewerKind viewerKind;
  final int accentHex;

  const DocumentFormatSpec({
    required this.ext,
    required this.family,
    required this.categoryKey,
    required this.label,
    required this.tier,
    required this.viewerKind,
    required this.accentHex,
  });
}

class DocumentFormatRegistry {
  DocumentFormatRegistry._();

  static const DocumentFormatSpec _fallback = DocumentFormatSpec(
    ext: '',
    family: DocumentFamily.docsNotes,
    categoryKey: 'other',
    label: 'Document',
    tier: DocumentRenderTier.recoveryMetadata,
    viewerKind: DocumentViewerKind.recoveryCard,
    accentHex: 0xFF94A3B8,
  );

  static final Map<String, DocumentFormatSpec> _specs = _buildSpecs();

  static Map<String, DocumentFormatSpec> _buildSpecs() {
    final map = <String, DocumentFormatSpec>{};
    void addAll(
      List<String> exts,
      DocumentFamily family,
      String categoryKey,
      String label,
      DocumentRenderTier tier,
      DocumentViewerKind viewerKind,
      int accentHex,
    ) {
      for (final ext in exts) {
        map[ext] = DocumentFormatSpec(
          ext: ext,
          family: family,
          categoryKey: categoryKey,
          label: label,
          tier: tier,
          viewerKind: viewerKind,
          accentHex: accentHex,
        );
      }
    }

    // 1. Books & Comics
    addAll(
      ['pdf', 'pdfa', 'pdfx', 'pdfe', 'pdfua'],
      DocumentFamily.booksComics,
      'pdf',
      'PDF',
      DocumentRenderTier.native,
      DocumentViewerKind.pdf,
      0xFFEF4444,
    );
    addAll(
      ['fdf', 'xfdf'],
      DocumentFamily.booksComics,
      'pdf',
      'PDF Form',
      DocumentRenderTier.structuredContainer,
      DocumentViewerKind.textMarkup,
      0xFFF87171,
    );
    addAll(
      ['epub'],
      DocumentFamily.booksComics,
      'epub',
      'EPUB',
      DocumentRenderTier.native,
      DocumentViewerKind.epub,
      0xFFA78BFA,
    );
    addAll(
      ['cbz', 'cbt', 'cb7', 'cba', 'cbr'],
      DocumentFamily.booksComics,
      'comic',
      'Comic Archive',
      DocumentRenderTier.native,
      DocumentViewerKind.comic,
      0xFFEC4899,
    );
    addAll(
      ['fb2', 'pdb', 'prc', 'tcr'],
      DocumentFamily.booksComics,
      'epub',
      'Reflow E-Book',
      DocumentRenderTier.structuredContainer,
      DocumentViewerKind.richDoc,
      0xFFC084FC,
    );
    addAll(
      ['xps', 'oxps'],
      DocumentFamily.booksComics,
      'pdf',
      'XPS Paper',
      DocumentRenderTier.structuredContainer,
      DocumentViewerKind.vectorCad,
      0xFFFB7185,
    );
    addAll(
      ['djvu', 'mobi', 'azw', 'azw3', 'azw4', 'kfx', 'lit', 'lrf', 'lrx', 'rb', 'snb'],
      DocumentFamily.booksComics,
      'epub',
      'Proprietary E-Book',
      DocumentRenderTier.recoveryMetadata,
      DocumentViewerKind.recoveryCard,
      0xFF8B5CF6,
    );

    // 2. Word Processing & Rich Notes
    addAll(
      ['docx', 'docm', 'dotx', 'dotm', 'odt', 'ott', 'fodt', 'rtf', 'pages', 'abw', 'zabw', 'enex', 'idml', 'scriv', 'celtx'],
      DocumentFamily.docsNotes,
      'doc',
      'Rich Document',
      DocumentRenderTier.structuredContainer,
      DocumentViewerKind.richDoc,
      0xFF38BDF8,
    );
    addAll(
      ['doc', 'dot', 'hwp', 'hwpx', 'wpd', 'wps', 'wri', 'lwp', 'kwd', 'sdw', 'sxw', 'stw', 'uot', 'mcw', 'mwd', 'cwk', 'pub', 'indd', 'qxp', 'pmd', 'one', 'onepkg'],
      DocumentFamily.docsNotes,
      'doc',
      'Legacy / Office Doc',
      DocumentRenderTier.recoveryMetadata,
      DocumentViewerKind.richDoc,
      0xFF60A5FA,
    );
    addAll(
      ['fdx', 'fountain'],
      DocumentFamily.docsNotes,
      'text',
      'Screenplay',
      DocumentRenderTier.structuredContainer,
      DocumentViewerKind.textMarkup,
      0xFF2DD4BF,
    );
    addAll(
      ['txt', 'md', 'markdown'],
      DocumentFamily.docsNotes,
      'text',
      'Text / Markdown',
      DocumentRenderTier.native,
      DocumentViewerKind.textMarkup,
      0xFF34D399,
    );

    // 3. Spreadsheets & Data Tables
    addAll(
      ['xlsx', 'xlsm', 'xltx', 'xltm', 'csv', 'tsv'],
      DocumentFamily.sheetsData,
      'xls',
      'Spreadsheet',
      DocumentRenderTier.native,
      DocumentViewerKind.spreadsheet,
      0xFF10B981,
    );
    addAll(
      ['ods', 'ots', 'fods', 'dif', 'sylk', 'slk', 'gnumeric', 'numbers'],
      DocumentFamily.sheetsData,
      'xls',
      'Workbook',
      DocumentRenderTier.structuredContainer,
      DocumentViewerKind.spreadsheet,
      0xFF059669,
    );
    addAll(
      ['xls', 'xlt', 'xlsb', 'wk1', 'wk3', 'wk4', 'wks', '123', 'ksp', 'sdc', 'sxc', 'stc', 'uos', 'qpw', 'wb1', 'wb2', 'wb3'],
      DocumentFamily.sheetsData,
      'xls',
      'Legacy Workbook',
      DocumentRenderTier.recoveryMetadata,
      DocumentViewerKind.spreadsheet,
      0xFF34D399,
    );

    // 4. Presentations & Slide Decks
    addAll(
      ['pptx', 'pptm', 'potx', 'potm', 'pot', 'ppsx', 'ppsm', 'odp', 'otp', 'fodp', 'key'],
      DocumentFamily.slides,
      'slides',
      'Slide Deck',
      DocumentRenderTier.structuredContainer,
      DocumentViewerKind.presentation,
      0xFFF59E0B,
    );
    addAll(
      ['ppt', 'pps', 'sdd', 'sxi', 'sti', 'uop'],
      DocumentFamily.slides,
      'slides',
      'Legacy Deck',
      DocumentRenderTier.recoveryMetadata,
      DocumentViewerKind.presentation,
      0xFFD97706,
    );

    // 5. Markup, Technical & Publishing Text
    addAll(
      ['html', 'htm', 'xhtml', 'mhtml', 'mht'],
      DocumentFamily.markupTech,
      'html',
      'Web Document',
      DocumentRenderTier.native,
      DocumentViewerKind.html,
      0xFFF97316,
    );
    addAll(
      [
        'xml', 'xsl', 'xslt', 'tex', 'latex', 'bib', 'rst', 'adoc', 'asciidoc',
        'org', 'wiki', 'mediawiki', 'textile', 'pod', 'man', 'roff', 'troff',
        'groff', 'docbook', 'dita', 'sgml', 'log', 'ini', 'cfg', 'json', 'yaml', 'yml',
      ],
      DocumentFamily.markupTech,
      'code',
      'Technical Markup',
      DocumentRenderTier.native,
      DocumentViewerKind.textMarkup,
      0xFF14B8A6,
    );

    // 6. Mail, Contacts & Calendar (PIM)
    addAll(
      ['eml', 'mbox', 'vcf', 'ics'],
      DocumentFamily.mailPim,
      'pim',
      'Mail / PIM',
      DocumentRenderTier.native,
      DocumentViewerKind.pim,
      0xFF06B6D4,
    );
    addAll(
      ['msg', 'oft'],
      DocumentFamily.mailPim,
      'pim',
      'Outlook Mail',
      DocumentRenderTier.recoveryMetadata,
      DocumentViewerKind.pim,
      0xFF0891B2,
    );

    // 7. Diagrams, Print & Vector Specs
    addAll(
      ['svg'],
      DocumentFamily.vectorCad,
      'vector',
      'Vector Graphic',
      DocumentRenderTier.native,
      DocumentViewerKind.vectorCad,
      0xFFE879F9,
    );
    addAll(
      ['dxf', 'vsdx', 'vsdm', 'odg', 'ai'],
      DocumentFamily.vectorCad,
      'vector',
      'Vector / Diagram',
      DocumentRenderTier.structuredContainer,
      DocumentViewerKind.vectorCad,
      0xFFD946EF,
    );
    addAll(
      ['dwg', 'vsd', 'ps', 'eps', 'plt', 'cgm', 'wmf', 'emf', 'xar', 'cdr'],
      DocumentFamily.vectorCad,
      'vector',
      'CAD / Print Spec',
      DocumentRenderTier.recoveryMetadata,
      DocumentViewerKind.vectorCad,
      0xFFC026D3,
    );

    return map;
  }

  /// All registered file extensions (without leading dots).
  static Set<String> get allExtensions => _specs.keys.toSet();

  /// Normalized extension lookup (strips leading dot, handles compound forms like `pdf/a`).
  static String normalizeExtension(String pathOrExt) {
    final trimmed = pathOrExt.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('pdf/')) {
      return lower.replaceAll('/', '');
    }
    final dotIdx = lower.lastIndexOf('.');
    if (dotIdx >= 0 && dotIdx < lower.length - 1) {
      return lower.substring(dotIdx + 1);
    }
    return lower.startsWith('.') ? lower.substring(1) : lower;
  }

  static DocumentFormatSpec specFor(String pathOrExt) {
    final ext = normalizeExtension(pathOrExt);
    return _specs[ext] ?? _fallback;
  }

  static bool isSupportedExtension(String pathOrExt) {
    final ext = normalizeExtension(pathOrExt);
    return _specs.containsKey(ext);
  }

  static DocumentFamily familyFor(String pathOrExt) => specFor(pathOrExt).family;

  static String categoryFor(String pathOrExt) => specFor(pathOrExt).categoryKey;

  static DocumentViewerKind viewerKindFor(String pathOrExt) => specFor(pathOrExt).viewerKind;

  /// Checks whether the file header starts with `%PDF-` (true for PDFs and PDF-compatible `.ai` files).
  static bool looksLikePdfBytes(List<int> bytes) {
    if (bytes.length < 5) return false;
    return bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46 && // F
        bytes[4] == 0x2D; // -
  }

  /// Checks whether the file header starts with PK\x03\x04 ZIP magic bytes.
  static bool looksLikeZipBytes(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;
  }
}
