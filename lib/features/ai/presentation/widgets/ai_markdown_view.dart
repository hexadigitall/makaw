import 'dart:convert';
import 'package:flutter/material.dart';

/// Renders AI markdown responses into rich styled Flutter widgets.
/// Converts headers, bold, italics, code blocks, inline code, lists, blockquotes,
/// and tables into beautiful native UI elements without displaying raw markdown symbols.
class AiMarkdownView extends StatelessWidget {
  final String text;
  final Color accentColor;
  final void Function(String code, String language)? onCopyCode;
  final void Function(String code, String language)? onSaveCode;
  final void Function(String url)? onLinkTap;

  const AiMarkdownView({
    super.key,
    required this.text,
    this.accentColor = const Color(0xFF00A7C2),
    this.onCopyCode,
    this.onSaveCode,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    final widgets = <Widget>[];
    final lines = text.split('\n');
    int i = 0;

    while (i < lines.length) {
      final line = lines[i];

      // 1. Fenced Code Block: ```lang ... ```
      if (line.trim().startsWith('```')) {
        final lang = line.trim().replaceFirst('```', '').trim();
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        if (i < lines.length && lines[i].trim().startsWith('```')) {
          i++; // skip closing ```
        }
        final code = codeLines.join('\n');
        widgets.add(_buildCodeBlock(context, code, lang));
        continue;
      }

      // 2. Horizontal Rule: --- or ***
      if (RegExp(r'^\s*(\-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line)) {
        widgets.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(color: Color(0xFF334155), height: 16),
        ));
        i++;
        continue;
      }

      // 3. Headings: #, ##, ###, ####, #####, ###### (with optional spacing or indent)
      final headingMatch = RegExp(r'^\s*(#{1,6})(?:\s+|(?=[A-Za-z0-9\*\`]))(.+)$').firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final title = _normalizeCellLineBreaks(headingMatch.group(2)!.trim());
        widgets.add(_buildHeading(context, title, level));
        i++;
        continue;
      }

      // 4. Blockquote: > text
      if (line.trim().startsWith('>')) {
        final quoteLines = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          quoteLines.add(
            _normalizeCellLineBreaks(
              lines[i].trim().replaceFirst(RegExp(r'^>\s?'), '').replaceFirst(RegExp(r'^#{1,6}\s+'), ''),
            ),
          );
          i++;
        }
        widgets.add(_buildBlockquote(context, quoteLines.join('\n')));
        continue;
      }

      // 5. Table: | Col | Col | (supports with or without outer pipes when divider row follows)
      final trimmedLine = line.trim();
      final nextLineTrimmed = (i + 1 < lines.length) ? lines[i + 1].trim() : '';
      final isPipedRow = trimmedLine.startsWith('|') && trimmedLine.contains('|', 1);
      final isHeaderPlusDivider = trimmedLine.contains('|') &&
          RegExp(r'^\|?[\s\-:]+\|[\|\s\-:]*$').hasMatch(nextLineTrimmed);
      if (isPipedRow || isHeaderPlusDivider) {
        final tableLines = <String>[];
        while (i < lines.length && lines[i].trim().contains('|') && lines[i].trim().isNotEmpty) {
          tableLines.add(lines[i].trim());
          i++;
        }
        if (tableLines.length >= 2) {
          widgets.add(_buildTable(context, tableLines));
          continue;
        }
        // Not actually a multi-row table: rewind single line to paragraph parser
        i -= tableLines.length;
      }

      // 6. Bullet List: * item, - item, + item
      final bulletMatch = RegExp(r'^(\s*)([\*\-\+])\s+(.+)$').firstMatch(line);
      if (bulletMatch != null) {
        final indent = bulletMatch.group(1)?.length ?? 0;
        final itemText = bulletMatch.group(3)!.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
        widgets.add(_buildListItem(context, itemText, indent: indent, isBullet: true));
        i++;
        continue;
      }

      // 7. Numbered List: 1. item, 2. item
      final numberMatch = RegExp(r'^(\s*)(\d+)[\.\)]\s+(.+)$').firstMatch(line);
      if (numberMatch != null) {
        final indent = numberMatch.group(1)?.length ?? 0;
        final numStr = numberMatch.group(2)!;
        final itemText = numberMatch.group(3)!.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
        widgets.add(_buildListItem(context, itemText, indent: indent, isBullet: false, numberStr: numStr));
        i++;
        continue;
      }

      // 8. Normal Paragraph
      if (line.trim().isNotEmpty) {
        // Collect consecutive non-empty normal lines as a paragraph
        final paraLines = <String>[line];
        i++;
        while (i < lines.length &&
            lines[i].trim().isNotEmpty &&
            !lines[i].trim().startsWith('```') &&
            !lines[i].trim().startsWith('#') &&
            !lines[i].trim().startsWith('>') &&
            !lines[i].trim().startsWith('|') &&
            !RegExp(r'^\s*([\*\-\+]|\d+[\.\)])\s+').hasMatch(lines[i]) &&
            !RegExp(r'^\s*(\-{3,}|\*{3,}|_{3,})\s*$').hasMatch(lines[i])) {
          paraLines.add(lines[i]);
          i++;
        }
        widgets.add(_buildParagraph(context, paraLines.join('\n')));
      } else {
        // Empty line adds subtle spacing
        widgets.add(const SizedBox(height: 6));
        i++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  Widget _buildHeading(BuildContext context, String title, int level) {
    double fontSize = 16.0;
    FontWeight fontWeight = FontWeight.bold;
    Color color = Colors.white;
    EdgeInsets padding = const EdgeInsets.only(top: 10, bottom: 4);

    switch (level) {
      case 1:
        fontSize = 20.0;
        color = Colors.white;
        padding = const EdgeInsets.only(top: 14, bottom: 6);
        break;
      case 2:
        fontSize = 18.0;
        color = Colors.white.withValues(alpha: 0.95);
        padding = const EdgeInsets.only(top: 12, bottom: 5);
        break;
      case 3:
        fontSize = 16.0;
        color = accentColor;
        padding = const EdgeInsets.only(top: 10, bottom: 4);
        break;
      case 4:
      default:
        fontSize = 14.5;
        color = Colors.white70;
        padding = const EdgeInsets.only(top: 8, bottom: 3);
        break;
    }

    return Padding(
      padding: padding,
      child: SelectableText.rich(
        TextSpan(
          children: _parseInlineSpans(
            title,
            baseStyle: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParagraph(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SelectableText.rich(
        TextSpan(
          children: _parseInlineSpans(
            text,
            baseStyle: TextStyle(
              fontSize: 14.5,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListItem(
    BuildContext context,
    String text, {
    int indent = 0,
    required bool isBullet,
    String? numberStr,
  }) {
    final leftPadding = 8.0 + (indent * 12.0);
    return Padding(
      padding: EdgeInsets.only(left: leftPadding, top: 2, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isBullet ? 16 : 24,
            child: Text(
              isBullet ? '•' : '$numberStr.',
              style: TextStyle(
                color: accentColor,
                fontSize: 14,
                fontWeight: isBullet ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText.rich(
              TextSpan(
                children: _parseInlineSpans(
                  text,
                  baseStyle: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockquote(BuildContext context, String text) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
        border: Border(left: BorderSide(color: accentColor, width: 3.5)),
      ),
      child: SelectableText.rich(
        TextSpan(
          children: _parseInlineSpans(
            text,
            baseStyle: TextStyle(
              fontSize: 14.0,
              fontStyle: FontStyle.italic,
              height: 1.45,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }

  static String _normalizeCellLineBreaks(String s) =>
      s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

  static List<String> _splitMarkdownTableRow(String rawLine) {
    var s = rawLine.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|') && !s.endsWith(r'\|')) s = s.substring(0, s.length - 1);
    // Protect escaped pipes `\|`
    const sentinel = '\uE000';
    s = s.replaceAll(r'\|', sentinel);
    return s
        .split('|')
        .map((c) => _normalizeCellLineBreaks(c.replaceAll(sentinel, '|').trim()))
        .toList();
  }

  Widget _buildTable(BuildContext context, List<String> tableLines) {
    if (tableLines.length < 2) return const SizedBox.shrink();

    final rawRows = <List<String>>[];
    for (final line in tableLines) {
      // Skip markdown divider line: |---|---| or :---:|:---
      if (RegExp(r'^\|?[\s\-:]+(\|[\s\-:]*)+$').hasMatch(line)) continue;
      final cells = _splitMarkdownTableRow(line);
      if (cells.isNotEmpty) rawRows.add(cells);
    }

    if (rawRows.isEmpty) return const SizedBox.shrink();
    final colCount = rawRows.first.length;
    if (colCount == 0) return const SizedBox.shrink();

    // Normalize every row to exact header column count so DataTable never asserts.
    final rows = rawRows.map((r) {
      if (r.length == colCount) return r;
      if (r.length > colCount) return r.sublist(0, colCount);
      return [...r, for (var k = r.length; k < colCount; k++) ''];
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
          dataRowMinHeight: 40,
          dataRowMaxHeight: double.infinity,
          horizontalMargin: 12,
          columnSpacing: 16,
          columns: rows.first.map((col) {
            return DataColumn(
              label: Text.rich(
                TextSpan(
                  children: _parseInlineSpans(
                    col,
                    baseStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            );
          }).toList(),
          rows: rows.skip(1).toList().asMap().entries.map((entry) {
            final idx = entry.key;
            final row = entry.value;
            return DataRow(
              color: idx.isOdd ? WidgetStateProperty.all(const Color(0xFF131D31)) : null,
              cells: row.map((cell) {
                return DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text.rich(
                        TextSpan(
                          children: _parseInlineSpans(
                            cell,
                            baseStyle: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13, height: 1.35),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCodeBlock(BuildContext context, String code, String lang) {
    final languageName = lang.trim().isNotEmpty ? lang.trim().toUpperCase() : 'CODE';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Text(
                  languageName,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (onCopyCode != null)
                  InkWell(
                    onTap: () => onCopyCode!(code, lang),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_rounded, size: 14, color: accentColor),
                          const SizedBox(width: 4),
                          Text('Copy Code', style: TextStyle(color: accentColor, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                if (onSaveCode != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => onSaveCode!(code, lang),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.download_rounded, size: 14, color: Color(0xFF94A3B8)),
                          SizedBox(width: 4),
                          Text('Save', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: Color(0xFFE2E8F0),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Parses inline markdown recursively: ***bold-italic***, **bold**, *italic*,
  /// ~~strike~~, `code`, [link](url), and cleans stray unclosed `**` / `###` markers.
  List<InlineSpan> _parseInlineSpans(String text, {required TextStyle baseStyle, int depth = 0}) {
    if (text.isEmpty) return const [];
    // Guard against runaway recursion on pathological input
    if (depth > 3) return [TextSpan(text: _sanitizeOrphanMarkers(text), style: baseStyle)];

    final spans = <InlineSpan>[];
    final regex = RegExp(
      r'(`([^`]+?)`)|(\[([^\]]+)\]\(([^)]+)\))|(\*\*\*(.+?)\*\*\*)|(\*\*(.+?)\*\*)|(__(.+?)__)|(~~(.+?)~~)|(\*([^\*\n]+?)\*)|(_([^_\n]+?)_)',
      dotAll: true,
    );

    int lastMatchEnd = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: _sanitizeOrphanMarkers(text.substring(lastMatchEnd, match.start)),
          style: baseStyle,
        ));
      }

      if (match.group(1) != null) {
        // `inline code` (never strip markers inside code)
        final content = match.group(2)!;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF334155), width: 0.8),
            ),
            child: Text(
              content,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.0,
                color: Color(0xFF38BDF8),
              ),
            ),
          ),
        ));
      } else if (match.group(3) != null) {
        // [text](url)
        final linkText = _sanitizeOrphanMarkers(match.group(4)!);
        final linkUrl = match.group(5)!;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => onLinkTap?.call(linkUrl),
            child: Text(
              linkText,
              style: baseStyle.copyWith(
                color: accentColor,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ));
      } else if (match.group(6) != null) {
        // ***bold-italic***
        spans.addAll(_parseInlineSpans(
          match.group(7)!,
          baseStyle: baseStyle.copyWith(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
          depth: depth + 1,
        ));
      } else if (match.group(8) != null || match.group(10) != null) {
        // **bold** or __bold__
        final content = match.group(9) ?? match.group(11)!;
        spans.addAll(_parseInlineSpans(
          content,
          baseStyle: baseStyle.copyWith(fontWeight: FontWeight.bold),
          depth: depth + 1,
        ));
      } else if (match.group(12) != null) {
        // ~~strikethrough~~
        spans.addAll(_parseInlineSpans(
          match.group(13)!,
          baseStyle: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
          depth: depth + 1,
        ));
      } else if (match.group(14) != null || match.group(16) != null) {
        // *italic* or _italic_
        final content = match.group(15) ?? match.group(17)!;
        spans.addAll(_parseInlineSpans(
          content,
          baseStyle: baseStyle.copyWith(fontStyle: FontStyle.italic),
          depth: depth + 1,
        ));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: _sanitizeOrphanMarkers(text.substring(lastMatchEnd)),
        style: baseStyle,
      ));
    }

    return spans;
  }

  /// Strips unclosed or escaped `**` / `###` markdown artifacts from normal prose.
  static String _sanitizeOrphanMarkers(String raw) {
    return raw
        .replaceAll(r'\*', '*')
        .replaceAll(r'\#', '#')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'(^|\n)\s*#{1,6}\s+'), r'$1')
        .replaceAll('***', '')
        .replaceAll('**', '');
  }

  // ── Document Export Transformers ──────────────────────────────────────────

  /// Strips raw markdown syntax characters for clean plain text (.txt).
  static String stripMarkdown(String md) {
    var out = md;
    // Remove fenced code blocks delimiter
    out = out.replaceAll(RegExp(r'```[a-zA-Z0-9_\-\+]*\n'), '');
    out = out.replaceAll(RegExp(r'```'), '');
    // Remove headings # (1..6, even after list markers/blockquotes or missing space)
    out = out.replaceAll(RegExp(r'^\s*(#{1,6})(?:\s+|(?=[A-Za-z0-9\*\`]))', multiLine: true), '');
    out = out.replaceAll(RegExp(r'^(\s*(?:[\*\-\+]|\d+[\.\)]|>)\s+)#{1,6}\s*', multiLine: true), r'$1');
    out = out.replaceAll(RegExp(r'(^|\s)#{1,6}\s+'), r'$1');
    // Remove markdown table dividers and flatten pipes
    out = out.replaceAll(RegExp(r'^\s*\|?[\s\-:]+(\|[\s\-:]*)+\s*$', multiLine: true), '');
    out = out.replaceAll(RegExp(r'^\s*\|\s*|\s*\|\s*$', multiLine: true), '');
    out = out.replaceAll(RegExp(r'\s*\|\s*'), '  |  ');
    // Remove bold and italic markers
    out = out.replaceAllMapped(RegExp(r'\*\*\*(.+?)\*\*\*'), (m) => m.group(1)!);
    out = out.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!);
    out = out.replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1)!);
    out = out.replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m.group(1)!);
    out = out.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1)!);
    out = out.replaceAllMapped(RegExp(r'_([^_]+?)_'), (m) => m.group(1)!);
    out = out.replaceAll('***', '').replaceAll('**', '');
    // Remove inline code backticks
    out = out.replaceAllMapped(RegExp(r'`([^`]+?)`'), (m) => m.group(1)!);
    // Remove blockquote >
    out = out.replaceAll(RegExp(r'^>\s?', multiLine: true), '');
    // Remove bullet markers at line start
    out = out.replaceAll(RegExp(r'^\s*[\*\-\+]\s+', multiLine: true), '');
    // Convert links [text](url) to text (url)
    out = out.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), (m) => '${m.group(1)} (${m.group(2)})');
    return out.trim();
  }

  static void _writeHtmlTable(StringBuffer buffer, List<String> tableLines) {
    final rows = <List<String>>[];
    for (final line in tableLines) {
      if (RegExp(r'^\|?[\s\-:]+(\|[\s\-:]*)+$').hasMatch(line)) continue;
      final cells = _splitMarkdownTableRow(line);
      if (cells.isNotEmpty) rows.add(cells);
    }
    if (rows.isEmpty) return;
    final colCount = rows.first.length;
    buffer.writeln('<table><thead><tr>');
    for (final h in rows.first) {
      buffer.writeln('<th>${_inlineToHtml(h)}</th>');
    }
    buffer.writeln('</tr></thead><tbody>');
    for (final row in rows.skip(1)) {
      buffer.writeln('<tr>');
      for (var c = 0; c < colCount; c++) {
        final cell = c < row.length ? row[c] : '';
        buffer.writeln('<td>${_inlineToHtml(cell)}</td>');
      }
      buffer.writeln('</tr>');
    }
    buffer.writeln('</tbody></table>');
  }

  /// Converts markdown into a styled, responsive HTML document (.html).
  static String markdownToHtml(String md, {String title = 'Makaw AI Response', String model = ''}) {
    final buffer = StringBuffer();
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html><head><meta charset="utf-8">');
    buffer.writeln('<meta name="viewport" content="width=device-width, initial-scale=1">');
    buffer.writeln('<title>$title</title>');
    buffer.writeln('<style>');
    buffer.writeln('body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f172a; color: #f8fafc; padding: 28px; line-height: 1.65; max-width: 860px; margin: 0 auto; }');
    buffer.writeln('h1, h2, h3, h4 { color: #ffffff; margin-top: 1.5em; margin-bottom: 0.5em; font-weight: 700; }');
    buffer.writeln('h1 { font-size: 24px; border-bottom: 1px solid #334155; padding-bottom: 8px; }');
    buffer.writeln('h2 { font-size: 20px; }');
    buffer.writeln('h3 { font-size: 17px; color: #38bdf8; }');
    buffer.writeln('p { margin: 0.6em 0; }');
    buffer.writeln('strong { font-weight: 700; color: #ffffff; }');
    buffer.writeln('em { font-style: italic; }');
    buffer.writeln('blockquote { border-left: 4px solid #38bdf8; background: #1e293b; padding: 8px 16px; margin: 12px 0; border-radius: 0 8px 8px 0; font-style: italic; }');
    buffer.writeln('pre { background: #1e293b; border: 1px solid #334155; padding: 14px; border-radius: 8px; overflow-x: auto; color: #38bdf8; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 13px; line-height: 1.5; }');
    buffer.writeln('code { background: #1e293b; border: 1px solid #334155; padding: 2px 6px; border-radius: 4px; color: #38bdf8; font-family: monospace; font-size: 13px; }');
    buffer.writeln('ul, ol { padding-left: 24px; margin: 8px 0; }');
    buffer.writeln('li { margin: 4px 0; }');
    buffer.writeln('table { border-collapse: collapse; width: 100%; margin: 16px 0; }');
    buffer.writeln('th, td { border: 1px solid #334155; padding: 8px 12px; text-align: left; }');
    buffer.writeln('th { background: #1e293b; color: #ffffff; }');
    buffer.writeln('.header { border-bottom: 1px solid #334155; padding-bottom: 14px; margin-bottom: 24px; color: #94a3b8; font-size: 13px; }');
    buffer.writeln('</style></head><body>');
    buffer.writeln('<div class="header"><strong>Makaw AI Assistant</strong> • Model: $model • ${DateTime.now().toLocal()}</div>');

    final lines = md.split('\n');
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // Code block
      if (line.trim().startsWith('```')) {
        final lang = line.trim().replaceFirst('```', '').trim();
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.add(const HtmlEscape().convert(lines[i]));
          i++;
        }
        if (i < lines.length) i++;
        buffer.writeln('<pre><code class="language-$lang">${codeLines.join('\n')}</code></pre>');
        continue;
      }

      // Headings (1..6)
      final hMatch = RegExp(r'^\s*(#{1,6})(?:\s+|(?=[A-Za-z0-9\*\`]))(.+)$').firstMatch(line);
      if (hMatch != null) {
        final lvl = hMatch.group(1)!.length;
        final hText = _inlineToHtml(hMatch.group(2)!);
        buffer.writeln('<h$lvl>$hText</h$lvl>');
        i++;
        continue;
      }

      // Markdown tables
      if (line.trim().contains('|') && i + 1 < lines.length && RegExp(r'^\|?[\s\-:]+\|[\|\s\-:]*$').hasMatch(lines[i + 1].trim())) {
        final tLines = <String>[];
        while (i < lines.length && lines[i].trim().contains('|') && lines[i].trim().isNotEmpty) {
          tLines.add(lines[i].trim());
          i++;
        }
        _writeHtmlTable(buffer, tLines);
        continue;
      }

      // Blockquote
      if (line.trim().startsWith('>')) {
        final qLines = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          qLines.add(_inlineToHtml(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), '')));
          i++;
        }
        buffer.writeln('<blockquote>${qLines.join('<br>')}</blockquote>');
        continue;
      }

      // Bullet List
      if (RegExp(r'^\s*[\*\-\+]\s+').hasMatch(line)) {
        buffer.writeln('<ul>');
        while (i < lines.length && RegExp(r'^\s*[\*\-\+]\s+').hasMatch(lines[i])) {
          final item = lines[i].trim().replaceFirst(RegExp(r'^[\*\-\+]\s+'), '');
          buffer.writeln('<li>${_inlineToHtml(item)}</li>');
          i++;
        }
        buffer.writeln('</ul>');
        continue;
      }

      // Numbered List
      if (RegExp(r'^\s*\d+[\.\)]\s+').hasMatch(line)) {
        buffer.writeln('<ol>');
        while (i < lines.length && RegExp(r'^\s*\d+[\.\)]\s+').hasMatch(lines[i])) {
          final item = lines[i].trim().replaceFirst(RegExp(r'^\d+[\.\)]\s+'), '');
          buffer.writeln('<li>${_inlineToHtml(item)}</li>');
          i++;
        }
        buffer.writeln('</ol>');
        continue;
      }

      // Paragraph
      if (line.trim().isNotEmpty) {
        buffer.writeln('<p>${_inlineToHtml(line)}</p>');
      }
      i++;
    }

    buffer.writeln('</body></html>');
    return buffer.toString();
  }

  /// Converts markdown into Word-compatible document format (.doc).
  /// Word and WPS natively open HTML documents with Word XML namespace tags and
  /// retain all bold, italic, heading, and table formatting.
  static String markdownToDoc(String md, {String title = 'Makaw AI Response', String model = ''}) {
    final buffer = StringBuffer();
    buffer.writeln('<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns="http://www.w3.org/TR/REC-html40">');
    buffer.writeln('<head><meta charset="utf-8"><title>$title</title>');
    buffer.writeln('<style>');
    buffer.writeln('body { font-family: "Calibri", "Segoe UI", Arial, sans-serif; font-size: 11pt; color: #1e293b; line-height: 1.5; padding: 24pt; }');
    buffer.writeln('h1 { font-size: 18pt; color: #0284c7; border-bottom: 2pt solid #0284c7; padding-bottom: 4pt; }');
    buffer.writeln('h2 { font-size: 14pt; color: #0f172a; margin-top: 12pt; }');
    buffer.writeln('h3 { font-size: 12pt; color: #0284c7; margin-top: 8pt; }');
    buffer.writeln('strong { font-weight: bold; color: #0f172a; }');
    buffer.writeln('em { font-style: italic; }');
    buffer.writeln('pre { background-color: #f1f5f9; border: 1pt solid #cbd5e1; padding: 8pt; font-family: "Consolas", monospace; font-size: 9.5pt; color: #0f172a; }');
    buffer.writeln('code { background-color: #f1f5f9; border: 0.5pt solid #cbd5e1; padding: 1pt 3pt; font-family: "Consolas", monospace; font-size: 9.5pt; color: #0284c7; }');
    buffer.writeln('blockquote { border-left: 3pt solid #0284c7; background-color: #f8fafc; padding: 6pt 12pt; margin: 6pt 0; font-style: italic; }');
    buffer.writeln('.meta { font-size: 9pt; color: #64748b; border-bottom: 1pt solid #e2e8f0; padding-bottom: 6pt; margin-bottom: 18pt; }');
    buffer.writeln('table { border-collapse: collapse; width: 100%; margin: 12pt 0; }');
    buffer.writeln('th, td { border: 1pt solid #cbd5e1; padding: 6pt 10pt; font-size: 10pt; }');
    buffer.writeln('th { background-color: #f1f5f9; font-weight: bold; }');
    buffer.writeln('</style></head><body>');
    buffer.writeln('<div class="meta"><strong>Makaw AI Assistant Document</strong> | Model: $model | Date: ${DateTime.now().toLocal()}</div>');

    final lines = md.split('\n');
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      if (line.trim().startsWith('```')) {
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.add(const HtmlEscape().convert(lines[i]));
          i++;
        }
        if (i < lines.length) i++;
        buffer.writeln('<pre><code>${codeLines.join('\n')}</code></pre>');
        continue;
      }

      final hMatch = RegExp(r'^\s*(#{1,6})(?:\s+|(?=[A-Za-z0-9\*\`]))(.+)$').firstMatch(line);
      if (hMatch != null) {
        final lvl = hMatch.group(1)!.length;
        final hText = _inlineToHtml(hMatch.group(2)!);
        buffer.writeln('<h$lvl>$hText</h$lvl>');
        i++;
        continue;
      }

      if (line.trim().contains('|') && i + 1 < lines.length && RegExp(r'^\|?[\s\-:]+\|[\|\s\-:]*$').hasMatch(lines[i + 1].trim())) {
        final tLines = <String>[];
        while (i < lines.length && lines[i].trim().contains('|') && lines[i].trim().isNotEmpty) {
          tLines.add(lines[i].trim());
          i++;
        }
        _writeHtmlTable(buffer, tLines);
        continue;
      }

      if (line.trim().startsWith('>')) {
        final qLines = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          qLines.add(_inlineToHtml(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), '')));
          i++;
        }
        buffer.writeln('<blockquote>${qLines.join('<br>')}</blockquote>');
        continue;
      }

      if (RegExp(r'^\s*[\*\-\+]\s+').hasMatch(line)) {
        buffer.writeln('<ul>');
        while (i < lines.length && RegExp(r'^\s*[\*\-\+]\s+').hasMatch(lines[i])) {
          final item = lines[i].trim().replaceFirst(RegExp(r'^[\*\-\+]\s+'), '');
          buffer.writeln('<li>${_inlineToHtml(item)}</li>');
          i++;
        }
        buffer.writeln('</ul>');
        continue;
      }

      if (RegExp(r'^\s*\d+[\.\)]\s+').hasMatch(line)) {
        buffer.writeln('<ol>');
        while (i < lines.length && RegExp(r'^\s*\d+[\.\)]\s+').hasMatch(lines[i])) {
          final item = lines[i].trim().replaceFirst(RegExp(r'^\d+[\.\)]\s+'), '');
          buffer.writeln('<li>${_inlineToHtml(item)}</li>');
          i++;
        }
        buffer.writeln('</ol>');
        continue;
      }

      if (line.trim().isNotEmpty) {
        buffer.writeln('<p>${_inlineToHtml(line)}</p>');
      }
      i++;
    }

    buffer.writeln('</body></html>');
    return buffer.toString();
  }

  static String _inlineToHtml(String text) {
    var out = const HtmlEscape().convert(text);
    // ***bold-italic***
    out = out.replaceAllMapped(RegExp(r'\*\*\*(.+?)\*\*\*'), (m) => '<strong><em>${m[1]}</em></strong>');
    // **bold**
    out = out.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => '<strong>${m[1]}</strong>');
    out = out.replaceAllMapped(RegExp(r'__(.+?)__'), (m) => '<strong>${m[1]}</strong>');
    // *italic*
    out = out.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => '<em>${m[1]}</em>');
    out = out.replaceAllMapped(RegExp(r'_([^_]+?)_'), (m) => '<em>${m[1]}</em>');
    // `code`
    out = out.replaceAllMapped(RegExp(r'`([^`]+?)`'), (m) => '<code>${m[1]}</code>');
    out = out.replaceAll('&lt;br&gt;', '<br>').replaceAll('&lt;br/&gt;', '<br>');
    out = out.replaceAll('***', '').replaceAll('**', '');
    return out;
  }
}
