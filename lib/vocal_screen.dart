import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'app_theme.dart';
import 'database_service.dart';

class VocalScreen extends StatefulWidget {
  const VocalScreen({super.key});

  @override
  _VocalScreenState createState() => _VocalScreenState();
}

class _VocalScreenState extends State<VocalScreen> {
  final FlutterTts _tts = FlutterTts();
  List<Map<String, dynamic>> _words = [];
  bool _loading = true;
  int? _speakingIndex;
  double _speechRate = 0.5;

  @override
  void initState() {
    super.initState();
    _loadWords();
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speakingIndex = null);
    });
  }

  Future<void> _loadWords() async {
    final words = await DatabaseService.getSavedWords();
    if (mounted) {
      setState(() {
        _words = words;
        _loading = false;
      });
    }
  }

  Future<void> _speak(String word, int index) async {
    if (_speakingIndex == index) {
      await _tts.stop();
      setState(() => _speakingIndex = null);
      return;
    }
    setState(() => _speakingIndex = index);
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(_speechRate);
    await _tts.speak(word);
  }

  Future<void> _speakSlow(String word, int index) async {
    setState(() => _speakingIndex = index);
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.3);
    await _tts.speak(word);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pronunciation',
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary(dark), letterSpacing: -0.5)),
                      Text('Practice saying your words',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary(dark))),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      setState(() => _loading = true);
                      _loadWords();
                    },
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card(dark),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.refresh_rounded, color: AppColors.cyan, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card(dark),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.speed_rounded, color: AppColors.cyan, size: 18),
                        const SizedBox(width: 8),
                        Text('Speech speed',
                            style: TextStyle(
                                color: AppColors.textPrimary(dark),
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(
                          _speechRate <= 0.3 ? 'Slow' : _speechRate <= 0.5 ? 'Normal' : 'Fast',
                          style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: AppColors.cyan,
                        inactiveTrackColor: AppColors.bg(dark),
                        thumbColor: AppColors.cyan,
                        overlayColor: AppColors.cyan.withOpacity(0.2),
                      ),
                      child: Slider(
                        value: _speechRate,
                        min: 0.2, max: 0.9, divisions: 7,
                        onChanged: (v) => setState(() => _speechRate = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                  : _words.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.record_voice_over_rounded, size: 64, color: Colors.white24),
                              const SizedBox(height: 16),
                              Text('No words yet!\nScan objects to build your vocab.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 15)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemCount: _words.length,
                          itemBuilder: (context, index) {
                            final word = _words[index];
                            final name = word['word'] ?? '';
                            final phonetic = word['phonetic'] ?? '';
                            final definition = word['definition'] ?? '';
                            final isSpeaking = _speakingIndex == index;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSpeaking
                                    ? AppColors.cyan.withOpacity(0.1)
                                    : AppColors.card(dark),
                                borderRadius: BorderRadius.circular(16),
                                border: isSpeaking
                                    ? Border.all(color: AppColors.cyan, width: 1.5)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            style: TextStyle(
                                                fontSize: 20, fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary(dark))),
                                        if (phonetic.isNotEmpty)
                                          Text(phonetic,
                                              style: const TextStyle(
                                                  fontSize: 13, color: AppColors.cyan,
                                                  fontStyle: FontStyle.italic)),
                                        if (definition.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              definition.length > 60
                                                  ? '${definition.substring(0, 60)}...'
                                                  : definition,
                                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary(dark)),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: () => _speakSlow(name, index),
                                    child: Container(
                                      width: 40, height: 40,
                                      decoration: BoxDecoration(
                                        color: AppColors.bg(dark),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppColors.border(dark)),
                                      ),
                                      child: Icon(Icons.slow_motion_video_rounded,
                                          color: AppColors.textSecondary(dark), size: 18),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _speak(name, index),
                                    child: Container(
                                      width: 48, height: 48,
                                      decoration: BoxDecoration(
                                        color: isSpeaking ? AppColors.cyan : AppColors.cyan.withOpacity(0.15),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppColors.cyan, width: 1.5),
                                      ),
                                      child: Icon(
                                        isSpeaking ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                        color: isSpeaking ? Colors.black : AppColors.cyan,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}