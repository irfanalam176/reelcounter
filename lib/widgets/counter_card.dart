import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/theme/app_theme.dart';

class CounterCard extends StatelessWidget {
  const CounterCard({
    super.key,
    required this.counter,
    required this.loading,
    this.dailyTarget = 0,
    this.comparisonLabel,
  });

  final BubbleCounter counter;
  final bool loading;
  final int dailyTarget;
  final String? comparisonLabel;

  @override
  Widget build(BuildContext context) {
    final progress = dailyTarget > 0 ? counter.total / dailyTarget : 0.0;
    final progressColor = dailyTarget <= 0
        ? AppColors.muted
        : progress > 1
            ? AppColors.danger
            : progress >= 0.8
                ? AppColors.warning
                : AppColors.accent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "TODAY'S COUNT",
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
                Text(
                  counter.date,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 224,
              height: 224,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (context, animated, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: dailyTarget > 0 ? animated : 0.0,
                          strokeWidth: 12,
                          backgroundColor: AppColors.surfaceLight,
                          color: progressColor,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      child ?? const SizedBox.shrink(),
                    ],
                  );
                },
                child: loading
                    ? const SizedBox(
                        width: 120,
                        height: 120,
                        child: Center(
                          child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 4),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              counter.total.toString(),
                              maxLines: 1,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 68,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'reels watched',
                            style: TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dailyTarget > 0 ? 'Daily limit $dailyTarget' : 'No daily limit',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                if (dailyTarget > 0)
                  Text(
                    '${(progress * 100).round()}% used',
                    style: TextStyle(color: progressColor, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
            if (comparisonLabel != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  comparisonLabel!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
