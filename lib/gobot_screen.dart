import 'package:flutter/material.dart';
import 'package:firebase_ai/firebase_ai.dart';

import 'app_theme.dart';
import 'firestore_service.dart';
import 'premium_paywall.dart';
import 'premium_status.dart';

class GobotScreen extends StatefulWidget {
  const GobotScreen({super.key});

  @override
  State<GobotScreen> createState() => _GobotScreenState();
}

class _GobotMessage {
  final bool fromUser;
  final String text;

  const _GobotMessage({required this.fromUser, required this.text});
}

class _GobotScreenState extends State<GobotScreen> {
  static const String _modelName = 'gemini-3.6-flash';

  static const List<String> _quickPrompts = [
    'Use one of my words in a sentence',
    'Quiz me on my saved words',
    'Give me an easy vocabulary practice',
    'Explain a word I saved simply',
  ];

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<_GobotMessage> _messages = [];

  GenerativeModel? _model;
  List<Map<String, dynamic>> _savedWords = [];
  bool _loading = true;
  bool _sending = false;
  bool _isPremium = false;
  int _usedToday = 0;

  bool get _limitReached =>
      !_isPremium && _usedToday >= FirestoreService.gobotFreeMessagesPerDay;

  @override
  void initState() {
    super.initState();
    _model = FirebaseAI.googleAI().generativeModel(model: _modelName);
    _loadChat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChat() async {
    try {
      final results = await Future.wait([
        FirestoreService.getSavedWords(),
        FirestoreService.getChatHistory(limit: 30),
        FirestoreService.getProfileOrDefault(),
      ]);

      final words = List<Map<String, dynamic>>.from(results[0] as List);
      final history = List<Map<String, String>>.from(results[1] as List);
      final profile = results[2] as Map<String, dynamic>;
      final isPremium = isSubscriptionActive(profile);

      final usedToday = isPremium
          ? 0
          : await FirestoreService.getGobotMessagesUsedToday();

      if (!mounted) return;

      setState(() {
        _savedWords = words;
        _isPremium = isPremium;
        _usedToday = usedToday;
        _messages
          ..clear()
          ..addAll(
            history.map(
              (item) => _GobotMessage(
                fromUser: item['role'] == 'user',
                text: item['content'] ?? '',
              ),
            ),
          );
        _loading = false;
      });

      _scrollToBottom();
    } catch (e) {
      debugPrint('Gobot load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _wordListForPrompt() {
    if (_savedWords.isEmpty) return '(No saved words yet.)';

    return _savedWords.map((word) {
      final name = (word['word'] ?? '').toString();
      final definition = (word['definition'] ?? '').toString();
      return '- $name${definition.isEmpty ? '' : ': $definition'}';
    }).join('\n');
  }

  String _historyForPrompt() {
    if (_messages.isEmpty) return '(No previous conversation.)';

    final recent = _messages.length > 12
        ? _messages.sublist(_messages.length - 12)
        : _messages;

    return recent.map((message) {
      final role = message.fromUser ? 'Student' : 'Tutor';
      return '$role: ${message.text}';
    }).join('\n');
  }

  Future<void> _sendMessage([String? preset]) async {
    if (_sending) return;

    if (_limitReached) {
      await _showLimitReachedDialog();
      return;
    }

    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;

    _controller.clear();

    setState(() {
      _messages.add(_GobotMessage(fromUser: true, text: text));
      _sending = true;
    });
    _scrollToBottom();

    try {
      await FirestoreService.saveChatMessage(
        role: 'user',
        content: text,
      );

      final prompt =
          '''You are Holo, the friendly AI English vocabulary tutor inside HoloLingo.

The student is learning English by scanning real-world objects.
Only use the student's saved words as the vocabulary set when the request refers to "my words" or their saved vocabulary.
Be concise, encouraging, and suitable for a high-school learner.
If the student asks for a sentence, give a natural English sentence and briefly explain it.
If the student asks about a word that is not saved, you may still answer normally, but clearly distinguish it from their saved vocabulary.
Do not claim that you can see an object or image unless one was actually provided.

SAVED WORDS:
${_wordListForPrompt()}

RECENT CONVERSATION:
${_historyForPrompt()}

STUDENT'S NEW MESSAGE:
$text

Answer the student now.''';

      final model = _model;
      if (model == null) {
        throw StateError('AI model is not initialized.');
      }

      final response = await model.generateContent([
        Content.text(prompt),
      ]);

      final answer = response.text?.trim();
      if (answer == null || answer.isEmpty) {
        throw StateError('The AI returned an empty response.');
      }

      await FirestoreService.saveChatMessage(
        role: 'assistant',
        content: answer,
      );

      if (!_isPremium) {
        await FirestoreService.incrementGobotMessagesUsedToday();
      }

      if (!mounted) return;
      setState(() {
        _messages.add(_GobotMessage(fromUser: false, text: answer));
        _sending = false;
        if (!_isPremium) _usedToday++;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Gobot AI error: $e');

      if (!mounted) return;
      setState(() => _sending = false);

      final message = _friendlyAiError(e);
      setState(() {
        _messages.add(_GobotMessage(fromUser: false, text: message));
      });
      _scrollToBottom();
    }
  }

  Future<void> _showLimitReachedDialog() async {
    final dark = ThemeProvider.isDark(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card(dark),
        title: Text(
          'Daily limit reached',
          style: TextStyle(color: AppColors.textPrimary(dark)),
        ),
        content: Text(
          "You've used all ${FirestoreService.gobotFreeMessagesPerDay} "
          'free messages with Holo today. Upgrade to Premium for '
          'unlimited chats, or come back tomorrow.',
          style: TextStyle(color: AppColors.textSecondary(dark)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyan,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await showPremiumPaywall(context);
              await _loadChat();
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  String _friendlyAiError(Object error) {
    final text = error.toString().toLowerCase();

    if (text.contains('not found') ||
        text.contains('no longer available') ||
        text.contains('model')) {
      return 'I could not connect to my AI model. Please make sure the Firebase AI Logic setup is up to date and the Gemini model is enabled for this Firebase project.';
    }

    if (text.contains('permission') || text.contains('unauthorized')) {
      return 'I do not have permission to use the AI service yet. Please check the Firebase AI Logic and App Check configuration.';
    }

    return 'I could not reach the AI right now. Please try again in a moment.';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Holo AI Tutor',
                  style: TextStyle(
                    color: const Color(0xFF7C5CBF),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.cyan,
                      ),
                    )
                  : _buildConversation(dark),
            ),
            if (!_loading) _buildUsageIndicator(dark),
            _buildQuickPrompts(dark),
            const SizedBox(height: 10),
            _buildComposer(dark),
          ],
        ),
      ),
    );
  }

  Widget _buildConversation(bool dark) {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      children: [
        ..._messages.map((message) => _messageBubble(dark, message)),
        if (_sending) _typingBubble(dark),
      ],
    );
  }

  Widget _buildUsageIndicator(bool dark) {
    final remaining =
        (FirestoreService.gobotFreeMessagesPerDay - _usedToday).clamp(
      0,
      FirestoreService.gobotFreeMessagesPerDay,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        _isPremium
            ? 'Unlimited chats · Premium'
            : '$remaining of ${FirestoreService.gobotFreeMessagesPerDay} '
                'free messages left today',
        style: TextStyle(
          color: _isPremium
              ? AppColors.cyan
              : AppColors.textSecondary(dark),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildQuickPrompts(bool dark) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _quickPrompts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final prompt = _quickPrompts[index];
          return GestureDetector(
            onTap: _sending ? null : () => _sendMessage(prompt),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.card(dark),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border(dark)),
              ),
              child: Text(
                prompt,
                style: TextStyle(
                  color: AppColors.textPrimary(dark),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _messageBubble(bool dark, _GobotMessage message) {
    if (message.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 45),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.cyan,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
            ),
          ),
          child: Text(
            message.text,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 16,
              height: 1.35,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.only(right: 12, top: 2),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/gobot.png',
                width: 44,
                height: 44,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: AppColors.card(dark),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: AppColors.textPrimary(dark),
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typingBubble(bool dark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 60, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card(dark),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const SizedBox(
          width: 24,
          height: 18,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: AppColors.cyan,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposer(bool dark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.bg(dark),
        border: Border(
          top: BorderSide(color: AppColors.border(dark)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_sending,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              style: TextStyle(color: AppColors.textPrimary(dark)),
              decoration: InputDecoration(
                hintText: 'Ask about your words...',
                hintStyle: TextStyle(color: AppColors.textSecondary(dark)),
                filled: true,
                fillColor: AppColors.card(dark),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 17,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                  borderSide: BorderSide(color: AppColors.border(dark)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                  borderSide: BorderSide(color: AppColors.border(dark)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                  borderSide: const BorderSide(
                    color: AppColors.cyan,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _sending ? null : () => _sendMessage(),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _sending
                    ? AppColors.cyan.withValues(alpha: 0.45)
                    : AppColors.cyan,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_upward_rounded,
                color: Colors.black,
                size: 31,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
