import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'app_theme.dart';

class FlashcardScreen extends StatefulWidget {
  final List<Map<String, dynamic>> words;
  const FlashcardScreen({super.key, required this.words});

  @override
  _FlashcardScreenState createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen>
    with SingleTickerProviderStateMixin {
  late List<Map<String, dynamic>> _deck;
  int _currentIndex = 0;
  bool _isRevealed = false;
  bool _isFlipping = false;
  int _knowCount = 0;
  int _reviewCount = 0;

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  final FlutterTts _tts = FlutterTts();

  static const Map<String, String> _thaiMap = {
    'book': 'หนังสือ', 'desk': 'โต๊ะ', 'cup': 'ถ้วย',
    'chair': 'เก้าอี้', 'phone': 'โทรศัพท์', 'pen': 'ปากกา',
    'laptop': 'แล็ปท็อป', 'bottle': 'ขวด', 'bag': 'กระเป๋า',
    'clock': 'นาฬิกา', 'plant': 'ต้นไม้', 'monitor': 'จอมอนิเตอร์',
    'keyboard': 'คีย์บอร์ด', 'mouse': 'เมาส์', 'lamp': 'โคมไฟ',
    'window': 'หน้าต่าง', 'door': 'ประตู', 'table': 'โต๊ะ',
    'notebook': 'สมุดบันทึก', 'pencil': 'ดินสอ', 'mug': 'แก้วมัก',
    'glasses': 'แว่นตา', 'bowl': 'ชาม', 'fork': 'ส้อม',
    'knife': 'มีด', 'spoon': 'ช้อน', 'plate': 'จาน', 'towel': 'ผ้าขนหนู',
  };

  @override
  void initState() {
    super.initState();
    _deck = List.from(widget.words)..shuffle();
    _flipController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400));
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _flipController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _flipCard() async {
    if (_isFlipping) return;
    setState(() => _isFlipping = true);
    if (!_isRevealed) {
      await _flipController.forward();
      setState(() => _isRevealed = true);
    } else {
      await _flipController.reverse();
      setState(() => _isRevealed = false);
    }
    setState(() => _isFlipping = false);
  }

  Future<void> _speak() async {
    final word = _deck[_currentIndex]['word'] ?? '';
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.speak(word);
  }

  void _nextCard(String result) {
    setState(() {
      if (result == 'known') _knowCount++;
      if (result == 'soSo') _reviewCount++;
      if (result == 'again') _deck.add(_deck[_currentIndex]);
      _isRevealed = false;
      _isFlipping = false;
    });
    _flipController.reset();

    if (_currentIndex < _deck.length - 1) {
      setState(() => _currentIndex++);
    } else {
      _showCompletionSheet();
    }
  }

  void _showCompletionSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('Deck complete!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ResultChip(label: 'Known', count: _knowCount, color: Colors.green),
                _ResultChip(label: 'Review', count: _reviewCount, color: const Color(0xFFFFB300)),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () { Navigator.pop(context); Navigator.pop(context); },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Exit', style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _deck = List.from(widget.words)..shuffle();
                        _currentIndex = 0;
                        _knowCount = 0;
                        _reviewCount = 0;
                        _isRevealed = false;
                        _flipController.reset();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Restart', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    final total = _deck.length;
    final leftCount = total - _currentIndex;
    final progress = _currentIndex / total;
    final word = _deck[_currentIndex];
    final wordName = word['word'] ?? '';
    final phonetic = word['phonetic'] ?? '';
    final definition = word['definition'] ?? '';
    final example = word['example'] ?? '';
    final thaiTranslation = _thaiMap[wordName.toLowerCase()] ?? '';

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card(dark), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppColors.textPrimary(dark), size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Flashcards',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary(dark))),
                        Text('English · $total cards',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(dark))),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _deck.shuffle();
                      _currentIndex = 0;
                      _knowCount = 0;
                      _reviewCount = 0;
                      _isRevealed = false;
                      _flipController.reset();
                    }),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card(dark), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.shuffle_rounded, color: AppColors.cyan, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: AppColors.card(dark),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
                        minHeight: 5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${_currentIndex + 1} / $total',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary(dark),
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _CounterChip(label: 'Know $_knowCount', color: Colors.green),
                  const SizedBox(width: 8),
                  _CounterChip(label: 'Review $_reviewCount', color: Colors.redAccent),
                  const SizedBox(width: 8),
                  _CounterChip(label: 'Left $leftCount', color: Colors.white38),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GestureDetector(
                  onTap: _flipCard,
                  child: AnimatedBuilder(
                    animation: _flipAnimation,
                    builder: (context, child) {
                      final angle = _flipAnimation.value * pi;
                      final showFront = angle <= pi / 2;
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(angle),
                        child: showFront
                            ? _CardFront(word: wordName, phonetic: phonetic, onListen: _speak, dark: dark)
                            : Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()..rotateY(pi),
                                child: _CardBack(
                                  word: wordName, phonetic: phonetic,
                                  thaiTranslation: thaiTranslation,
                                  definition: definition, example: example,
                                  onListen: _speak, dark: dark,
                                ),
                              ),
                      );
                    },
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Row(
                children: [
                  Expanded(child: _RatingButton(
                    icon: Icons.close_rounded, label: 'Again',
                    color: Colors.redAccent, bgColor: Colors.red.withOpacity(0.12),
                    onTap: () => _nextCard('again'))),
                  const SizedBox(width: 10),
                  Expanded(child: _RatingButton(
                    icon: Icons.remove_rounded, label: 'So-so',
                    color: const Color(0xFFFFB300), bgColor: const Color(0xFFFFB300).withOpacity(0.1),
                    onTap: () => _nextCard('soSo'))),
                  const SizedBox(width: 10),
                  Expanded(child: _RatingButton(
                    icon: Icons.check_rounded, label: 'Known',
                    color: Colors.greenAccent, bgColor: Colors.green.withOpacity(0.12),
                    onTap: () => _nextCard('known'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  final String word, phonetic;
  final VoidCallback onListen;
  final bool dark;

  const _CardFront({required this.word, required this.phonetic, required this.onListen, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cyan.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.cyan, width: 1.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('English',
                style: TextStyle(fontSize: 12, color: AppColors.cyan, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 20),
          Text(word,
              style: TextStyle(fontSize: 42, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(dark), letterSpacing: -1)),
          if (phonetic.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(phonetic,
                  style: const TextStyle(fontSize: 16, color: AppColors.cyan, fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bg(dark), borderRadius: BorderRadius.circular(20)),
            child: Text('Tap card to reveal',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary(dark))),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onListen,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cyan, width: 1.5),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: AppColors.cyan, size: 20),
                ),
                const SizedBox(width: 8),
                Text('Hear pronunciation',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary(dark))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  final String word, phonetic, thaiTranslation, definition, example;
  final VoidCallback onListen;
  final bool dark;

  const _CardBack({
    required this.word, required this.phonetic, required this.thaiTranslation,
    required this.definition, required this.example, required this.onListen, required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1F10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.25), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(word,
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800,
                      color: Colors.white, letterSpacing: -1)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GestureDetector(
                  onTap: onListen,
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.cyan, width: 1.5),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: AppColors.cyan, size: 18),
                  ),
                ),
              ),
            ],
          ),
          if (phonetic.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(phonetic,
                  style: const TextStyle(fontSize: 14, color: AppColors.cyan, fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 14),
          if (thaiTranslation.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.darkCard.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('THAI', style: TextStyle(fontSize: 10, color: AppColors.cyan,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(thaiTranslation, style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (definition.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.darkCard.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DEFINITION', style: TextStyle(fontSize: 10, color: AppColors.cyan,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(
                    definition.length > 80 ? '${definition.substring(0, 80)}...' : definition,
                    style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (example.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.greenAccent.withOpacity(0.6), width: 3))),
              child: Text('"$example"',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF8A8A9A),
                      fontStyle: FontStyle.italic, height: 1.4)),
            ),
        ],
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color, bgColor;
  final VoidCallback onTap;

  const _RatingButton({
    required this.icon, required this.label,
    required this.color, required this.bgColor, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.5), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _CounterChip extends StatelessWidget {
  final String label;
  final Color color;
  const _CounterChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _ResultChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _ResultChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        children: [
          Text('$count', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}