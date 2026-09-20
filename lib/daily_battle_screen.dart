import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'daily_battle_result_screen.dart';
import 'daily_battle_service.dart';

class DailyBattleScreen extends StatefulWidget {
  final String battleId;

  const DailyBattleScreen({super.key, required this.battleId});

  @override
  State<DailyBattleScreen> createState() => _DailyBattleScreenState();
}

class _DailyBattleScreenState extends State<DailyBattleScreen> {
  StreamSubscription<Map<String, dynamic>?>? _battleSub;
  StreamSubscription<List<Map<String, dynamic>>>? _roundsSub;

  Map<String, dynamic>? _battle;
  List<Map<String, dynamic>> _rounds = [];
  int _currentIndex = 0;
  DateTime? _roundShownAt;
  bool _submitting = false;
  bool _resultShown = false;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  bool get _isPlayerA => _battle?['player_a_uid'] == _uid;

  @override
  void initState() {
    super.initState();
    _battleSub = DailyBattleService.watchBattle(widget.battleId).listen(_onBattle);
    _roundsSub = DailyBattleService.watchRounds(widget.battleId).listen(_onRounds);
  }

  @override
  void dispose() {
    _battleSub?.cancel();
    _roundsSub?.cancel();
    super.dispose();
  }

  void _onBattle(Map<String, dynamic>? battle) {
    if (!mounted) return;
    setState(() => _battle = battle);

    if (battle?['status'] == 'resolved' && !_resultShown) {
      _resultShown = true;
      _showResult(battle!);
    }
  }

  void _onRounds(List<Map<String, dynamic>> rounds) {
    if (!mounted) return;

    var nextIndex = rounds.length;
    for (var i = 0; i < rounds.length; i++) {
      final mine = _isPlayerA ? rounds[i]['player_a_choice'] : rounds[i]['player_b_choice'];
      if (mine == null) {
        nextIndex = i;
        break;
      }
    }

    setState(() {
      _rounds = rounds;
      if (_currentIndex != nextIndex) {
        _currentIndex = nextIndex;
        _roundShownAt = DateTime.now();
      }
    });

    final allComplete = rounds.length == DailyBattleService.roundCount &&
        rounds.every((r) => r['player_a_choice'] != null && r['player_b_choice'] != null);

    if (allComplete && _battle != null && _battle!['status'] == 'active') {
      DailyBattleService.resolveIfReady(widget.battleId);
    }
  }

  Future<void> _showResult(Map<String, dynamic> battle) async {
    final result = battle['result'] as String?;
    final isDraw = result == 'draw';
    final won = _isPlayerA ? result == 'player_a' : result == 'player_b';
    final myScore = (_isPlayerA ? battle['player_a_score'] : battle['player_b_score']) as int? ?? 0;
    final theirScore = (_isPlayerA ? battle['player_b_score'] : battle['player_a_score']) as int? ?? 0;
    final wager = (battle['wager'] as num?)?.toInt() ?? 0;

    final review = _rounds.map((r) {
      final options = List<String>.from(r['options'] as List);
      final correctIndex = r['correct_index'] as int;
      final myChoice = (_isPlayerA ? r['player_a_choice'] : r['player_b_choice']) as int?;

      return {
        'thai': (r['thai'] ?? '').toString(),
        'correctAnswer': options[correctIndex],
        'myAnswer': myChoice != null ? options[myChoice] : null,
        'isCorrect': myChoice == correctIndex,
      };
    }).toList();

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DailyBattleResultScreen(
          won: won,
          isDraw: isDraw,
          myScore: myScore,
          theirScore: theirScore,
          wager: wager,
          review: review,
        ),
      ),
    );
  }

  Future<void> _answer(int choice) async {
    if (_submitting || _currentIndex >= _rounds.length) return;

    setState(() => _submitting = true);

    final elapsedMs = DateTime.now().difference(_roundShownAt ?? DateTime.now()).inMilliseconds;

    try {
      await DailyBattleService.submitRoundAnswer(
        battleId: widget.battleId,
        index: _currentIndex,
        isPlayerA: _isPlayerA,
        choice: choice,
        elapsedMs: elapsedMs.clamp(0, 1 << 30),
      );
    } catch (e) {
      // Fall through — the rounds stream will just show the same round
      // again if this failed, and the button re-enables below.
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary(dark)),
        title: Text(
          'Daily Challenge',
          style: TextStyle(color: AppColors.textPrimary(dark)),
        ),
      ),
      body: (_battle == null || _rounds.isEmpty)
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : _buildContent(dark),
    );
  }

  Widget _buildContent(bool dark) {
    if (_currentIndex >= _rounds.length) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.cyan),
              const SizedBox(height: 16),
              Text(
                'All 10 answered — waiting for your opponent to finish…',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final round = _rounds[_currentIndex];
    final options = List<String>.from(round['options'] as List);
    final myChoice = (_isPlayerA ? round['player_a_choice'] : round['player_b_choice']) as int?;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Round ${_currentIndex + 1} / ${DailyBattleService.roundCount}',
                style: TextStyle(
                  color: AppColors.textSecondary(dark),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Wager: ${DailyBattleService.wager}',
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Text(
                  'What is this in English?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  (round['thai'] ?? '').toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary(dark),
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ...options.asMap().entries.map((entry) {
            final index = entry.key;
            final text = entry.value;
            final selected = myChoice == index;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: (myChoice != null || _submitting) ? null : () => _answer(index),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.cyan.withOpacity(0.14) : AppColors.card(dark),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? AppColors.cyan : AppColors.border(dark),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: AppColors.textPrimary(dark),
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
