import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:reelcount/screens/onboarding_screen.dart';
import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/services/onboarding_storage.dart';
import 'package:reelcount/theme/app_theme.dart';
import 'package:reelcount/widgets/counter_card.dart';
import 'package:reelcount/widgets/platform_stats_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.service, this.storage});

  final FloatingBubbleService? service;
  final OnboardingStorage? storage;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final FloatingBubbleService _service;
  late final OnboardingStorage _storage;
  StreamSubscription<BubbleEvent>? _events;
  final TextEditingController _targetController = TextEditingController();
  final FocusNode _targetFocus = FocusNode();

  BubbleCounter _counter = _emptyCounter();
  BubbleStatus _status = _emptyStatus();
  int _dailyTarget = 0;
  bool _loading = true;
  bool _busy = false;
  bool _setupNeedsAttention = false;
  String _setupIssue = '';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? FloatingBubbleService();
    _storage = widget.storage ?? SharedPreferencesOnboardingStorage();
    WidgetsBinding.instance.addObserver(this);
    _subscribeEvents();
    _refreshAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    _targetController.dispose();
    _targetFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAll(showLoading: false);
    }
  }

  void _subscribeEvents() {
    _events = _service.events.listen(
      (event) {
        if (!mounted) {
          return;
        }
        setState(() {
          _counter = event.status.counter;
          _status = event.status;
        });
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        _showMessage(_errorMessage(error));
      },
    );
  }

  Future<void> _refreshAll({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _loading = true);
    }
    try {
      final counter = await _service.getCounter();
      final status = await _service.getBubbleStatus();
      final target = await _service.getDailyTarget();
      final pauseAppActivityStatus = await _service.checkPauseAppActivity();
      final confirmedSteps = await _storage.confirmedSteps();
      if (!mounted) {
        return;
      }
      setState(() {
        _counter = counter;
        _status = status;
        _dailyTarget = target;
        final issues = _setupIssues(status, pauseAppActivityStatus, confirmedSteps);
        _setupNeedsAttention = issues.isNotEmpty;
        _setupIssue = issues.isEmpty ? '' : issues.first;
        if (!_targetFocus.hasFocus) {
          _targetController.text = target > 0 ? target.toString() : '';
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      _showMessage(_errorMessage(error));
    }
  }

  Future<void> _requestPermission() async {
    try {
      await _service.requestOverlayPermission();
      if (!mounted) {
        return;
      }
      _showMessage('Return to ReelCount after enabling overlay permission.');
      await _refreshAll(showLoading: false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(_errorMessage(error));
    }
  }

  List<String> _setupIssues(
    BubbleStatus status,
    String pauseAppActivityStatus,
    Set<String> confirmedSteps,
  ) {
    final issues = <String>[];
    if (!status.overlayPermissionGranted) {
      issues.add('Display over other apps');
    }
    if (status.backgroundActivityStatus == 'restricted' ||
        (status.backgroundActivityStatus == 'unknown' &&
            !confirmedSteps.contains(SetupStep.background.name))) {
      issues.add('Background activity');
    }
    if (!confirmedSteps.contains(SetupStep.autoStart.name)) {
      issues.add('Auto Background Start');
    }
    if (pauseAppActivityStatus == 'enabled' ||
        (pauseAppActivityStatus == 'unknown' &&
            !confirmedSteps.contains(SetupStep.pauseApp.name))) {
      issues.add('Pause app activity if unused');
    }
    if (!status.accessibilityEnabled) {
      issues.add('Accessibility');
    } else if (!status.accessibilityServiceRunning) {
      issues.add('Accessibility service connection');
    }
    return issues;
  }

  Future<void> _openSetup() async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OnboardingFlow(
          service: _service,
          storage: _storage,
          startAtConfirmation: true,
          onFinished: () => Navigator.of(context).pop(true),
        ),
      ),
    );
    if (completed == true && mounted) {
      await _refreshAll(showLoading: false);
    }
  }

  Future<void> _runBubbleAction(Future<bool> Function() action) async {
    if (!_status.overlayPermissionGranted) {
      await _requestPermission();
      return;
    }
    setState(() => _busy = true);
    try {
      final succeeded = await action();
      await _refreshAll(showLoading: false);
      if (succeeded && mounted) {
        _showMessage('Bubble updated.');
      }
    } catch (error) {
      await _refreshAll(showLoading: false);
      if (mounted) {
        _showMessage(_errorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resetStatistics() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset today\'s statistics?'),
        content: const Text(
          'This clears every platform counter for today. Bubble position is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      final counter = await _service.resetCounter();
      if (!mounted) {
        return;
      }
      setState(() => _counter = counter);
      await _refreshAll(showLoading: false);
      _showMessage('Today\'s statistics were reset.');
    } catch (error) {
      if (mounted) {
        _showMessage(_errorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorMessage(Object error) =>
      error is FloatingBubbleException ? error.message : 'Something went wrong: $error';

  Future<void> _saveDailyTarget(String value) async {
    final parsed = int.tryParse(value.trim()) ?? 0;
    final target = parsed < 0 ? 0 : parsed;
    if (target == _dailyTarget) {
      return;
    }
    setState(() => _dailyTarget = target);
    try {
      final saved = await _service.setDailyTarget(target);
      if (!mounted) {
        return;
      }
      setState(() => _dailyTarget = saved);
    } catch (error) {
      if (mounted) {
        _showMessage(_errorMessage(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final permission = _status.overlayPermissionGranted;
    final accessibility = _status.accessibilityEnabled;
    final running = _status.serviceRunning;
    final visible = _status.bubbleVisible;
    final expanded = _status.expanded;
    final missingPermissions = <String>[
      if (!permission) 'Display over other apps',
      if (!accessibility) 'Accessibility',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.adjust_rounded, color: AppColors.background, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'ReelCount',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : () => _refreshAll(showLoading: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.green,
          backgroundColor: AppColors.surface,
          onRefresh: () => _refreshAll(showLoading: false),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DAILY REEL TARGET',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _targetController,
                        focusNode: _targetFocus,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText:
                              'How many Reels do you want to limit yourself to today?',
                          border: OutlineInputBorder(),
                          helperText: 'Set 0 for no limit',
                        ),
                        onChanged: _saveDailyTarget,
                      ),
                    ],
                  ),
                ),
              ),
              CounterCard(
                counter: _counter,
                loading: _loading,
                dailyTarget: _dailyTarget,
              ),
              PlatformStatsCard(counter: _counter),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AT A GLANCE',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _statusRow(
                        icon: Icons.radar_outlined,
                        label: 'Tracking',
                        value: _status.trackingActive ? 'Active' : 'Inactive',
                        active: _status.trackingActive,
                      ),
                      _statusRow(
                        icon: Icons.bolt_rounded,
                        label: 'Floating Bubble',
                        value: running
                            ? (visible ? 'Running · Visible' : 'Running · Hidden')
                            : 'Stopped',
                        active: running,
                      ),
                      _statusRow(
                        icon: _setupNeedsAttention
                            ? Icons.warning_amber_rounded
                            : Icons.verified_rounded,
                        label: 'Setup',
                        value: _setupNeedsAttention
                            ? 'Needs attention'
                            : 'All configurations ready',
                        active: !_setupNeedsAttention,
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 18, 18, 0),
                      child: Text(
                        'SETTINGS',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.tune_rounded,
                        color: _setupNeedsAttention ? AppColors.danger : AppColors.green,
                      ),
                      title: const Text(
                        'Setup & Permissions',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _setupNeedsAttention
                            ? 'Fix: $_setupIssue'
                            : 'Review permissions and device settings',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _openSetup,
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
                      const Text(
                        'BUBBLE CONTROLS',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth >= 520
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _control(
                                width: width,
                                label: 'Start Bubble',
                                icon: Icons.play_arrow_rounded,
                                filled: true,
                                enabled: missingPermissions.isEmpty && !running,
                                onPressed: () => _runBubbleAction(_service.startFloatingBubble),
                              ),
                              _control(
                                width: width,
                                label: 'Stop Bubble',
                                icon: Icons.stop_rounded,
                                enabled: running,
                                onPressed: () => _runBubbleAction(_service.stopFloatingBubble),
                              ),
                              _control(
                                width: width,
                                label: visible ? 'Hide Bubble' : 'Show Bubble',
                                icon: visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                enabled: running && permission,
                                onPressed: visible
                                    ? () => _runBubbleAction(_service.hideFloatingBubble)
                                    : () => _runBubbleAction(_service.showFloatingBubble),
                              ),
                              _control(
                                width: width,
                                label: expanded ? 'Collapse Bubble' : 'Expand Bubble',
                                icon: expanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
                                enabled: visible && !_busy,
                                onPressed: expanded
                                    ? () => _runBubbleAction(_service.collapseFloatingBubble)
                                    : () => _runBubbleAction(_service.expandFloatingBubble),
                              ),
                            ],
                          );
                        },
                      ),
                      if (!running && missingPermissions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Start Bubble disabled: missing ${missingPermissions.join(' and ')} '
                          '${missingPermissions.length == 1 ? 'permission' : 'permissions'}. '
                          'Grant in Android Settings.',
                          style: const TextStyle(color: AppColors.danger, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _resetStatistics,
                          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                          label: const Text('Reset Today\'s Statistics'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'ReelCount counts reels automatically. Setup and permission controls '
                  'live in Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusRow({
    required IconData icon,
    required String label,
    required String value,
    required bool active,
  }) {
    final color = active ? AppColors.green : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                Text(
                  value,
                  style: TextStyle(color: active ? AppColors.text : AppColors.danger, fontSize: 14),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? AppColors.green : AppColors.border,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _control({
    required double width,
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
    bool filled = false,
  }) {
    final button = filled
        ? FilledButton.icon(
            onPressed: enabled && !_busy ? onPressed : null,
            icon: Icon(icon, size: 18),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: enabled && !_busy ? onPressed : null,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
    return SizedBox(width: width, child: button);
  }
}

BubbleCounter _emptyCounter() => const BubbleCounter(
      total: 0,
      instagram: 0,
      youtube: 0,
      facebook: 0,
      tiktok: 0,
      snapchat: 0,
      date: '—',
    );

BubbleStatus _emptyStatus() => const BubbleStatus(
      bubbleVisible: false,
      expanded: false,
      overlayPermissionGranted: false,
      serviceRunning: false,
      accessibilityEnabled: false,
      accessibilityServiceRunning: false,
      detectionState: 'checking',
      detectionMessage: 'Checking detection status…',
      counter: BubbleCounter(
        total: 0,
        instagram: 0,
        youtube: 0,
        facebook: 0,
        tiktok: 0,
        snapchat: 0,
        date: '—',
      ),
    );
