import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
  // EVENT DEFINITION
  // ============================================================

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
      debugPrint(
        'getEventDefinition error: $e',
      );

      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getEventTargets(
    String eventId,
  ) async {
    try {
      final snapshot = await _db
          .collection('events')
          .doc(eventId)
          .collection('targets')
          .get();

      final targets = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        targets.add(
          {
            'id': doc.id,
            ...doc.data(),
          },
        );
      }

      targets.sort(
        (a, b) {
          final aOrder = (a['order'] as num?)?.toInt() ?? 999999;

          final bOrder = (b['order'] as num?)?.toInt() ?? 999999;

          return aOrder.compareTo(
            bOrder,
          );
        },
      );

      return targets;
    } catch (e) {
      debugPrint(
        'getEventTargets error: $e',
      );

      return [];
    }
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
  // EVENT GROUPS
  // ============================================================

  static CollectionReference<Map<String, dynamic>> _eventGroupsCollection(
    String eventId,
  ) {
    return _db.collection('events').doc(eventId).collection('groups');
  }

  static String _generateGroupCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

    final random = math.Random.secure();

    return List.generate(
      6,
      (_) => chars[random.nextInt(
        chars.length,
      )],
    ).join();
  }

  // ------------------------------------------------------------
  // CREATE GROUP
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>> createEventGroup({
    required String eventId,
    required String name,
    required String type,
  }) async {
    final uid = _uid;

    final normalizedType =
        type.toLowerCase() == 'private' ? 'private' : 'public';

    final profile = await getProfileOrDefault();

    final profileName = profile['name']?.toString().trim();

    final displayName =
        profileName == null || profileName.isEmpty ? 'Player' : profileName;

    final groupName =
        name.trim().isEmpty ? '$displayName\'s Group' : name.trim();

    final groups = _eventGroupsCollection(
      eventId,
    );

    String code = '';

    for (int attempt = 0; attempt < 10; attempt++) {
      final candidate = _generateGroupCode();

      final existing = await groups
          .where(
            'code',
            isEqualTo: candidate,
          )
          .limit(1)
          .get();

      if (existing.docs.isEmpty) {
        code = candidate;
        break;
      }
    }

    if (code.isEmpty) {
      throw Exception(
        'Could not create a unique group code.',
      );
    }

    final groupRef = groups.doc();

    final data = {
      'event_id': eventId,
      'name': groupName,
      'type': normalizedType,
      'code': code,
      'leader_id': uid,
      'member_uids': [uid],
      'members': [
        {
          'uid': uid,
          'name': displayName,
        },
      ],
      'ready_ids': <String>[],
      'completed_target_ids': <String>[],
      'score': 0,
      'status': 'waiting',
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    await groupRef.set(data);

    final saved = await groupRef.get();

    return {
      'id': groupRef.id,
      ...saved.data()!,
    };
  }

  // ------------------------------------------------------------
  // PUBLIC GROUPS
  // ------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> getPublicEventGroups(
    String eventId,
  ) async {
    try {
      final snapshot = await _eventGroupsCollection(
        eventId,
      ).get();

      final groups = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final type = data['type']?.toString().toLowerCase();

        final status = data['status']?.toString().toLowerCase();

        if (type != 'public' || status != 'waiting') {
          continue;
        }

        final members = data['member_uids'];

        final memberCount = members is List ? members.length : 0;

        if (memberCount >= 4) {
          continue;
        }

        groups.add(
          {
            'id': doc.id,
            ...data,
          },
        );
      }

      return groups;
    } catch (e) {
      debugPrint(
        'getPublicEventGroups error: $e',
      );

      return [];
    }
  }

  // ------------------------------------------------------------
  // GET ONE GROUP
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>?> getEventGroup(
    String eventId,
    String groupId,
  ) async {
    final doc = await _eventGroupsCollection(
      eventId,
    ).doc(groupId).get();

    if (!doc.exists) {
      return null;
    }

    return {
      'id': doc.id,
      ...doc.data()!,
    };
  }

  // ------------------------------------------------------------
  // GET MY GROUP
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>?> getMyEventGroup(
    String eventId,
  ) async {
    try {
      final snapshot = await _eventGroupsCollection(
        eventId,
      ).get();

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final memberUids = data['member_uids'];

        if (memberUids is List &&
            memberUids.map((e) => e.toString()).contains(_uid)) {
          return {
            'id': doc.id,
            ...data,
          };
        }
      }

      return null;
    } catch (e) {
      debugPrint(
        'getMyEventGroup error: $e',
      );

      return null;
    }
  }

  // ------------------------------------------------------------
  // JOIN PUBLIC GROUP
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>> joinPublicEventGroup({
    required String eventId,
    required String groupId,
  }) async {
    return _joinEventGroup(
      eventId: eventId,
      groupId: groupId,
      requirePublic: true,
      code: null,
    );
  }

  // ------------------------------------------------------------
  // JOIN PRIVATE GROUP
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>> joinPrivateEventGroup({
    required String eventId,
    required String code,
  }) async {
    final normalized = code.trim().toUpperCase();

    if (normalized.length != 6) {
      throw Exception(
        'Group code must contain 6 characters.',
      );
    }

    final snapshot = await _eventGroupsCollection(
      eventId,
    )
        .where(
          'code',
          isEqualTo: normalized,
        )
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      throw Exception(
        'Private group not found.',
      );
    }

    return _joinEventGroup(
      eventId: eventId,
      groupId: snapshot.docs.first.id,
      requirePublic: false,
      code: normalized,
    );
  }

  // ------------------------------------------------------------
  // JOIN ANY GROUP BY INVITE CODE
  // ------------------------------------------------------------
  // The same 6-character code can be shared for both public and private
  // groups. This is what the Event Group Invite button uses.
  static Future<Map<String, dynamic>> joinEventGroupByCode({
    required String eventId,
    required String code,
  }) async {
    final normalized = code.trim().toUpperCase();

    if (normalized.length != 6) {
      throw Exception('Group code must contain 6 characters.');
    }

    final snapshot = await _eventGroupsCollection(eventId)
        .where('code', isEqualTo: normalized)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      throw Exception('Group not found. Check the invite code.');
    }

    final group = snapshot.docs.first.data();
    final status = group['status']?.toString().toLowerCase() ?? 'waiting';
    if (status != 'waiting') {
      throw Exception('This group has already started.');
    }

    return _joinEventGroup(
      eventId: eventId,
      groupId: snapshot.docs.first.id,
      requirePublic: false,
      code: normalized,
    );
  }

  // ------------------------------------------------------------
  // EVENT GROUP INVITATIONS
  // ------------------------------------------------------------

  static CollectionReference<Map<String, dynamic>> _eventInvitesCollection(
      String uid) {
    return _db.collection('users').doc(uid).collection('event_invites');
  }

  static Future<List<Map<String, dynamic>>> getEventGroupInvites({
    required String eventId,
  }) async {
    try {
      final snapshot = await _eventInvitesCollection(_uid)
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: 'pending')
          .get();

      return snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }).toList();
    } catch (e) {
      debugPrint('getEventGroupInvites error: $e');
      return [];
    }
  }

  static Future<int> getEventGroupInviteCount({
    required String eventId,
  }) async {
    try {
      final snapshot = await _eventInvitesCollection(_uid)
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: 'pending')
          .get();
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('getEventGroupInviteCount error: $e');
      return 0;
    }
  }

  static Future<void> sendEventGroupInvite({
    required String eventId,
    required String groupId,
    required String toUid,
    required String eventName,
  }) async {
    if (toUid == _uid) {
      throw Exception('You cannot invite yourself.');
    }

    final group = await getEventGroup(eventId, groupId);
    if (group == null) {
      throw Exception('This group no longer exists.');
    }

    final status = group['status']?.toString().toLowerCase() ?? 'waiting';
    if (status != 'waiting') {
      throw Exception('This group has already started.');
    }

    final memberUids = group['member_uids'];
    if (memberUids is List &&
        memberUids.map((e) => e.toString()).contains(toUid)) {
      throw Exception('This person is already in the group.');
    }

    if (memberUids is List && memberUids.length >= 4) {
      throw Exception('This group is full.');
    }

    final senderProfile = await getProfileOrDefault();
    final senderName = senderProfile['name']?.toString().trim();

    final recipient = await _db.collection('users').doc(toUid).get();
    if (!recipient.exists) {
      throw Exception('User not found.');
    }

    final groupType = group['type']?.toString().toLowerCase() ?? 'private';
    final inviteRef = _eventInvitesCollection(toUid).doc();

    await inviteRef.set({
      'from': _uid,
      'fromName':
          senderName == null || senderName.isEmpty ? 'A friend' : senderName,
      'to': toUid,
      'eventId': eventId,
      'eventName': eventName,
      'groupId': groupId,
      'groupName': (group['name'] ?? 'Event Group').toString(),
      'groupType': groupType,
      'code': (group['code'] ?? '').toString(),
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteEventGroupInvite({
    required String eventId,
    required String inviteId,
  }) async {
    await _eventInvitesCollection(_uid).doc(inviteId).delete();
  }

  // ------------------------------------------------------------
  // JOIN INTERNAL
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>> _joinEventGroup({
    required String eventId,
    required String groupId,
    required bool requirePublic,
    required String? code,
  }) async {
    final uid = _uid;

    final profile = await getProfileOrDefault();

    final profileName = profile['name']?.toString().trim();

    final displayName =
        profileName == null || profileName.isEmpty ? 'Player' : profileName;

    final groupRef = _eventGroupsCollection(
      eventId,
    ).doc(groupId);

    await _db.runTransaction(
      (transaction) async {
        final snapshot = await transaction.get(groupRef);

        if (!snapshot.exists) {
          throw Exception(
            'Group no longer exists.',
          );
        }

        final data = snapshot.data()!;

        final type = data['type']?.toString().toLowerCase();

        final status = data['status']?.toString().toLowerCase();

        if (requirePublic && type != 'public') {
          throw Exception(
            'This is not a public group.',
          );
        }

        if (!requirePublic && code == null && type != 'private') {
          throw Exception(
            'This is not a private group.',
          );
        }

        if (status != 'waiting') {
          throw Exception(
            'This group has already started.',
          );
        }

        final memberUids = List<String>.from(
          data['member_uids'] ?? [],
        );

        final members = (data['members'] is List)
            ? List<Map<String, dynamic>>.from(
                (data['members'] as List).map(
                  (item) => Map<String, dynamic>.from(
                    item as Map,
                  ),
                ),
              )
            : <Map<String, dynamic>>[];

        if (memberUids.contains(uid)) {
          return;
        }

        if (memberUids.length >= 4) {
          throw Exception(
            'This group is full.',
          );
        }

        memberUids.add(uid);

        members.add(
          {
            'uid': uid,
            'name': displayName,
          },
        );

        transaction.update(
          groupRef,
          {
            'member_uids': memberUids,
            'members': members,
            'updated_at': FieldValue.serverTimestamp(),
          },
        );
      },
    );

    final result = await groupRef.get();

    return {
      'id': result.id,
      ...result.data()!,
    };
  }

  // ------------------------------------------------------------
  // READY
  // ------------------------------------------------------------

  static Future<void> setEventGroupReady({
    required String eventId,
    required String groupId,
    required bool ready,
  }) async {
    final ref = _eventGroupsCollection(
      eventId,
    ).doc(groupId);

    await ref.update(
      {
        'ready_ids': ready
            ? FieldValue.arrayUnion(
                [_uid],
              )
            : FieldValue.arrayRemove(
                [_uid],
              ),
        'updated_at': FieldValue.serverTimestamp(),
      },
    );
  }

  // ------------------------------------------------------------
  // START EVENT
  // ------------------------------------------------------------

  static Future<void> startEventGroup({
    required String eventId,
    required String groupId,
  }) async {
    final ref = _eventGroupsCollection(
      eventId,
    ).doc(groupId);

    await _db.runTransaction(
      (transaction) async {
        final snapshot = await transaction.get(ref);

        if (!snapshot.exists) {
          throw Exception(
            'Group no longer exists.',
          );
        }

        final data = snapshot.data()!;

        final leaderId = data['leader_id']?.toString();

        if (leaderId != _uid) {
          throw Exception(
            'Only the group leader can start the event.',
          );
        }

        final memberUids = List<String>.from(
          data['member_uids'] ?? [],
        );

        final readyIds = List<String>.from(
          data['ready_ids'] ?? [],
        );

        if (memberUids.isEmpty) {
          throw Exception(
            'There are no players in this group.',
          );
        }

        if (!readyIds.toSet().containsAll(
              memberUids.toSet(),
            )) {
          throw Exception(
            'Everyone must be ready before starting.',
          );
        }

        transaction.update(
          ref,
          {
            'status': 'starting',
            'started_at': FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
          },
        );
      },
    );
  }

  // ------------------------------------------------------------
  // COMPLETE EVENT TARGET
  // ------------------------------------------------------------

  static Future<bool> completeEventTarget({
    required String eventId,
    required String groupId,
    required String targetId,
    required int points,
  }) async {
    final ref = _eventGroupsCollection(
      eventId,
    ).doc(groupId);

    bool newlyCompleted = false;

    await _db.runTransaction(
      (transaction) async {
        final snapshot = await transaction.get(ref);

        if (!snapshot.exists) {
          throw Exception(
            'Group no longer exists.',
          );
        }

        final data = snapshot.data()!;

        final completed = List<String>.from(
          data['completed_target_ids'] ?? [],
        );

        if (completed.contains(targetId)) {
          newlyCompleted = false;
          return;
        }

        completed.add(
          targetId,
        );

        transaction.update(
          ref,
          {
            'completed_target_ids': completed,
            'score': FieldValue.increment(
              points,
            ),
            'updated_at': FieldValue.serverTimestamp(),
          },
        );

        newlyCompleted = true;
      },
    );

    return newlyCompleted;
  }

  // ------------------------------------------------------------
  // LEAVE GROUP
  // ------------------------------------------------------------

  static Future<void> leaveEventGroup({
    required String eventId,
    required String groupId,
  }) async {
    final ref = _eventGroupsCollection(
      eventId,
    ).doc(groupId);

    await _db.runTransaction(
      (transaction) async {
        final snapshot = await transaction.get(ref);

        if (!snapshot.exists) {
          return;
        }

        final data = snapshot.data()!;

        final members = (data['members'] is List)
            ? List<Map<String, dynamic>>.from(
                (data['members'] as List).map(
                  (item) => Map<String, dynamic>.from(
                    item as Map,
                  ),
                ),
              )
            : <Map<String, dynamic>>[];

        final memberUids = List<String>.from(
          data['member_uids'] ?? [],
        );

        memberUids.remove(_uid);

        members.removeWhere(
          (member) => member['uid']?.toString() == _uid,
        );

        if (memberUids.isEmpty) {
          transaction.delete(ref);
          return;
        }

        final leaderId = data['leader_id']?.toString();

        String newLeader = leaderId ?? '';

        if (newLeader == _uid ||
            !memberUids.contains(
              newLeader,
            )) {
          newLeader = memberUids.first;
        }

        transaction.update(
          ref,
          {
            'member_uids': memberUids,
            'members': members,
            'leader_id': newLeader,
            'ready_ids': FieldValue.arrayRemove(
              [_uid],
            ),
            'updated_at': FieldValue.serverTimestamp(),
          },
        );
      },
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
