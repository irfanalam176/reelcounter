import 'dart:async';

import 'package:flutter/material.dart';

import 'package:reelcount/screens/dashboard_screen.dart';
import 'package:reelcount/screens/history_screen.dart';
import 'package:reelcount/screens/insights_screen.dart';
import 'package:reelcount/screens/onboarding_screen.dart';
import 'package:reelcount/screens/settings_screen.dart';
import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/services/onboarding_storage.dart';

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

  BubbleCounter _counter = _emptyCounter();
  BubbleStatus _status = _emptyStatus();
  int _dailyTarget = 0;
  List<BubbleCounter> _history = const [];
  DailyReminderSettings _reminder = const DailyReminderSettings(
    enabled: false,
    hour: 20,
    minute: 0,
    permissionGranted: false,
  );
  int _tabIndex = 0;
  bool _loading = true;
  bool _busy = false;
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
      final history = await _safeHistory();
      final reminder = await _safeReminder();
      if (!mounted) {
        return;
      }
      setState(() {
        _counter = counter;
        _status = status;
        _dailyTarget = target;
        _history = history;
        _reminder = reminder;
        final issues = _setupIssues(status, pauseAppActivityStatus, confirmedSteps);
        _setupIssue = issues.isEmpty ? '' : issues.first;
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

  Future<List<BubbleCounter>> _safeHistory() async {
    try {
      return await _service.getDailyHistory();
    } catch (_) {
      return const [];
    }
  }

  Future<DailyReminderSettings> _safeReminder() async {
    try {
      return await _service.getDailyReminder();
    } catch (_) {
      return _reminder;
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

  Future<void> _requestPermission() async {
    try {
      await _service.requestOverlayPermission();
      if (!mounted) {
        return;
      }
      _showMessage('Return to Scrollo after enabling overlay permission.');
      await _refreshAll(showLoading: false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(_errorMessage(error));
    }
  }

  Future<void> _startTracking() => _runBubbleAction(_service.startFloatingBubble);

  Future<void> _stopTracking() => _runBubbleAction(_service.stopFloatingBubble);

  Future<void> _saveDailyTarget(int target) async {
    final clamped = target < 0 ? 0 : target;
    setState(() => _dailyTarget = clamped);
    try {
      final saved = await _service.setDailyTarget(clamped);
      if (!mounted) {
        return;
      }
      setState(() => _dailyTarget = saved);
      _showMessage('Daily limit saved.');
    } catch (error) {
      if (mounted) {
        _showMessage(_errorMessage(error));
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    setState(() => _busy = true);
    try {
      final granted = await _service.requestNotificationPermission();
      if (!mounted) {
        return;
      }
      setState(() => _reminder = _reminder.copyWith(permissionGranted: granted));
      _showMessage(granted ? 'Notifications enabled.' : 'Notification permission was not granted.');
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

  Future<void> _openNotificationSettings() async {
    setState(() => _busy = true);
    try {
      await _service.openNotificationSettings();
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

  Future<void> _setReminder({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    setState(() => _busy = true);
    try {
      final reminder = await _service.setDailyReminder(
        enabled: enabled,
        hour: hour,
        minute: minute,
      );
      if (!mounted) {
        return;
      }
      setState(() => _reminder = reminder);
      _showMessage(enabled ? 'Daily reminder enabled.' : 'Daily reminder disabled.');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          child: _buildTab(),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildTab() {
    return switch (_tabIndex) {
      0 => DashboardScreen(
          key: const ValueKey('dashboard'),
          counter: _counter,
          status: _status,
          dailyTarget: _dailyTarget,
          history: _history,
          loading: _loading,
          busy: _busy,
          setupIssue: _setupIssue.isEmpty ? null : _setupIssue,
          onRefresh: () => _refreshAll(showLoading: false),
          onOpenSetup: _openSetup,
          onStartTracking: _startTracking,
          onStopTracking: _stopTracking,
          onOpenSettings: () => setState(() => _tabIndex = 3),
        ),
      1 => InsightsScreen(
          key: const ValueKey('insights'),
          history: _history,
          dailyTarget: _dailyTarget,
        ),
      2 => HistoryScreen(
          key: const ValueKey('history'),
          history: _history,
          dailyTarget: _dailyTarget,
          today: _counter.date,
        ),
      _ => SettingsScreen(
          key: const ValueKey('settings'),
          status: _status,
          dailyTarget: _dailyTarget,
          reminder: _reminder,
          busy: _busy,
          onSaveDailyTarget: _saveDailyTarget,
          onOpenSetup: _openSetup,
          onRequestNotificationPermission: _requestNotificationPermission,
          onOpenNotificationSettings: _openNotificationSettings,
          onSetReminder: _setReminder,
          onStartTracking: _startTracking,
          onStopTracking: _stopTracking,
          onResetStatistics: _resetStatistics,
        ),
    };
  }
}

BubbleCounter _emptyCounter() => const BubbleCounter(
      total: 0,
      instagram: 0,
      youtube: 0,
      facebook: 0,
      tiktok: 0,
      snapchat: 0,
      date: '',
    );

BubbleStatus _emptyStatus() => const BubbleStatus(
      bubbleVisible: false,
      expanded: false,
      overlayPermissionGranted: false,
      serviceRunning: false,
      counter: BubbleCounter(
        total: 0,
        instagram: 0,
        youtube: 0,
        facebook: 0,
        tiktok: 0,
        snapchat: 0,
        date: '',
      ),
    );
