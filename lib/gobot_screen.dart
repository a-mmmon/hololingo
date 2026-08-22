import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_ai/firebase_ai.dart';
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
  List<String> _savedWords = [];
  bool _isTyping = false;
  bool _loadingWords = true;
  String? _initError;

  ChatSession? _chat;

  final List<String> _suggestions = [
    'Use one of my words in a sentence',
    'Quiz me on my saved words',
    'Explain the difference between two of my words',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final words = await DatabaseService.getSavedWords();
      _savedWords = words
          .map((w) => (w['word'] ?? '').toString())
          .where((w) => w.isNotEmpty)
          .toList();

      final model = FirebaseAI.googleAI().generativeModel(
        model: 'gemini-2.5-flash',
        systemInstruction: Content.system(
          'You are Holo AI tutor, a friendly language-learning chatbot '
          'inside the HoloLingo app. The user has saved these vocabulary '
          'words: ${_savedWords.isEmpty ? "(no words saved yet)" : _savedWords.join(", ")}. '
          'Use ONLY these saved words when creating example sentences, quiz '
          'questions, or comparisons — do not invent vocabulary they have '
          'not saved. If they ask something unrelated to their words, '
          'answer briefly and steer them back to practicing their saved '
          'words. Keep replies short (2-4 sentences), warm, and '
          'encouraging. When quizzing, ask one question at a time and wait '
          'for their answer before moving on.',
        ),
      );
      _chat = model.startChat();
    } catch (e) {
      _initError = e.toString();
    }
    if (mounted) setState(() => _loadingWords = false);
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
    if (text.trim().isEmpty || _chat == null) return;
    _controller.clear();

    setState(() {
      _messages.add(_Message(text: text, isUser: true));
      _isTyping = true;
    });
    _scrollToBottom();
    unawaited(DatabaseService.saveChatMessage(role: 'user', content: text));

    try {
      final response = await _chat!.sendMessage(Content.text(text));
      final reply = (response.text?.trim().isNotEmpty ?? false)
          ? response.text!.trim()
          : "Sorry, I couldn't come up with a reply — try asking again.";
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(_Message(text: reply, isUser: false));
      });
      unawaited(
          DatabaseService.saveChatMessage(role: 'assistant', content: reply));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(_Message(
          text: 'Something went wrong reaching the AI: $e',
          isUser: false,
        ));
      });
    }
    _scrollToBottom();
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
                      color: AppColors.cyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.cyan.withValues(alpha: 0.4),
                          width: 1.5),
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
                        Text(
                            _loadingWords
                                ? 'Loading your words...'
                                : 'Using your ${_savedWords.length} saved words',
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
              child: _initError != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Couldn\'t start the AI tutor: $_initError',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    )
                  : _messages.isEmpty
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
                        enabled: !_loadingWords && _initError == null,
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
                    onTap: (_loadingWords || _initError != null)
                        ? null
                        : () => _sendMessage(_controller.text),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.15),
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
                    _loadingWords
                        ? 'Loading your saved words...'
                        : (_savedWords.isEmpty
                            ? "You haven't saved any words yet — save some first, then come back and I'll quiz you on them!"
                            : 'Hi! I know your ${_savedWords.length} saved words. '
                                'Ask me anything — try using them in sentences or compare similar words.'),
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
          if (!_loadingWords && _savedWords.isNotEmpty) ...[
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
                      border: Border.all(
                          color: AppColors.border(dark), width: 1.5),
                    ),
                    child: Text(s,
                        style: TextStyle(
                            color: AppColors.cyan,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────
class _Message {
  final String text;
  final bool isUser;

  _Message({required this.text, required this.isUser});
}

// ── Message Bubble ────────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final _Message message;
  final bool dark;

  const _MessageBubble({required this.message, required this.dark});

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
              color: AppColors.cyan.withValues(alpha: 0.15),
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
              child: Text(message.text,
                  style: TextStyle(
                      color: AppColors.textPrimary(dark),
                      fontSize: 14,
                      height: 1.5)),
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
              color: AppColors.cyan.withValues(alpha: 0.15),
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
                      color: AppColors.cyan.withValues(
                          alpha: 0.3 + 0.7 * (((_anim.value + i * 0.3) % 1.0))),
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