import 'dart:io';

class VideoItem {
  final String path;
  final String title;
  final String folderName;
  final int sizeBytes;
  final DateTime dateModified;

  VideoItem({
    required this.path,
    required this.title,
    required this.folderName,
    required this.sizeBytes,
    required this.dateModified,
  });

  String get sizeFormatted => '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class CrossPlatformVideoScanner {
  static const Set<String> _validExtensions = {
    'mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'wmv', 'm4v', '3gp', 'ts',
  };

  static const List<String> _junkDirectoryNames = [
    'cache', '.thumbnails', 'stickers', 'temp', 'ad_cache', '.trashed',
    'whatsapp animated gifs', 'facebook_video_cache', 'whatsapp stickers',
    'status', 'gifs',
  ];

  static Future<List<VideoItem>> scanVideos() async {
    final List<Directory> searchRoots = [];

    if (Platform.isAndroid) {
      for (final d in [
        '/storage/emulated/0/Movies', '/storage/emulated/0/Download',
        '/storage/emulated/0/DCIM/Camera', '/storage/emulated/0/Video',
        '/storage/emulated/0/WhatsApp', '/storage/emulated/0/TikTok',
        '/storage/emulated/0/CapCut', '/storage/emulated/0/Instagram',
        '/storage/emulated/0/Telegram', '/storage/emulated/0/Snapchat',
        '/storage/emulated/0/ScreenRecorder', '/storage/emulated/0/recordings',
      ]) {
        searchRoots.add(Directory(d));
      }
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\';
      for (final d in ['$userProfile\\Videos', '$userProfile\\Downloads', '$userProfile\\Desktop']) {
        searchRoots.add(Directory(d));
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      for (final d in ['$home/Videos', '$home/Downloads', '$home/Movies']) {
        searchRoots.add(Directory(d));
      }
    }

    final List<VideoItem> videos = [];

    for (final dir in searchRoots) {
      if (!await dir.exists()) continue;
      try {
        final entities = dir.listSync(recursive: true, followLinks: false);
        for (final entity in entities) {
          if (entity is File) {
            final pathLower = entity.path.toLowerCase();
            final ext = pathLower.split('.').last;
            if (!_validExtensions.contains(ext)) continue;

            final isJunkPath = _junkDirectoryNames.any((junk) => pathLower.contains(junk));
            if (isJunkPath) continue;

            try {
              final stat = entity.statSync();
              if (stat.size < 1.5 * 1024 * 1024) continue;

              final parts = entity.path.split(Platform.pathSeparator);
              final title = parts.last;
              final folderName = parts.length > 1 ? parts[parts.length - 2] : 'Videos';

              videos.add(VideoItem(
                path: entity.path,
                title: title,
                folderName: folderName,
                sizeBytes: stat.size,
                dateModified: stat.modified,
              ));
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    videos.sort((a, b) => b.dateModified.compareTo(a.dateModified));
    return videos;
  }
}
