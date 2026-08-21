import 'package:flutter/material.dart';
import 'app_theme.dart';

class _WordPanel extends StatelessWidget {
  final String word, phonetic, partOfSpeech, definition, example;
  final bool isLoading, isDark;
  final VoidCallback onClose, onListen, onSave, onQuiz, onPlaceAr;
  const _WordPanel(
      {required this.word,
      required this.phonetic,
      required this.partOfSpeech,
      required this.definition,
      required this.example,
      required this.isLoading,
      required this.isDark,
      required this.onClose,
      required this.onListen,
      required this.onSave,
      required this.onQuiz,
      required this.onPlaceAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      decoration: BoxDecoration(
          color: AppColors.card(isDark),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
                color: Colors.black
                    .withValues(alpha: isDark ? 0.4 : 0.1),
                blurRadius: 20,
                offset: const Offset(0, -4))
          ]),
      child: isLoading
          ? const SizedBox(
              height: 120,
              child: Center(
                  child: CircularProgressIndicator(
                      color: AppColors.cyan)))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                  Center(
                      child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                              color: AppColors.border(isDark),
                              borderRadius:
                                  BorderRadius.circular(2)))),
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(word,
                            style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary(isDark),
                                letterSpacing: -0.5)),
                        const SizedBox(width: 10),
                        Padding(
                            padding:
                                const EdgeInsets.only(bottom: 6),
                            child: Text('· $partOfSpeech',
                                style: TextStyle(
                                    color: AppColors.textSecondary(
                                        isDark),
                                    fontSize: 14))),
                        const Spacer(),
                        GestureDetector(
                            onTap: onClose,
                            child: Icon(Icons.close_rounded,
                                color:
                                    AppColors.textSecondary(isDark))),
                      ]),
                  if (phonetic.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(
                            top: 2, bottom: 10),
                        child: Text(phonetic,
                            style: const TextStyle(
                                color: AppColors.cyan,
                                fontSize: 14,
                                fontStyle: FontStyle.italic))),
                  Text(definition,
                      style: TextStyle(
                          color: AppColors.textPrimary(isDark),
                          fontSize: 15,
                          height: 1.5)),
                  if (example.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Container(
                                  width: 3,
                                  height: 48,
                                  margin: const EdgeInsets.only(
                                      right: 10),
                                  decoration: BoxDecoration(
                                      color: AppColors.cyan,
                                      borderRadius:
                                          BorderRadius.circular(2))),
                              Expanded(
                                  child: Text('"$example"',
                                      style: TextStyle(
                                          color: AppColors
                                              .textSecondary(isDark),
                                          fontSize: 13,
                                          fontStyle: FontStyle.italic,
                                          height: 1.5))),
                            ])),
                  const SizedBox(height: 18),
                  Row(children: [
                    _ActionBtn(
                        icon: Icons.play_arrow_rounded,
                        label: 'Listen',
                        onTap: onListen,
                        filled: true,
                        isDark: isDark),
                    const SizedBox(width: 10),
                    _ActionBtn(
                        icon: Icons.add_rounded,
                        label: 'Save',
                        onTap: onSave,
                        isDark: isDark),
                    const SizedBox(width: 10),
                    _ActionBtn(
                        icon: Icons.quiz_rounded,
                        label: 'Quiz me',
                        onTap: onQuiz,
                        isDark: isDark),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: _ActionBtn(
                        icon: Icons.view_in_ar_rounded,
                        label: 'Place in AR',
                        onTap: onPlaceAr,
                        isDark: isDark),
                  ),
                ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled, isDark;
  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.filled = false,
      required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
              color: filled ? AppColors.cyan : Colors.transparent,
              border: Border.all(
                  color: filled
                      ? AppColors.cyan
                      : AppColors.border(isDark),
                  width: 1.5),
              borderRadius: BorderRadius.circular(24)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 16,
                color: filled
                    ? Colors.black
                    : AppColors.textPrimary(isDark)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: filled
                        ? Colors.black
                        : AppColors.textPrimary(isDark))),
          ]),
        ));
  }
}