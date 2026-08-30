import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Central SQLite database for the Makaw manager tools (books/passwords/
/// settings/downloads/file explorer/lyrics/subtitles).
///
/// Unlike the legacy `makaw.db` (history + projects) opened in [State.init],
/// this DB lives at `makaw_mgr.db` next to the app documents, opened once and
/// injected into each manager service via `Service.init(db)` (mirrors the
/// `HistoryService` pattern).
class MakawManagerDb {
  MakawManagerDb._();

  static Database? _db;

  static const int version = 1;

  static Database get db {
    if (_db == null) throw StateError('MakawManagerDb not initialized. Call init() first.');
    return _db!;
  }

  static bool get isInitialized => _db != null;

  static Future<Database> init() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'makaw_mgr.db');
    _db = await openDatabase(
      path,
      version: version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 1) {
          await _createSchema(db);
        }
      },
    );
    return _db!;
  }

  static Future<void> _createSchema(Database db) async {
    // ── Bookmark folders ──────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE bookmark_folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        sort_order INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // ── Bookmarks ─────────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        url TEXT NOT NULL UNIQUE,
        folder_id INTEGER,
        favicon_url TEXT,
        tags TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (folder_id) REFERENCES bookmark_folders(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_bookmarks_folder ON bookmarks(folder_id)');
    await db.execute('CREATE INDEX idx_bookmarks_url ON bookmarks(url)');

    // ── Settings (typed key/value) ────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        type TEXT NOT NULL DEFAULT 'string',
        updated_at TEXT NOT NULL
      )
    ''');

    // ── Passwords (index; secret lives in flutter_secure_storage) ─────────────
    await db.execute('''
      CREATE TABLE passwords (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        domain TEXT NOT NULL,
        url TEXT,
        username TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(domain, username)
      )
    ''');
    await db.execute('CREATE INDEX idx_passwords_domain ON passwords(domain)');

    // ── Downloads history ─────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE downloads (
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        filename TEXT NOT NULL,
        save_path TEXT,
        mime TEXT,
        size INTEGER DEFAULT 0,
        received INTEGER DEFAULT 0,
        state TEXT NOT NULL,
        speed REAL DEFAULT 0,
        error TEXT,
        created_at TEXT NOT NULL,
        completed_at TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_downloads_state ON downloads(state)');
    await db.execute('CREATE INDEX idx_downloads_created ON downloads(created_at DESC)');

    // ── File explorer recents/tags ────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE file_recents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        is_directory INTEGER DEFAULT 0,
        open_count INTEGER DEFAULT 1,
        last_opened TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_file_recents_last ON file_recents(last_opened DESC)');

    // ── Lyrics (per-song, optional timed lines) ──────────────────────────────
    await db.execute('''
      CREATE TABLE lyrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        song_id TEXT NOT NULL,
        song_title TEXT NOT NULL,
        artist TEXT,
        text TEXT NOT NULL,
        start_ms INTEGER,
        end_ms INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_lyrics_song ON lyrics(song_id)');

    // ── Subtitles (timed cues per media item) ─────────────────────────────────
    await db.execute('''
      CREATE TABLE subtitles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_id TEXT NOT NULL,
        media_title TEXT NOT NULL,
        text TEXT NOT NULL,
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_subtitles_media ON subtitles(media_id)');
  }

  /// Convenience helper to close the DB (used in tests / teardown only).
  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
