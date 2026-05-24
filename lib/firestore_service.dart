import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  static String get _uid => _auth.currentUser!.uid;

  // ── Words ──────────────────────────────────────────────────────────────────
  static Future<void> saveWord(Map<String, dynamic> word) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('saved_words')
        .doc(word['word'].toString().toLowerCase())
        .set({
      ...word,
      'status': 'saved',
      'created_at': FieldValue.serverTimestamp(),
      'times_reviewed': 0,
    }, SetOptions(merge: true));
    await _db.collection('users').doc(_uid).update({
      'words_saved': FieldValue.increment(1),
      'total_xp': FieldValue.increment(10),
    });
  }

  static Future<List<Map<String, dynamic>>> getSavedWords() async {
    final snap = await _db
        .collection('users')
        .doc(_uid)
        .collection('saved_words')
        .orderBy('created_at', descending: true)
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  static Future<void> deleteWord(String word) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('saved_words')
        .doc(word.toLowerCase())
        .delete();
  }

  static Future<void> updateWordStatus(String word, String status) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('saved_words')
        .doc(word.toLowerCase())
        .update({'status': status, 'times_reviewed': FieldValue.increment(1)});
  }

  // ── Chat History ──────────────────────────────────────────────────────────
  static Future<void> saveChatMessage({
    required String role,
    required String content,
  }) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('chat_history')
        .add({
      'role': role,
      'content': content,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<List<Map<String, String>>> getChatHistory({int limit = 20}) async {
    final snap = await _db
        .collection('users')
        .doc(_uid)
        .collection('chat_history')
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => {
              'role': d['role'] as String,
              'content': d['content'] as String,
            })
        .toList()
        .reversed
        .toList();
  }

  static Future<void> clearChatHistory() async {
    final snap = await _db
        .collection('users')
        .doc(_uid)
        .collection('chat_history')
        .get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  // ── User Profile ──────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getProfile() async {
    final doc = await _db.collection('users').doc(_uid).get();
    return doc.data();
  }

  static Future<void> updateProfile(Map<String, dynamic> data) async {
    await _db.collection('users').doc(_uid).update(data);
  }

  static Future<void> createUserProfile({
    required String name,
    required String email,
  }) async {
    await _db.collection('users').doc(_uid).set({
      'name': name,
      'email': email,
      'city': 'Bangkok',
      'language': 'English (US)',
      'level': 1,
      'total_xp': 0,
      'words_saved': 0,
      'streak_days': 0,
      'auto_tts': true,
      'words_goal': 10,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // ── Streak ────────────────────────────────────────────────────────────────
  static Future<void> markTodayActive() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _db
        .collection('users')
        .doc(_uid)
        .collection('streak')
        .doc(today)
        .set({'date': today, 'completed': true});
  }

  static Future<List<bool>> getWeeklyStreak() async {
    final now = DateTime.now();
    final results = <bool>[];
    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final key = day.toIso8601String().substring(0, 10);
      final doc = await _db
          .collection('users')
          .doc(_uid)
          .collection('streak')
          .doc(key)
          .get();
      results.add(doc.exists);
    }
    return results;
  }
}

// Alias — all screens can use DatabaseService.x or FirestoreService.x
typedef DatabaseService = FirestoreService;