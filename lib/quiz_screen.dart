import 'dart:math';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'firestore_service.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

enum _QuizDirection { engToThai, thaiToEng }

class _QuizQuestion {
  final _QuizDirection direction;
  final String prompt;
  final String correctAnswer;
  final List<String> options;

  const _QuizQuestion({
    required this.direction,
    required this.prompt,
    required this.correctAnswer,
    required this.options,
  });
}

class _QuizScreenState extends State<QuizScreen> {
  final Random _random = Random();
  List<_QuizQuestion> _questions = [];
  int _index = 0;
  int _score = 0;
  String? _selected;
  bool _loading = true;
  bool _finished = false;

  // Thai translations for words the app can detect/save. Only words in
  // here are eligible for quiz questions.
  static const Map<String, String> _thaiDictionary = {
    'book': 'หนังสือ',
    'bottle': 'ขวด',
    'chair': 'เก้าอี้',
    'laptop': 'แล็ปท็อป',
    'cell phone': 'โทรศัพท์มือถือ',
    'phone': 'โทรศัพท์',
    'clock': 'นาฬิกา',
    'remote': 'รีโมต',
    'vase': 'แจกัน',
    'scissors': 'กรรไกร',
    'cup': 'ถ้วย',
    'bed': 'เตียง',
    'plant': 'ต้นไม้',
    'flower': 'ดอกไม้',
    'table': 'โต๊ะ',
    'desk': 'โต๊ะทำงาน',
    'pen': 'ปากกา',
    'pencil': 'ดินสอ',
    'suitcase': 'กระเป๋าเดินทาง',
    'bag': 'กระเป๋า',
    'backpack': 'กระเป๋าเป้',
    'keyboard': 'แป้นพิมพ์',
    'mouse': 'เมาส์',
    'monitor': 'จอภาพ',
    'lamp': 'โคมไฟ',
    'shoe': 'รองเท้า',
    'umbrella': 'ร่ม',
    'bowl': 'ชาม',
    'car': 'รถยนต์',
    'dog': 'สุนัข',
    'cat': 'แมว',
    'bird': 'นก',
    'horse': 'ม้า',
    'sheep': 'แกะ',
    'cow': 'วัว',
    'elephant': 'ช้าง',
    'bear': 'หมี',
    'zebra': 'ม้าลาย',
    'giraffe': 'ยีราฟ',
    'couch': 'โซฟา',
    'dining table': 'โต๊ะรับประทานอาหาร',
    'bench': 'ม้านั่ง',
    'apple': 'แอปเปิล',
    'banana': 'กล้วย',
    'orange': 'ส้ม',
    'pizza': 'พิซซ่า',
    'cake': 'เค้ก',
    'sandwich': 'แซนด์วิช',
    'hot dog': 'ฮอตดอก',
    'broccoli': 'บรอกโคลี',
    'carrot': 'แครอท',
    'donut': 'โดนัท',
    'bicycle': 'จักรยาน',
    'motorcycle': 'รถจักรยานยนต์',
    'airplane': 'เครื่องบิน',
    'bus': 'รถบัส',
    'train': 'รถไฟ',
    'truck': 'รถบรรทุก',
    'boat': 'เรือ',
    'watch': 'นาฬิกาข้อมือ',
    'jacket': 'แจ็คเก็ต',
    'sunglasses': 'แว่นกันแดด',
    'tissue': 'ทิชชู่',
    'toothbrush': 'แปรงสีฟัน',
    'laptop charger': 'ที่ชาร์จแล็ปท็อป',
    'charger': 'ที่ชาร์จ',
    'usb': 'ยูเอสบี',
    'sensor': 'เซนเซอร์',
    'camera': 'กล้อง',
    'calculator': 'เครื่องคิดเลข',
  };

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _loadQuiz() async {
    try {
      final words = await FirestoreService.getSavedWords();
      final saved = words
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => (e['word'] ?? '').toString().trim().isNotEmpty)
          .toList();

      // Saved words that have a known Thai translation.
      final translatableKeys = saved
          .map((e) => e['word'].toString().trim().toLowerCase())
          .where((key) => _thaiDictionary.containsKey(key))
          .toSet();

      // Pad with dictionary words the user hasn't saved yet, so there's
      // still a full quiz even with few saved+translated words.
      final fillerKeys = _thaiDictionary.keys
          .where((k) => !translatableKeys.contains(k))
          .toList()
        ..shuffle(_random);

      final pool = [...translatableKeys, ...fillerKeys];
      pool.shuffle(_random);

      final count = min(5, pool.length);
      final questions = <_QuizQuestion>[];

      for (int i = 0; i < count; i++) {
        final key = pool[i];
        final thai = _thaiDictionary[key]!;
        final englishWord = _capitalize(key);

        final direction = _random.nextBool()
            ? _QuizDirection.engToThai
            : _QuizDirection.thaiToEng;

        final otherKeys =
            _thaiDictionary.keys.where((k) => k != key).toList()
              ..shuffle(_random);

        late final String prompt;
        late final String correctAnswer;
        late final List<String> options;

        if (direction == _QuizDirection.engToThai) {
          prompt = englishWord;
          correctAnswer = thai;
          options = [
            thai,
            ...otherKeys.take(3).map((k) => _thaiDictionary[k]!),
          ];
        } else {
          prompt = thai;
          correctAnswer = englishWord;
          options = [
            englishWord,
            ...otherKeys.take(3).map((k) => _capitalize(k)),
          ];
        }

        options.shuffle(_random);

        questions.add(_QuizQuestion(
          direction: direction,
          prompt: prompt,
          correctAnswer: correctAnswer,
          options: options,
        ));
      }

      if (!mounted) return;
      setState(() {
        _questions = questions;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Quiz load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _answer(String option) {
    if (_selected != null || _finished || _questions.isEmpty) return;

    final correct = _questions[_index].correctAnswer;
    setState(() {
      _selected = option;
      if (option == correct) _score++;
    });
  }

  void _next() {
    if (_selected == null) return;

    if (_index + 1 >= _questions.length) {
      setState(() => _finished = true);
      return;
    }

    setState(() {
      _index++;
      _selected = null;
    });
  }

  void _restart() {
    setState(() {
      _loading = true;
      _finished = false;
      _index = 0;
      _score = 0;
      _selected = null;
    });
    _loadQuiz();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bg(dark),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.cyan),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.bg(dark),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.quiz_rounded, color: AppColors.cyan, size: 60),
                  const SizedBox(height: 18),
                  Text(
                    'No quiz words yet',
                    style: TextStyle(
                      color: AppColors.textPrimary(dark),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan and save some objects first.',
                    style: TextStyle(color: AppColors.textSecondary(dark)),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_finished) return _buildResult(dark);

    final question = _questions[_index];
    final instruction = question.direction == _QuizDirection.engToThai
        ? 'Choose the correct Thai translation'
        : 'Choose the correct English word';

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textPrimary(dark),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_index + 1} / ${_questions.length}',
                    style: TextStyle(
                      color: AppColors.textSecondary(dark),
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 7,
                  value: (_index + 1) / _questions.length,
                  backgroundColor: AppColors.border(dark),
                  valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 28,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.card(dark),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.cyan, width: 2),
                      ),
                      child: Column(
                        children: [
                          Text(
                            question.prompt,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textPrimary(dark),
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            instruction,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary(dark),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ...question.options.map(
                      (option) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AnswerButton(
                          text: option,
                          dark: dark,
                          selected: _selected == option,
                          correct: option == question.correctAnswer,
                          answered: _selected != null,
                          onTap: () => _answer(option),
                        ),
                      ),
                    ),
                    if (_selected != null) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _index + 1 == _questions.length ? 'Finish' : 'Next',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(bool dark) {
    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events_rounded, color: AppColors.cyan, size: 80),
                const SizedBox(height: 18),
                Text(
                  'Quiz complete!',
                  style: TextStyle(
                    color: AppColors.textPrimary(dark),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_score / ${_questions.length} correct',
                  style: TextStyle(
                    color: AppColors.textSecondary(dark),
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _restart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('Quiz again'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  final String text;
  final bool dark;
  final bool selected;
  final bool correct;
  final bool answered;
  final VoidCallback onTap;

  const _AnswerButton({
    required this.text,
    required this.dark,
    required this.selected,
    required this.correct,
    required this.answered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color border = AppColors.border(dark);
    Color background = AppColors.card(dark);

    if (answered && correct) {
      border = Colors.greenAccent;
      background = Colors.green.withValues(alpha: 0.16);
    } else if (selected) {
      border = Colors.redAccent;
      background = Colors.red.withValues(alpha: 0.14);
    }

    return GestureDetector(
      onTap: answered ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: AppColors.textPrimary(dark),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (answered && correct)
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
            if (selected && !correct)
              const Icon(Icons.cancel_rounded, color: Colors.redAccent),
          ],
        ),
      ),
    );
  }
}