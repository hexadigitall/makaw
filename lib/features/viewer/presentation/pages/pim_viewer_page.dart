import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import '../../../documents/data/services/document_state_service.dart';

/// Mail, Calendar & Contact Viewer (`EML`, `MBOX`, `ICS`, `VCF`, `MSG`, `OFT`).
class PimViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const PimViewerPage({
    super.key,
    required this.filePath,
    this.title = '',
    this.onClose,
  });

  @override
  State<PimViewerPage> createState() => _PimViewerPageState();
}

class _PimViewerPageState extends State<PimViewerPage> {
  bool _loading = true;
  String? _error;
  String _ext = '';
  List<_MailMessage> _emails = [];
  List<Map<String, String>> _events = [];
  List<Map<String, String>> _contacts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.filePath);
      if (!file.existsSync()) {
        setState(() {
          _error = 'File not found';
          _loading = false;
        });
        return;
      }
      _ext = p.extension(widget.filePath).replaceAll('.', '').toLowerCase();
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);

      if (_ext == 'ics') {
        _events = _parseIcs(text);
      } else if (_ext == 'vcf') {
        _contacts = _parseVcf(text);
      } else if (_ext == 'mbox') {
        final rawMsgs = text.split(RegExp(r'^From ', multiLine: true)).where((s) => s.trim().isNotEmpty).take(50);
        _emails = rawMsgs.map(_parseRfcMail).toList();
      } else if (_ext == 'msg' || _ext == 'oft') {
        _emails = [_parseBinaryMsgStrings(bytes)];
      } else {
        _emails = [_parseRfcMail(text)];
      }

      await DocumentStateService.saveProgress(
        widget.filePath,
        title: widget.title.isNotEmpty ? widget.title : p.basename(widget.filePath),
        currentPage: 1,
        totalPages: 1,
        scrollProgress: 1.0,
      );

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to parse file: $e';
          _loading = false;
        });
      }
    }
  }

  static _MailMessage _parseRfcMail(String raw) {
    final sepIdx = raw.indexOf(RegExp(r'\r?\n\r?\n'));
    final headerBlock = sepIdx > 0 ? raw.substring(0, sepIdx) : raw;
    var body = sepIdx > 0 ? raw.substring(sepIdx).trim() : '';

    final unfolded = headerBlock.replaceAll(RegExp(r'\r?\n[ \t]+'), ' ');
    String header(String key) {
      final m = RegExp('^$key:\\s*(.+)\$', caseSensitive: false, multiLine: true).firstMatch(unfolded);
      return m?.group(1)?.trim() ?? '';
    }

    // Strip basic MIME boundary wrapper if plain text exists
    if (body.contains('Content-Type: text/plain')) {
      final plainMatch = RegExp(
        r'Content-Type:\s*text/plain[^\n]*\r?\n(?:[^\r\n]+\r?\n)*\r?\n([\s\S]*?)(?:\r?\n--|\z)',
        caseSensitive: false,
      ).firstMatch(body);
      if (plainMatch != null && plainMatch.group(1)!.trim().isNotEmpty) {
        body = plainMatch.group(1)!.trim();
      }
    } else if (body.contains('<html') || body.contains('<body')) {
      body = body.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s{2,}'), '\n').trim();
    }

    return _MailMessage(
      subject: header('Subject').isEmpty ? '(No Subject)' : header('Subject'),
      from: header('From'),
      to: header('To'),
      date: header('Date'),
      body: body.length > 60000 ? body.substring(0, 60000) : body,
    );
  }

  static _MailMessage _parseBinaryMsgStrings(List<int> bytes) {
    final runs = <String>[];
    final printable = utf8.decode(bytes, allowMalformed: true)
        .replaceAll(RegExp(r'[^\x20-\x7E\n\r\t]'), ' ')
        .replaceAll(RegExp(r' {3,}'), '\n')
        .trim();
    if (printable.isNotEmpty) runs.add(printable);
    return _MailMessage(
      subject: 'Outlook Message Recovery',
      from: '',
      to: '',
      date: '',
      body: runs.join('\n').trim(),
      isRecovered: true,
    );
  }

  static List<Map<String, String>> _parseIcs(String text) {
    final unfolded = text.replaceAll(RegExp(r'\r?\n[ \t]'), '');
    final blocks = RegExp(r'BEGIN:V(?:EVENT|TODO)([\s\S]*?)END:V(?:EVENT|TODO)', caseSensitive: false).allMatches(unfolded);
    return blocks.map((b) {
      final content = b.group(1)!;
      String field(String key) {
        final m = RegExp('^$key(?:;[^:]*)?:(.+)\$', caseSensitive: false, multiLine: true).firstMatch(content);
        return m?.group(1)?.trim() ?? '';
      }
      return {
        'summary': field('SUMMARY').isEmpty ? 'Untitled Event' : field('SUMMARY'),
        'start': field('DTSTART'),
        'end': field('DTEND'),
        'location': field('LOCATION'),
        'organizer': field('ORGANIZER'),
        'description': field('DESCRIPTION').replaceAll('\\n', '\n'),
      };
    }).toList();
  }

  static List<Map<String, String>> _parseVcf(String text) {
    final unfolded = text.replaceAll(RegExp(r'\r?\n[ \t]'), '');
    final cards = RegExp(r'BEGIN:VCARD([\s\S]*?)END:VCARD', caseSensitive: false).allMatches(unfolded);
    return cards.map((c) {
      final content = c.group(1)!;
      String field(String key) {
        final m = RegExp('^$key(?:;[^:]*)?:(.+)\$', caseSensitive: false, multiLine: true).firstMatch(content);
        return m?.group(1)?.trim() ?? '';
      }
      return {
        'name': field('FN').isEmpty ? field('N').replaceAll(';', ' ').trim() : field('FN'),
        'org': field('ORG'),
        'title': field('TITLE'),
        'tel': field('TEL'),
        'email': field('EMAIL'),
        'note': field('NOTE'),
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.title.isNotEmpty ? widget.title : p.basename(widget.filePath);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141826),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
        ),
        title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 20),
            onPressed: () => OpenFilex.open(widget.filePath),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF06B6D4)));
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.white60)));

    if (_ext == 'ics') {
      if (_events.isEmpty) return const Center(child: Text('No calendar events found', style: TextStyle(color: Colors.white54)));
      return ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: _events.length,
        itemBuilder: (_, i) {
          final e = _events[i];
          return Card(
            color: const Color(0xFF141C2E),
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.event_rounded, color: Color(0xFF06B6D4), size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e['summary']!, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
                  ]),
                  if (e['start']!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Start: ${e['start']}${e['end']!.isNotEmpty ? '  ->  End: ${e['end']}' : ''}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  ],
                  if (e['location']!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Location: ${e['location']}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                  ],
                  if (e['description']!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(e['description']!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ],
              ),
            ),
          );
        },
      );
    }

    if (_ext == 'vcf') {
      if (_contacts.isEmpty) return const Center(child: Text('No contacts found', style: TextStyle(color: Colors.white54)));
      return ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: _contacts.length,
        itemBuilder: (_, i) {
          final c = _contacts[i];
          return Card(
            color: const Color(0xFF141C2E),
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF06B6D4), child: Icon(Icons.person_rounded, color: Colors.black)),
              title: Text(c['name']!.isEmpty ? 'Contact' : c['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c['org']!.isNotEmpty || c['title']!.isNotEmpty)
                    Text('${c['title']} ${c['org']}'.trim(), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  if (c['tel']!.isNotEmpty) Text('Phone: ${c['tel']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  if (c['email']!.isNotEmpty) Text('Email: ${c['email']}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                ],
              ),
            ),
          );
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _emails.length,
      itemBuilder: (_, i) {
        final m = _emails[i];
        return Card(
          color: const Color(0xFF141C2E),
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.subject, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (m.from.isNotEmpty) Text('From: ${m.from}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                if (m.to.isNotEmpty) Text('To: ${m.to}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                if (m.date.isNotEmpty) Text('Date: ${m.date}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                const Divider(color: Color(0xFF283148), height: 22),
                SelectableText(m.body.isEmpty ? '(Empty body)' : m.body, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14, height: 1.5)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MailMessage {
  final String subject;
  final String from;
  final String to;
  final String date;
  final String body;
  final bool isRecovered;

  const _MailMessage({
    required this.subject,
    required this.from,
    required this.to,
    required this.date,
    required this.body,
    this.isRecovered = false,
  });
}
