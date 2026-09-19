import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'coin_battle_service.dart';
import 'firestore_service.dart';

/// ============================================================================
/// DAILY CHALLENGE SERVICE
/// ============================================================================
///
/// Event-scoped, admin-curated 1v1 battles — a separate mode from the casual
/// Coin Battle. Fixed 20-coin wager, both players see the SAME 10 admin-set
/// Thai -> English rounds for that calendar day, matched via a queue instead
/// of browsing a challenge list. Score per round rewards both correctness and
/// speed (Kahoot-style); higher total score wins.
///
/// Same no-Cloud-Function trade-off as Coin Battle: the winner and coin
/// transfer are validated by firestore.rules instead of a trusted server.
/// Two things are explicitly NOT rules-verifiable and are disclosed,
/// client-trusted simplifications:
///   - a player's own reported elapsed_ms per round (a modified client could
///     under-report it for a higher score) — rules only bounds-check it's a
///     non-negative int, not that it's truthful.
///   - who actually won the most Daily Challenge battles over an event is a
///     client-side tally (whichever client's app happens to open after the
///     event ends computes it) — rules only verify the event genuinely
///     ended and that this specific write hasn't already happened.
class DailyBattleService {
  static String get _uid => FirebaseAuth.instance.currentUser!.uid;

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const int wager = 20;
  static const int roundCount = 10;

  static String todayKey() {
    final now = DateTime.now().toUtc();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static int pointsForRound({required bool correct, required int elapsedMs}) {
    if (!correct) return 0;
    final penalty = (elapsedMs / 100).round();
    final points = 100 - penalty;
    return points < 40 ? 40 : points;
  }

  // ============================================================
  // EVENT / CHALLENGE LOOKUP
  // ============================================================

  static Future<String?> getActiveEventId() async {
    final event = await FirestoreService.getCurrentEvent();
    if (event == null) return null;

    final eventName = event['name']?.toString().trim() ?? '';
    if (eventName.isEmpty) return null;

    final rawEventId = event['event_id']?.toString().trim();
    return (rawEventId != null && rawEventId.isNotEmpty)
        ? rawEventId
        : FirestoreService.eventIdFromName(eventName);
  }

  static Future<bool> hasTodaysChallenge(String eventId) async {
    try {
      final doc = await _db
          .collection('events')
          .doc(eventId)
          .collection('daily_challenges')
          .doc(todayKey())
          .collection('words')
          .doc('0')
          .get();
      return doc.exists;
    } catch (e) {
      debugPrint('hasTodaysChallenge error: $e');
      return false;
    }
  }

  // ============================================================
  // MATCHMAKING
  // ============================================================

  static Stream<Map<String, dynamic>?> watchMyQueueEntry() {
    return _db
        .collection('daily_challenge_queue')
        .doc(_uid)
        .snapshots()
        .map((d) => d.exists ? {'id': d.id, ...d.data()!} : null)
        .handleError((e) => debugPrint('watchMyQueueEntry error: $e'));
  }

  static Future<void> cancelQueue() {
    return _db.collection('daily_challenge_queue').doc(_uid).delete();
  }

  /// Looks for someone already waiting for this event+day; if found,
  /// creates the battle and matches them, returning the battle id. If
  /// nobody's waiting, joins the queue itself and returns null — the
  /// caller should then listen via [watchMyQueueEntry] for a match.
  static Future<String?> findOrJoinQueue({
    required String eventId,
    required String date,
  }) async {
    final candidates = await _db
        .collection('daily_challenge_queue')
        .where('event_id', isEqualTo: eventId)
        .where('challenge_date', isEqualTo: date)
        .where('status', isEqualTo: 'waiting')
        .limit(5)
        .get();

    for (final doc in candidates.docs) {
      if (doc.id == _uid) continue;

      final battleId = await _matchWith(
        otherUid: doc.id,
        eventId: eventId,
        date: date,
      );

      if (battleId != null) return battleId;
    }

    await _db.collection('daily_challenge_queue').doc(_uid).set({
      'status': 'waiting',
      'event_id': eventId,
      'challenge_date': date,
      'queued_at': FieldValue.serverTimestamp(),
    });

    return null;
  }

  static Future<String?> _matchWith({
    required String otherUid,
    required String eventId,
    required String date,
  }) async {
    final settings = await CoinBattleService.getSettings();
    final battleRef = _db.collection('daily_battles').doc();

    try {
      await _db.runTransaction((transaction) async {
        final otherRef = _db.collection('daily_challenge_queue').doc(otherUid);
        final otherSnap = await transaction.get(otherRef);

        if (!otherSnap.exists || otherSnap.data()?['status'] != 'waiting') {
          throw StateError('no longer waiting');
        }

        transaction.set(battleRef, {
          'event_id': eventId,
          'challenge_date': date,
          'player_a_uid': otherUid,
          'player_b_uid': _uid,
          'wager': wager,
          'coin_floor': settings['coin_floor'],
          'round_count': roundCount,
          'player_a_score': null,
          'player_b_score': null,
          'status': 'active',
          'result': null,
          'settled': false,
          'created_at': FieldValue.serverTimestamp(),
          'resolved_at': null,
        });

        transaction.update(otherRef, {
          'status': 'matched',
          'matched_with': _uid,
          'battle_id': battleRef.id,
        });
      });
    } catch (e) {
      debugPrint('DailyBattleService: match attempt failed: $e');
      return null;
    }

    // Individual writes, not a batch — each round's create rule makes two
    // get() calls to validate against the admin's real word list, and
    // batching all ten into one commit risks the per-request get() budget.
    for (var i = 0; i < roundCount; i++) {
      try {
        final wordDoc = await _db
            .collection('events')
            .doc(eventId)
            .collection('daily_challenges')
            .doc(date)
            .collection('words')
            .doc('$i')
            .get();

        final word = wordDoc.data();
        if (word == null) continue;

        await battleRef.collection('rounds').doc('$i').set({
          'thai': word['thai'],
          'options': word['options'],
          'correct_index': word['correct_index'],
          'player_a_choice': null,
          'player_b_choice': null,
          'player_a_answered_at': null,
          'player_b_answered_at': null,
          'player_a_elapsed_ms': null,
          'player_b_elapsed_ms': null,
        });
      } catch (e) {
        debugPrint('DailyBattleService: round $i create failed: $e');
      }
    }

    return battleRef.id;
  }

  // ============================================================
  // BATTLE
  // ============================================================

  static Stream<Map<String, dynamic>?> watchBattle(String battleId) {
    return _db
        .collection('daily_battles')
        .doc(battleId)
        .snapshots()
        .map((d) => d.exists ? {'id': d.id, ...d.data()!} : null)
        .handleError((e) => debugPrint('watchBattle error: $e'));
  }

  static Stream<List<Map<String, dynamic>>> watchRounds(String battleId) {
    return _db
        .collection('daily_battles')
        .doc(battleId)
        .collection('rounds')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList()
            ..sort((a, b) => int.parse(a['id'] as String).compareTo(int.parse(b['id'] as String))),
        )
        .handleError((e) => debugPrint('watchRounds error: $e'));
  }

  static Future<void> submitRoundAnswer({
    required String battleId,
    required int index,
    required bool isPlayerA,
    required int choice,
    required int elapsedMs,
  }) {
    final choiceField = isPlayerA ? 'player_a_choice' : 'player_b_choice';
    final timeField = isPlayerA ? 'player_a_answered_at' : 'player_b_answered_at';
    final elapsedField = isPlayerA ? 'player_a_elapsed_ms' : 'player_b_elapsed_ms';

    return _db
        .collection('daily_battles')
        .doc(battleId)
        .collection('rounds')
        .doc('$index')
        .update({
      choiceField: choice,
      timeField: FieldValue.serverTimestamp(),
      elapsedField: elapsedMs,
    });
  }

  /// Called whenever a client's round stream shows every round now has
  /// both players' answers. Safe to call more than once — rules reject a
  /// resolution once the battle is no longer 'active'.
  static Future<void> resolveIfReady(String battleId) async {
    final battleDoc = await _db.collection('daily_battles').doc(battleId).get();
    final battle = battleDoc.data();
    if (battle == null || battle['status'] != 'active') return;

    final roundsSnap =
        await _db.collection('daily_battles').doc(battleId).collection('rounds').get();

    if (roundsSnap.docs.length < roundCount) return;

    var scoreA = 0;
    var scoreB = 0;

    for (final doc in roundsSnap.docs) {
      final r = doc.data();
      if (r['player_a_choice'] == null || r['player_b_choice'] == null) return;

      final correctIndex = r['correct_index'] as int;
      final aCorrect = r['player_a_choice'] == correctIndex;
      final bCorrect = r['player_b_choice'] == correctIndex;

      scoreA += pointsForRound(
        correct: aCorrect,
        elapsedMs: (r['player_a_elapsed_ms'] as num).toInt(),
      );
      scoreB += pointsForRound(
        correct: bCorrect,
        elapsedMs: (r['player_b_elapsed_ms'] as num).toInt(),
      );
    }

    final result = scoreA == scoreB ? 'draw' : (scoreA > scoreB ? 'player_a' : 'player_b');

    try {
      await _db.collection('daily_battles').doc(battleId).update({
        'status': 'resolved',
        'result': result,
        'player_a_score': scoreA,
        'player_b_score': scoreB,
        'resolved_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('resolveIfReady resolve step: $e');
    }

    await _settleCoins(battleId);
  }

  static Future<void> _settleCoins(String battleId) async {
    try {
      await _db.runTransaction((transaction) async {
        final battleRef = _db.collection('daily_battles').doc(battleId);
        final battleSnap = await transaction.get(battleRef);
        final battle = battleSnap.data();

        if (battle == null ||
            battle['status'] != 'resolved' ||
            battle['settled'] == true) {
          return;
        }

        final playerAUid = battle['player_a_uid'] as String;
        final playerBUid = battle['player_b_uid'] as String;
        final wagerAmount = (battle['wager'] as num).toInt();
        final coinFloor = (battle['coin_floor'] as num).toInt();
        final result = battle['result'] as String;

        final userARef = _db.collection('users').doc(playerAUid);
        final userBRef = _db.collection('users').doc(playerBUid);

        final userASnap = await transaction.get(userARef);
        final userBSnap = await transaction.get(userBRef);

        final aTokens = (userASnap.data()?['tokens'] as num?)?.toInt() ?? 0;
        final bTokens = (userBSnap.data()?['tokens'] as num?)?.toInt() ?? 0;

        var newA = aTokens;
        var newB = bTokens;

        if (result == 'player_a') {
          newA = aTokens + wagerAmount;
          newB = (bTokens - wagerAmount) < coinFloor ? coinFloor : bTokens - wagerAmount;
        } else if (result == 'player_b') {
          newB = bTokens + wagerAmount;
          newA = (aTokens - wagerAmount) < coinFloor ? coinFloor : aTokens - wagerAmount;
        }

        transaction.update(userARef, {
          'tokens': newA,
          'last_daily_settlement': battleId,
        });
        transaction.update(userBRef, {
          'tokens': newB,
          'last_daily_settlement': battleId,
        });
        transaction.update(battleRef, {'settled': true});
      });
    } catch (e) {
      debugPrint('_settleCoins error: $e');
    }
  }

  // ============================================================
  // CHAMPION (end of event)
  // ============================================================

  static Stream<Map<String, dynamic>?> watchLastChampion() {
    return _db
        .collection('config')
        .doc('last_champion')
        .snapshots()
        .map((d) => d.exists ? d.data() : null)
        .handleError((e) => debugPrint('watchLastChampion error: $e'));
  }

  static Stream<List<Map<String, dynamic>>> watchMyBadges() {
    return _db
        .collection('users')
        .doc(_uid)
        .collection('badges')
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList())
        .handleError((e) => debugPrint('watchMyBadges error: $e'));
  }

  /// Call opportunistically (e.g. on Home screen load) with whatever the
  /// current/most-recent event id is. No-ops instantly unless that event
  /// has genuinely ended and nobody's been crowned yet.
  static Future<void> checkAndCrownChampionIfEnded(String eventId) async {
    try {
      final eventDoc = await _db.collection('events').doc(eventId).get();
      final event = eventDoc.data();
      if (event == null || event['champion_uid'] != null) return;

      final endAt = (event['end_at'] as Timestamp?)?.toDate();
      if (endAt == null || DateTime.now().isBefore(endAt)) return;

      final battlesSnap = await _db
          .collection('daily_battles')
          .where('event_id', isEqualTo: eventId)
          .where('status', isEqualTo: 'resolved')
          .get();

      final wins = <String, int>{};
      for (final doc in battlesSnap.docs) {
        final b = doc.data();
        final result = b['result'] as String?;
        if (result == 'player_a') {
          final uid = b['player_a_uid'] as String;
          wins[uid] = (wins[uid] ?? 0) + 1;
        } else if (result == 'player_b') {
          final uid = b['player_b_uid'] as String;
          wins[uid] = (wins[uid] ?? 0) + 1;
        }
      }

      if (wins.isEmpty) return;

      final championEntry =
          wins.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final championUid = championEntry.key;

      await _db.collection('events').doc(eventId).update({
        'champion_uid': championUid,
      });

      final championProfile = await _db.collection('users').doc(championUid).get();
      final championName =
          championProfile.data()?['name']?.toString() ??
              championProfile.data()?['display_name']?.toString() ??
              'A player';

      await _db.collection('config').doc('last_champion').set({
        'uid': championUid,
        'name': championName,
        'event_id': eventId,
        'event_name': event['name'],
        'wins': championEntry.value,
        'crowned_at': FieldValue.serverTimestamp(),
      });

      await _db
          .collection('users')
          .doc(championUid)
          .collection('badges')
          .doc(eventId)
          .set({
        'event_name': event['name'],
        'wins': championEntry.value,
        'earned_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('checkAndCrownChampionIfEnded error: $e');
    }
  }
}
