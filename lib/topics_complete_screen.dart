import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'topics_screen.dart';

class TopicCompleteScreen extends StatelessWidget {
  final String topicName;
  final int wordsLearned;
  final int tokensEarned;
  final int xpEarned;

  const TopicCompleteScreen({
    super.key,
    required this.topicName,
    required this.wordsLearned,
    required this.tokensEarned,
    required this.xpEarned,
  });

  @override
  Widget build(BuildContext context) {
    final dark =
        ThemeProvider.isDark(context);

    return Scaffold(
      backgroundColor:
          AppColors.bg(dark),

      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 28,
          ),

          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,

            children: [
              const Spacer(),

              const Text(
                '🎉',
                style:
                    TextStyle(fontSize: 72),
              ),

              const SizedBox(height: 20),

              Text(
                '$topicName complete!',
                textAlign:
                    TextAlign.center,

                style: TextStyle(
                  fontSize: 28,
                  fontWeight:
                      FontWeight.w800,
                  color:
                      AppColors
                          .textPrimary(
                    dark,
                  ),
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'You learned all $wordsLearned words in $topicName',
                textAlign:
                    TextAlign.center,

                style: TextStyle(
                  color:
                      AppColors
                          .textSecondary(
                    dark,
                  ),
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 36),

              // ========================================================
              // REWARDS
              // ========================================================

              Row(
                children: [
                  Expanded(
                    child: _RewardBox(
                      color:
                          const Color(
                        0xFFFFB300,
                      ),

                      bg:
                          const Color(
                        0xFF2A2000,
                      ),

                      icon:
                          Icons.toll_rounded,

                      label:
                          '+$tokensEarned Tokens',
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: _RewardBox(
                      color:
                          AppColors.cyan,

                      bg: dark
                          ? const Color(
                              0xFF0D2A2A,
                            )
                          : const Color(
                              0xFFE0FAFA,
                            ),

                      icon:
                          Icons.bolt_rounded,

                      label:
                          '+$xpEarned XP',
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // ========================================================
              // BUTTONS
              // ========================================================

              Row(
                children: [
                  Expanded(
                    child:
                        OutlinedButton(
                      onPressed: () =>
                          Navigator.popUntil(
                        context,
                        (r) => r.isFirst,
                      ),

                      style:
                          OutlinedButton.styleFrom(
                        side: BorderSide(
                          color:
                              AppColors
                                  .border(
                            dark,
                          ),
                        ),

                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical: 16,
                        ),

                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(
                            16,
                          ),
                        ),
                      ),

                      child: Text(
                        'Back to Topics',

                        style: TextStyle(
                          color:
                              AppColors
                                  .textPrimary(
                            dark,
                          ),
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child:
                        ElevatedButton(
                      onPressed: () =>
                          Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const TopicsScreen(),
                        ),
                      ),

                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.cyan,

                        foregroundColor:
                            Colors.black,

                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical: 16,
                        ),

                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(
                            16,
                          ),
                        ),
                      ),

                      child: const Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .center,

                        children: [
                          Text(
                            'Next topic',
                            style:
                                TextStyle(
                              fontWeight:
                                  FontWeight
                                      .w800,
                            ),
                          ),

                          SizedBox(width: 4),

                          Icon(
                            Icons
                                .chevron_right_rounded,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================================================================
// REWARD BOX
// ====================================================================

class _RewardBox extends StatelessWidget {
  final Color color;
  final Color bg;
  final IconData icon;
  final String label;

  const _RewardBox({
    required this.color,
    required this.bg,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        vertical: 22,
      ),

      decoration: BoxDecoration(
        color: bg,

        borderRadius:
            BorderRadius.circular(18),

        border: Border.all(
          color:
              color.withOpacity(0.4),
          width: 1.5,
        ),
      ),

      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 30,
          ),

          const SizedBox(height: 8),

          Text(
            label,

            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}