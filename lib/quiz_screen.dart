import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'database_service.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  _QuizScreenState createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _currentQuestion = 0;
  int _score = 0;
  bool _answered = false;
  int? _selectedIndex;
  bool _loading = true;

  List<Map<String, dynamic>> _questions = [];

  // Fallback static questions if DB is empty
  final List<Map<String, dynamic>> _staticQuestions = [
    {
      'emoji': '📖',
      'correct': 'Book',
      'options': ['Book', 'Notebook', 'Magazine', 'Folder'],
      'definition': 'A set of written or printed pages',
    },
    {
      'emoji': '🪑',
      'correct': 'Chair',
      'options': ['Table', 'Chair', 'Desk', 'Stool'],
      'definition': 'A seat with a back and legs',
    },
    {
      'emoji': '🍶',
      'correct': 'Bottle',
      'options': ['Bottle', 'Cup', 'Bowl', 'Jar'],
      'definition': 'A container for liquids',
    },
    {
      'emoji': '🖥️',
      'correct': 'Monitor',
      'options': ['Television', 'Monitor', 'Projector', 'Screen'],
      'definition': 'A display screen for a computer',
    },
    {
      'emoji': '🌿',
      'correct': 'Plant',
      'options': ['Flower', 'Tree', 'Plant', 'Grass'],
      'definition': 'A living organism that grows in soil',
    },
  ];

  // Map common words to emojis
  String _wordToEmoji(String word) {
    const map = {
      'book': '📖', 'desk': '🪑', 'cup': '☕', 'chair': '🪑',
      'phone': '📱', 'pen': '✏️', 'laptop': '💻', 'bottle': '🍶',
      'bag': '👜', 'clock': '🕐', 'plant': '🌿', 'monitor': '🖥️',
      'keyboard': '⌨️', 'mouse': '🖱️', 'lamp': '💡', 'window': '🪟',
      'door': '🚪', 'table': '🪵', 'notebook': '📓', 'pencil': '✏️',
      'glasses': '👓', 'mug': '☕', 'bowl': '🥣', 'fork': '🍴',
      'knife': '🔪', 'spoon': '🥄', 'plate': '🍽️', 'towel': '🛁',
    };
    return map[word.toLowerCase()] ?? '🔍';
  }

  // Generate wrong options from pool
  List<String> _generateOptions(String correct, List<String> allWords) {
    final pool = <String>[
      'Book', 'Chair', 'Cup', 'Desk', 'Phone', 'Pen', 'Laptop',
      'Bottle', 'Bag', 'Clock', 'Plant', 'Monitor', 'Keyboard',
      'Mouse', 'Lamp', 'Window', 'Door', 'Table', 'Notebook',
    ].where((w) => w.toLowerCase() != correct.toLowerCase()).toList();

    pool.shuffle();
    final wrongs = pool.take(3).toList();
    final options = [...wrongs, _capitalize(correct)]..shuffle();
    return options;
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    final saved = await DatabaseService.getSavedWords();
    if (saved.isNotEmpty) {
      final allWords = saved.map((w) => w['word'] as String).toList();
      // Pick up to 5 random words
      saved.shuffle();
      final picked = saved.take(5).toList();
      _questions = picked.map((w) {
        final word = w['word'] as String;
        return {
          'emoji': _wordToEmoji(word),
          'correct': _capitalize(word),
          'options': _generateOptions(word, allWords),
          'definition': w['definition'] ?? '',
        };
      }).toList();
    } else {
      _questions = _staticQuestions;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _answer(int index) {
    if (_answered) return;
    setState(() {
      _answered = true;
      _selectedIndex = index;
      if (_questions[_currentQuestion]['options'][index] ==
          _questions[_currentQuestion]['correct']) {
        _score++;
      }
    });
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) _next();
    });
  }

  void _next() {
    if (_currentQuestion < _questions.length - 1) {
      setState(() {
        _currentQuestion++;
        _answered = false;
        _selectedIndex = null;
      });
    } else {
      _showResult();
    }
  }

  void _showResult() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: AppColors.card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text('Quiz Complete!',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text('$_score / ${_questions.length}',
                  style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: AppColors.cyan)),
              const SizedBox(height: 6),
              Text(
                  _score == _questions.length
                      ? 'Perfect score! 🔥'
                      : 'Keep scanning to learn more!',
                  style:
                      const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Exit',
                          style: TextStyle(
                              color: AppColors.textPrimary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _currentQuestion = 0;
                          _score = 0;
                          _answered = false;
                          _selectedIndex = null;
                        });
                        // Reload fresh random questions
                        setState(() => _loading = true);
                        _loadQuestions();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Try Again',
                          style:
                              TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: const Center(
            child: CircularProgressIndicator(color: AppColors.cyan)),
      );
    }

    final question = _questions[_currentQuestion];
    final total = _questions.length;
    final letters = ['A', 'B', 'C', 'D'];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  const Spacer(),
                  Text('${_currentQuestion + 1} / $total',
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),

            // Progress bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_currentQuestion + 1) / total,
                  backgroundColor: AppColors.card,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.cyan),
                  minHeight: 5,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Image / mystery box
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 48),
              height: 160,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _answered
                      ? (_questions[_currentQuestion]['options'][_selectedIndex ?? 0] ==
                              _questions[_currentQuestion]['correct']
                          ? Colors.green
                          : Colors.redAccent)
                      : AppColors.cyan,
                  width: 2,
                ),
              ),
              child: Center(
                child: _answered
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(question['emoji'] as String,
                              style: const TextStyle(fontSize: 64)),
                          if ((question['definition'] as String).isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                question['correct'] as String,
                                style: const TextStyle(
                                    color: AppColors.cyan,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      )
                    : const Text('?',
                        style: TextStyle(
                            fontSize: 64,
                            color: AppColors.cyan,
                            fontWeight: FontWeight.w900)),
              ),
            ),

            const SizedBox(height: 28),

            // Question text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: const Text(
                'What is this object called?',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 24),

            // Answer options
            Expanded(
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: (question['options'] as List).length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final options = question['options'] as List;
                  final option = options[index] as String;
                  final isCorrect = option == question['correct'];
                  final isSelected = index == _selectedIndex;

                  Color borderColor = Colors.white12;
                  Color bgColor = AppColors.card;
                  Color textColor = AppColors.textPrimary;
                  Widget? trailingIcon;

                  if (_answered) {
                    if (isCorrect) {
                      borderColor = Colors.green;
                      bgColor = AppColors.correctGreen;
                      textColor = Colors.greenAccent;
                      trailingIcon = const Icon(Icons.check_rounded,
                          color: Colors.greenAccent, size: 20);
                    } else if (isSelected) {
                      borderColor = Colors.redAccent;
                      bgColor = AppColors.wrongRed;
                      textColor = Colors.redAccent;
                      trailingIcon = const Icon(Icons.close_rounded,
                          color: Colors.redAccent, size: 20);
                    }
                  }

                  return GestureDetector(
                    onTap: () => _answer(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: borderColor, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Text('${letters[index]}. ',
                              style: TextStyle(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                          Expanded(
                            child: Text(option,
                                style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                          ),
                          ?trailingIcon,
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // XP footer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Text('${_currentQuestion + 1} / $total',
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13)),
                  const Spacer(),
                  if (_answered && _selectedIndex != null)
                    Text(
                      (_questions[_currentQuestion]['options']
                                  as List)[_selectedIndex!] ==
                              _questions[_currentQuestion]['correct']
                          ? '+10 XP'
                          : '',
                      style: const TextStyle(
                          color: AppColors.cyan,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),

            
          ],
        ),
      ),
    );
  }
}