import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'vocab.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE words (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word TEXT NOT NULL,
            phonetic TEXT,
            definition TEXT,
            example TEXT,
            image_path TEXT,
            created_at TEXT DEFAULT (datetime('now'))
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE words ADD COLUMN image_path TEXT DEFAULT ""');
        }
      },
    );
  }

  /// Save a word. Accepts keys: word, phonetic, definition, example, image_path
  static Future<int> saveWord(Map<String, dynamic> word) async {
    final db = await database;
    return await db.insert(
      'words',
      {
        'word': word['word'] ?? '',
        'phonetic': word['phonetic'] ?? '',
        'definition': word['definition'] ?? '',
        'example': word['example'] ?? '',
        'image_path': word['image_path'] ?? '',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns all saved words, newest first
  static Future<List<Map<String, dynamic>>> getSavedWords() async {
    final db = await database;
    return await db.query('words', orderBy: 'created_at DESC');
  }

  /// Delete a word by id
  static Future<void> deleteWord(int id) async {
    final db = await database;
    await db.delete('words', where: 'id = ?', whereArgs: [id]);
  }

  /// Export all words as a CSV string
  static Future<String> exportToCsv() async {
    final words = await getSavedWords();
    final buffer = StringBuffer();
    buffer.writeln('word,phonetic,definition,example,created_at');
    for (final w in words) {
      final word = _escapeCsv(w['word'] ?? '');
      final phonetic = _escapeCsv(w['phonetic'] ?? '');
      final definition = _escapeCsv(w['definition'] ?? '');
      final example = _escapeCsv(w['example'] ?? '');
      final createdAt = _escapeCsv(w['created_at'] ?? '');
      buffer.writeln('$word,$phonetic,$definition,$example,$createdAt');
    }
    return buffer.toString();
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Clear all words (useful for testing)
  static Future<void> clearAll() async {
    final db = await database;
    await db.delete('words');
  }
}