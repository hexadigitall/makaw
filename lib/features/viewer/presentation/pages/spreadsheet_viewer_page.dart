import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

/// Lightweight XLSX / XLS viewer for the Documents ecosystem.
///
/// Parses the raw cell data from an .xlsx workbook (shared strings + first
/// worksheet) into a scrollable table. Legacy binary .xls files fall back to
/// the system opener.
class SpreadsheetViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const SpreadsheetViewerPage({super.key, required this.filePath, this.title = '', this.onClose});

  @override
  State<SpreadsheetViewerPage> createState() => _SpreadsheetViewerPageState();
}

class _SpreadsheetViewerPageState extends State<SpreadsheetViewerPage> {
  List<List<String>> _rows = [];
  bool _loading = true;
  String? _error;
  bool _isBinaryXls = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ext = widget.filePath.split('.').last.toLowerCase();
    if (ext == 'xls') {
      setState(() {
        _loading = false;
        _isBinaryXls = true;
      });
      return;
    }
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        setState(() { _error = 'File not found'; _loading = false; });
        return;
      }
      final bytes = await file.readAsBytes();
      final rows = _parseXlsx(bytes);
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Error reading spreadsheet: $e'; _loading = false; });
    }
  }

  List<List<String>> _parseXlsx(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final shared = <String>[];
    final sharedFile = archive.findFile('xl/sharedStrings.xml');
    if (sharedFile != null) {
      final text = sharedFile.getContent()!.readString();
      final siMatches = RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(text);
      for (final m in siMatches) {
        final inner = m.group(1)!;
        final tMatches = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(inner);
        final parts = tMatches.map((t) => t.group(1)!).toList();
        shared.add(parts.isEmpty ? '' : _decodeXml(parts.join()));
      }
    }

    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml');
    if (sheetFile == null) return [];

    final sheetText = sheetFile.getContent()!.readString();
    final rows = <List<String>>[];
    final rowMatches = RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true).allMatches(sheetText);
    for (final rowM in rowMatches) {
      final rowBody = rowM.group(1)!;
      final rowData = <String>[];
      final cellMatches = RegExp(r'<c\b([^>]*)>(.*?)</c>', dotAll: true).allMatches(rowBody);
      var maxPos = 0;
      final cells = <int, String>{};
      for (final c in cellMatches) {
        final attrs = c.group(1)!;
        final cellBody = c.group(2)!;
        final ref = RegExp(r'r="([A-Z]+)(\d+)"').firstMatch(attrs);
        final colNum = ref != null ? _colLetterToIndex(ref.group(1)!) : maxPos;
        if (ref != null) maxPos = colNum + 1;
        var value = '';
        final type = RegExp(r't="([^"]*)"').firstMatch(attrs)?.group(1) ?? 'n';
        final vMatch = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(cellBody);
        if (type == 's' && vMatch != null) {
          final idx = int.tryParse(vMatch.group(1)!.trim());
          value = (idx != null && idx >= 0 && idx < shared.length) ? shared[idx] : '';
        } else if (type == 'inlineStr') {
          final inline = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(cellBody);
          value = inline.map((t) => t.group(1)!).join();
        } else if (vMatch != null) {
          value = vMatch.group(1)!.trim();
        }
        cells[colNum] = value;
      }
      final width = cells.keys.fold(-1, (a, b) => b > a ? b : a) + 1;
      for (var i = 0; i < width; i++) {
        rowData.add(cells[i] ?? '');
      }
      rows.add(rowData);
    }
    return rows.take(5000).toList();
  }

  static int _colLetterToIndex(String letters) {
    var sum = 0;
    for (final ch in letters.codeUnits) {
      sum = sum * 26 + (ch - 64);
    }
    return sum - 1;
  }

  static String _decodeXml(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.title.isNotEmpty ? widget.title : widget.filePath.split('\\').last.split('/').last;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(name, style: const TextStyle(fontSize: 14)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: widget.onClose ?? () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
    }
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.white54))));
    }
    if (_isBinaryXls) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.grid_on, color: Colors.white38, size: 48),
        const SizedBox(height: 12),
        const Text('Legacy .xls files open with the system app.', style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 8),
        TextButton(onPressed: () => OpenFilex.open(widget.filePath), child: const Text('Open externally')),
      ]));
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('No data found in this spreadsheet', style: TextStyle(color: Colors.white54)));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(color: Colors.white12, width: 0.5),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            for (var r = 0; r < _rows.length; r++)
              TableRow(
                decoration: r == 0 ? const BoxDecoration(color: Color(0xFF1E293B)) : null,
                children: _rows[r].map((cell) {
                  return Container(
                    constraints: const BoxConstraints(minWidth: 90, maxWidth: 320),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      cell,
                      style: TextStyle(
                        color: r == 0 ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: r == 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
