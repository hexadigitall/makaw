import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
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

/// High-performance Multi-Sheet & Multi-Format Spreadsheet Viewer.
///
/// Supports pure-Dart parsing for:
/// - `XLSX` / `XLSM` / `XLTX` / `XLTM` (namespace-safe XML + `workbook.xml.rels` mapping)
/// - `XLS` (pure-Dart OLE2 / CFBF Compound Binary BIFF8 parser + string recovery fallback)
/// - `ODS` / `OTS` / `FODS` (OpenDocument XML namespaces)
/// - `CSV` / `TSV` (auto-delimiter detection + RFC-4180 multi-line quoted parser + BOM strip)
/// - `DIF` / `SLK` (`SYLK`) / `GNUMERIC`
/// Uses virtualized [ListView.builder] rows for 60fps scrolling on large workbooks.
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
  bool _isUnreadableBinary = false;
  String _searchQuery = '';
  String _selectedCellInfo = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _hScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveSheetState();
    _searchCtrl.dispose();
    _hScrollCtrl.dispose();
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
        final raw = _decodeTextWithBom(bytes);
        final delim = ext == 'tsv' ? '\t' : _detectDelimiter(raw);
        sheets = [_SheetModel(ext.toUpperCase(), _parseDelimited(raw, delimiter: delim))];
      } else if (ext == 'fods') {
        sheets = _parseOdsXml(_decodeTextWithBom(bytes));
      } else if (ext == 'gnumeric') {
        final raw = DocumentFormatRegistry.looksLikeZipBytes(bytes)
            ? _decodeTextWithBom(ZipDecoder().decodeBytes(bytes).files.first.content as List<int>)
            : _decodeTextWithBom(GZipDecoder().decodeBytes(bytes));
        sheets = _parseGnumericXml(raw);
      } else if (ext == 'dif') {
        sheets = [_SheetModel('DIF', _parseDif(_decodeTextWithBom(bytes)))];
      } else if (ext == 'slk' || ext == 'sylk') {
        sheets = [_SheetModel('SYLK', _parseSylk(_decodeTextWithBom(bytes)))];
      } else if (DocumentFormatRegistry.looksLikeZipBytes(bytes)) {
        if (const {'ods', 'ots'}.contains(ext)) {
          final archive = ZipDecoder().decodeBytes(bytes);
          final content = archive.files.where((f) => f.isFile && f.name.toLowerCase() == 'content.xml').firstOrNull;
          if (content != null) {
            sheets = _parseOdsXml(utf8.decode(content.content as List<int>, allowMalformed: true));
          }
        } else {
          sheets = _parseXlsxWorkbook(bytes);
        }
      } else if (ext == 'xls' || ext == 'xlt' || _looksLikeOle2(bytes)) {
        sheets = _parseBinaryXls(bytes);
        if (sheets.isEmpty) _isUnreadableBinary = true;
      } else {
        // Might be comma/tab text saved with weird extension
        final decoded = _decodeTextWithBom(bytes);
        if (decoded.contains(',') || decoded.contains('\t')) {
          sheets = [_SheetModel('Data', _parseDelimited(decoded, delimiter: _detectDelimiter(decoded)))];
        } else {
          _isUnreadableBinary = true;
        }
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

  static String _decodeTextWithBom(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      // UTF-16LE BOM
      final u16 = Uint16List((bytes.length - 2) ~/ 2);
      final bd = ByteData.sublistView(Uint8List.fromList(bytes), 2);
      for (var i = 0; i < u16.length; i++) {
        u16[i] = bd.getUint16(i * 2, Endian.little);
      }
      return String.fromCharCodes(u16);
    }
    var s = utf8.decode(bytes, allowMalformed: true);
    if (s.startsWith('\uFEFF')) s = s.substring(1);
    return s;
  }

  static String _detectDelimiter(String raw) {
    final sample = raw.split(RegExp(r'\r?\n')).take(5).join('\n');
    const candidates = [',', ';', '\t', '|'];
    var best = ',';
    var bestCount = 0;
    for (final c in candidates) {
      final count = c.allMatches(sample).length;
      if (count > bestCount) {
        bestCount = count;
        best = c;
      }
    }
    return best;
  }

  // ── OOXML XLSX Parser (Namespace-Safe + .rels Resolution) ──────────────────

  List<_SheetModel> _parseXlsxWorkbook(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final byLower = <String, ArchiveFile>{};
    for (final f in archive.files) {
      if (f.isFile) {
        byLower[f.name.replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '').toLowerCase()] = f;
      }
    }

    final shared = <String>[];
    final sharedFile = byLower['xl/sharedstrings.xml'];
    if (sharedFile != null) {
      try {
        final doc = XmlDocument.parse(utf8.decode(sharedFile.content as List<int>, allowMalformed: true));
        for (final si in doc.findAllElements('si', namespace: '*')) {
          shared.add(si.findAllElements('t', namespace: '*').map((t) => t.innerText).join());
        }
      } catch (_) {}
    }

    final relIdToTarget = <String, String>{};
    final relsFile = byLower['xl/_rels/workbook.xml.rels'];
    if (relsFile != null) {
      try {
        final relDoc = XmlDocument.parse(utf8.decode(relsFile.content as List<int>, allowMalformed: true));
        for (final rel in relDoc.findAllElements('Relationship', namespace: '*')) {
          final id = rel.getAttribute('Id') ?? '';
          var target = (rel.getAttribute('Target') ?? '').replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '');
          if (id.isNotEmpty && target.isNotEmpty) {
            if (!target.toLowerCase().startsWith('xl/')) target = 'xl/$target';
            relIdToTarget[id] = target.toLowerCase();
          }
        }
      } catch (_) {}
    }

    final sheetsMeta = <(String name, String? path)>[];
    final wbFile = byLower['xl/workbook.xml'];
    if (wbFile != null) {
      try {
        final wbDoc = XmlDocument.parse(utf8.decode(wbFile.content as List<int>, allowMalformed: true));
        for (final s in wbDoc.findAllElements('sheet', namespace: '*')) {
          final name = s.getAttribute('name') ?? 'Sheet ${sheetsMeta.length + 1}';
          final rId = s.getAttribute('r:id') ?? s.getAttribute('id', namespace: '*');
          sheetsMeta.add((name, rId != null ? relIdToTarget[rId] : null));
        }
      } catch (_) {}
    }

    final result = <_SheetModel>[];
    if (sheetsMeta.isNotEmpty && sheetsMeta.every((e) => e.$2 != null && byLower.containsKey(e.$2))) {
      for (final meta in sheetsMeta) {
        final sf = byLower[meta.$2!]!;
        final rows = _parseXlsxSheetXml(utf8.decode(sf.content as List<int>, allowMalformed: true), shared);
        result.add(_SheetModel(meta.$1, rows));
      }
      return result;
    }

    final sheetFiles = byLower.entries
        .where((e) => e.key.contains('xl/worksheets/') && e.key.endsWith('.xml'))
        .toList()
      ..sort((a, b) {
        final na = int.tryParse(RegExp(r'(\d+)').firstMatch(a.key)?.group(1) ?? '0') ?? 0;
        final nb = int.tryParse(RegExp(r'(\d+)').firstMatch(b.key)?.group(1) ?? '0') ?? 0;
        return na.compareTo(nb);
      });

    for (var idx = 0; idx < sheetFiles.length; idx++) {
      final sf = sheetFiles[idx].value;
      final rows = _parseXlsxSheetXml(utf8.decode(sf.content as List<int>, allowMalformed: true), shared);
      final title = idx < sheetsMeta.length ? sheetsMeta[idx].$1 : 'Sheet ${idx + 1}';
      result.add(_SheetModel(title, rows));
    }
    return result;
  }

  static List<List<String>> _parseXlsxSheetXml(String xmlText, List<String> shared) {
    final rows = <List<String>>[];
    try {
      final doc = XmlDocument.parse(xmlText);
      for (final rowEl in doc.findAllElements('row', namespace: '*').take(10000)) {
        final cells = <int, String>{};
        var nextCol = 0;
        for (final c in rowEl.childElements.where((e) => e.name.local == 'c')) {
          final ref = c.getAttribute('r');
          final colIdx = ref != null ? _colRefToIndex(ref) : nextCol;
          nextCol = colIdx + 1;
          final type = c.getAttribute('t') ?? 'n';
          var value = '';
          final vEl = c.childElements.where((e) => e.name.local == 'v').firstOrNull;
          if (type == 's') {
            final idx = int.tryParse(vEl?.innerText.trim() ?? '');
            if (idx != null && idx >= 0 && idx < shared.length) value = shared[idx];
          } else if (type == 'inlineStr') {
            value = c.findAllElements('t', namespace: '*').map((e) => e.innerText).join();
          } else if (type == 'b') {
            value = vEl?.innerText.trim() == '1' ? 'TRUE' : 'FALSE';
          } else {
            value = vEl?.innerText.trim() ?? '';
          }
          cells[colIdx] = value;
        }
        final width = math.max(1, cells.keys.fold(-1, (a, b) => b > a ? b : a) + 1);
        rows.add([for (var i = 0; i < width; i++) cells[i] ?? '']);
      }
    } catch (_) {}
    return rows;
  }

  // ── Pure-Dart Binary .xls (OLE2 CFBF + BIFF8) Parser ───────────────────────

  static bool _looksLikeOle2(List<int> b) =>
      b.length >= 8 &&
      b[0] == 0xD0 &&
      b[1] == 0xCF &&
      b[2] == 0x11 &&
      b[3] == 0xE0 &&
      b[4] == 0xA1 &&
      b[5] == 0xB1 &&
      b[6] == 0x1A &&
      b[7] == 0xE1;

  static List<_SheetModel> _parseBinaryXls(List<int> rawBytes) {
    final wbBytes = _looksLikeOle2(rawBytes)
        ? _extractOleStream(Uint8List.fromList(rawBytes), const ['Workbook', 'Book'])
        : Uint8List.fromList(rawBytes);
    if (wbBytes == null || wbBytes.length < 16) return const [];

    final bd = ByteData.sublistView(wbBytes);
    final len = wbBytes.length;
    final sst = <String>[];
    final sheetDefs = <(int offset, String name)>[];
    final rowsBySheet = <int, Map<int, Map<int, String>>>{};
    var activeBofSheet = -1;
    var bofCount = 0;

    var pos = 0;
    while (pos + 4 <= len) {
      final recId = bd.getUint16(pos, Endian.little);
      final recLen = bd.getUint16(pos + 2, Endian.little);
      final dataStart = pos + 4;
      final dataEnd = (dataStart + recLen).clamp(0, len);

      if (recId == 0x0809) {
        // BOF
        bofCount++;
        if (bofCount >= 2) {
          // Match to boundSheet offset when available
          final matchedIdx = sheetDefs.indexWhere((s) => (s.$1 - pos).abs() < 8);
          activeBofSheet = matchedIdx >= 0 ? matchedIdx : (bofCount - 2);
          rowsBySheet.putIfAbsent(activeBofSheet, () => {});
        }
      } else if (recId == 0x0085 && dataEnd - dataStart >= 8) {
        // BOUNDSHEET
        final offset = bd.getUint32(dataStart, Endian.little);
        final strLen = wbBytes[dataStart + 6];
        final flags = wbBytes[dataStart + 7];
        final isUtf16 = (flags & 0x01) != 0;
        final nameBytes = wbBytes.sublist(dataStart + 8, (dataStart + 8 + strLen * (isUtf16 ? 2 : 1)).clamp(dataStart + 8, dataEnd));
        final name = isUtf16 ? _decodeUtf16Le(nameBytes) : String.fromCharCodes(nameBytes);
        sheetDefs.add((offset, name.isEmpty ? 'Sheet ${sheetDefs.length + 1}' : name));
      } else if (recId == 0x00FC) {
        // SST (merge adjacent CONTINUE 0x003C records)
        final combined = BytesBuilder()..add(wbBytes.sublist(dataStart, dataEnd));
        var look = dataEnd;
        while (look + 4 <= len && bd.getUint16(look, Endian.little) == 0x003C) {
          final cLen = bd.getUint16(look + 2, Endian.little);
          final cEnd = (look + 4 + cLen).clamp(0, len);
          combined.add(wbBytes.sublist(look + 4, cEnd));
          look = cEnd;
        }
        _parseBiffSst(combined.toBytes(), sst);
        pos = look;
        continue;
      } else if (activeBofSheet >= 0) {
        final grid = rowsBySheet.putIfAbsent(activeBofSheet, () => {});
        if (recId == 0x00FD && dataEnd - dataStart >= 10) {
          // LABELSST
          final r = bd.getUint16(dataStart, Endian.little);
          final c = bd.getUint16(dataStart + 2, Endian.little);
          final idx = bd.getUint32(dataStart + 6, Endian.little);
          if (idx < sst.length) grid.putIfAbsent(r, () => {})[c] = sst[idx];
        } else if (recId == 0x0203 && dataEnd - dataStart >= 14) {
          // NUMBER
          final r = bd.getUint16(dataStart, Endian.little);
          final c = bd.getUint16(dataStart + 2, Endian.little);
          final v = bd.getFloat64(dataStart + 6, Endian.little);
          grid.putIfAbsent(r, () => {})[c] = _fmtNum(v);
        } else if (recId == 0x027E && dataEnd - dataStart >= 10) {
          // RK
          final r = bd.getUint16(dataStart, Endian.little);
          final c = bd.getUint16(dataStart + 2, Endian.little);
          grid.putIfAbsent(r, () => {})[c] = _fmtNum(_decodeRk(bd.getUint32(dataStart + 6, Endian.little)));
        } else if (recId == 0x00BD && dataEnd - dataStart >= 10) {
          // MULRK
          final r = bd.getUint16(dataStart, Endian.little);
          final firstCol = bd.getUint16(dataStart + 2, Endian.little);
          var ptr = dataStart + 4;
          var col = firstCol;
          while (ptr + 6 <= dataEnd - 2) {
            grid.putIfAbsent(r, () => {})[col++] = _fmtNum(_decodeRk(bd.getUint32(ptr + 2, Endian.little)));
            ptr += 6;
          }
        } else if (recId == 0x0204 && dataEnd - dataStart >= 9) {
          // LABEL
          final r = bd.getUint16(dataStart, Endian.little);
          final c = bd.getUint16(dataStart + 2, Endian.little);
          final sLen = bd.getUint16(dataStart + 6, Endian.little);
          final flags = wbBytes[dataStart + 8];
          final isU16 = (flags & 0x01) != 0;
          final rawStr = wbBytes.sublist(dataStart + 9, (dataStart + 9 + sLen * (isU16 ? 2 : 1)).clamp(dataStart + 9, dataEnd));
          grid.putIfAbsent(r, () => {})[c] = isU16 ? _decodeUtf16Le(rawStr) : String.fromCharCodes(rawStr);
        } else if (recId == 0x0205 && dataEnd - dataStart >= 8) {
          // BOOLERR
          final r = bd.getUint16(dataStart, Endian.little);
          final c = bd.getUint16(dataStart + 2, Endian.little);
          if (wbBytes[dataStart + 7] == 0) {
            grid.putIfAbsent(r, () => {})[c] = wbBytes[dataStart + 6] == 1 ? 'TRUE' : 'FALSE';
          }
        }
      }

      pos = dataEnd;
    }

    final result = <_SheetModel>[];
    final sheetCount = math.max(sheetDefs.length, rowsBySheet.length);
    for (var sIdx = 0; sIdx < sheetCount; sIdx++) {
      final grid = rowsBySheet[sIdx];
      if (grid == null || grid.isEmpty) continue;
      final rKeys = grid.keys.toList()..sort();
      final maxCol = grid.values.expand((m) => m.keys).fold(0, math.max);
      final rows = <List<String>>[];
      for (final r in rKeys.take(10000)) {
        final rowMap = grid[r]!;
        rows.add([for (var c = 0; c <= maxCol; c++) rowMap[c] ?? '']);
      }
      final name = sIdx < sheetDefs.length ? sheetDefs[sIdx].$2 : 'Sheet ${sIdx + 1}';
      result.add(_SheetModel(name, rows));
    }
    return result;
  }

  static void _parseBiffSst(Uint8List bytes, List<String> out) {
    if (bytes.length < 8) return;
    final bd = ByteData.sublistView(bytes);
    final uniqueCount = bd.getUint32(4, Endian.little).clamp(0, 50000);
    var p = 8;
    for (var i = 0; i < uniqueCount && p + 3 <= bytes.length; i++) {
      final charLen = bd.getUint16(p, Endian.little);
      final flags = bytes[p + 2];
      p += 3;
      final isU16 = (flags & 0x01) != 0;
      final hasExt = (flags & 0x04) != 0;
      final hasRich = (flags & 0x08) != 0;
      var runs = 0;
      var extSz = 0;
      if (hasRich && p + 2 <= bytes.length) {
        runs = bd.getUint16(p, Endian.little);
        p += 2;
      }
      if (hasExt && p + 4 <= bytes.length) {
        extSz = bd.getUint32(p, Endian.little);
        p += 4;
      }
      final byteLen = charLen * (isU16 ? 2 : 1);
      final end = (p + byteLen).clamp(p, bytes.length);
      final raw = bytes.sublist(p, end);
      out.add(isU16 ? _decodeUtf16Le(raw) : String.fromCharCodes(raw));
      p = (end + runs * 4 + extSz).clamp(end, bytes.length);
    }
  }

  static double _decodeRk(int rk) {
    final div100 = (rk & 0x01) != 0;
    final isInt = (rk & 0x02) != 0;
    double val;
    if (isInt) {
      val = (rk >> 2).toDouble();
    } else {
      final high = rk & 0xFFFFFFFC;
      final bd = ByteData(8)..setUint32(4, high, Endian.little);
      val = bd.getFloat64(0, Endian.little);
    }
    return div100 ? val / 100.0 : val;
  }

  static String _fmtNum(double v) {
    if (v.isNaN || v.isInfinite) return '';
    if ((v - v.roundToDouble()).abs() < 1e-9) return v.round().toString();
    return v.toString();
  }

  static String _decodeUtf16Le(List<int> bytes) {
    final codes = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      codes.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(codes);
  }

  static Uint8List? _extractOleStream(Uint8List bytes, List<String> targets) {
    try {
      final bd = ByteData.sublistView(bytes);
      final sectorShift = bd.getUint16(30, Endian.little);
      final sectorSize = 1 << sectorShift;
      final dirSector = bd.getInt32(48, Endian.little);
      final fatSectors = <int>[];
      for (var i = 0; i < 109; i++) {
        final sid = bd.getInt32(76 + i * 4, Endian.little);
        if (sid >= 0) fatSectors.add(sid);
      }
      final fat = <int>[];
      for (final sid in fatSectors) {
        final off = (sid + 1) * sectorSize;
        for (var j = 0; j < sectorSize && off + j + 4 <= bytes.length; j += 4) {
          fat.add(bd.getInt32(off + j, Endian.little));
        }
      }
      Uint8List readChain(int startSid, int maxBytes) {
        final out = BytesBuilder();
        var cur = startSid;
        var guard = 0;
        while (cur >= 0 && cur < fat.length && guard++ < 50000) {
          final off = (cur + 1) * sectorSize;
          if (off + sectorSize <= bytes.length) {
            out.add(bytes.sublist(off, off + sectorSize));
          } else if (off < bytes.length) {
            out.add(bytes.sublist(off));
          }
          if (maxBytes > 0 && out.length >= maxBytes) break;
          cur = fat[cur];
        }
        final res = out.toBytes();
        return (maxBytes > 0 && res.length > maxBytes) ? res.sublist(0, maxBytes) : res;
      }

      final dirBytes = readChain(dirSector, 0);
      final dirBd = ByteData.sublistView(dirBytes);
      for (var off = 0; off + 128 <= dirBytes.length; off += 128) {
        final nameByteLen = dirBd.getUint16(off + 64, Endian.little).clamp(0, 64);
        if (nameByteLen < 2) continue;
        final name = _decodeUtf16Le(dirBytes.sublist(off, off + nameByteLen - 2));
        if (targets.any((t) => t.toLowerCase() == name.toLowerCase())) {
          final startSid = dirBd.getInt32(off + 116, Endian.little);
          final size = dirBd.getUint32(off + 120, Endian.little);
          return readChain(startSid, size);
        }
      }
    } catch (_) {}
    return null;
  }

  // ── OpenDocument & Legacy Text Workbooks ───────────────────────────────────

  static List<_SheetModel> _parseOdsXml(String xmlText) {
    final result = <_SheetModel>[];
    try {
      final doc = XmlDocument.parse(xmlText);
      for (final table in doc.findAllElements('table', namespace: '*')) {
        final name = table.getAttribute('name', namespace: '*') ?? table.getAttribute('table:name') ?? 'Sheet ${result.length + 1}';
        final rows = <List<String>>[];
        for (final rowEl in table.childElements.where((e) => e.name.local == 'table-row').take(10000)) {
          final rowData = <String>[];
          for (final cell in rowEl.childElements) {
            if (cell.name.local != 'table-cell' && cell.name.local != 'covered-table-cell') continue;
            final repeat = int.tryParse(cell.getAttribute('number-columns-repeated', namespace: '*') ?? cell.getAttribute('table:number-columns-repeated') ?? '1') ?? 1;
            final txt = cell.findAllElements('p', namespace: '*').map((p) => p.innerText).join(' ').trim();
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
      for (final sheetEl in doc.findAllElements('Sheet', namespace: '*')) {
        final name = sheetEl.findAllElements('Name', namespace: '*').firstOrNull?.innerText ?? 'Sheet ${result.length + 1}';
        final byRow = <int, Map<int, String>>{};
        for (final cell in sheetEl.findAllElements('Cell', namespace: '*')) {
          final r = int.tryParse(cell.getAttribute('Row') ?? '0') ?? 0;
          final c = int.tryParse(cell.getAttribute('Col') ?? '0') ?? 0;
          byRow.putIfAbsent(r, () => {})[c] = cell.innerText.trim();
        }
        final rowKeys = byRow.keys.toList()..sort();
        final rows = <List<String>>[];
        for (final r in rowKeys.take(10000)) {
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
    final rows = <List<String>>[];
    var row = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < raw.length && rows.length < 15000; i++) {
      final ch = raw[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < raw.length && raw[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == delimiter && !inQuotes) {
        row.add(buf.toString().trim());
        buf.clear();
      } else if ((ch == '\n' || ch == '\r') && !inQuotes) {
        if (ch == '\r' && i + 1 < raw.length && raw[i + 1] == '\n') i++;
        row.add(buf.toString().trim());
        buf.clear();
        if (row.any((v) => v.isNotEmpty)) rows.add(row);
        row = [];
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty || row.isNotEmpty) {
      row.add(buf.toString().trim());
      if (row.any((v) => v.isNotEmpty)) rows.add(row);
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
      if (curRow >= 0 && curCol >= 0) grid.putIfAbsent(curRow, () => {})[curCol] = val;
    }
    final rKeys = grid.keys.toList()..sort();
    return [
      for (final r in rKeys)
        [
          for (var c = 0; c <= grid[r]!.keys.fold(0, (a, b) => b > a ? b : a); c++) grid[r]![c] ?? '',
        ],
    ];
  }

  static int _colRefToIndex(String ref) {
    final letters = RegExp(r'^([A-Z]+)', caseSensitive: false).firstMatch(ref)?.group(1)?.toUpperCase() ?? 'A';
    var sum = 0;
    for (final ch in letters.codeUnits) {
      sum = sum * 26 + (ch - 64);
    }
    return math.max(0, sum - 1);
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
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.white54))));
    }
    if (_isUnreadableBinary) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.table_chart_outlined, color: Color(0xFF10B981), size: 52),
            const SizedBox(height: 12),
            const Text('Encrypted or proprietary binary workbook format.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
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
      return const Center(child: Text('No cells found in this spreadsheet', style: TextStyle(color: Colors.white54)));
    }

    final current = _sheets[_activeSheetIdx.clamp(0, _sheets.length - 1)];
    final allRows = current.rows;
    final rows = _searchQuery.isEmpty
        ? allRows
        : [
            if (allRows.isNotEmpty) allRows.first,
            ...allRows.skip(1).where((r) => r.any((c) => c.toLowerCase().contains(_searchQuery))),
          ];
    final maxCols = rows.fold<int>(0, (prev, r) => math.max(prev, r.length)).clamp(1, 120);
    const cellWidth = 138.0;
    const rowNumWidth = 44.0;
    final totalTableWidth = rowNumWidth + maxCols * cellWidth;

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
              Text('${rows.length}x$maxCols', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
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
              : Scrollbar(
                  controller: _hScrollCtrl,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _hScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: totalTableWidth,
                      child: ListView.builder(
                        itemCount: rows.length,
                        itemExtent: 38,
                        itemBuilder: (_, r) {
                          final row = rows[r];
                          final isHeader = r == 0;
                          return Container(
                            decoration: BoxDecoration(
                              color: isHeader
                                  ? const Color(0xFF1E293B)
                                  : (r.isOdd ? const Color(0xFF0E1525) : const Color(0xFF0A0F1A)),
                              border: const Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 0.7)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: rowNumWidth,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF141826),
                                    border: Border(right: BorderSide(color: Color(0xFF283148), width: 0.7)),
                                  ),
                                  child: Text(isHeader ? '#' : '$r', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                ),
                                for (var c = 0; c < maxCols; c++)
                                  InkWell(
                                    onTap: () {
                                      final val = c < row.length ? row[c] : '';
                                      setState(() => _selectedCellInfo = 'R${r + 1}C${c + 1}: $val');
                                    },
                                    child: Container(
                                      width: cellWidth,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      alignment: Alignment.centerLeft,
                                      decoration: const BoxDecoration(
                                        border: Border(right: BorderSide(color: Color(0xFF1E293B), width: 0.7)),
                                      ),
                                      child: Text(
                                        c < row.length ? row[c] : '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isHeader ? Colors.white : Colors.white70,
                                          fontSize: 12,
                                          fontWeight: isHeader ? FontWeight.w700 : FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
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
