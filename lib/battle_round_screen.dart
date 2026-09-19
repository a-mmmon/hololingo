import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'battle_result_screen.dart';
import 'coin_battle_service.dart';

class BattleRoundScreen extends StatefulWidget {
  final String battleId;

  const BattleRoundScreen({super.key, required this.battleId});

  @override
  State<BattleRoundScreen> createState() => _BattleRoundScreenState();
}

class _BattleRoundScreenState extends State<BattleRoundScreen> {
  StreamSubscription<Map<String, dynamic>?>? _subscription;
  Map<String, dynamic>? _battle;
  int? _myChoice;
  bool _submitting = false;
  bool _resultShown = false;
  String? _error;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  bool get _isPlayerA {
    final battle = _battle;
    return battle != null && battle['player_a_uid'] == _uid;
  }

  dynamic _mine(String suffix) {
    final battle = _battle;
    if (battle == null) return null;
    return _isPlayerA ? battle['player_a_$suffix'] : battle['player_b_$suffix'];
  }

  dynamic _theirs(String suffix) {
    final battle = _battle;
    if (battle == null) return null;
    return _isPlayerA ? battle['player_b_$suffix'] : battle['player_a_$suffix'];
  }

  String get _myWord => (_mine('word') ?? '').toString();

  List<String> get _myOptions =>
      List<String>.from(_mine('options') as List? ?? const []);

  int? get _myStoredChoice => _mine('choice') as int?;

  bool get _opponentAnswered => _theirs('choice') != null;

  @override
  void initState() {
    super.initState();
    _subscription =
        CoinBattleService.watchBattle(widget.battleId).listen(_onBattle);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onBattle(Map<String, dynamic>? battle) {
    if (!mounted || battle == null) return;

    setState(() => _battle = battle);

    if (battle['status'] == 'active' &&
        battle['player_a_choice'] != null &&
        battle['player_b_choice'] != null) {
      CoinBattleService.resolveIfReady(battle);
    }

    if (battle['status'] == 'resolved' && !_resultShown) {
      _resultShown = true;
      _showResult(battle);
    }
  }

  Future<void> _showResult(Map<String, dynamic> battle) async {
    final result = battle['result'] as String?;
    final isDraw = result == 'draw';
    final won = _isPlayerA ? result == 'player_a' : result == 'player_b';
    final wager = (battle['wager'] as num?)?.toInt() ?? 0;

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BattleResultScreen(
          won: won,
          isDraw: isDraw,
          wager: wager,
        ),
      ),
    );
  }

  Future<void> _submit(int index) async {
    if (_submitting || _myStoredChoice != null) return;

    setState(() {
      _myChoice = index;
      _submitting = true;
      _error = null;
    });

    try {
      await CoinBattleService.submitAnswer(
        battleId: widget.battleId,
        isPlayerA: _isPlayerA,
        choice: index,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not submit your answer. Try again.';
        _myChoice = null;
      });
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
        iconTheme: IconThemeData(color: AppColors.textPrimary(dark)),
        title: Text(
          'Coin Battle',
          style: TextStyle(color: AppColors.textPrimary(dark)),
        ),
      ),
      body: _battle == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.cyan),
            )
          : _buildContent(dark),
    );
  }

  Widget _buildContent(bool dark) {
    final wager = (_battle?['wager'] as num?)?.toInt() ?? 0;
    final alreadyAnswered = _myStoredChoice != null;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.cyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Wager: $wager coins',
              style: const TextStyle(
                color: AppColors.cyan,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'What does this word mean?',
            style: TextStyle(
              color: AppColors.textSecondary(dark),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _myWord,
            style: TextStyle(
              color: AppColors.textPrimary(dark),
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 24),
          ..._myOptions.asMap().entries.map((entry) {
            final index = entry.key;
            final text = entry.value;
            final selected = _myChoice == index || _myStoredChoice == index;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: alreadyAnswered ? null : () => _submit(index),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.cyan.withOpacity(0.14)
                        : AppColors.card(dark),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? AppColors.cyan
                          : AppColors.border(dark),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: AppColors.textPrimary(dark),
                      fontSize: 15,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: AppColors.wrongText(dark), fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          if (alreadyAnswered)
            Center(
              child: Column(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: AppColors.cyan,
                      strokeWidth: 2.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _opponentAnswered
                        ? 'Both answered — resolving…'
                        : 'Waiting for your opponent…',
                    style: TextStyle(
                      color: AppColors.textSecondary(dark),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
