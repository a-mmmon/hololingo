import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> getDatabase() async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      join(await getDatabasesPath(), 'ar_language.db'),
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE saved_words('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'word TEXT, '
          'phonetic TEXT, '
          'definition TEXT, '
          'example TEXT'
          ')',
        );
      },
      version: 1,
    );
    return _db!;
  }

  static Future<void> saveWord(Map<String, dynamic> wordData) async {
    final db = await getDatabase();
    final row =
        wordData.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    await db.insert(
      'saved_words',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getSavedWords() async {
    final db = await getDatabase();
    return await db.query('saved_words', orderBy: 'id DESC');
  }

  static Future<void> deleteWord(int id) async {
    final db = await getDatabase();
    await db.delete('saved_words', where: 'id = ?', whereArgs: [id]);
  }

  static Future<String> exportToCsv() async {
    final words = await getSavedWords();
    String csv = 'Word,Phonetic,Definition,Example\n';
    for (final word in words) {
      final w = word['word'] ?? '';
      final p = word['phonetic'] ?? '';
      final d =
          (word['definition'] ?? '').toString().replaceAll(',', ';');
      final e =
          (word['example'] ?? '').toString().replaceAll(',', ';');
      csv += '"$w","$p","$d","$e"\n';
    }
    return csv;
  }
}