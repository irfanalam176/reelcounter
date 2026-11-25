import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/theme/app_theme.dart';

class CounterCard extends StatelessWidget {
  const CounterCard({
    super.key,
    required this.counter,
    required this.loading,
    this.dailyTarget = 0,
  });

  final BubbleCounter counter;
  final bool loading;
  final int dailyTarget;

  @override
  Widget build(BuildContext context) {
    final progress = dailyTarget > 0 ? counter.total / dailyTarget : 0.0;
    final progressColor = dailyTarget <= 0
        ? AppColors.muted
        : progress > 1
            ? AppColors.danger
            : progress > 0.5
                ? AppColors.green
                : AppColors.brain;

    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.surfaceLight, AppColors.surface],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'TODAY\'S TOTAL',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (loading)
              const SizedBox(
                height: 76,
                child: Center(child: CircularProgressIndicator(color: AppColors.green)),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  counter.total.toString(),
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 76,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -3,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Videos detected today  ·  ${counter.date}',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            if (dailyTarget > 0) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily limit $dailyTarget',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  Text(
                    '${(progress * 100).round()}% used',
                    style: TextStyle(color: progressColor, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: AppColors.surface,
                  color: progressColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
