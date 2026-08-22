import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
    await _db.collection('users').doc(_uid).set({
      'words_saved': FieldValue.increment(1),
      'total_xp': FieldValue.increment(10),
      'words_today': FieldValue.increment(1),
    }, SetOptions(merge: true));
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
        .update({
      'status': status,
      'times_reviewed': FieldValue.increment(1),
    });
  }

  // ── Chat History ───────────────────────────────────────────────────────────
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

  static Future<List<Map<String, String>>> getChatHistory(
      {int limit = 20}) async {
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

  // ── User Profile ───────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getProfile() async {
    final doc = await _db.collection('users').doc(_uid).get();
    return doc.data();
  }

  static Future<Map<String, dynamic>> getProfileOrDefault() async {
    try {
      final data = await getProfile();
      return data ?? {};
    } catch (e) {
      debugPrint('getProfileOrDefault error: $e');
      return {};
    }
  }

  static Future<void> updateProfile(Map<String, dynamic> data) async {
    final payload = {...data};
    if (payload['name'] != null) {
      payload['name_lower'] = (payload['name'] as String).toLowerCase();
    }
    await _db.collection('users').doc(_uid).set(payload, SetOptions(merge: true));
  }

  static Future<void> createUserProfile({
    required String name,
    required String email,
  }) async {
    await _db.collection('users').doc(_uid).set({
      'name': name,
      'name_lower': name.toLowerCase(),
      'email': email,
      'city': 'Bangkok',
      'language': 'English (US)',
      'level': 1,
      'total_xp': 0,
      'tokens': 0,
      'words_saved': 0,
      'words_today': 0,
      'auto_tts': true,
      'words_goal': 10,
      'daily_reminder': true,
      'review_reminder': true,
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Friends & Friend Requests ────────────────────────────────────────────
  // Friendship docs live in a top-level 'friendships' collection so both
  // sides of a friendship can be created/read without needing write access
  // to each other's private user document. Doc id is a sorted pair of uids.
  static String _friendshipId(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  // Search other users by display name (case-insensitive prefix match).
  static Future<List<Map<String, dynamic>>> searchUsersByName(
      String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    try {
      final snap = await _db
          .collection('users')
          .where('name_lower', isGreaterThanOrEqualTo: q)
          .where('name_lower', isLessThanOrEqualTo: '$q\uf8ff')
          .limit(20)
          .get();
      return snap.docs
          .where((d) => d.id != _uid)
          .map((d) => {'uid': d.id, ...d.data()})
          .toList();
    } catch (e) {
      debugPrint('searchUsersByName error: $e');
      return [];
    }
  }

  // Sends a friend request. Doc id is '<fromUid>_<toUid>' so re-sending is
  // idempotent (won't create duplicate pending requests).
  static Future<void> sendFriendRequest(String toUid, String toName) async {
    final myProfile = await getProfileOrDefault();
    final myName = myProfile['name'] ?? 'Someone';
    await _db.collection('friend_requests').doc('${_uid}_$toUid').set({
      'from': _uid,
      'fromName': myName,
      'to': toUid,
      'toName': toName,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // Requests sent TO me that I haven't responded to yet.
  static Future<List<Map<String, dynamic>>> getIncomingRequests() async {
    try {
      final snap = await _db
          .collection('friend_requests')
          .where('to', isEqualTo: _uid)
          .where('status', isEqualTo: 'pending')
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('getIncomingRequests error: $e');
      return [];
    }
  }

  // Requests I've sent that are still pending — used to show "Requested"
  // instead of "Add" in search results.
  static Future<List<Map<String, dynamic>>> getOutgoingRequests() async {
    try {
      final snap = await _db
          .collection('friend_requests')
          .where('from', isEqualTo: _uid)
          .where('status', isEqualTo: 'pending')
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('getOutgoingRequests error: $e');
      return [];
    }
  }

  static Future<void> acceptFriendRequest(
      String requestId, String fromUid) async {
    await _db
        .collection('friendships')
        .doc(_friendshipId(_uid, fromUid))
        .set({
      'users': [_uid, fromUid],
      'created_at': FieldValue.serverTimestamp(),
    });
    await _db.collection('friend_requests').doc(requestId).delete();
  }

  static Future<void> declineFriendRequest(String requestId) async {
    await _db.collection('friend_requests').doc(requestId).delete();
  }

  static Future<List<Map<String, dynamic>>> getFriends() async {
    try {
      final snap = await _db
          .collection('friendships')
          .where('users', arrayContains: _uid)
          .get();
      final friends = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final users = (doc.data()['users'] as List).cast<String>();
        final otherUid = users.firstWhere((u) => u != _uid, orElse: () => '');
        if (otherUid.isEmpty) continue;
        final profile = await _db.collection('users').doc(otherUid).get();
        if (profile.exists) {
          friends.add({'uid': otherUid, ...profile.data()!});
        }
      }
      return friends;
    } catch (e) {
      debugPrint('getFriends error: $e');
      return [];
    }
  }

  // Friend count for any given uid (used on FriendProfileScreen to show
  // how many friends *that* person has, not the current user).
  static Future<int> getFriendsCountFor(String uid) async {
    try {
      final snap = await _db
          .collection('friendships')
          .where('users', arrayContains: uid)
          .get();
      return snap.docs.length;
    } catch (e) {
      debugPrint('getFriendsCountFor error: $e');
      return 0;
    }
  }

  // ── Bonds & Gifts ──────────────────────────────────────────────────────────
  // Bond docs live in a top-level 'bonds' collection, mirroring the
  // 'friendships' pattern — doc id is a sorted pair of uids so either side
  // can read/update without needing write access to the other user's doc.
  //   bonds/{sorted_uid_pair}: { users: [uidA, uidB], bond: int, updated_at }
  static const List<Map<String, dynamic>> giftCatalog = [
    {'id': 'flower', 'emoji': '🌸', 'name': 'Flower', 'cost': 5, 'bond': 5},
    {'id': 'chocolate', 'emoji': '🍫', 'name': 'Chocolate', 'cost': 8, 'bond': 8},
    {'id': 'balloon', 'emoji': '🎈', 'name': 'Balloon', 'cost': 10, 'bond': 10},
    {'id': 'star', 'emoji': '⭐', 'name': 'Star', 'cost': 15, 'bond': 15},
    {'id': 'trophy', 'emoji': '🏆', 'name': 'Trophy', 'cost': 25, 'bond': 25},
    {'id': 'diamond', 'emoji': '💎', 'name': 'Diamond', 'cost': 50, 'bond': 50},
  ];

  static String _bondId(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  static Future<int> getBond(String otherUid) async {
    try {
      final doc =
          await _db.collection('bonds').doc(_bondId(_uid, otherUid)).get();
      return (doc.data()?['bond'] as int?) ?? 0;
    } catch (e) {
      debugPrint('getBond error: $e');
      return 0;
    }
  }

  // Sends a gift to a friend: deducts tokens from me, increments the bond
  // between us. Throws if the gift id is unknown or I don't have enough
  // tokens, so the caller can show an error.
  static Future<void> sendGift({
    required String toUid,
    required String giftId,
  }) async {
    final gift = giftCatalog.firstWhere(
      (g) => g['id'] == giftId,
      orElse: () => throw Exception('Unknown gift'),
    );
    final cost = gift['cost'] as int;
    final bondValue = gift['bond'] as int;

    final myDoc = await _db.collection('users').doc(_uid).get();
    final myTokens = (myDoc.data()?['tokens'] as int?) ?? 0;
    if (myTokens < cost) throw Exception('Not enough tokens');

    await _db.collection('users').doc(_uid).set({
      'tokens': FieldValue.increment(-cost),
    }, SetOptions(merge: true));

    await _db.collection('bonds').doc(_bondId(_uid, toUid)).set({
      'users': [_uid, toUid],
      'bond': FieldValue.increment(bondValue),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Topic Progress ────────────────────────────────────────────────────────
  // Returns a map like { 'colors': ['Red', 'Blue'], 'animals': ['Cat'] }
  // — one entry per topic, listing which words have been learned.
  static Future<Map<String, dynamic>> getTopicProgress() async {
    final doc = await _db
        .collection('users')
        .doc(_uid)
        .collection('progress')
        .doc('topics')
        .get();
    return doc.data() ?? {};
  }

  // Marks a single word as learned within a topic.
  static Future<void> markWordLearned(String topicId, String word) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('progress')
        .doc('topics')
        .set({
      topicId: FieldValue.arrayUnion([word]),
    }, SetOptions(merge: true));
  }

  // Saves per-topic word-completion count and grants 100 XP.
  static Future<void> saveTopicProgress(
      String topicId, int wordsCompleted) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('topic_progress')
        .doc(topicId)
        .set({
      'words_completed': wordsCompleted,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _db.collection('users').doc(_uid).set({
      'total_xp': FieldValue.increment(100),
    }, SetOptions(merge: true));
  }

  // Grants Tokens + XP rewards (e.g. on topic completion).
  static Future<void> addRewards({required int tokens, required int xp}) async {
    await _db.collection('users').doc(_uid).set({
      'tokens': FieldValue.increment(tokens),
      'total_xp': FieldValue.increment(xp),
    }, SetOptions(merge: true));
  }

  // ── Events (admin-managed, shared across all users) ──────────────────────
  // Event lives in a single shared doc so one admin write updates it for
  // everyone. Structure: collection 'config', doc 'current_event':
  //   { name: String, date: Timestamp, active: bool }
  // Per-user "Notify Me" state is stored on the user doc as
  // 'notified_event_id', so it naturally resets when the admin launches a
  // new event (different event name won't match the old notify flag).
  static Future<Map<String, dynamic>?> getCurrentEvent() async {
    try {
      final doc = await _db
          .collection('config')
          .doc('current_event')
          .get(const GetOptions(source: Source.server));
      debugPrint('EVENT DEBUG doc.exists=${doc.exists} data=${doc.data()}');
      if (!doc.exists) return null;
      final data = doc.data()!;
      if (data['active'] != true) return null;
      return data;
    } catch (e) {
      debugPrint('getCurrentEvent error: $e');
      return null;
    }
  }

  // Admin-side: call this (from an admin screen, or manually in the
  // Firebase console) to announce/launch an event for all users.
  static Future<void> setCurrentEvent({
    required String name,
    required DateTime date,
    bool active = true,
  }) async {
    await _db.collection('config').doc('current_event').set({
      'name': name,
      'date': Timestamp.fromDate(date),
      'active': active,
    });
  }

  static Future<void> endCurrentEvent() async {
    await _db.collection('config').doc('current_event').set(
      {'active': false},
      SetOptions(merge: true),
    );
  }

  // Per-user notify toggle, scoped to a specific event name so it resets
  // automatically when a new event replaces the old one.
  static Future<void> setEventNotify(String eventName, bool value) async {
    await _db.collection('users').doc(_uid).set({
      'notified_event_id': value ? eventName : null,
    }, SetOptions(merge: true));
  }

  static bool isNotifiedForEvent(
      Map<String, dynamic> profile, String eventName) {
    return profile['notified_event_id'] == eventName;
  }

  // ── Delete All Data ────────────────────────────────────────────────────────
  static Future<void> deleteAllData() async {
    final uid = _uid;

    final wordsSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('saved_words')
        .get();
    for (final doc in wordsSnap.docs) {
      await doc.reference.delete();
    }

    final chatSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('chat_history')
        .get();
    for (final doc in chatSnap.docs) {
      await doc.reference.delete();
    }

    final streakSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('streak')
        .get();
    for (final doc in streakSnap.docs) {
      await doc.reference.delete();
    }

    final topicsSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('progress')
        .doc('topics')
        .get();
    if (topicsSnap.exists) {
      await topicsSnap.reference.delete();
    }

    await _db.collection('users').doc(uid).set({
      'words_saved': 0,
      'total_xp': 0,
      'tokens': 0,
      'words_today': 0,
      'level': 1,
      'streak_days': 0,
    }, SetOptions(merge: true));
  }
}

typedef DatabaseService = FirestoreService;