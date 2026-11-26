import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/theme/app_theme.dart';
import 'package:reelcount/widgets/app_ui.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    super.key,
    required this.history,
    required this.dailyTarget,
    required this.today,
  });

  final List<BubbleCounter> history;
  final int dailyTarget;
  final String today;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        const _HistoryHeading(),
        if (history.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(Icons.history_toggle_off_outlined, size: 42, color: AppColors.muted),
                  SizedBox(height: 14),
                  Text(
                    'No history yet',
                    style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your daily totals will appear here after your first full day of tracking.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Daily log'),
                  const SizedBox(height: 10),
                  ...history.asMap().entries.map(
                        (entry) => _HistoryRow(
                          counter: entry.value,
                          dailyTarget: dailyTarget,
                          isToday: entry.value.date == today,
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryHeading extends StatelessWidget {
  const _HistoryHeading();

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
                Text('History', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                const Text('Every day, at a glance.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
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
            child: const Icon(Icons.calendar_view_month_outlined, color: AppColors.accent, size: 21),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.counter, required this.dailyTarget, required this.isToday});

  final BubbleCounter counter;
  final int dailyTarget;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(counter.date);
    final label = parsed == null
        ? counter.date
        : '${_weekdayLong(parsed.weekday)}, ${_month(parsed.month)} ${parsed.day}';
    final tone = dailyTarget > 0 && counter.total > dailyTarget ? StatusTone.warning : StatusTone.success;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.7))),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isToday ? Icons.today_outlined : Icons.event_outlined,
              color: isToday ? AppColors.accent : AppColors.muted,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'IG ${counter.instagram}  ·  YT ${counter.youtube}  ·  FB ${counter.facebook}  ·  TT ${counter.tiktok}  ·  SC ${counter.snapchat}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                counter.total.toString(),
                style: const TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              StatusPill(
                label: dailyTarget > 0 && counter.total > dailyTarget ? 'Over target' : 'On track',
                tone: tone,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const List<String> _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _monthLabels = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _weekdayLong(int weekday) => _weekdayLabels[weekday - 1];
String _month(int month) => _monthLabels[month - 1];
