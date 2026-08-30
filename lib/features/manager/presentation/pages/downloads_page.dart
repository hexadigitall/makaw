import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../../../browser/presentation/widgets/downloads_widget.dart' as feature;

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

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
      ),
    );
  }
}
