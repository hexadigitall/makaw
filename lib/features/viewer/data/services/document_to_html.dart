import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

class DocumentToHtml {
  static Future<String> convert(File file) async {
    final bytes = await file.readAsBytes();
    final ext = file.path.split('.').last.toLowerCase();
    final body = await _body(bytes, ext);
    if (ext == 'docx') return body;
    return _wrap(body);
  }

  static Future<String> _body(List<int> bytes, String ext) async {
    switch (ext) {
      case 'docx': return _docx(bytes);
      case 'odt': return _odt(bytes);
      case 'rtf': return _rtf(utf8.decode(bytes, allowMalformed: true));
      case 'doc': return _doc(bytes);
      case 'pages': return _pages(bytes);
      default: return '<pre>${_e(utf8.decode(bytes, allowMalformed: true))}</pre>';
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────

  static String _e(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  static XmlElement? _f(XmlElement p, String n) {
    for (final c in p.childElements) {
      if (c.name.local == n) return c;
    }
    return null;
  }

  static List<XmlElement> _fs(XmlElement p, String n) {
    final r = <XmlElement>[];
    for (final c in p.childElements) {
      if (c.name.local == n) r.add(c);
      r.addAll(_fs(c, n));
    }
    return r;
  }

  static List<XmlElement> _dc(XmlElement p, String n) {
    final r = <XmlElement>[];
    for (final c in p.childElements) {
      if (c.name.local == n) r.add(c);
    }
    return r;
  }

  static String? _a(XmlElement? e, String n) => e?.getAttribute('w:$n') ?? e?.getAttribute(n);

  static int? _ai(XmlElement? e, String n) => int.tryParse(_a(e, n) ?? '');

  static String _twips(String? v) => '${((int.tryParse(v ?? '') ?? 0) / 15).round()}px';

  static String _align(String? v) {
    switch (v?.toLowerCase()) {
      case 'center': return 'center';
      case 'right': return 'right';
      case 'both': case 'distribute': return 'justify';
      default: return 'left';
    }
  }

  static String _imgMime(String path) {
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    if (path.endsWith('.gif')) return 'image/gif';
    if (path.endsWith('.bmp')) return 'image/bmp';
    return 'image/png';
  }

  static String _roman(int n) {
    if (n <= 0 || n > 3999) return '$n';
    final v = [1000,900,500,400,100,90,50,40,10,9,5,4,1];
    final s = ['M','CM','D','CD','C','XC','L','XL','X','IX','V','IV','I'];
    final buf = StringBuffer();
    for (var i = 0; i < v.length; i++) { while (n >= v[i]) { buf.write(s[i]); n -= v[i]; } }
    return buf.toString();
  }

  static String _numFmt(int n, String? fmt) {
    switch (fmt) {
      case 'decimal': return '$n';
      case 'lowerLetter': return String.fromCharCode(96 + ((n - 1) % 26) + 1);
      case 'upperLetter': return String.fromCharCode(64 + ((n - 1) % 26) + 1);
      case 'lowerRoman': return _roman(n).toLowerCase();
      case 'upperRoman': return _roman(n);
      case 'bullet': return '•';
      default: return '$n';
    }
  }

  // ── DOCX via Mammoth.js ───────────────────────────────────────

  static Future<String> _docx(List<int> bytes) async {
    try {
      final mammothJs = await rootBundle.loadString('assets/js/mammoth.min.js');
      final docxBase64 = base64Encode(bytes);

      // Build HTML with Mammoth.js embedded + auto-conversion
      final buf = StringBuffer();
      buf.write('<!DOCTYPE html><html><head><meta charset="utf-8">');
      buf.write('<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=5,viewport-fit=cover">');
      buf.write('<style>');
      buf.write('*{box-sizing:border-box;margin:0;padding:0}');
      buf.write('html,body{width:100%;height:100%;overflow-x:hidden}');
      buf.write('body{background:#0F172A;color:#E2E8F0;font-family:-apple-system,BlinkMacSystemFont,Roboto,sans-serif;font-size:16px;line-height:1.65;padding:16px;word-wrap:break-word;overflow-wrap:break-word}');
      buf.write('@media(orientation:landscape){body{padding:8px 20px}}');
      buf.write('h1{font-size:1.8em;font-weight:700;margin:0.6em 0 0.3em;color:#F8FAFC}');
      buf.write('h2{font-size:1.5em;font-weight:700;margin:0.5em 0 0.3em;color:#F8FAFC}');
      buf.write('h3{font-size:1.25em;font-weight:600;margin:0.5em 0 0.3em;color:#F1F5F9}');
      buf.write('h4{font-size:1.1em;font-weight:600;margin:0.5em 0 0.3em;color:#F1F5F9}');
      buf.write('h5{font-size:1em;font-weight:600;margin:0.5em 0 0.3em;color:#E2E8F0}');
      buf.write('h6{font-size:0.9em;font-weight:600;margin:0.5em 0 0.3em;color:#CBD5E1}');
      buf.write('p{margin:0.5em 0}');
      buf.write('table{border-collapse:collapse;width:100%;margin:12px 0;font-size:14px}');
      buf.write('th,td{border:1px solid #475569;padding:6px 8px;vertical-align:top}');
      buf.write('th{background:#1E293B;font-weight:600;color:#F1F5F9}');
      buf.write('tr:nth-child(even) td{background:rgba(255,255,255,0.02)}');
      buf.write('img{max-width:100%;height:auto;display:block;margin:8px 0;border-radius:4px}');
      buf.write('a{color:#38BDF8;text-decoration:underline}');
      buf.write('ul,ol{margin:0.5em 0;padding-left:1.5em}');
      buf.write('li{margin:0.25em 0}');
      buf.write('blockquote{border-left:3px solid #38BDF8;margin:0.5em 0;padding:0.5em 1em;background:rgba(56,189,248,0.05)}');
      buf.write('pre{white-space:pre-wrap;font-family:monospace;font-size:14px;background:#1E293B;padding:12px;border-radius:6px;overflow-x:auto}');
      buf.write('#loader{display:flex;align-items:center;justify-content:center;min-height:50vh;flex-direction:column;gap:12px}');
      buf.write('#loader .spinner{width:32px;height:32px;border:3px solid #334155;border-top-color:#00897B;border-radius:50%;animation:spin 0.8s linear infinite}');
      buf.write('@keyframes spin{to{transform:rotate(360deg)}}');
      buf.write('</style></head><body>');
      buf.write('<div id="loader"><div class="spinner"></div><span style="color:#94A3B8">Converting document...</span></div>');
      buf.write('<div id="content" style="display:none"></div>');
      buf.write('<script>');
      buf.write(mammothJs);
      buf.write(r'''
(function() {
  try {
    var b64 = "''' + docxBase64 + r'''";
    var raw = atob(b64);
    var bytes = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    mammoth.convertToHtml({arrayBuffer: bytes.buffer}, {
      styleMap: [
        "p[style-name='Heading 1'] => h1:fresh",
        "p[style-name='Heading 2'] => h2:fresh",
        "p[style-name='Heading 3'] => h3:fresh",
        "p[style-name='Heading 4'] => h4:fresh",
        "p[style-name='Heading 5'] => h5:fresh",
        "p[style-name='Heading 6'] => h6:fresh",
        "p[style-name='Title'] => h1:fresh",
        "p[style-name='Subtitle'] => h2:fresh",
        "b => strong",
        "i => em"
      ],
      convertImage: mammoth.images.imgElement(function(image) {
        return image.read("base64").then(function(imageBuffer) {
          return {src: "data:" + image.contentType + ";base64," + imageBuffer};
        });
      })
    }).then(function(result) {
      var loader = document.getElementById("loader");
      var content = document.getElementById("content");
      loader.style.display = "none";
      content.style.display = "block";
      content.innerHTML = result.value || "<p style='color:#94A3B8'>No content found in document</p>";
      if (result.messages.length > 0) {
        var msgs = result.messages.map(function(m) { return m.message; }).join("; ");
        console.log("Mammoth warnings: " + msgs);
      }
    }).catch(function(err) {
      document.getElementById("loader").innerHTML = "<p style='color:#F87171'>Error converting: " + err.message + "</p>";
    });
  } catch(e) {
    document.getElementById("loader").innerHTML = "<p style='color:#F87171'>Error: " + e.message + "</p>";
  }
})();
''');
      buf.write('</script></body></html>');
      return buf.toString();
    } catch (e) {
      return '<p style="color:#F87171;padding:20px">Error loading document converter: $e</p>';
    }
  }

  // ── ODT (Dart parser) ─────────────────────────────────────────

  static Future<String> _odt(List<int> bytes) async {
    final arc = ZipDecoder().decodeBytes(bytes);
    final images = <String, Uint8List>{};
    for (final f in arc) {
      if (f.name.startsWith('Pictures/') && f.content is List<int>) {
        images[f.name] = Uint8List.fromList(f.content as List<int>);
      }
    }
    final cf = arc.files.where((f) => f.name == 'content.xml').firstOrNull;
    if (cf == null) return '<p>[Could not parse ODT]</p>';
    final xml = XmlDocument.parse(utf8.decode(cf.content as List<int>));
    final body = _fs(xml.rootElement, 'body').firstOrNull;
    if (body == null) return '<p>[No body found]</p>';
    final buf = StringBuffer();
    _odtWalk(body, buf, images);
    return buf.toString();
  }

  static void _odtWalk(XmlElement node, StringBuffer buf, Map<String, Uint8List> images) {
    for (final ch in node.childElements) {
      switch (ch.name.local) {
        case 'p': buf.write(_odtP(ch, images)); break;
        case 'h': buf.write(_odtH(ch, images)); break;
        case 'table': buf.write(_odtTbl(ch, images)); break;
        case 'list': _odtWalk(ch, buf, images); break;
        case 'list-item':
          buf.write('<li>');
          _odtWalk(ch, buf, images);
          buf.write('</li>\n');
          break;
        default: _odtWalk(ch, buf, images);
      }
    }
  }

  static String _odtP(XmlElement p, Map<String, Uint8List> images) {
    final st = <String>[];
    final sn = p.getAttribute('text:style-name') ?? '';
    if (sn.contains('Right')) st.add('text-align:right');
    else if (sn.contains('Center')) st.add('text-align:center');
    else if (sn.contains('Justify')) st.add('text-align:justify');

    final content = StringBuffer();
    for (final ch in p.childElements) { content.write(_odtInline(ch, images)); }
    final html = content.toString();
    if (html.trim().isEmpty) return '<p style="min-height:1em"><br></p>\n';
    final sa = st.isNotEmpty ? ' style="${st.join(';')}"' : '';
    return '<p$sa>$html</p>\n';
  }

  static String _odtH(XmlElement h, Map<String, Uint8List> images) {
    final lvl = (int.tryParse(h.getAttribute('text:outline-level') ?? '') ?? 1).clamp(1, 6);
    final content = StringBuffer();
    for (final ch in h.childElements) { content.write(_odtInline(ch, images)); }
    return '<h$lvl>${content}</h$lvl>\n';
  }

  static String _odtInline(XmlElement node, Map<String, Uint8List> images) {
    switch (node.name.local) {
      case 'span': return _odtSpan(node, images);
      case 'a':
        final href = node.getAttribute('xlink:href') ?? node.getAttribute('{http://www.w3.org/1999/xlink}href') ?? '#';
        final buf = StringBuffer();
        for (final ch in node.childElements) { buf.write(_odtInline(ch, images)); }
        return '<a href="${_e(href)}" style="color:#38BDF8" target="_blank">${buf}</a>';
      case 'tab': return '&nbsp;&nbsp;&nbsp;&nbsp;';
      case 'line-break': return '<br>';
      case 's': return ' ' * (int.tryParse(node.getAttribute('text:c') ?? '') ?? 1);
      case 'image': return _odtImg(node, images);
      case 'bookmark': case 'reference-mark': return '';
      default:
        final t = node.innerText;
        return t.isNotEmpty ? _e(t) : '';
    }
  }

  static String _odtSpan(XmlElement span, Map<String, Uint8List> images) {
    final sn = span.getAttribute('text:style-name') ?? '';
    final buf = StringBuffer();
    for (final ch in span.childElements) { buf.write(_odtInline(ch, images)); }
    if (buf.isEmpty) { final t = span.innerText; if (t.isEmpty) return ''; buf.write(_e(t)); }

    final st = <String>[];
    final snl = sn.toLowerCase();
    if (snl.contains('bold') || sn.startsWith('T')) st.add('font-weight:700');
    if (snl.contains('italic')) st.add('font-style:italic');
    if (snl.contains('underline')) st.add('text-decoration:underline');
    if (snl.contains('strike')) st.add('text-decoration:line-through');
    if (snl.contains('superscript') || sn == 'T3') st.add('vertical-align:super;font-size:0.8em');
    if (snl.contains('subscript') || sn == 'T4') st.add('vertical-align:sub;font-size:0.8em');
    if (st.isEmpty) return buf.toString();
    return '<span style="${st.join(';')}">${buf}</span>';
  }

  static String _odtImg(XmlElement img, Map<String, Uint8List> images) {
    final href = img.getAttribute('xlink:href') ?? img.getAttribute('{http://www.w3.org/1999/xlink}href') ?? '';
    if (href.isEmpty) return '';
    final data = images[href];
    if (data == null) return '';
    final mime = _imgMime(href);
    return '<img src="data:$mime;base64,${base64Encode(data)}" style="max-width:100%;height:auto;display:block;margin:8px 0">';
  }

  static String _odtTbl(XmlElement tbl, Map<String, Uint8List> images) {
    final buf = StringBuffer();
    buf.write('<table style="width:100%;border-collapse:collapse;margin:12px 0">\n');
    for (final row in _fs(tbl, 'table-row')) {
      buf.write('<tr>\n');
      for (final cell in _fs(row, 'table-cell')) {
        final cs = int.tryParse(cell.getAttribute('number-columns-spanned') ?? '') ?? 1;
        buf.write('<td style="border:1px solid #475569;padding:6px 8px;vertical-align:top"');
        if (cs > 1) buf.write(' colspan="$cs"');
        buf.write('>\n');
        for (final ch in cell.childElements) {
          if (ch.name.local == 'p') buf.write(_odtP(ch, images));
        }
        buf.write('</td>\n');
      }
      buf.write('</tr>\n');
    }
    buf.write('</table>\n');
    return buf.toString();
  }

  // ── RTF (Dart parser) ─────────────────────────────────────────

  static String _rtf(String rtf) {
    final paras = rtf.split(RegExp(r'\\par[d\s]'));
    final buf = StringBuffer();
    bool bold = false, italic = false, underline = false;
    int fs = 24;

    for (final para in paras) {
      final spans = StringBuffer();
      final tokens = RegExp(r'\\[a-z]+\d*\s?|\\["\x27\\\\{}]|[^\\{}]+|\{|\}').allMatches(para);
      bool hasContent = false;

      for (final m in tokens) {
        final tok = m.group(0)!;
        if (tok == '{' || tok == '}') continue;
        if (tok == '\\b ' || tok == '\\b1') { bold = true; continue; }
        if (tok == '\\b0') { bold = false; continue; }
        if (tok == '\\i ' || tok == '\\i1') { italic = true; continue; }
        if (tok == '\\i0') { italic = false; continue; }
        if (tok.startsWith('\\ul') && !tok.startsWith('\\ulnone')) { underline = true; continue; }
        if (tok == '\\ulnone') { underline = false; continue; }
        if (tok.startsWith('\\fs')) { fs = int.tryParse(tok.substring(3).trim()) ?? fs; continue; }
        if (tok.startsWith('\\')) continue;

        final text = _e(tok);
        if (text.isEmpty) continue;
        hasContent = true;
        final st = <String>[];
        if (bold) st.add('font-weight:700');
        if (italic) st.add('font-style:italic');
        if (underline) st.add('text-decoration:underline');
        if (fs != 24) st.add('font-size:${(fs / 2).round()}pt');
        if (st.isNotEmpty) spans.write('<span style="${st.join(';')}">$text</span>');
        else spans.write(text);
      }

      if (hasContent && spans.isNotEmpty) buf.write('<p>$spans</p>\n');
    }
    return buf.toString();
  }

  // ── DOC / Pages (fallback) ────────────────────────────────────

  static Future<String> _doc(List<int> bytes) async {
    final text = utf8.decode(bytes, allowMalformed: true);
    final printable = text.replaceAll(RegExp(r'[^\x20-\x7E\n\r\t]'), ' ');
    final cleaned = printable.replaceAll(RegExp(r' {3,}'), '\n').trim();
    if (cleaned.length > 100) return '<pre style="white-space:pre-wrap">${_e(cleaned)}</pre>';
    return '<p style="color:#94A3B8;padding:20px">[DOC file — legacy binary format. Export as DOCX for full rendering.]</p>';
  }

  static Future<String> _pages(List<int> bytes) async {
    return '<p style="color:#94A3B8;padding:20px">[Apple Pages file — export as DOCX or PDF for full rendering.]</p>';
  }

  // ── HTML wrapper ────────────────────────────────────────────────

  static String _wrap(String body) => '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=5,user-scalable=yes,viewport-fit=cover">
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;overflow-x:hidden}
body{background:#0F172A;color:#E2E8F0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Noto Sans',sans-serif;font-size:16px;line-height:1.65;padding:16px;word-wrap:break-word;overflow-wrap:break-word;-webkit-text-size-adjust:none}
@media(orientation:landscape){body{padding:8px 20px}}
h1{font-size:1.8em;font-weight:700;margin:0.6em 0 0.3em;color:#F8FAFC}
h2{font-size:1.5em;font-weight:700;margin:0.5em 0 0.3em;color:#F8FAFC}
h3{font-size:1.25em;font-weight:600;margin:0.5em 0 0.3em;color:#F1F5F9}
h4{font-size:1.1em;font-weight:600;margin:0.5em 0 0.3em;color:#F1F5F9}
h5{font-size:1em;font-weight:600;margin:0.5em 0 0.3em;color:#E2E8F0}
h6{font-size:0.9em;font-weight:600;margin:0.5em 0 0.3em;color:#CBD5E1}
p{margin:0.5em 0}
table{border-collapse:collapse;width:100%;margin:12px 0;font-size:14px}
th,td{border:1px solid #475569;padding:6px 8px;vertical-align:top}
th{background:#1E293B;font-weight:600;color:#F1F5F9}
tr:nth-child(even) td{background:rgba(255,255,255,0.02)}
img{max-width:100%;height:auto;display:block;margin:8px 0;border-radius:4px}
a{color:#38BDF8;text-decoration:underline}
pre{white-space:pre-wrap;font-family:'Fira Code',Consolas,monospace;font-size:14px;background:#1E293B;padding:12px;border-radius:6px;overflow-x:auto}
ul,ol{margin:0.5em 0;padding-left:1.5em}
li{margin:0.25em 0}
blockquote{border-left:3px solid #38BDF8;margin:0.5em 0;padding:0.5em 1em;background:rgba(56,189,248,0.05)}
code{font-family:'Fira Code',Consolas,monospace;background:#1E293B;padding:2px 6px;border-radius:3px;font-size:0.9em}
</style>
</head>
<body>
$body
</body>
</html>''';
}
