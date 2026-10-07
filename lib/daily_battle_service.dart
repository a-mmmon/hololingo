import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'firestore_service.dart';

/// Thrown by [DailyBattleService.findOrJoinQueue] when this user has
/// already used all of today's [DailyBattleService.maxPlaysPerDay] attempts.
class DailyChallengeLimitReached implements Exception {}

/// ============================================================================
/// DAILY CHALLENGE SERVICE
/// ============================================================================
///
/// Event-scoped, admin-curated 1v1 battles — the only wager mode this app
/// has (a separate casual, player-chosen-wager mode was built and then
/// deliberately dropped in favor of keeping this the one wager game, tied to
/// live events). Fixed 20-token wager. Each match randomly draws
/// [roundCount] Thai -> English rounds from that day's admin-set word pool
/// (which may hold more than [roundCount] words, so back-to-back matches
/// the same day don't always repeat the same set), and both players in a
/// match see the identical drawn rounds. Users get [maxPlaysPerDay]
/// attempts per calendar day. Score per round rewards correctness and
/// speed (Kahoot-style); if both players answer a round correctly, only
/// whoever answered first (by server timestamp) keeps the points for it.
/// Higher total score wins.
///
/// There is no Cloud Function refereeing this (Spark plan, no billing
/// account on this project). The winner and token transfer are validated by
/// firestore.rules instead of a trusted server. Two things are explicitly
/// NOT rules-verifiable and are disclosed, client-trusted simplifications:
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
  static const int maxPlaysPerDay = 3;

  static const int defaultTokenFloor = 10;
  static const int defaultFreeTopUp = 75;

  // ============================================================
  // SETTINGS (admin-configurable, config/daily_challenge_settings)
  // ============================================================

  static Future<Map<String, int>> getSettings() async {
    try {
      final doc = await _db
          .collection('config')
          .doc('daily_challenge_settings')
          .get();

      final data = doc.data() ?? {};

      return {
        'token_floor': (data['token_floor'] as num?)?.toInt() ?? defaultTokenFloor,
        'free_top_up': (data['free_top_up'] as num?)?.toInt() ?? defaultFreeTopUp,
      };
    } catch (e) {
      return {
        'token_floor': defaultTokenFloor,
        'free_top_up': defaultFreeTopUp,
      };
    }
  }

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

  /// Grants this event's one-time free top-up the first time this user
  /// interacts with it — so someone who hasn't earned tokens from Topics
  /// yet isn't forced to buy the refill pack just to try the Daily
  /// Challenge. Safe to call every time the queue screen opens; no-ops
  /// instantly once already claimed.
  static Future<void> claimFreeTopUpIfNeeded(String eventId) async {
    try {
      final claimRef =
          _db.collection('users').doc(_uid).collection('event_topups').doc(eventId);

      final claimSnap = await claimRef.get();
      if (claimSnap.exists) return;

      final settings = await getSettings();
      final amount = settings['free_top_up'] ?? defaultFreeTopUp;

      await claimRef.set({'claimed_at': FieldValue.serverTimestamp(), 'amount': amount});

      await _db.collection('users').doc(_uid).set(
        {'tokens': FieldValue.increment(amount)},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('claimFreeTopUpIfNeeded error: $e');
    }
  }

  /// How many of today's [maxPlaysPerDay] Daily Challenge attempts this
  /// user has already used, for showing "2 of 3 played today" style UI
  /// before they commit to joining the queue.
  static Future<int> getPlaysToday() async {
    try {
      final doc = await _db
          .collection('users')
          .doc(_uid)
          .collection('daily_challenge_history')
          .doc(todayKey())
          .get();
      return (doc.data()?['plays'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('getPlaysToday error: $e');
      return 0;
    }
  }

  /// Claims one of today's [maxPlaysPerDay] attempts. Returns false (and
  /// claims nothing) once the daily limit is already used up — checked
  /// via a transaction so this can't be raced past the cap, and also
  /// re-checked by firestore.rules on the write itself.
  static Future<bool> _claimPlayForToday() async {
    final ref = _db
        .collection('users')
        .doc(_uid)
        .collection('daily_challenge_history')
        .doc(todayKey());

    try {
      return await _db.runTransaction<bool>((transaction) async {
        final snap = await transaction.get(ref);
        final current = (snap.data()?['plays'] as num?)?.toInt() ?? 0;

        if (current >= maxPlaysPerDay) return false;

        if (snap.exists) {
          transaction.update(ref, {'plays': current + 1});
        } else {
          transaction.set(ref, {'plays': 1});
        }
        return true;
      });
    } catch (e) {
      debugPrint('_claimPlayForToday error: $e');
      return false;
    }
  }

  /// Refunds a play claimed by [_claimPlayForToday] when the queue attempt
  /// it was for never actually resulted in a real match — cancelled by the
  /// user, or timed out with no opponent found. Without this, every
  /// abandoned queue attempt (backgrounded app, no opponent, manual cancel)
  /// would permanently cost one of today's 3 attempts for nothing.
  static Future<void> refundPlayForToday() async {
    final ref = _db
        .collection('users')
        .doc(_uid)
        .collection('daily_challenge_history')
        .doc(todayKey());

    try {
      await _db.runTransaction((transaction) async {
        final snap = await transaction.get(ref);
        final current = (snap.data()?['plays'] as num?)?.toInt() ?? 0;

        if (current <= 0) return;

        transaction.update(ref, {'plays': current - 1});
      });
    } catch (e) {
      debugPrint('refundPlayForToday error: $e');
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
  ///
  /// Throws [DailyChallengeLimitReached] if this user has already used
  /// all of today's [maxPlaysPerDay] attempts.
  static Future<String?> findOrJoinQueue({
    required String eventId,
    required String date,
  }) async {
    final claimed = await _claimPlayForToday();
    if (!claimed) throw DailyChallengeLimitReached();

    final candidates = await _db
        .collection('daily_challenge_queue')
        .where('event_id', isEqualTo: eventId)
        .where('challenge_date', isEqualTo: date)
        .where('status', isEqualTo: 'waiting')
        .limit(5)
        .get();

    // A queue entry left behind by a client that backgrounded/crashed
    // mid-queue (never hit Cancel, never hit the 3-minute timeout) stays
    // 'waiting' forever and would otherwise match a future real player
    // against a ghost opponent who never answers, hanging that battle.
    // Anything older than the queue screen's own timeout is treated as
    // abandoned and skipped rather than matched against.
    final staleCutoff = DateTime.now().toUtc().subtract(
          const Duration(minutes: 3),
        );

    for (final doc in candidates.docs) {
      if (doc.id == _uid) continue;

      final queuedAt = (doc.data()['queued_at'] as Timestamp?)?.toDate();
      if (queuedAt == null || queuedAt.isBefore(staleCutoff)) continue;

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
    final settings = await getSettings();
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
          'token_floor': settings['token_floor'],
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

    // Pull the whole day's word pool (the admin may seed more than
    // roundCount words, e.g. 20, so repeated matches the same day draw a
    // different random 10) and pick a random subset — one read instead of
    // up to 20 individual get()s, and naturally degrades to "shuffled
    // order" on a day the admin only seeded exactly roundCount words.
    final wordsSnap = await _db
        .collection('events')
        .doc(eventId)
        .collection('daily_challenges')
        .doc(date)
        .collection('words')
        .get();

    final pool = wordsSnap.docs.toList()..shuffle(Random());
    final selected = pool.take(roundCount).toList();

    // Individual writes, not a batch — each round's create rule makes two
    // get() calls to validate against the admin's real word list, and
    // batching all ten into one commit risks the per-request get() budget.
    for (var i = 0; i < selected.length; i++) {
      try {
        final doc = selected[i];
        final word = doc.data();
        final sourceIndex = int.parse(doc.id);

        await battleRef.collection('rounds').doc('$i').set({
          'source_index': sourceIndex,
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

      var aPoints = pointsForRound(
        correct: aCorrect,
        elapsedMs: (r['player_a_elapsed_ms'] as num).toInt(),
      );
      var bPoints = pointsForRound(
        correct: bCorrect,
        elapsedMs: (r['player_b_elapsed_ms'] as num).toInt(),
      );

      // Both got it right — first click wins the round outright, using
      // the server's own answered_at timestamp (not the self-reported
      // elapsed_ms) so it can't be gamed by under-reporting elapsed time.
      if (aCorrect && bCorrect) {
        final aAt = r['player_a_answered_at'] as Timestamp?;
        final bAt = r['player_b_answered_at'] as Timestamp?;

        if (aAt != null && bAt != null) {
          if (aAt.compareTo(bAt) < 0) {
            bPoints = 0;
          } else if (bAt.compareTo(aAt) < 0) {
            aPoints = 0;
          }
        }
      }

      scoreA += aPoints;
      scoreB += bPoints;
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

    await _settleTokens(battleId);
  }

  static Future<void> _settleTokens(String battleId) async {
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
        final tokenFloor = (battle['token_floor'] as num).toInt();
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
          newA = aTokens + (wagerAmount * 2);
          newB = (bTokens - wagerAmount) < tokenFloor ? tokenFloor : bTokens - wagerAmount;
        } else if (result == 'player_b') {
          newB = bTokens + (wagerAmount * 2);
          newA = (aTokens - wagerAmount) < tokenFloor ? tokenFloor : aTokens - wagerAmount;
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
      debugPrint('_settleTokens error: $e');
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

  // ============================================================
  // TOKEN REFILL PURCHASE (consumable IAP)
  //
  // Same client-trusted pattern as the Premium subscription — Apple
  // charges the user and pays out on its own, independent of this;
  // there's no server here to double-check the receipt before
  // crediting tokens, which is an accepted trade-off, not a new one.
  // ============================================================

  static const String tokenRefillProductId = 'com.hololingo.tokens.refill';
  static const int tokenRefillAmount = 100;

  static final InAppPurchase _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  static bool _purchasesInitialized = false;

  static final ValueNotifier<String?> refillError = ValueNotifier<String?>(null);

  static Future<void> initPurchases() async {
    if (_purchasesInitialized) return;
    _purchasesInitialized = true;

    final available = await _iap.isAvailable();
    if (!available) {
      debugPrint('DailyBattleService: store unavailable.');
      return;
    }

    _purchaseSubscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error) {
        debugPrint('DailyBattleService: purchase stream error: $error');
      },
    );
  }

  static Future<ProductDetailsResponse> queryRefillProduct() {
    return _iap.queryProductDetails({tokenRefillProductId});
  }

  static Future<void> buyRefill(ProductDetails product) {
    final purchaseParam = PurchaseParam(productDetails: product);
    return _iap.buyConsumable(purchaseParam: purchaseParam, autoConsume: true);
  }

  static Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      if (purchase.productID != tokenRefillProductId) continue;

      switch (purchase.status) {
        case PurchaseStatus.error:
          refillError.value = purchase.error?.message ?? 'Purchase failed.';
          debugPrint('DailyBattleService: purchase error: ${purchase.error}');
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            await _db.collection('users').doc(_uid).set(
              {'tokens': FieldValue.increment(tokenRefillAmount)},
              SetOptions(merge: true),
            );
          } catch (e) {
            debugPrint('DailyBattleService: could not credit tokens: $e');
          }
          break;

        case PurchaseStatus.pending:
        case PurchaseStatus.canceled:
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  static void disposePurchases() {
    _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _purchasesInitialized = false;
  }
}
