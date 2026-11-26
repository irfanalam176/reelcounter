import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/theme/app_theme.dart';
import 'package:reelcount/widgets/app_ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.status,
    required this.dailyTarget,
    required this.reminder,
    required this.busy,
    required this.onSaveDailyTarget,
    required this.onOpenSetup,
    required this.onRequestNotificationPermission,
    required this.onOpenNotificationSettings,
    required this.onSetReminder,
    required this.onStartTracking,
    required this.onStopTracking,
    required this.onResetStatistics,
  });

  final BubbleStatus status;
  final int dailyTarget;
  final DailyReminderSettings reminder;
  final bool busy;
  final Future<void> Function(int target) onSaveDailyTarget;
  final VoidCallback onOpenSetup;
  final Future<void> Function() onRequestNotificationPermission;
  final Future<void> Function() onOpenNotificationSettings;
  final Future<void> Function({required bool enabled, required int hour, required int minute}) onSetReminder;
  final Future<void> Function() onStartTracking;
  final Future<void> Function() onStopTracking;
  final Future<void> Function() onResetStatistics;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _targetController;

  @override
  void initState() {
    super.initState();
    _targetController = TextEditingController(text: widget.dailyTarget.toString());
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dailyTarget != widget.dailyTarget &&
        _targetController.text != widget.dailyTarget.toString()) {
      _targetController.text = widget.dailyTarget.toString();
    }
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    const Text('Make Scrollo fit your routine.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
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
              child: const Icon(Icons.tune_rounded, color: AppColors.accent, size: 21),
            ),
            ],
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Daily limit'),
                const SizedBox(height: 14),
                TextField(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Daily limit (reels)',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: widget.busy
                        ? null
                        : () => widget.onSaveDailyTarget(int.tryParse(_targetController.text) ?? 0),
                    child: const Text('Save daily limit'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Notifications'),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_none_rounded, color: AppColors.accent),
                  title: const Text('Notification access', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    widget.reminder.permissionGranted ? 'Granted' : 'Not granted',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  trailing: StatusPill(
                    label: widget.reminder.permissionGranted ? 'On' : 'Off',
                    tone: widget.reminder.permissionGranted ? StatusTone.success : StatusTone.warning,
                  ),
                ),
                if (!widget.reminder.permissionGranted)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.busy ? null : widget.onRequestNotificationPermission,
                          icon: const Icon(Icons.notifications_active_outlined, size: 17),
                          label: const Text('Allow notifications'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.busy ? null : widget.onOpenNotificationSettings,
                          icon: const Icon(Icons.settings_outlined, size: 17),
                          label: const Text('App settings'),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: widget.reminder.enabled,
                  onChanged: widget.busy || !widget.reminder.permissionGranted
                      ? null
                      : (enabled) => widget.onSetReminder(
                            enabled: enabled,
                            hour: widget.reminder.hour,
                            minute: widget.reminder.minute,
                          ),
                  title: const Text('Daily reminder', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    widget.reminder.enabled
                        ? 'Every day at ${widget.reminder.timeLabel}'
                        : 'A gentle nudge before you scroll',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
                if (widget.reminder.enabled)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: widget.busy ? null : () => _pickTime(context),
                      icon: const Icon(Icons.schedule_outlined, size: 17),
                      label: Text('Change time (${widget.reminder.timeLabel})'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Tracking'),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.radar_outlined, color: AppColors.accent),
                  title: const Text('Detection status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    widget.status.detectionMessage,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: widget.busy || widget.status.serviceRunning ? null : widget.onStartTracking,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Start'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.busy || !widget.status.serviceRunning ? null : widget.onStopTracking,
                        icon: const Icon(Icons.pause_rounded, size: 18),
                        label: const Text('Pause'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onOpenSetup,
                    icon: const Icon(Icons.shield_outlined, size: 18),
                    label: const Text('Setup & Permissions'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Data'),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                  title: const Text('Reset statistics', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    'Clears all counters and history. This cannot be undone.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.busy ? null : widget.onResetStatistics,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Reset all statistics'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 14),
          child: Text(
            'Scrollo: Reel Counter & Planner · Built for mindful scrolling',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ),
        ],
      ),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: widget.reminder.hour, minute: widget.reminder.minute),
    );
    if (time == null || !context.mounted) {
      return;
    }
    await widget.onSetReminder(
      enabled: true,
      hour: time.hour,
      minute: time.minute,
    );
  }
}
