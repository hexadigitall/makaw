import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../browser/presentation/widgets/downloads_widget.dart' as feature;

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  /// Returns an Android DocumentsProvider content URI for the given absolute
  /// filesystem directory path, or null when it can't be represented.
  String? _folderContentUri(String dirPath) {
    if (!Platform.isAndroid) return null;
    // Normalize to the external storage tree, e.g.
    //   /storage/emulated/0/Download/Makaw/MakawDownloads
    //     -> primary:Download/Makaw/MakawDownloads
    const prefixes = ['/storage/emulated/0/', '/sdcard/'];
    String? rel;
    for (final p in prefixes) {
      if (dirPath.startsWith(p)) {
        rel = dirPath.substring(p.length);
        break;
      }
    }
    if (rel == null) return null;
    final encoded = rel.split('/').map(Uri.encodeComponent).join('%2F');
    return 'content://com.android.externalstorage.documents/tree/$encoded';
  }

  Future<void> _openLocation(String? savePath) async {
    if (savePath == null) return;
    final dir = Directory(savePath).parent.path;
    // Windows/Linux/macOS: reveal in the OS file manager.
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        await Process.run(
          Platform.isWindows ? 'explorer.exe' : 'xdg-open',
          Platform.isWindows ? [dir] : [dir],
        );
      } catch (_) {}
      return;
    }
    final uri = _folderContentUri(dir);
    if (uri == null) return;
    try {
      await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Downloads', style: TextStyle(color: Colors.white, fontSize: 17)),
      ),
      body: feature.DownloadsWidget(
        onOpenDownload: (url, filename, savePath) async {
          try {
            if (savePath != null) {
              await OpenFilex.open(savePath);
            }
          } catch (_) {}
        },
        onOpenLocation: (url, filename, savePath) async {
          await _openLocation(savePath);
        },
      ),
    );
  }
}
