import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/theme/app_theme.dart';
import 'package:reelcount/widgets/app_ui.dart';
import 'package:reelcount/widgets/counter_card.dart';
import 'package:reelcount/widgets/platform_stats_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.counter,
    required this.status,
    required this.dailyTarget,
    required this.history,
    required this.loading,
    required this.busy,
    required this.setupIssue,
    required this.onRefresh,
    required this.onOpenSetup,
    required this.onStartTracking,
    required this.onStopTracking,
    required this.onOpenSettings,
  });

  final BubbleCounter counter;
  final BubbleStatus status;
  final int dailyTarget;
  final List<BubbleCounter> history;
  final bool loading;
  final bool busy;
  final String? setupIssue;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenSetup;
  final Future<void> Function() onStartTracking;
  final Future<void> Function() onStopTracking;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final comparison = _comparisonLabel(counter, history);
    final bubbleRunning = status.serviceRunning;
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome_motion_outlined, color: AppColors.accent, size: 21),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scrollo',
                      style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Reel Counter & Planner',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: status.trackingActive ? 'Tracking' : 'Paused',
                tone: status.trackingActive ? StatusTone.success : StatusTone.neutral,
                icon: status.trackingActive ? Icons.radar_outlined : Icons.pause_circle_outlined,
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => onRefresh(),
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: onOpenSettings,
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (setupIssue != null)
            Card(
              color: AppColors.surfaceLight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shield_outlined, color: AppColors.warning),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Needs attention', style: TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(setupIssue!, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: onOpenSetup,
                      icon: const Icon(Icons.shield_outlined, size: 17),
                      label: const Text('Setup & Permissions'),
                    ),
                  ],
                ),
              ),
            ),
          CounterCard(
            counter: counter,
            loading: loading,
            dailyTarget: dailyTarget,
            comparisonLabel: comparison,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Tracking'),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: busy || !status.overlayPermissionGranted || !status.accessibilityEnabled || bubbleRunning
                        ? null
                        : onStartTracking,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(bubbleRunning ? 'Tracking is running' : 'Start tracking'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: busy || !bubbleRunning ? null : onStopTracking,
                    icon: const Icon(Icons.pause_rounded),
                    label: const Text('Pause tracking'),
                  ),
                  const SizedBox(height: 12),
                  _StatusLine(
                    label: 'Floating bubble',
                    value: bubbleRunning
                        ? (status.bubbleVisible ? 'Running · Visible' : 'Running · Hidden')
                        : 'Stopped',
                    active: bubbleRunning,
                  ),
                  _StatusLine(
                    label: 'Detection',
                    value: status.trackingActive ? 'Active' : 'Inactive',
                    active: status.trackingActive,
                  ),
                  if (!status.overlayPermissionGranted || !status.accessibilityEnabled)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Grant overlay and accessibility access in Setup to start tracking.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          PlatformStatsCard(counter: counter),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Scrollo counts reels automatically. No manual counting, ever.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value, required this.active});

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
          Text(
            value,
            style: TextStyle(
              color: active ? AppColors.accent : AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String? _comparisonLabel(BubbleCounter today, List<BubbleCounter> history) {
  final todayDate = DateTime.tryParse(today.date);
  if (todayDate == null) {
    return null;
  }
  final yesterdayKey = _dateKey(todayDate.subtract(const Duration(days: 1)));
  final yesterday = history.where((entry) => entry.date == yesterdayKey).toList();
  if (yesterday.isEmpty) {
    return 'No comparison available for yesterday yet';
  }
  final delta = today.total - yesterday.first.total;
  if (delta > 0) {
    return '+$delta reels vs yesterday';
  }
  if (delta < 0) {
    return '${delta.abs()} fewer reels vs yesterday';
  }
  return 'Same as yesterday';
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
