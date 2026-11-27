import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makaw/features/media/data/services/image_viewer_service.dart';
import 'package:makaw/features/media/data/services/video_player_service.dart';
import 'package:makaw/features/documents/data/services/document_service.dart';
import 'package:makaw/features/music/data/services/music_player_service.dart';
import 'package:makaw/features/news/data/services/news_feed_service.dart';
import 'package:makaw/core/services/terminal_sessions_store.dart';
import 'package:makaw/features/terminal/application/terminal_runtime_manager.dart';
import 'package:makaw/features/terminal/data/ssh_vault_service.dart';

final imageViewerServiceProvider = StateProvider<ImageViewerService?>((ref) => null);
final videoPlayerServiceProvider = StateProvider<VideoPlayerService?>((ref) => null);
final documentServiceProvider = StateProvider<DocumentService?>((ref) => null);
final musicPlayerServiceProvider = StateProvider<MusicPlayerService?>((ref) => null);
final newsFeedServiceProvider = StateProvider<NewsFeedService?>((ref) => null);
final terminalSessionsStoreProvider = StateProvider<TerminalSessionsStore?>((ref) => TerminalSessionsStore());
final sshVaultServiceProvider = Provider<SshVaultService>((ref) => SshVaultService());
final terminalRuntimeManagerProvider = ChangeNotifierProvider<TerminalRuntimeManager>((ref) {
  final store = ref.read(terminalSessionsStoreProvider) ?? TerminalSessionsStore();
  final vault = ref.read(sshVaultServiceProvider);
  return TerminalRuntimeManager(store: store, sshVault: vault);
});
