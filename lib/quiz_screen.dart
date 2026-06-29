import 'dart:io';
import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'app_theme.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override
  _QuizScreenState createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _currentQuestion = 0, _score = 0;
  bool _answered = false, _loading = true;
  int? _selectedIndex;
  List<Map<String, dynamic>> _questions = [];

  final List<Map<String, dynamic>> _staticQuestions = [
    {'emoji': '📖', 'image_path': null, 'correct': 'Book',
      'options': ['Book', 'Notebook', 'Magazine', 'Folder'], 'definition': 'A set of written or printed pages'},
    {'emoji': '🪑', 'image_path': null, 'correct': 'Chair',
      'options': ['Table', 'Chair', 'Desk', 'Stool'], 'definition': 'A seat with a back and legs'},
    {'emoji': '🍶', 'image_path': null, 'correct': 'Bottle',
      'options': ['Bottle', 'Cup', 'Bowl', 'Jar'], 'definition': 'A container for liquids'},
    {'emoji': '🖥️', 'image_path': null, 'correct': 'Monitor',
      'options': ['Television', 'Monitor', 'Projector', 'Screen'], 'definition': 'A display screen for a computer'},
    {'emoji': '🌿', 'image_path': null, 'correct': 'Plant',
      'options': ['Flower', 'Tree', 'Plant', 'Grass'], 'definition': 'A living organism that grows in soil'},
  ];

  String _wordToEmoji(String word) {
    const map = {
      'book': '📖', 'desk': '🪑', 'cup': '☕', 'chair': '🪑', 'phone': '📱',
      'pen': '✏️', 'laptop': '💻', 'bottle': '🍶', 'bag': '👜', 'clock': '🕐',
      'plant': '🌿', 'monitor': '🖥️', 'keyboard': '⌨️', 'mouse': '🖱️',
      'lamp': '💡', 'window': '🪟', 'door': '🚪', 'table': '🪵',
    };
    return map[word.toLowerCase()] ?? '🔍';
  }

  List<String> _generateOptions(String correct, List<String> allWords) {
    final pool = <String>[
      'Book', 'Chair', 'Cup', 'Desk', 'Phone', 'Pen', 'Laptop', 'Bottle',
      'Bag', 'Clock', 'Plant', 'Monitor', 'Keyboard', 'Mouse', 'Lamp',
    ].where((w) => w.toLowerCase() != correct.toLowerCase()).toList();
    for (final w in allWords) {
      final cap = _capitalize(w);
      if (w.toLowerCase() != correct.toLowerCase() && !pool.contains(cap)) pool.add(cap);
    }
    pool.shuffle();
    return [...pool.take(3), _capitalize(correct)]..shuffle();
  }

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  void initState() { super.initState(); _loadQuestions(); }

  Future<void> _loadQuestions() async {
    setState(() => _loading = true);
    final saved = await DatabaseService.getSavedWords();
    if (saved.isNotEmpty) {
      final allWords = saved.map((w) => w['word'] as String).toList();
      saved.shuffle();
      _questions = saved.take(5).map((w) {
        final word = w['word'] as String;
        final imgPath = w['image_path'] as String?;
        return {
          'emoji': _wordToEmoji(word),
          'image_path': (imgPath != null && imgPath.isNotEmpty) ? imgPath : null,
          'correct': _capitalize(word),
          'options': _generateOptions(word, allWords),
          'definition': w['definition'] ?? '',
        };
      }).toList();
    } else {
      _questions = List.from(_staticQuestions);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _answer(int index) {
    if (_answered) return;
    setState(() {
      _answered = true; _selectedIndex = index;
      if ((_questions[_currentQuestion]['options'] as List)[index] ==
          _questions[_currentQuestion]['correct']) _score++;
    });
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) _next();
    });
  }

  void _next() {
    if (_currentQuestion < _questions.length - 1) {
      setState(() { _currentQuestion++; _answered = false; _selectedIndex = null; });
    } else {
      _showResult();
    }
  }

  void _showResult() {
    final dark = ThemeProvider.isDark(context);
    showDialog(
      context: context, barrierDismissible: false, barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: AppColors.card(dark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Quiz Complete!', style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary(dark))),
            const SizedBox(height: 8),
            Text('$_score / ${_questions.length}', style: const TextStyle(
              fontSize: 40, fontWeight: FontWeight.w900, color: AppColors.cyan)),
            const SizedBox(height: 6),
            Text(_score == _questions.length ? 'Perfect score! 🔥' : 'Keep scanning to learn more!',
              style: TextStyle(color: AppColors.textSecondary(dark))),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () { Navigator.pop(context); Navigator.pop(context); },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.border(dark)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text('Exit', style: TextStyle(color: AppColors.textPrimary(dark))),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() { _currentQuestion = 0; _score = 0; _answered = false; _selectedIndex = null; });
                  _loadQuestions();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan, foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w700)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildQuestionVisual(Map<String, dynamic> question, bool dark) {
    final imagePath = question['image_path'] as String?;
    if (_answered) {
      if (imagePath != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(File(imagePath), fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Text(question['emoji'] as String,
              style: const TextStyle(fontSize: 64))));
      }
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(question['emoji'] as String, style: const TextStyle(fontSize: 64)),
        Text(question['correct'] as String, style: const TextStyle(
          color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
      ]);
    }
    if (imagePath != null) {
      return Stack(fit: StackFit.expand, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(File(imagePath), fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.55), colorBlendMode: BlendMode.darken,
            errorBuilder: (_, __, ___) => const SizedBox())),
        const Center(child: Text('?', style: TextStyle(
          fontSize: 64, color: AppColors.cyan, fontWeight: FontWeight.w900))),
      ]);
    }
    return const Center(child: Text('?', style: TextStyle(
      fontSize: 64, color: AppColors.cyan, fontWeight: FontWeight.w900)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    if (_loading) return Scaffold(backgroundColor: AppColors.bg(dark),
      body: const Center(child: CircularProgressIndicator(color: AppColors.cyan)));

    final question = _questions[_currentQuestion];
    final total = _questions.length;
    final letters = ['A', 'B', 'C', 'D'];

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.card(dark),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border(dark))),
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppColors.textPrimary(dark), size: 18)),
              ),
              const Spacer(),
              Text('${_currentQuestion + 1} / $total', style: TextStyle(
                color: AppColors.textSecondary(dark), fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              const SizedBox(width: 40),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_currentQuestion + 1) / total,
                backgroundColor: AppColors.secondary(dark),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
                minHeight: 5),
            ),
          ),
          const SizedBox(height: 32),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 48),
            height: 160,
            decoration: BoxDecoration(
              color: AppColors.card(dark), borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _answered
                  ? ((_questions[_currentQuestion]['options'] as List)[_selectedIndex ?? 0] ==
                      _questions[_currentQuestion]['correct'] ? Colors.green : Colors.redAccent)
                  : AppColors.cyan,
                width: 2),
              boxShadow: [BoxShadow(color: AppColors.shadow(dark), blurRadius: 8)],
            ),
            child: _buildQuestionVisual(question, dark),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('What is this object called?', style: TextStyle(
              color: AppColors.textPrimary(dark), fontSize: 20, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: (question['options'] as List).length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, index) {
                final options = question['options'] as List;
                final option = options[index] as String;
                final isCorrect = option == question['correct'];
                final isSelected = index == _selectedIndex;

                Color borderColor = AppColors.border(dark);
                Color bgColor = AppColors.card(dark);
                Color textColor = AppColors.textPrimary(dark);
                Widget? trailingIcon;

                if (_answered) {
                  if (isCorrect) {
                    borderColor = Colors.green;
                    bgColor = AppColors.correctGreen(dark);
                    textColor = AppColors.correctText(dark);
                    trailingIcon = Icon(Icons.check_rounded, color: AppColors.correctText(dark), size: 20);
                  } else if (isSelected) {
                    borderColor = Colors.redAccent;
                    bgColor = AppColors.wrongRed(dark);
                    textColor = AppColors.wrongText(dark);
                    trailingIcon = Icon(Icons.close_rounded, color: AppColors.wrongText(dark), size: 20);
                  }
                }

                return GestureDetector(
                  onTap: () => _answer(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: bgColor, borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor, width: 1.5),
                      boxShadow: [BoxShadow(color: AppColors.shadow(dark), blurRadius: 4)]),
                    child: Row(children: [
                      Text('${letters[index]}. ', style: TextStyle(
                        color: textColor, fontSize: 16, fontWeight: FontWeight.w600)),
                      Expanded(child: Text(option, style: TextStyle(
                        color: textColor, fontSize: 16, fontWeight: FontWeight.w600))),
                      if (trailingIcon != null) trailingIcon,
                    ]),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              Text('${_currentQuestion + 1} / $total',
                style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 13)),
              const Spacer(),
              if (_answered && _selectedIndex != null)
                Text(
                  (_questions[_currentQuestion]['options'] as List)[_selectedIndex!] ==
                      _questions[_currentQuestion]['correct'] ? '+10 XP' : '',
                  style: const TextStyle(color: AppColors.cyan, fontSize: 13,
                    fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }
}