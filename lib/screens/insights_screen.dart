import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/theme/app_theme.dart';
import 'package:reelcount/widgets/app_ui.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({
    super.key,
    required this.history,
    required this.dailyTarget,
  });

  final List<BubbleCounter> history;
  final int dailyTarget;

  @override
  Widget build(BuildContext context) {
    final last7 = history.take(7).toList();
    final total = last7.fold<int>(0, (sum, entry) => sum + entry.total);
    final average = last7.isEmpty ? 0 : (total / last7.length).round();
    final best = last7.isEmpty ? null : last7.reduce((a, b) => a.total >= b.total ? a : b);
    final targetHits = dailyTarget > 0 ? last7.where((entry) => entry.total <= dailyTarget).length : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        const _ScreenHeading(
          title: 'Insights',
          subtitle: 'Understand your scrolling rhythm.',
          icon: Icons.insights_outlined,
        ),
        if (last7.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(Icons.bar_chart_rounded, size: 42, color: AppColors.muted),
                  SizedBox(height: 14),
                  Text(
                    'Your story starts today',
                    style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Complete a full day with Scrollo to unlock trends, averages, and platform breakdowns.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Last 7 days'),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 170,
                    child: _WeeklyChart(entries: last7, dailyTarget: dailyTarget),
                  ),
                ],
              ),
            ),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
            children: [
              MetricTile(
                label: '7-day total',
                value: total.toString(),
                icon: Icons.numbers_outlined,
                tone: StatusTone.success,
              ),
              MetricTile(
                label: 'Daily average',
                value: average.toString(),
                icon: Icons.show_chart_rounded,
                tone: StatusTone.success,
              ),
              MetricTile(
                label: 'Busiest day',
                value: best?.total.toString() ?? '0',
                subtitle: best != null ? _shortDate(best.date) : null,
                icon: Icons.calendar_month_outlined,
                tone: StatusTone.warning,
              ),
              MetricTile(
                label: 'Days under target',
                value: dailyTarget > 0 ? '$targetHits/${last7.length}' : 'N/A',
                icon: Icons.flag_outlined,
                tone: StatusTone.success,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Platform mix'),
                  const SizedBox(height: 14),
                  ...ReelPlatform.values.map(
                    (platform) => _PlatformBar(
                      platform: platform,
                      value: last7.fold<int>(0, (sum, entry) => sum + entry.countFor(platform)),
                      max: last7.fold<int>(
                        1,
                        (max, entry) => ReelPlatform.values.fold<int>(
                              max,
                              (innerMax, current) => innerMax > entry.countFor(current)
                                  ? innerMax
                                  : entry.countFor(current),
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: AppColors.surfaceLight,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, color: AppColors.accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      best == null
                          ? 'Scrollo will surface patterns once you have a few days of data.'
                          : 'Your heaviest scrolling day was ${_shortDate(best.date)} with ${best.total} reels. '
                              'Try opening Scrollo before your next session.',
                      style: const TextStyle(color: AppColors.text, fontSize: 13, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ],
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.entries, required this.dailyTarget});

  final List<BubbleCounter> entries;
  final int dailyTarget;

  @override
  Widget build(BuildContext context) {
    final maxValue = entries.fold<int>(1, (max, entry) => max > entry.total ? max : entry.total);
    final ceiling = dailyTarget > 0 && maxValue > dailyTarget ? maxValue : dailyTarget;
    final displayMax = ceiling <= 0 ? maxValue : ceiling;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: entries.map((entry) {
        final ratio = displayMax <= 0 ? 0.0 : (entry.total / displayMax).clamp(0.03, 1.0);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  entry.total.toString(),
                  style: const TextStyle(color: AppColors.text, fontSize: 10, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: ratio),
                  duration: const Duration(milliseconds: 500),
                  builder: (context, value, _) => Container(
                    width: double.infinity,
                    height: 116 * value,
                    decoration: BoxDecoration(
                      color: dailyTarget > 0 && entry.total > dailyTarget ? AppColors.warning : AppColors.accent,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _weekday(entry.date),
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PlatformBar extends StatelessWidget {
  const _PlatformBar({required this.platform, required this.value, required this.max});

  final ReelPlatform platform;
  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    final label = switch (platform) {
      ReelPlatform.instagram => 'Instagram',
      ReelPlatform.youtube => 'YouTube',
      ReelPlatform.facebook => 'Facebook',
      ReelPlatform.tiktok => 'TikTok',
      ReelPlatform.snapchat => 'Snapchat',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(color: AppColors.text, fontSize: 13))),
              Text(value.toString(), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.surfaceLight,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenHeading extends StatelessWidget {
  const _ScreenHeading({required this.title, required this.subtitle, required this.icon});

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: AppColors.accent, size: 21),
          ),
        ],
      ),
    );
  }
}

String _shortDate(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[parsed.month - 1]} ${parsed.day}';
}

String _weekday(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return '--';
  }
  const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  return labels[parsed.weekday - 1];
}
