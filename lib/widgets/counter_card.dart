import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/theme/app_theme.dart';

class CounterCard extends StatelessWidget {
  const CounterCard({super.key, required this.counter, required this.loading});

  final BubbleCounter counter;
  final bool loading;

  @override
  Widget build(BuildContext context) {
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
          ],
        ),
      ),
    );
  }
}
