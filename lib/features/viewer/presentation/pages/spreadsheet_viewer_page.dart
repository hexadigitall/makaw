import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:xml/xml.dart';
import '../../../documents/data/services/document_state_service.dart';
import '../../../documents/domain/document_format_registry.dart';

class _SheetModel {
  final String name;
  final List<List<String>> rows;
  const _SheetModel(this.name, this.rows);
}

/// Multi-sheet & multi-format Spreadsheet / Data Table Viewer for Makaw Documents.
///
/// Supports native/pure-Dart parsing for `XLSX`, `XLSM`, `XLTX`, `XLTM`, `ODS`,
/// `OTS`, `FODS`, `CSV`, `TSV`, `DIF`, `SLK`/`SYLK`, `GNUMERIC`, plus printable
/// text/table recovery or external handoff for legacy binary formats (`XLS`, `XLSB`, etc.).
class SpreadsheetViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const SpreadsheetViewerPage({super.key, required this.filePath, this.title = '', this.onClose});

  @override
  State<SpreadsheetViewerPage> createState() => _SpreadsheetViewerPageState();
}

class _SpreadsheetViewerPageState extends State<SpreadsheetViewerPage> {
  List<_SheetModel> _sheets = [];
  int _activeSheetIdx = 0;
  bool _loading = true;
  String? _error;
  bool _isLegacyBinary = false;
  String _searchQuery = '';
  String _selectedCellInfo = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveSheetState();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSheetState() async {
    if (_sheets.isEmpty) return;
    await DocumentStateService.saveProgress(
      widget.filePath,
      title: widget.title.isNotEmpty ? widget.title : widget.filePath.split('\\').last.split('/').last,
      currentPage: _activeSheetIdx + 1,
      totalPages: _sheets.length,
      scrollProgress: ((_activeSheetIdx + 1) / _sheets.length).clamp(0.0, 1.0),
    );
  }

  Future<void> _load() async {
    final ext = DocumentFormatRegistry.normalizeExtension(widget.filePath);
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        setState(() {
          _error = 'File not found';
          _loading = false;
        });
        return;
      }
      final bytes = await file.readAsBytes();
      List<_SheetModel> sheets = [];

      if (ext == 'csv' || ext == 'tsv') {
        final text = utf8.decode(bytes, allowMalformed: true);
        sheets = [_SheetModel(ext.toUpperCase(), _parseDelimited(text, delimiter: ext == 'tsv' ? '\t' : ','))];
      } else if (ext == 'fods') {
        sheets = _parseOdsXml(utf8.decode(bytes, allowMalformed: true));
      } else if (ext == 'gnumeric') {
        final raw = DocumentFormatRegistry.looksLikeZipBytes(bytes)
            ? utf8.decode(ZipDecoder().decodeBytes(bytes).files.first.content as List<int>, allowMalformed: true)
            : utf8.decode(GZipDecoder().decodeBytes(bytes), allowMalformed: true);
        sheets = _parseGnumericXml(raw);
      } else if (ext == 'dif') {
        sheets = [_SheetModel('DIF', _parseDif(utf8.decode(bytes, allowMalformed: true)))];
      } else if (ext == 'slk' || ext == 'sylk') {
        sheets = [_SheetModel('SYLK', _parseSylk(utf8.decode(bytes, allowMalformed: true)))];
      } else if (DocumentFormatRegistry.looksLikeZipBytes(bytes)) {
        if (const {'ods', 'ots'}.contains(ext)) {
          final archive = ZipDecoder().decodeBytes(bytes);
          final content = archive.findFile('content.xml');
          if (content != null) {
            sheets = _parseOdsXml(utf8.decode(content.content as List<int>, allowMalformed: true));
          }
        } else {
          sheets = _parseXlsxWorkbook(bytes);
        }
      } else {
        _isLegacyBinary = true;
      }

      final saved = await DocumentStateService.getState(widget.filePath);
      final restoredSheet = (saved != null && sheets.isNotEmpty)
          ? (saved.currentPage - 1).clamp(0, sheets.length - 1)
          : 0;

      if (mounted) {
        setState(() {
          _sheets = sheets;
          _activeSheetIdx = restoredSheet;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error reading spreadsheet: $e';
          _loading = false;
        });
      }
    }
  }

  List<_SheetModel> _parseXlsxWorkbook(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final shared = <String>[];
    final sharedFile = archive.findFile('xl/sharedStrings.xml');
    if (sharedFile != null) {
      try {
        final doc = XmlDocument.parse(utf8.decode(sharedFile.content as List<int>, allowMalformed: true));
        for (final si in doc.findAllElements('si')) {
          shared.add(si.findAllElements('t').map((t) => t.innerText).join());
        }
      } catch (_) {}
    }

    final sheetNames = <String>[];
    final wbFile = archive.findFile('xl/workbook.xml');
    if (wbFile != null) {
      try {
        final wbDoc = XmlDocument.parse(utf8.decode(wbFile.content as List<int>, allowMalformed: true));
        for (final s in wbDoc.findAllElements('sheet')) {
          sheetNames.add(s.getAttribute('name') ?? 'Sheet ${sheetNames.length + 1}');
        }
      } catch (_) {}
    }

    final sheetFiles = archive.files
        .where((f) => f.isFile && RegExp(r'^xl/worksheets/sheet\d+\.xml$', caseSensitive: false).hasMatch(f.name))
        .toList()
      ..sort((a, b) {
        final na = int.tryParse(RegExp(r'(\d+)').firstMatch(a.name)?.group(1) ?? '0') ?? 0;
        final nb = int.tryParse(RegExp(r'(\d+)').firstMatch(b.name)?.group(1) ?? '0') ?? 0;
        return na.compareTo(nb);
      });

    final result = <_SheetModel>[];
    for (var idx = 0; idx < sheetFiles.length; idx++) {
      final sf = sheetFiles[idx];
      final xmlText = utf8.decode(sf.content as List<int>, allowMalformed: true);
      final rows = _parseXlsxSheetXml(xmlText, shared);
      final title = idx < sheetNames.length ? sheetNames[idx] : 'Sheet ${idx + 1}';
      result.add(_SheetModel(title, rows));
    }
    return result;
  }

  static List<List<String>> _parseXlsxSheetXml(String xmlText, List<String> shared) {
    final rows = <List<String>>[];
    try {
      final doc = XmlDocument.parse(xmlText);
      for (final rowEl in doc.findAllElements('row').take(5000)) {
        final cells = <int, String>{};
        var nextCol = 0;
        for (final c in rowEl.findElements('c')) {
          final ref = c.getAttribute('r');
          final colIdx = ref != null ? _colRefToIndex(ref) : nextCol;
          nextCol = colIdx + 1;
          final type = c.getAttribute('t') ?? 'n';
          var value = '';
          if (type == 's') {
            final idx = int.tryParse(c.findElements('v').firstOrNull?.innerText.trim() ?? '');
            if (idx != null && idx >= 0 && idx < shared.length) value = shared[idx];
          } else if (type == 'inlineStr') {
            value = c.findAllElements('t').map((e) => e.innerText).join();
          } else if (type == 'b') {
            value = c.findElements('v').firstOrNull?.innerText.trim() == '1' ? 'TRUE' : 'FALSE';
          } else {
            value = c.findElements('v').firstOrNull?.innerText.trim() ?? '';
          }
          cells[colIdx] = value;
        }
        final width = cells.keys.fold(-1, (a, b) => b > a ? b : a) + 1;
        rows.add([for (var i = 0; i < width; i++) cells[i] ?? '']);
      }
    } catch (_) {}
    return rows;
  }

  static List<_SheetModel> _parseOdsXml(String xmlText) {
    final result = <_SheetModel>[];
    try {
      final doc = XmlDocument.parse(xmlText);
      for (final table in doc.findAllElements('table')) {
        final name = table.getAttribute('table:name') ?? table.getAttribute('name') ?? 'Sheet ${result.length + 1}';
        final rows = <List<String>>[];
        for (final rowEl in table.findElements('table-row').take(5000)) {
          final rowData = <String>[];
          for (final cell in rowEl.childElements) {
            if (cell.name.local != 'table-cell' && cell.name.local != 'covered-table-cell') continue;
            final repeat = int.tryParse(cell.getAttribute('table:number-columns-repeated') ?? cell.getAttribute('number-columns-repeated') ?? '1') ?? 1;
            final txt = cell.findAllElements('p').map((p) => p.innerText).join(' ').trim();
            final count = repeat.clamp(1, txt.isEmpty ? 1 : 20);
            for (var k = 0; k < count; k++) {
              rowData.add(txt);
            }
          }
          if (rowData.any((v) => v.isNotEmpty)) rows.add(rowData);
        }
        if (rows.isNotEmpty) result.add(_SheetModel(name, rows));
      }
    } catch (_) {}
    return result;
  }

  static List<_SheetModel> _parseGnumericXml(String xmlText) {
    final result = <_SheetModel>[];
    try {
      final doc = XmlDocument.parse(xmlText);
      for (final sheetEl in doc.findAllElements('Sheet')) {
        final name = sheetEl.findElements('Name').firstOrNull?.innerText ?? 'Sheet ${result.length + 1}';
        final byRow = <int, Map<int, String>>{};
        for (final cell in sheetEl.findAllElements('Cell')) {
          final r = int.tryParse(cell.getAttribute('Row') ?? '0') ?? 0;
          final c = int.tryParse(cell.getAttribute('Col') ?? '0') ?? 0;
          byRow.putIfAbsent(r, () => {})[c] = cell.innerText.trim();
        }
        final rowKeys = byRow.keys.toList()..sort();
        final rows = <List<String>>[];
        for (final r in rowKeys.take(3000)) {
          final map = byRow[r]!;
          final width = map.keys.fold(-1, (a, b) => b > a ? b : a) + 1;
          rows.add([for (var c = 0; c < width; c++) map[c] ?? '']);
        }
        result.add(_SheetModel(name, rows));
      }
    } catch (_) {}
    return result;
  }

  static List<List<String>> _parseDelimited(String raw, {required String delimiter}) {
    final lines = raw.split(RegExp(r'\r?\n'));
    final rows = <List<String>>[];
    for (final line in lines.take(5000)) {
      if (line.isEmpty) continue;
      if (delimiter == '\t') {
        rows.add(line.split('\t'));
        continue;
      }
      final cells = <String>[];
      final buf = StringBuffer();
      var inQuotes = false;
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') {
          if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = !inQuotes;
          }
        } else if (ch == delimiter && !inQuotes) {
          cells.add(buf.toString());
          buf.clear();
        } else {
          buf.write(ch);
        }
      }
      cells.add(buf.toString());
      rows.add(cells);
    }
    return rows;
  }

  static List<List<String>> _parseDif(String raw) {
    final lines = raw.split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();
    final rows = <List<String>>[];
    var currentRow = <String>[];
    var inData = false;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i] == 'DATA') {
        inData = true;
        continue;
      }
      if (!inData) continue;
      if (lines[i] == '-1,0' && i + 1 < lines.length && lines[i + 1] == 'BOT') {
        if (currentRow.isNotEmpty) rows.add(currentRow);
        currentRow = [];
        i++;
      } else if (lines[i].startsWith('1,0') && i + 1 < lines.length) {
        currentRow.add(lines[i + 1].replaceAll('"', ''));
        i++;
      } else if (lines[i].startsWith('0,')) {
        final parts = lines[i].split(',');
        if (parts.length >= 2) currentRow.add(parts[1]);
        i++;
      }
    }
    if (currentRow.isNotEmpty) rows.add(currentRow);
    return rows;
  }

  static List<List<String>> _parseSylk(String raw) {
    final grid = <int, Map<int, String>>{};
    var curRow = 0;
    var curCol = 0;
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      if (!line.startsWith('C;')) continue;
      var val = '';
      for (final part in line.substring(2).split(';')) {
        if (part.startsWith('Y')) curRow = (int.tryParse(part.substring(1)) ?? 1) - 1;
        if (part.startsWith('X')) curCol = (int.tryParse(part.substring(1)) ?? 1) - 1;
        if (part.startsWith('K')) val = part.substring(1).replaceAll('"', '');
      }
      if (curRow >= 0 && curCol >= 0) {
        grid.putIfAbsent(curRow, () => {})[curCol] = val;
      }
    }
    final rKeys = grid.keys.toList()..sort();
    return [
      for (final r in rKeys)
        [
          for (var c = 0; c <= grid[r]!.keys.fold(0, (a, b) => b > a ? b : a); c++)
            grid[r]![c] ?? '',
        ],
    ];
  }

  static int _colRefToIndex(String ref) {
    final letters = RegExp(r'^([A-Z]+)').firstMatch(ref)?.group(1) ?? 'A';
    var sum = 0;
    for (final ch in letters.codeUnits) {
      sum = sum * 26 + (ch - 64);
    }
    return sum - 1;
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.title.isNotEmpty ? widget.title : widget.filePath.split('\\').last.split('/').last;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141826),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: widget.onClose ?? () => Navigator.pop(context),
        ),
        title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 20),
            onPressed: () => OpenFilex.open(widget.filePath),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
    }
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.white54))));
    }
    if (_isLegacyBinary) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.table_chart_outlined, color: Color(0xFF10B981), size: 52),
            const SizedBox(height: 12),
            const Text('Legacy binary workbook format opens cleanly with the system office viewer.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => OpenFilex.open(widget.filePath),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open Externally'),
            ),
          ]),
        ),
      );
    }
    if (_sheets.isEmpty) {
      return const Center(child: Text('No data found in this workbook', style: TextStyle(color: Colors.white54)));
    }

    final current = _sheets[_activeSheetIdx.clamp(0, _sheets.length - 1)];
    final allRows = current.rows;
    final rows = _searchQuery.isEmpty
        ? allRows
        : [
            if (allRows.isNotEmpty) allRows.first,
            ...allRows.skip(1).where((r) => r.any((c) => c.toLowerCase().contains(_searchQuery))),
          ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Filter rows in ${current.name}...',
                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF141C2E),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              Text('${rows.length} rows', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            ],
          ),
        ),
        if (_selectedCellInfo.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF1E293B),
            child: SelectableText(
              _selectedCellInfo,
              style: const TextStyle(color: Color(0xFF34D399), fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No matching rows', style: TextStyle(color: Colors.white54)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      border: TableBorder.all(color: Colors.white12, width: 0.5),
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [
                        for (var r = 0; r < rows.length; r++)
                          TableRow(
                            decoration: r == 0 ? const BoxDecoration(color: Color(0xFF1E293B)) : null,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                color: const Color(0xFF141826),
                                child: Text(
                                  r == 0 ? '#' : '$r',
                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                ),
                              ),
                              for (var c = 0; c < rows[r].length; c++)
                                InkWell(
                                  onTap: () => setState(() => _selectedCellInfo = 'R${r + 1}C${c + 1}: ${rows[r][c]}'),
                                  child: Container(
                                    constraints: const BoxConstraints(minWidth: 90, maxWidth: 280),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    child: Text(
                                      rows[r][c],
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: r == 0 ? Colors.white : Colors.white70,
                                        fontSize: 12,
                                        fontWeight: r == 0 ? FontWeight.w700 : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
        ),
        if (_sheets.length > 1)
          Container(
            height: 44,
            color: const Color(0xFF141826),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _sheets.length,
              itemBuilder: (_, idx) {
                final active = idx == _activeSheetIdx;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_sheets[idx].name),
                    selected: active,
                    selectedColor: const Color(0xFF10B981),
                    backgroundColor: const Color(0xFF1E293B),
                    labelStyle: TextStyle(
                      color: active ? Colors.black : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _activeSheetIdx = idx;
                        _selectedCellInfo = '';
                      });
                      _saveSheetState();
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
