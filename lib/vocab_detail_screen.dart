import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'app_theme.dart';
import 'firestore_service.dart';
import 'quiz_screen.dart';

class VocabDetailScreen extends StatefulWidget {
  final String word;
  final String phonetic;
  final String definition;
  final String example;
  final String? imagePath;
  final String? imageUrl;

  const VocabDetailScreen({
    super.key,
    required this.word,
    required this.phonetic,
    required this.definition,
    required this.example,
    this.imagePath,
    this.imageUrl,
  });

  @override
  State<VocabDetailScreen> createState() => _VocabDetailScreenState();
}

class _VocabDetailScreenState extends State<VocabDetailScreen> {
  final FlutterTts _tts = FlutterTts();
  bool _saved = false;
  bool _saving = false;
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('Vocab TTS init error: $e');
    }
  }

  Future<void> _speak() async {
    if (widget.word.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      final result = await _tts.speak(widget.word.trim());
      debugPrint('Vocab TTS result: $result');
    } catch (e) {
      debugPrint('Vocab TTS error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not play pronunciation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await FirestoreService.saveWord({
      'word': widget.word,
      'phonetic': widget.phonetic,
      'definition': widget.definition,
      'example': widget.example,
      'image_path': widget.imagePath ?? '',
      'image_url': widget.imageUrl ?? '',
      'note': _noteController.text,
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('"${widget.word}" saved!'),
      backgroundColor: Colors.green[700],
      duration: const Duration(seconds: 2),
    ));
  }

  Widget _buildWordImage() {
    final imageUrl = widget.imageUrl?.trim() ?? '';
    final imagePath = widget.imagePath?.trim() ?? '';

    if (imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        width: 220,
        height: 220,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          if (imagePath.isNotEmpty) {
            return Image.file(
              File(imagePath),
              width: 220,
              height: 220,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _imagePlaceholder(),
            );
          }
          return _imagePlaceholder();
        },
      );
    }

    if (imagePath.isNotEmpty) {
      return Image.file(
        File(imagePath),
        width: 220,
        height: 220,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _imagePlaceholder(),
      );
    }

    return _imagePlaceholder();
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 220,
      height: 220,
      color: AppColors.card(ThemeProvider.isDark(context)),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.cyan,
        size: 42,
      ),
    );
  }

  @override
  void dispose() {
    _tts.stop();
    _noteController.dispose();
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card(dark),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border(dark)),
                      ),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppColors.textPrimary(dark), size: 18),
                    ),
                  ),
                  const Spacer(),
                  Text('Word detail',
                      style: TextStyle(
                          color: AppColors.textPrimary(dark),
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_saved)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                            SizedBox(width: 6),
                            Text('Saved',
                                style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    Text(widget.word,
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary(dark),
                            letterSpacing: -0.5)),
                    if (widget.phonetic.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(widget.phonetic,
                            style: const TextStyle(
                                color: AppColors.cyan,
                                fontSize: 15,
                                fontStyle: FontStyle.italic)),
                      ),
                    if ((widget.imageUrl ?? '').isNotEmpty ||
                        (widget.imagePath ?? '').isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: _buildWordImage(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(widget.definition,
                        style: TextStyle(
                            color: AppColors.textPrimary(dark), fontSize: 16, height: 1.5)),
                    if (widget.example.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 3,
                              height: 48,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                  color: AppColors.cyan, borderRadius: BorderRadius.circular(2)),
                            ),
                            Expanded(
                              child: Text('"${widget.example}"',
                                  style: TextStyle(
                                      color: AppColors.textSecondary(dark),
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic,
                                      height: 1.5)),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _noteController,
                      maxLength: 150,
                      style: TextStyle(color: AppColors.textPrimary(dark), fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Your note',
                        hintStyle: TextStyle(color: AppColors.textSecondary(dark)),
                        filled: true,
                        fillColor: AppColors.card(dark),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.border(dark)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _speak,
                            icon: const Icon(Icons.play_arrow_rounded, color: AppColors.cyan),
                            label: const Text('Listen', style: TextStyle(color: AppColors.cyan)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.cyan, width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.black))
                                : const Icon(Icons.add_rounded, color: Colors.black),
                            label: Text(_saved ? 'Saved' : 'Save',
                                style: const TextStyle(
                                    color: Colors.black, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => const QuizScreen())),
                        icon: Icon(Icons.quiz_rounded, color: AppColors.textPrimary(dark)),
                        label: Text('Quiz me',
                            style: TextStyle(color: AppColors.textPrimary(dark))),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.border(dark)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}