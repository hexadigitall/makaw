import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makaw/features/media/data/services/image_viewer_service.dart';
import 'package:makaw/features/media/data/services/video_player_service.dart';
import 'package:makaw/features/documents/data/services/document_service.dart';
import 'package:makaw/features/music/data/services/music_player_service.dart';
import 'package:makaw/features/news/data/services/news_feed_service.dart';

final imageViewerServiceProvider = StateProvider<ImageViewerService?>((ref) => null);
final videoPlayerServiceProvider = StateProvider<VideoPlayerService?>((ref) => null);
final documentServiceProvider = StateProvider<DocumentService?>((ref) => null);
final musicPlayerServiceProvider = StateProvider<MusicPlayerService?>((ref) => null);
final newsFeedServiceProvider = StateProvider<NewsFeedService?>((ref) => null);
