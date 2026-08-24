import 'package:flutter/material.dart';
import '../../../media/presentation/pages/video_player_page.dart';

class FolderVideoPlayerWidget extends StatefulWidget {
  final List<String> files;
  final VoidCallback? onClose;

  const FolderVideoPlayerWidget({super.key, required this.files, this.onClose});

  @override
  State<FolderVideoPlayerWidget> createState() => _FolderVideoPlayerWidgetState();
}

class _FolderVideoPlayerWidgetState extends State<FolderVideoPlayerWidget> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final filePath = widget.files[_currentIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(filePath.split('\\').last.split('/').last, style: TextStyle(fontSize: 13)),
        backgroundColor: Colors.black87,
        actions: [
          if (_currentIndex > 0)
            IconButton(icon: Icon(Icons.skip_previous), onPressed: () => setState(() => _currentIndex--)),
          Text('${_currentIndex + 1}/${widget.files.length}', style: TextStyle(color: Colors.white54, fontSize: 12)),
          if (_currentIndex < widget.files.length - 1)
            IconButton(icon: Icon(Icons.skip_next), onPressed: () => setState(() => _currentIndex++)),
          if (widget.onClose != null)
            IconButton(icon: Icon(Icons.close), onPressed: widget.onClose),
        ],
      ),
      body: MakawVideoPlayerScreen(
        videoPath: filePath,
        videoTitle: filePath.split('\\').last.split('/').last,
      ),
    );
  }
}
