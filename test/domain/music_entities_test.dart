import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/features/music/domain/entities/song_info.dart';
import 'package:makaw/features/music/domain/entities/playlist.dart';

void main() {
  group('SongInfo', () {
    final song = SongInfo(
      id: 1,
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      album: 'A Night at the Opera',
      filePath: '/storage/emulated/0/Music/bohemian.mp3',
      duration: 354000,
      albumId: 10,
      size: 5000000,
    );

    test('creates correctly', () {
      expect(song.title, 'Bohemian Rhapsody');
      expect(song.displayArtist, 'Queen');
    });

    test('displayTitle falls back to filename', () {
      final untitled = SongInfo(id: 2, title: '', artist: '', album: '', filePath: 'unknown.mp3');
      expect(untitled.displayTitle, 'unknown');
    });

    test('displayArtist falls back to Unknown Artist', () {
      final unknownArtist = SongInfo(id: 3, title: 'Test', artist: '', album: '', filePath: '/music/test.mp3');
      expect(unknownArtist.displayArtist, 'Unknown Artist');
    });

    test('displayArtist handles <unknown>', () {
      final unknown = SongInfo(id: 4, title: 'Test', artist: '<unknown>', album: '', filePath: '/music/test.mp3');
      expect(unknown.displayArtist, 'Unknown Artist');
    });

    test('displayAlbum falls back to Unknown Album', () {
      final noAlbum = SongInfo(id: 5, title: 'Test', artist: '', album: '', filePath: '/music/test.mp3');
      expect(noAlbum.displayAlbum, 'Unknown Album');
    });

    test('displayAlbum handles <unknown>', () {
      final unknown = SongInfo(id: 6, title: 'Test', artist: '', album: '<unknown>', filePath: '/music/test.mp3');
      expect(unknown.displayAlbum, 'Unknown Album');
    });

    test('fileName extracts from filePath', () {
      final song = SongInfo(id: 7, title: '', artist: '', album: '', filePath: 'song.mp3');
      expect(song.fileName, 'song.mp3');
    });

    test('copyWith', () {
      final copy = song.copyWith(title: 'Another One Bites the Dust');
      expect(copy.title, 'Another One Bites the Dust');
      expect(copy.id, 1);
    });

    test('equality uses id and filePath', () {
      final a = SongInfo(id: 1, title: 'A', artist: '', album: '', filePath: '/a.mp3');
      final b = SongInfo(id: 1, title: 'Different Title', artist: '', album: '', filePath: '/a.mp3');
      expect(a, b);
    });

    test('toJson / fromJson roundtrip', () {
      final json = song.toJson();
      final restored = SongInfo.fromJson(json);
      expect(restored.id, song.id);
      expect(restored.title, song.title);
      expect(restored.artist, song.artist);
    });

    test('toString', () {
      expect(song.toString(), contains('Bohemian Rhapsody'));
    });
  });

  group('Playlist', () {
    test('creates correctly', () {
      final pl = Playlist(name: 'Favorites', songIds: [1, 2, 3]);
      expect(pl.name, 'Favorites');
      expect(pl.songIds, [1, 2, 3]);
    });

    test('copyWith', () {
      final pl = Playlist(name: 'Favorites', songIds: [1, 2]);
      final copy = pl.copyWith(songIds: [3, 4]);
      expect(copy.name, 'Favorites');
      expect(copy.songIds, [3, 4]);
    });

    test('equality by name', () {
      final a = Playlist(name: 'Rock', songIds: [1, 2]);
      final b = Playlist(name: 'Rock', songIds: [3, 4]);
      expect(a, b);
    });

    test('toJson / fromJson roundtrip', () {
      final pl = Playlist(name: 'Jazz', songIds: [5, 6, 7]);
      final json = pl.toJson();
      final restored = Playlist.fromJson(json);
      expect(restored.name, 'Jazz');
      expect(restored.songIds, [5, 6, 7]);
    });
  });
}
