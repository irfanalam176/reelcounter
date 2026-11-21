import 'dart:async';

import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/theme/app_theme.dart';
import 'package:reelcount/widgets/bubble_status_card.dart';
import 'package:reelcount/widgets/counter_card.dart';
import 'package:reelcount/widgets/permission_card.dart';
import 'package:reelcount/widgets/platform_stats_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.service});

  final FloatingBubbleService? service;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final FloatingBubbleService _service;
  StreamSubscription<BubbleEvent>? _events;

  BubbleCounter _counter = _emptyCounter();
  BubbleStatus _status = _emptyStatus();
  bool _loading = true;
  bool _busy = false;
  bool _requestingPermission = false;
  bool _requestingAccessibility = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? FloatingBubbleService();
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
      if (!mounted) {
        return;
      }
      setState(() {
        _counter = counter;
        _status = status;
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
    setState(() => _requestingPermission = true);
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
    } finally {
      if (mounted) {
        setState(() => _requestingPermission = false);
      }
    }
  }

  Future<void> _requestAccessibilityPermission() async {
    setState(() => _requestingAccessibility = true);
    try {
      await _service.requestAccessibilityPermission();
      if (!mounted) {
        return;
      }
      _showMessage('Enable ReelCount detection in Android accessibility settings.');
      await _refreshAll(showLoading: false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(_errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _requestingAccessibility = false);
      }
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

  @override
  Widget build(BuildContext context) {
    final permission = _status.overlayPermissionGranted;
    final running = _status.serviceRunning;
    final visible = _status.bubbleVisible;
    final expanded = _status.expanded;

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
              PermissionCard(
                granted: permission,
                requesting: _requestingPermission,
                onEnable: _requestPermission,
              ),
              CounterCard(counter: _counter, loading: _loading),
              PlatformStatsCard(counter: _counter),
              BubbleStatusCard(
                status: _status,
                onEnableAccessibility: _requestAccessibilityPermission,
                requestingAccessibility: _requestingAccessibility,
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
                                enabled: permission && !running,
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
                  'Enable the ReelCount accessibility service to detect reels automatically. '
                  'No manual count controls are exposed.',
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
