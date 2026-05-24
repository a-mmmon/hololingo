import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'firestore_service.dart';

class GobotScreen extends StatefulWidget {
  const GobotScreen({super.key});

  @override
  State<GobotScreen> createState() => _GobotScreenState();
}

class _GobotScreenState extends State<GobotScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Message> _messages = [];
  int _savedWordCount = 48;
  bool _isTyping = false;

  final List<String> _suggestions = [
    'Use "desk" in a sentence',
    'What\'s the difference between cup and mug?',
    'Quiz me on my review words',
  ];

  @override
  void initState() {
    super.initState();
    _loadWordCount();
  }

  Future<void> _loadWordCount() async {
    final words = await DatabaseService.getSavedWords();
    if (mounted) setState(() => _savedWordCount = words.length);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add(_Message(text: text, isUser: true));
      _isTyping = true;
    });
    _scrollToBottom();

    // Simulate AI response
    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;
    final reply = _generateReply(text);
    setState(() {
      _isTyping = false;
      _messages.add(reply);
    });
    _scrollToBottom();
  }

  _Message _generateReply(String input) {
    final lower = input.toLowerCase();

    if (lower.contains('desk')) {
      return _Message(
        text: 'Here\'s a sentence: ',
        isUser: false,
        highlight: '"She put her notebook on the desk before the meeting."',
        chips: ['More sentences with desk', 'Quiz me on desk'],
      );
    }
    if (lower.contains('cup') && lower.contains('mug')) {
      return _Message(
        text:
            'A cup is smaller and often used for tea or coffee without a handle. A mug is larger with a handle — great for hot drinks.',
        isUser: false,
        vocabTags: ['cup ✓', 'mug — save it?'],
        chips: ['Quiz me on cup vs mug', 'More sentences with mug'],
      );
    }
    if (lower.contains('quiz')) {
      return _Message(
        text:
            'Sure! Let\'s quiz you on your saved words. What does "desk" mean?',
        isUser: false,
        chips: ['Table', 'Chair', 'Shelf', 'Lamp'],
      );
    }
    return _Message(
      text:
          'Great question! I\'m using your $_savedWordCount saved words to help you. Try asking me to use a word in a sentence or explain the difference between two words.',
      isUser: false,
      chips: ['Use "book" in a sentence', 'Quiz me'],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              decoration: BoxDecoration(
                color: AppColors.bg(dark),
                border: Border(
                    bottom: BorderSide(color: AppColors.border(dark))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.cyan.withOpacity(0.4), width: 1.5),
                    ),
                    child: const Icon(Icons.smart_toy_rounded,
                        color: AppColors.cyan, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Holo AI tutor',
                            style: TextStyle(
                                color: AppColors.textPrimary(dark),
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        Text('Using your $_savedWordCount saved words',
                            style: const TextStyle(
                                color: AppColors.cyan, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.secondary(dark),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.menu_rounded,
                        color: AppColors.textSecondary(dark), size: 20),
                  ),
                ],
              ),
            ),

            // ── Messages ────────────────────────────────────────────────
            Expanded(
              child: _messages.isEmpty
                  ? _buildEmptyState(dark)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      itemCount: _messages.length + (_isTyping ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (_isTyping && i == _messages.length) {
                          return _TypingBubble(dark: dark);
                        }
                        return _MessageBubble(
                          message: _messages[i],
                          dark: dark,
                          onChipTap: _sendMessage,
                        );
                      },
                    ),
            ),

            // ── Input ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: AppColors.bg(dark),
                border: Border(top: BorderSide(color: AppColors.border(dark))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.card(dark),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                            color: AppColors.border(dark), width: 1),
                      ),
                      child: TextField(
                        controller: _controller,
                        style: TextStyle(
                            color: AppColors.textPrimary(dark), fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Ask about your words...',
                          hintStyle: TextStyle(
                              color: AppColors.textSecondary(dark),
                              fontSize: 14),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: _sendMessage,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => _sendMessage(_controller.text),
                    child: Container(
                      width: 44, height: 44,
                      decoration: const BoxDecoration(
                        color: AppColors.cyan,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_upward_rounded,
                          color: Colors.black, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool dark) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bot greeting
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.smart_toy_rounded,
                    color: AppColors.cyan, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card(dark),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Hi Nattaya! I know your $_savedWordCount saved words. '
                    'Ask me anything — try using them in sentences or compare similar words.',
                    style: TextStyle(
                        color: AppColors.textPrimary(dark),
                        fontSize: 14,
                        height: 1.5),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          Text('TRY ASKING',
              style: TextStyle(
                  color: AppColors.textSecondary(dark),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),

          ..._suggestions.map((s) => GestureDetector(
                onTap: () => _sendMessage(s),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(28),
                    border:
                        Border.all(color: AppColors.border(dark), width: 1.5),
                  ),
                  child: Text(s,
                      style: TextStyle(
                          color: AppColors.cyan,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                ),
              )),
        ],
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────
class _Message {
  final String text;
  final bool isUser;
  final String? highlight;
  final List<String> chips;
  final List<String> vocabTags;

  _Message({
    required this.text,
    required this.isUser,
    this.highlight,
    this.chips = const [],
    this.vocabTags = const [],
  });
}

// ── Message Bubble ────────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final _Message message;
  final bool dark;
  final void Function(String) onChipTap;

  const _MessageBubble({
    required this.message,
    required this.dark,
    required this.onChipTap,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.cyan,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
          ),
          child: Text(message.text,
              style: const TextStyle(
                  color: Colors.black, fontSize: 14, height: 1.4)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.cyan.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: AppColors.cyan, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card(dark),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Main text with optional highlight
                      if (message.highlight != null) ...[
                        Text(message.text,
                            style: TextStyle(
                                color: AppColors.textSecondary(dark),
                                fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(message.highlight!,
                            style: const TextStyle(
                                color: Color(0xFFFFB300),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.5)),
                        const SizedBox(height: 10),
                        // Play button
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.secondary(dark),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: AppColors.textPrimary(dark), size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Hear "${message.highlight!.split(' ')[2].replaceAll('"', '')}" in the sentence',
                                style: TextStyle(
                                    color: AppColors.textPrimary(dark),
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Text(message.text,
                            style: TextStyle(
                                color: AppColors.textPrimary(dark),
                                fontSize: 14,
                                height: 1.5)),
                      ],

                      // Vocab tags
                      if (message.vocabTags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text('From your vocab:',
                            style: TextStyle(
                                color: AppColors.textSecondary(dark),
                                fontSize: 11)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: message.vocabTags.map((tag) {
                            final isSaved = tag.contains('✓');
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSaved
                                    ? AppColors.cyan.withOpacity(0.15)
                                    : const Color(0xFF7C5CBF).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSaved
                                      ? AppColors.cyan.withOpacity(0.4)
                                      : const Color(0xFF7C5CBF).withOpacity(0.4),
                                ),
                              ),
                              child: Text(tag,
                                  style: TextStyle(
                                      color: isSaved
                                          ? AppColors.cyan
                                          : const Color(0xFF9C6FFF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // Suggestion chips
                if (message.chips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: message.chips.map((chip) {
                      return GestureDetector(
                        onTap: () => onChipTap(chip),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: AppColors.border(dark), width: 1.2),
                          ),
                          child: Text(chip,
                              style: TextStyle(
                                  color: AppColors.textSecondary(dark),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────
class _TypingBubble extends StatefulWidget {
  final bool dark;
  const _TypingBubble({required this.dark});

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.cyan.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: AppColors.cyan, size: 20),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.card(widget.dark),
              borderRadius: BorderRadius.circular(16),
            ),
            child: AnimatedBuilder(
              animation: _anim,
              builder: (_, __) => Row(
                children: List.generate(3, (i) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.cyan.withOpacity(
                          0.3 + 0.7 * (((_anim.value + i * 0.3) % 1.0))),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}