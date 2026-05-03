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
          'CREATE TABLE saved_words(id INTEGER PRIMARY KEY AUTOINCREMENT, word TEXT, phonetic TEXT, definition TEXT, example TEXT)',
        );
      },
      version: 1,
    );
    return _db!;
  }

  static Future<void> saveWord(Map<String, String> wordData) async {
    final db = await getDatabase();
    await db.insert(
      'saved_words',
      wordData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getSavedWords() async {
    final db = await getDatabase();
    return await db.query('saved_words');
  }

  static Future<void> deleteWord(int id) async {
    final db = await getDatabase();
    await db.delete('saved_words', where: 'id = ?', whereArgs: [id]);
  }
}