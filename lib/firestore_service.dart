import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'topics_data.dart';

class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String get _uid {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('You must be signed in.');
    }

    return user.uid;
  }

  static String get currentUserId => _uid;

  // ============================================================
  // WORDS
  // ============================================================

  static Future<void> saveWord(
    Map<String, dynamic> word,
  ) async {
    final normalizedWord = word['word'].toString().trim().toLowerCase();

    if (normalizedWord.isEmpty) return;

    final wordRef = _db
        .collection('users')
        .doc(_uid)
        .collection('saved_words')
        .doc(normalizedWord);

    final existing = await wordRef.get();

    final data = <String, dynamic>{
      ...word,
      'word': normalizedWord,
      'status': 'saved',
      'updated_at': FieldValue.serverTimestamp(),
    };

    // image_path is a local file path inside this app install's sandboxed
    // container, which iOS invalidates on every reinstall — so it can't be
    // relied on to persist. Embed a downscaled copy directly in the
    // document instead (no Cloud Storage/Blaze plan needed); image_path
    // stays as a same-session fallback for screens that haven't reloaded.
    final localImagePath = (word['image_path'] ?? '').toString();
    final hasEmbeddedImage =
        (word['image_base64'] ?? '').toString().isNotEmpty;

    if (localImagePath.isNotEmpty && !hasEmbeddedImage) {
      final encoded = await _encodeWordImageBase64(localImagePath);

      if (encoded != null) {
        data['image_base64'] = encoded;
      }
    }

    if (!existing.exists) {
      data['created_at'] = FieldValue.serverTimestamp();
      data['times_reviewed'] = 0;
    }

    await wordRef.set(
      data,
      SetOptions(merge: true),
    );

    if (!existing.exists) {
      await _db.collection('users').doc(_uid).set(
        {
          'words_saved': FieldValue.increment(1),
          'total_xp': FieldValue.increment(10),
          'words_today': FieldValue.increment(1),
        },
        SetOptions(merge: true),
      );
    }
  }

  /// Downscales a local cutout and returns it as a base64 PNG string, or
  /// null if the file is missing, unreadable, or still too large to embed
  /// safely after resizing. Kept as PNG (not JPEG) so the cutout's
  /// transparent background still blends into whatever card color it's
  /// shown on, rather than being flattened to a solid fill.
  ///
  /// This is stored directly on the saved_words document (no Cloud
  /// Storage/Blaze plan needed) — Firestore caps a document at 1MiB, so
  /// the image has to stay small and leave headroom for the doc's other
  /// fields.
  static Future<String?> _encodeWordImageBase64(
    String localPath,
  ) async {
    try {
      final file = File(localPath);

      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        return null;
      }

      const maxDimension = 360;

      final resized = (decoded.width > maxDimension ||
              decoded.height > maxDimension)
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? maxDimension : null,
              height: decoded.height > decoded.width ? maxDimension : null,
            )
          : decoded;

      final encodedBytes = img.encodePng(resized, level: 9);

      const maxBytes = 700 * 1024;

      if (encodedBytes.length > maxBytes) {
        debugPrint(
          'Cutout still ${encodedBytes.length} bytes after resize, '
          'skipping embed.',
        );
        return null;
      }

      return base64Encode(encodedBytes);
    } catch (e) {
      debugPrint('encodeWordImageBase64 error: $e');
      return null;
    }
  }

  static Future<void> updateSavedWord(
    String word,
    Map<String, dynamic> data,
  ) async {
    final normalizedWord = word.trim().toLowerCase();

    if (normalizedWord.isEmpty) return;

    await _db
        .collection('users')
        .doc(_uid)
        .collection('saved_words')
        .doc(normalizedWord)
        .set(
      {
        ...data,
        'word': normalizedWord,
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<List<Map<String, dynamic>>> getSavedWords() async {
    final snap = await _db
        .collection('users')
        .doc(_uid)
        .collection('saved_words')
        .orderBy(
          'created_at',
          descending: true,
        )
        .get();

    return snap.docs.map((d) => d.data()).toList();
  }

  /// Live version of getSavedWords(), for any screen kept alive by the
  /// bottom nav's IndexedStack (Home, Review, ...) — those screens' State
  /// is created once and never rebuilt from scratch, so a one-time Future
  /// fetch in initState only ever reflects whatever was saved at the
  /// moment that tab was first built. A live stream (same fix already
  /// used for the profile stats) keeps this current without depending on
  /// the widget itself rebuilding. Pass null for the full list (e.g. the
  /// Review screen); Home passes a small limit for its preview section.
  static Stream<List<Map<String, dynamic>>> watchSavedWords({
    int? limit = 5,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('users')
        .doc(_uid)
        .collection('saved_words')
        .orderBy('created_at', descending: true);

    if (limit != null) {
      query = query.limit(limit);
    }

    return query
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // ============================================================
  // FEEDBACK / REPORTS
  // ============================================================

  static Future<void> submitFeedback({
    required String message,
    String type = 'feedback',
  }) async {
    final trimmed = message.trim();

    if (trimmed.isEmpty) return;

    final user = _auth.currentUser;

    await _db.collection('feedback').add({
      'uid': user?.uid,
      'email': user?.email,
      'type': type,
      'message': trimmed,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // SCAN HISTORY
  // ============================================================

  static Future<void> recordScan({
    required String word,
    String definition = '',
    String phonetic = '',
    String source = 'ar_scan',
  }) async {
    final normalizedWord = word.trim().toLowerCase();
    if (normalizedWord.isEmpty) return;

    await _db.collection('scan_history').add({
      'user_id': _uid,
      'word': normalizedWord,
      'definition': definition,
      'phonetic': phonetic,
      'source': source,
      'created_at': FieldValue.serverTimestamp(),
    });

    // Site-wide counter, separate from scan_history: every user's scan of
    // this word bumps the same doc, so the Home screen can show what's
    // popular across everyone without reading (and being allowed to read)
    // other users' individual scan_history entries.
    await _db.collection('word_stats').doc(normalizedWord).set(
      {
        'word': normalizedWord,
        'scan_count': FieldValue.increment(1),
        'last_scanned_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Most-scanned words across all users, for the Home screen's "Popular
  /// Now" section. Unlike getSavedWords(), this has nothing to do with
  /// what the current user personally saved.
  static Future<List<Map<String, dynamic>>> getPopularWords({
    int limit = 5,
  }) async {
    try {
      final snap = await _db
          .collection('word_stats')
          .orderBy('scan_count', descending: true)
          .limit(limit)
          .get();

      return snap.docs.map((d) => d.data()).toList();
    } catch (e) {
      debugPrint('getPopularWords error: $e');
      return [];
    }
  }

  /// Live version of getPopularWords(), same reasoning as watchSavedWords().
  static Stream<List<Map<String, dynamic>>> watchPopularWords({
    int limit = 5,
  }) {
    return _db
        .collection('word_stats')
        .orderBy('scan_count', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList())
        .handleError((e) => debugPrint('watchPopularWords error: $e'));
  }

  /// This user's own recent scan activity (every scan, not deduplicated by
  /// word) — distinct from getSavedWords()/watchSavedWords(), which only
  /// reflects words the user explicitly tapped Save on. Used by the Home
  /// screen's "Recently Scanned" section, which shows a Save button per
  /// row precisely because scanning something doesn't save it.
  static Stream<List<Map<String, dynamic>>> watchRecentScans({
    int limit = 5,
  }) {
    return _db
        .collection('scan_history')
        .where('user_id', isEqualTo: _uid)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList())
        .handleError((e) => debugPrint('watchRecentScans error: $e'));
  }

  static Future<void> deleteWord(
    String word,
  ) async {
    final normalizedWord = word.trim().toLowerCase();

    if (normalizedWord.isEmpty) return;

    final wordRef = _db
        .collection('users')
        .doc(_uid)
        .collection('saved_words')
        .doc(normalizedWord);

    final existing = await wordRef.get();

    if (!existing.exists) return;

    await wordRef.delete();

    await _db.collection('users').doc(_uid).set(
      {
        'words_saved': FieldValue.increment(-1),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> updateWordStatus(
    String word,
    String status,
  ) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('saved_words')
        .doc(word.toLowerCase())
        .update(
      {
        'status': status,
        'times_reviewed': FieldValue.increment(1),
      },
    );
  }

  // ============================================================
  // CHAT HISTORY
  // ============================================================

  static Future<void> saveChatMessage({
    required String role,
    required String content,
  }) async {
    await _db.collection('users').doc(_uid).collection('chat_history').add(
      {
        'role': role,
        'content': content,
        'created_at': FieldValue.serverTimestamp(),
      },
    );
  }

  static Future<List<Map<String, String>>> getChatHistory({
    int limit = 20,
  }) async {
    final snap = await _db
        .collection('users')
        .doc(_uid)
        .collection('chat_history')
        .orderBy(
          'created_at',
          descending: true,
        )
        .limit(limit)
        .get();

    return snap.docs
        .map(
          (d) => {
            'role': d['role'] as String,
            'content': d['content'] as String,
          },
        )
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

  // ============================================================
  // USER PROFILE
  // ============================================================

  static Future<Map<String, dynamic>?> getProfile() async {
    final doc = await _db.collection('users').doc(_uid).get();

    return doc.data();
  }

  static Future<Map<String, dynamic>> getProfileOrDefault() async {
    try {
      final data = await getProfile();

      return data ?? {};
    } catch (e) {
      debugPrint(
        'getProfileOrDefault error: $e',
      );

      return {};
    }
  }

  /// Live stream of the user's profile document. Use this anywhere the UI
  /// must reflect changes made from another screen/tab immediately (e.g.
  /// HomeScreen showing the daily word goal right after it's changed in
  /// ProfileScreen), without relying on a one-time fetch in initState that
  /// won't re-run once the tab is kept alive by an IndexedStack-based nav.
  static Stream<Map<String, dynamic>> watchProfile() {
    return _db
        .collection('users')
        .doc(_uid)
        .snapshots()
        .map((doc) => doc.data() ?? {});
  }

  static Future<void> updateProfile(
    Map<String, dynamic> data,
  ) async {
    final payload = {...data};

    if (payload['name'] != null) {
      payload['name_lower'] = (payload['name'] as String).toLowerCase();
    }

    await _db.collection('users').doc(_uid).set(
          payload,
          SetOptions(merge: true),
        );
  }

  // ============================================================
  // SUBSCRIPTION
  // ============================================================
  //
  // Client-only entitlement tracking (see subscription_service.dart for the
  // full trade-off). `expires_at` is an approximation computed from the
  // purchase date plus the product's nominal duration, not a value Apple
  // gave us directly. `verification_data` is stored now, unused, so a future
  // server-side validation step doesn't need to re-collect it.

  static Future<void> updateSubscriptionStatus({
    required String productId,
    required DateTime expiresAt,
    required String transactionId,
    required String verificationData,
  }) async {
    await _db.collection('users').doc(_uid).set(
      {
        'subscription': {
          'status': 'active',
          'product_id': productId,
          'expires_at': Timestamp.fromDate(expiresAt),
          'transaction_id': transactionId,
          'verification_data': verificationData,
          'updated_at': FieldValue.serverTimestamp(),
        },
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> createUserProfile({
    required String name,
    required String email,
  }) async {
    await _db.collection('users').doc(_uid).set(
      {
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
      },
      SetOptions(merge: true),
    );
  }

  // ============================================================
  // FRIENDS
  // ============================================================

  static String _friendshipId(
    String a,
    String b,
  ) {
    final ids = [a, b]..sort();

    return '${ids[0]}_${ids[1]}';
  }

  static Future<List<Map<String, dynamic>>> searchUsersByName(
    String query,
  ) async {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) return [];

    try {
      final snap = await _db
          .collection('users')
          .where(
            'name_lower',
            isGreaterThanOrEqualTo: q,
          )
          .where(
            'name_lower',
            isLessThanOrEqualTo: '$q\uf8ff',
          )
          .limit(20)
          .get();

      return snap.docs
          .where(
            (d) => d.id != _uid,
          )
          .map(
            (d) => {
              'uid': d.id,
              ...d.data(),
            },
          )
          .toList();
    } catch (e) {
      debugPrint(
        'searchUsersByName error: $e',
      );

      return [];
    }
  }

  static Future<void> sendFriendRequest(
    String toUid,
    String toName,
  ) async {
    final myProfile = await getProfileOrDefault();

    final myName = myProfile['name'] ?? 'Someone';

    await _db.collection('friend_requests').doc('${_uid}_$toUid').set(
      {
        'from': _uid,
        'fromName': myName,
        'to': toUid,
        'toName': toName,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      },
    );
  }

  static Future<List<Map<String, dynamic>>> getIncomingRequests() async {
    try {
      final snap = await _db
          .collection('friend_requests')
          .where(
            'to',
            isEqualTo: _uid,
          )
          .where(
            'status',
            isEqualTo: 'pending',
          )
          .get();

      return snap.docs
          .map(
            (d) => {
              'id': d.id,
              ...d.data(),
            },
          )
          .toList();
    } catch (e) {
      debugPrint(
        'getIncomingRequests error: $e',
      );

      return [];
    }
  }

  /// Live count of pending incoming friend requests, for the Profile
  /// screen's notification dot on the add-friend icon.
  static Stream<int> watchIncomingRequestCount() {
    return _db
        .collection('friend_requests')
        .where('to', isEqualTo: _uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.length)
        .handleError((e) => debugPrint('watchIncomingRequestCount error: $e'));
  }

  static Future<List<Map<String, dynamic>>> getOutgoingRequests() async {
    try {
      final snap = await _db
          .collection('friend_requests')
          .where(
            'from',
            isEqualTo: _uid,
          )
          .where(
            'status',
            isEqualTo: 'pending',
          )
          .get();

      return snap.docs
          .map(
            (d) => {
              'id': d.id,
              ...d.data(),
            },
          )
          .toList();
    } catch (e) {
      debugPrint(
        'getOutgoingRequests error: $e',
      );

      return [];
    }
  }

  static Future<void> acceptFriendRequest(
    String requestId,
    String fromUid,
  ) async {
    await _db
        .collection('friendships')
        .doc(
          _friendshipId(
            _uid,
            fromUid,
          ),
        )
        .set(
      {
        'users': [
          _uid,
          fromUid,
        ],
        'created_at': FieldValue.serverTimestamp(),
      },
    );

    await _db.collection('friend_requests').doc(requestId).delete();
  }

  static Future<void> declineFriendRequest(
    String requestId,
  ) async {
    await _db.collection('friend_requests').doc(requestId).delete();
  }

  static Future<List<Map<String, dynamic>>> getFriends() async {
    try {
      final snap = await _db
          .collection('friendships')
          .where(
            'users',
            arrayContains: _uid,
          )
          .get();

      final friends = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final users = (doc.data()['users'] as List).cast<String>();

        final otherUid = users.firstWhere(
          (u) => u != _uid,
          orElse: () => '',
        );

        if (otherUid.isEmpty) {
          continue;
        }

        final profile = await _db.collection('users').doc(otherUid).get();

        if (profile.exists) {
          friends.add(
            {
              'uid': otherUid,
              ...profile.data()!,
            },
          );
        }
      }

      return friends;
    } catch (e) {
      debugPrint(
        'getFriends error: $e',
      );

      return [];
    }
  }

  static Future<int> getFriendsCountFor(
    String uid,
  ) async {
    try {
      final snap = await _db
          .collection('friendships')
          .where(
            'users',
            arrayContains: uid,
          )
          .get();

      return snap.docs.length;
    } catch (e) {
      debugPrint(
        'getFriendsCountFor error: $e',
      );

      return 0;
    }
  }

  // ============================================================
  // BONDS & GIFTS
  // ============================================================

  static const List<Map<String, dynamic>> giftCatalog = [
    {
      'id': 'flower',
      'emoji': '🌸',
      'name': 'Flower',
      'cost': 5,
      'bond': 5,
    },
    {
      'id': 'chocolate',
      'emoji': '🍫',
      'name': 'Chocolate',
      'cost': 8,
      'bond': 8,
    },
    {
      'id': 'balloon',
      'emoji': '🎈',
      'name': 'Balloon',
      'cost': 10,
      'bond': 10,
    },
    {
      'id': 'star',
      'emoji': '⭐',
      'name': 'Star',
      'cost': 15,
      'bond': 15,
    },
    {
      'id': 'trophy',
      'emoji': '🏆',
      'name': 'Trophy',
      'cost': 25,
      'bond': 25,
    },
    {
      'id': 'diamond',
      'emoji': '💎',
      'name': 'Diamond',
      'cost': 50,
      'bond': 50,
    },
  ];

  static String _bondId(
    String a,
    String b,
  ) {
    final ids = [a, b]..sort();

    return '${ids[0]}_${ids[1]}';
  }

  static Future<int> getBond(
    String otherUid,
  ) async {
    try {
      final doc = await _db
          .collection('bonds')
          .doc(
            _bondId(
              _uid,
              otherUid,
            ),
          )
          .get();

      return (doc.data()?['bond'] as int?) ?? 0;
    } catch (e) {
      debugPrint(
        'getBond error: $e',
      );

      return 0;
    }
  }

  static Future<void> sendGift({
    required String toUid,
    required String giftId,
  }) async {
    final gift = giftCatalog.firstWhere(
      (g) => g['id'] == giftId,
      orElse: () => throw Exception(
        'Unknown gift',
      ),
    );

    final cost = gift['cost'] as int;

    final bondValue = gift['bond'] as int;

    final myDoc = await _db.collection('users').doc(_uid).get();

    final myTokens = (myDoc.data()?['tokens'] as int?) ?? 0;

    if (myTokens < cost) {
      throw Exception(
        'Not enough tokens',
      );
    }

    await _db.collection('users').doc(_uid).set(
      {
        'tokens': FieldValue.increment(
          -cost,
        ),
      },
      SetOptions(merge: true),
    );

    await _db
        .collection('bonds')
        .doc(
          _bondId(
            _uid,
            toUid,
          ),
        )
        .set(
      {
        'users': [
          _uid,
          toUid,
        ],
        'bond': FieldValue.increment(
          bondValue,
        ),
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ============================================================
  // TOPIC PROGRESS
  // ============================================================

  static Future<Map<String, dynamic>> getTopicProgress() async {
    final doc = await _db
        .collection('users')
        .doc(_uid)
        .collection('progress')
        .doc('topics')
        .get();

    return doc.data() ?? {};
  }

  static Future<void> markWordLearned(
    String topicId,
    String word,
  ) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('progress')
        .doc('topics')
        .set(
      {
        topicId: FieldValue.arrayUnion(
          [word],
        ),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> saveTopicProgress(
    String topicId,
    int wordsCompleted,
  ) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('topic_progress')
        .doc(topicId)
        .set(
      {
        'words_completed': wordsCompleted,
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await _db.collection('users').doc(_uid).set(
      {
        'total_xp': FieldValue.increment(
          100,
        ),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> addRewards({
    required int tokens,
    required int xp,
  }) async {
    await _db.collection('users').doc(_uid).set(
      {
        'tokens': FieldValue.increment(
          tokens,
        ),
        'total_xp': FieldValue.increment(
          xp,
        ),
      },
      SetOptions(merge: true),
    );
  }

  // ============================================================
  // TOPICS
  // ============================================================
  //
  // Topic content (name, icon, color, map position, word list) lives in
  // the `topics` collection so new topics and words can be added from the
  // Firebase Console without shipping an app update. See topics_data.dart
  // for the TopicDef model and the icon name lookup table.

  static Future<List<TopicDef>> getTopics() async {
    try {
      final snap =
          await _db.collection('topics').orderBy('order').get();

      return snap.docs
          .map((d) => TopicDef.fromFirestore(d.id, d.data()))
          .toList();
    } catch (e) {
      debugPrint('getTopics error: $e');
      return [];
    }
  }

  /// One-time migration: populates `topics` from kTopicsSeedData the first
  /// time this runs against an empty collection. A no-op on every call
  /// after that (checked via the cheap existence check below), so it's
  /// safe to leave wired into app startup permanently — new topics/words
  /// added later through the Firebase Console are never touched by this.
  static Future<void> seedTopicsOnce() async {
    try {
      final existing = await _db.collection('topics').limit(1).get();

      if (existing.docs.isNotEmpty) return;

      final batch = _db.batch();

      for (final topic in kTopicsSeedData) {
        final id = topic['id'] as String;

        batch.set(
          _db.collection('topics').doc(id),
          topic,
        );
      }

      await batch.commit();

      debugPrint('seedTopicsOnce: seeded ${kTopicsSeedData.length} topics.');
    } catch (e) {
      debugPrint('seedTopicsOnce error: $e');
    }
  }

  // ============================================================
  // EVENTS
  // ============================================================

  static String eventIdFromName(
    String name,
  ) {
    final cleaned = name
        .trim()
        .toLowerCase()
        .replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '_',
        )
        .replaceAll(
          RegExp(r'^_+|_+$'),
          '',
        );

    return cleaned.isEmpty ? 'special_event' : cleaned;
  }

  static DateTime? _timestampToDate(
    dynamic value,
  ) {
    if (value == null) return null;

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    try {
      final converted = (value as dynamic).toDate();

      if (converted is DateTime) {
        return converted;
      }
    } catch (_) {}

    return DateTime.tryParse(
      value.toString(),
    );
  }

  /// Reads config/current_event.
  ///
  /// IMPORTANT:
  /// active is checked first.
  /// start_at and end_at are also checked so the event
  /// automatically becomes live only inside its time window.
  static Future<Map<String, dynamic>?> getCurrentEvent() async {
    try {
      final doc = await _db.collection('config').doc('current_event').get(
            const GetOptions(
              source: Source.server,
            ),
          );

      debugPrint(
        'EVENT DEBUG '
        'doc.exists=${doc.exists} '
        'data=${doc.data()}',
      );

      if (!doc.exists) {
        return null;
      }

      final data = doc.data()!;

      if (data['active'] != true) {
        return null;
      }

      final now = DateTime.now();

      final start = _timestampToDate(
        data['start_at'],
      );

      final end = _timestampToDate(
        data['end_at'],
      );

      if (start != null && now.isBefore(start)) {
        return null;
      }

      if (end != null && !now.isBefore(end)) {
        return null;
      }

      return data;
    } catch (e) {
      debugPrint(
        'getCurrentEvent error: $e',
      );

      return null;
    }
  }

  static Future<void> setCurrentEvent({
    required String name,
    required DateTime startAt,
    required DateTime endAt,
    required String type,
    bool active = true,
  }) async {
    if (!endAt.isAfter(startAt)) {
      throw ArgumentError(
        'Event end time must be after start time.',
      );
    }

    await _db.collection('config').doc('current_event').set(
      {
        'name': name.trim(),
        'type': type.trim(),
        'date': Timestamp.fromDate(
          startAt,
        ),
        'start_at': Timestamp.fromDate(
          startAt,
        ),
        'end_at': Timestamp.fromDate(
          endAt,
        ),
        'active': active,
      },
    );
  }

  static Future<void> endCurrentEvent() async {
    await _db.collection('config').doc('current_event').set(
      {
        'active': false,
      },
      SetOptions(merge: true),
    );
  }

  // ============================================================
  // EVENT NOTIFICATION
  // ============================================================

  static Future<void> setEventNotify(
    String eventName,
    bool value,
  ) async {
    await _db.collection('users').doc(_uid).set(
      {
        'notified_event_id': value ? eventName : null,
      },
      SetOptions(merge: true),
    );
  }

  static bool isNotifiedForEvent(
    Map<String, dynamic> profile,
    String eventName,
  ) {
    return profile['notified_event_id'] == eventName;
  }

  // ============================================================
  // SCAN CHALLENGE
  //
  // A single-player replacement for the old group/lobby event flow:
  // scan a target number of words during the event's window, then
  // claim a one-time reward. No groups, no invites.
  // ============================================================

  /// Reads an `events/{eventId}` doc (theme, dates, target_count,
  /// reward_xp, reward_tokens) — the richer definition the admin
  /// dashboard's event form writes, separate from the lightweight
  /// config/current_event pointer used for the upcoming/live banner.
  static Future<Map<String, dynamic>?> getEventDefinition(
    String eventId,
  ) async {
    try {
      final doc = await _db.collection('events').doc(eventId).get();

      if (!doc.exists) {
        return null;
      }

      return {
        'id': doc.id,
        ...doc.data()!,
      };
    } catch (e) {
      debugPrint('getEventDefinition error: $e');
      return null;
    }
  }

  /// Counts this user's scans within [startAt, endAt] for the challenge
  /// progress bar, using a server-side aggregate count instead of
  /// downloading every matching scan_history doc.
  static Future<int> getEventScanCount({
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    try {
      final query = _db
          .collection('scan_history')
          .where('user_id', isEqualTo: _uid)
          .where(
            'created_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startAt),
          )
          .where(
            'created_at',
            isLessThanOrEqualTo: Timestamp.fromDate(endAt),
          );

      final result = await query.count().get();
      return result.count ?? 0;
    } catch (e) {
      debugPrint('getEventScanCount error: $e');
      return 0;
    }
  }

  static Future<bool> hasClaimedEvent(String eventId) async {
    try {
      final doc = await _db
          .collection('users')
          .doc(_uid)
          .collection('claimed_events')
          .doc(eventId)
          .get();

      return doc.exists;
    } catch (e) {
      debugPrint('hasClaimedEvent error: $e');
      return false;
    }
  }

  /// Grants the challenge reward exactly once per user per event.
  /// Returns true if this call is the one that actually granted it,
  /// false if it was already claimed earlier.
  static Future<bool> claimEventReward({
    required String eventId,
    required int xp,
    required int tokens,
  }) async {
    final claimRef = _db
        .collection('users')
        .doc(_uid)
        .collection('claimed_events')
        .doc(eventId);

    final userRef = _db.collection('users').doc(_uid);

    return _db.runTransaction<bool>((transaction) async {
      final claimSnap = await transaction.get(claimRef);

      if (claimSnap.exists) {
        return false;
      }

      transaction.set(claimRef, {
        'claimed_at': FieldValue.serverTimestamp(),
        'xp': xp,
        'tokens': tokens,
      });

      transaction.set(
        userRef,
        {
          'total_xp': FieldValue.increment(xp),
          'tokens': FieldValue.increment(tokens),
        },
        SetOptions(merge: true),
      );

      return true;
    });
  }

  // ============================================================
  // GOBOT USAGE LIMIT
  //
  // Free users get a limited number of AI chat messages per day (each
  // one costs a real Gemini API call); Premium users are unlimited.
  // Tracked per calendar day (UTC) so it resets on its own with no
  // cron job needed.
  // ============================================================

  static const int gobotFreeMessagesPerDay = 10;

  static String _todayKey() {
    final now = DateTime.now().toUtc();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static Future<int> getGobotMessagesUsedToday() async {
    try {
      final doc = await _db
          .collection('users')
          .doc(_uid)
          .collection('gobot_usage')
          .doc(_todayKey())
          .get();

      return (doc.data()?['count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('getGobotMessagesUsedToday error: $e');
      return 0;
    }
  }

  static Future<void> incrementGobotMessagesUsedToday() async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('gobot_usage')
        .doc(_todayKey())
        .set(
      {
        'count': FieldValue.increment(1),
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ============================================================
  // DELETE ALL DATA
  // ============================================================

  static Future<void> deleteAllData() async {
    final uid = _uid;

    final wordsSnap =
        await _db.collection('users').doc(uid).collection('saved_words').get();

    for (final doc in wordsSnap.docs) {
      await doc.reference.delete();
    }

    final chatSnap =
        await _db.collection('users').doc(uid).collection('chat_history').get();

    for (final doc in chatSnap.docs) {
      await doc.reference.delete();
    }

    final streakSnap =
        await _db.collection('users').doc(uid).collection('streak').get();

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

    await _db.collection('users').doc(uid).set(
      {
        'words_saved': 0,
        'total_xp': 0,
        'tokens': 0,
        'words_today': 0,
        'level': 1,
        'streak_days': 0,
      },
      SetOptions(merge: true),
    );
  }
}

typedef DatabaseService = FirestoreService;
