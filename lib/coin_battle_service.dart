import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'firestore_service.dart';

/// ============================================================================
/// COIN BATTLE SERVICE
/// ============================================================================
///
/// 1v1 async wager battles. Each player answers a multiple-choice question
/// built from their OWN saved words (never the other player's — saved_words
/// is owner-only-read, so a shared question isn't possible without one
/// player reading the other's private word list), mixed with the current
/// event's theme vocabulary when one is live (events are public data, so
/// mixing that in doesn't have the same privacy constraint). Winner: correct
/// beats incorrect; if both correct, whoever answered first wins; if both
/// wrong, it's a draw and no coins move.
///
/// IMPORTANT — there is no Cloud Function refereeing this (Spark plan, no
/// billing account on this project). The winner and the coin transfer it
/// triggers are both validated by firestore.rules instead of a trusted
/// server: the correct answers are locked in at battle creation and can
/// never change, each player can only submit their own choice once with a
/// server-assigned timestamp, and coins can only move by the exact amount a
/// resolved battle says is owed. This is the same "client-trusted" trade-off
/// already accepted for the Premium subscription and the coin refill
/// purchase — reasonable for this project's size, not bulletproof.
///
/// Coins are never escrowed up front — they only move once, at resolution —
/// so an abandoned/never-finished battle has zero financial impact on
/// either player; it just sits unresolved.
class CoinBattleService {
  static String get _uid => FirebaseAuth.instance.currentUser!.uid;

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const int defaultCoinFloor = 10;
  static const int defaultFreeTopUp = 75;

  // ============================================================
  // SETTINGS (admin-configurable, config/coin_battle_settings)
  // ============================================================

  static Future<Map<String, int>> getSettings() async {
    try {
      final doc = await _db
          .collection('config')
          .doc('coin_battle_settings')
          .get();

      final data = doc.data() ?? {};

      return {
        'coin_floor': (data['coin_floor'] as num?)?.toInt() ?? defaultCoinFloor,
        'free_top_up': (data['free_top_up'] as num?)?.toInt() ?? defaultFreeTopUp,
      };
    } catch (e) {
      return {
        'coin_floor': defaultCoinFloor,
        'free_top_up': defaultFreeTopUp,
      };
    }
  }

  // ============================================================
  // QUESTION GENERATION (own saved words + live event vocab, if any)
  // ============================================================

  /// The live event's theme word list, if `config/current_event` points
  /// at an `events/{id}` doc with a `theme_words` array. Public data
  /// (events are readable by any signed-in user), so mixing this into a
  /// question has none of the privacy constraint saved_words has.
  static Future<List<Map<String, String>>> _eventThemeWords() async {
    try {
      final event = await FirestoreService.getCurrentEvent();
      if (event == null) return [];

      final eventName = event['name']?.toString().trim() ?? '';
      if (eventName.isEmpty) return [];

      final rawEventId = event['event_id']?.toString().trim();
      final eventId = (rawEventId != null && rawEventId.isNotEmpty)
          ? rawEventId
          : FirestoreService.eventIdFromName(eventName);

      final definition = await FirestoreService.getEventDefinition(eventId);
      final themeWords = definition?['theme_words'];
      if (themeWords is! List) return [];

      return themeWords
          .whereType<Map>()
          .map(
            (w) => {
              'word': (w['word'] ?? '').toString().trim(),
              'definition': (w['definition'] ?? '').toString().trim(),
            },
          )
          .where((w) => w['word']!.isNotEmpty && w['definition']!.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('_eventThemeWords error: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> buildQuestionFromOwnWords() async {
    final snap = await _db
        .collection('users')
        .doc(_uid)
        .collection('saved_words')
        .get();

    final ownWords = snap.docs
        .map((d) => d.data())
        .where(
          (w) =>
              (w['word'] ?? '').toString().trim().isNotEmpty &&
              (w['definition'] ?? '').toString().trim().isNotEmpty,
        )
        .map(
          (w) => {
            'word': w['word'].toString(),
            'definition': w['definition'].toString(),
          },
        )
        .toList();

    final eventWords = await _eventThemeWords();

    // Own words mixed with whatever the live event's theme adds — mostly
    // personal vocabulary, occasionally an event word, matching the
    // "words they've each learned, event vocab mixed in" design.
    final pool = [...ownWords, ...eventWords];

    // Need at least 4 distinct words: one to ask about, three as
    // plausible-looking wrong answers.
    if (pool.length < 4) return null;

    pool.shuffle();

    final target = pool.first;
    final targetDefinition = target['definition']!;

    final distractors = pool
        .skip(1)
        .map((w) => w['definition']!)
        .where((d) => d != targetDefinition)
        .take(3)
        .toList();

    if (distractors.length < 3) return null;

    final options = [targetDefinition, ...distractors]..shuffle();
    final correctIndex = options.indexOf(targetDefinition);

    return {
      'word': target['word'].toString(),
      'options': options,
      'correct_index': correctIndex,
    };
  }

  // ============================================================
  // CHALLENGES (open wager offers, waiting to be accepted)
  // ============================================================

  static Future<String> createChallenge({required int wager}) async {
    final question = await buildQuestionFromOwnWords();

    if (question == null) {
      throw StateError(
        'You need at least 4 saved words with definitions to start a battle.',
      );
    }

    final doc = await _db.collection('battle_challenges').add({
      'creator_uid': _uid,
      'status': 'open',
      'wager': wager,
      'creator_word': question['word'],
      'creator_options': question['options'],
      'creator_correct_index': question['correct_index'],
      'created_at': FieldValue.serverTimestamp(),
    });

    return doc.id;
  }

  static Stream<List<Map<String, dynamic>>> watchOpenChallenges() {
    return _db
        .collection('battle_challenges')
        .where('status', isEqualTo: 'open')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .where((c) => c['creator_uid'] != _uid)
              .toList(),
        )
        .handleError((e) => debugPrint('watchOpenChallenges error: $e'));
  }

  static Stream<List<Map<String, dynamic>>> watchMyOpenChallenges() {
    return _db
        .collection('battle_challenges')
        .where('creator_uid', isEqualTo: _uid)
        .where('status', isEqualTo: 'open')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList())
        .handleError((e) => debugPrint('watchMyOpenChallenges error: $e'));
  }

  static Future<void> cancelChallenge(String challengeId) {
    return _db.collection('battle_challenges').doc(challengeId).delete();
  }

  /// Accepts an open challenge: builds the acceptor's own question,
  /// creates the `battles` doc (carrying both players' questions), then
  /// marks the challenge accepted. Returns the new battle's id.
  static Future<String> acceptChallenge(Map<String, dynamic> challenge) async {
    final creatorUid = challenge['creator_uid'] as String;
    final wager = (challenge['wager'] as num).toInt();

    final myQuestion = await buildQuestionFromOwnWords();

    if (myQuestion == null) {
      throw StateError(
        'You need at least 4 saved words with definitions to accept a battle.',
      );
    }

    final settings = await getSettings();
    final battleRef = _db.collection('battles').doc();

    await battleRef.set({
      'player_a_uid': creatorUid,
      'player_b_uid': _uid,
      'wager': wager,
      'coin_floor': settings['coin_floor'],
      'player_a_word': challenge['creator_word'],
      'player_a_options': List<String>.from(challenge['creator_options'] as List),
      'player_a_correct_index': challenge['creator_correct_index'],
      'player_b_word': myQuestion['word'],
      'player_b_options': myQuestion['options'],
      'player_b_correct_index': myQuestion['correct_index'],
      'player_a_choice': null,
      'player_b_choice': null,
      'player_a_answered_at': null,
      'player_b_answered_at': null,
      'status': 'active',
      'result': null,
      'settled': false,
      'created_at': FieldValue.serverTimestamp(),
      'resolved_at': null,
    });

    await _db.collection('battle_challenges').doc(challenge['id'] as String).update({
      'status': 'accepted',
      'acceptor_uid': _uid,
      'battle_id': battleRef.id,
    });

    return battleRef.id;
  }

  // ============================================================
  // BATTLE
  // ============================================================

  static Stream<Map<String, dynamic>?> watchBattle(String battleId) {
    return _db
        .collection('battles')
        .doc(battleId)
        .snapshots()
        .map((d) => d.exists ? {'id': d.id, ...d.data()!} : null)
        .handleError((e) => debugPrint('watchBattle error: $e'));
  }

  static Future<void> submitAnswer({
    required String battleId,
    required bool isPlayerA,
    required int choice,
  }) {
    final choiceField = isPlayerA ? 'player_a_choice' : 'player_b_choice';
    final timeField = isPlayerA ? 'player_a_answered_at' : 'player_b_answered_at';

    return _db.collection('battles').doc(battleId).update({
      choiceField: choice,
      timeField: FieldValue.serverTimestamp(),
    });
  }

  /// Called by whichever client's stream first observes both answers are
  /// in. Safe to call more than once / from both clients — the rules
  /// reject a resolution attempt once the battle is no longer 'active',
  /// so a race just means one call succeeds and the other silently no-ops.
  static Future<void> resolveIfReady(Map<String, dynamic> battle) async {
    if (battle['status'] != 'active') return;
    if (battle['player_a_choice'] == null || battle['player_b_choice'] == null) return;

    final aCorrect = battle['player_a_choice'] == battle['player_a_correct_index'];
    final bCorrect = battle['player_b_choice'] == battle['player_b_correct_index'];

    String result;
    if (aCorrect && bCorrect) {
      final aTime = (battle['player_a_answered_at'] as Timestamp).toDate();
      final bTime = (battle['player_b_answered_at'] as Timestamp).toDate();
      result = !aTime.isAfter(bTime) ? 'player_a' : 'player_b';
    } else if (aCorrect) {
      result = 'player_a';
    } else if (bCorrect) {
      result = 'player_b';
    } else {
      result = 'draw';
    }

    try {
      await _db.collection('battles').doc(battle['id'] as String).update({
        'status': 'resolved',
        'result': result,
        'resolved_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Already resolved by the other client — fine, fall through to
      // settlement anyway in case that client hasn't gotten to it yet.
      debugPrint('resolveIfReady resolve step: $e');
    }

    await _settleCoins(battle['id'] as String);
  }

  static Future<void> _settleCoins(String battleId) async {
    try {
      await _db.runTransaction((transaction) async {
        final battleRef = _db.collection('battles').doc(battleId);
        final battleSnap = await transaction.get(battleRef);
        final battle = battleSnap.data();

        if (battle == null ||
            battle['status'] != 'resolved' ||
            battle['settled'] == true) {
          return;
        }

        final playerAUid = battle['player_a_uid'] as String;
        final playerBUid = battle['player_b_uid'] as String;
        final wager = (battle['wager'] as num).toInt();
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
          newA = aTokens + wager;
          newB = (bTokens - wager) < coinFloor ? coinFloor : bTokens - wager;
        } else if (result == 'player_b') {
          newB = bTokens + wager;
          newA = (aTokens - wager) < coinFloor ? coinFloor : aTokens - wager;
        }

        transaction.update(userARef, {
          'tokens': newA,
          'last_battle_settlement': battleId,
        });
        transaction.update(userBRef, {
          'tokens': newB,
          'last_battle_settlement': battleId,
        });
        transaction.update(battleRef, {'settled': true});
      });
    } catch (e) {
      debugPrint('_settleCoins error: $e');
    }
  }

  // ============================================================
  // COIN REFILL PURCHASE (consumable IAP)
  //
  // Same client-trusted pattern as the Premium subscription — Apple
  // charges the user and pays out on its own, independent of this;
  // there's no server here to double-check the receipt before
  // crediting coins, which is an accepted trade-off, not a new one.
  // ============================================================

  static const String coinRefillProductId = 'com.hololingo.coins.refill';
  static const int coinRefillAmount = 100;

  static final InAppPurchase _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  static bool _purchasesInitialized = false;

  static final ValueNotifier<String?> refillError = ValueNotifier<String?>(null);

  static Future<void> initPurchases() async {
    if (_purchasesInitialized) return;
    _purchasesInitialized = true;

    final available = await _iap.isAvailable();
    if (!available) {
      debugPrint('CoinBattleService: store unavailable.');
      return;
    }

    _purchaseSubscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error) {
        debugPrint('CoinBattleService: purchase stream error: $error');
      },
    );
  }

  static Future<ProductDetailsResponse> queryRefillProduct() {
    return _iap.queryProductDetails({coinRefillProductId});
  }

  static Future<void> buyRefill(ProductDetails product) {
    final purchaseParam = PurchaseParam(productDetails: product);
    return _iap.buyConsumable(purchaseParam: purchaseParam, autoConsume: true);
  }

  static Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      if (purchase.productID != coinRefillProductId) continue;

      switch (purchase.status) {
        case PurchaseStatus.error:
          refillError.value = purchase.error?.message ?? 'Purchase failed.';
          debugPrint('CoinBattleService: purchase error: ${purchase.error}');
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            await _db.collection('users').doc(_uid).set(
              {'tokens': FieldValue.increment(coinRefillAmount)},
              SetOptions(merge: true),
            );
          } catch (e) {
            debugPrint('CoinBattleService: could not credit coins: $e');
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
