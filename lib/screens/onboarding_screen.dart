import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/services/onboarding_storage.dart';
import 'package:reelcount/theme/app_theme.dart';
import 'package:reelcount/widgets/app_ui.dart';

enum SetupStep {
  notifications,
  overlay,
  background,
  autoStart,
  pauseApp,
  restrictedSettings,
  accessibility,
  confirmation,
  success,
}

enum SetupState {
  notRequired,
  verified,
  needsConfirmation,
  incomplete,
}

extension SetupStepLabel on SetupStep {
  String get title => switch (this) {
        SetupStep.notifications => 'Notifications',
        SetupStep.overlay => 'Display Over Other Apps',
        SetupStep.background => 'Background Activity & Battery',
        SetupStep.autoStart => 'Auto Background Start',
        SetupStep.pauseApp => 'Pause App Activity If Unused',
        SetupStep.restrictedSettings => 'Allow Restricted Settings',
        SetupStep.accessibility => 'Accessibility Service',
        SetupStep.confirmation => 'Confirm Your Setup',
        SetupStep.success => 'Setup Complete',
      };

  String get settingsPath => switch (this) {
        SetupStep.notifications =>
          'Settings → Apps → Scrollo → Notifications',
        SetupStep.overlay =>
          'Settings → Apps → Scrollo → Display over other apps → Allow',
        SetupStep.background =>
          'Settings → Apps → Scrollo → Battery → Allow background activity (menu names may vary)',
        SetupStep.autoStart =>
          'Settings → Apps → Scrollo → Auto-start → Allow\n'
              'Some devices call this Auto-launch or Autostart.',
        SetupStep.pauseApp =>
          'Settings → Apps → Scrollo → Pause app activity if unused → Disable',
        SetupStep.restrictedSettings =>
          'Settings → Apps → Scrollo → Three-dot menu → Allow restricted settings\n'
              'On some devices this is under Advanced settings.',
        SetupStep.accessibility =>
          'Settings → Accessibility → Downloaded Apps → Scrollo → Enable',
        SetupStep.confirmation => '',
        SetupStep.success => '',
      };

  IconData get icon => switch (this) {
        SetupStep.notifications => Icons.notifications_none_rounded,
        SetupStep.overlay => Icons.layers_outlined,
        SetupStep.background => Icons.battery_charging_full_outlined,
        SetupStep.autoStart => Icons.flash_on_outlined,
        SetupStep.pauseApp => Icons.pause_circle_outline,
        SetupStep.restrictedSettings => Icons.tune_rounded,
        SetupStep.accessibility => Icons.accessibility_new_rounded,
        SetupStep.confirmation => Icons.fact_check_outlined,
        SetupStep.success => Icons.check_circle_outline,
      };
}

class SetupCheck {
  const SetupCheck(this.state, this.detail);

  final SetupState state;
  final String detail;
}

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    this.service,
    this.storage,
    required this.onFinished,
    this.startAtConfirmation = false,
  });

  final FloatingBubbleService? service;
  final OnboardingStorage? storage;
  final VoidCallback onFinished;
  final bool startAtConfirmation;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow>
    with WidgetsBindingObserver {
  static const _setupSteps = <SetupStep>[
    SetupStep.notifications,
    SetupStep.overlay,
    SetupStep.background,
    SetupStep.autoStart,
    SetupStep.pauseApp,
    SetupStep.restrictedSettings,
    SetupStep.accessibility,
  ];

  late final FloatingBubbleService _service;
  late final OnboardingStorage _storage;
  final ScrollController _scrollController = ScrollController();
  late final Map<SetupStep, GlobalKey> _permissionKeys = {
    for (final step in _setupSteps) step: GlobalKey(),
  };
  int _stepIndex = 0;
  Set<String> _confirmedSteps = <String>{};
  BubbleStatus _status = _emptyStatus();
  String _pauseAppActivityStatus = 'unknown';
  bool _notificationGranted = false;
  bool _loading = true;
  bool _checking = false;
  SetupStep? _busyStep;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? FloatingBubbleService();
    _storage = widget.storage ?? SharedPreferencesOnboardingStorage();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _refresh(showLoading: false);
    }
  }

  Future<void> _initialize() async {
    try {
      final savedStep = await _storage.currentStep();
      final confirmed = await _storage.confirmedSteps();
      if (!mounted) {
        return;
      }
      setState(() {
        _confirmedSteps = confirmed;
        _stepIndex = widget.startAtConfirmation
            ? SetupStep.confirmation.index
            : savedStep.clamp(0, SetupStep.success.index);
      });
    } catch (error) {
      _setMessage('Could not load saved setup progress: $error');
    }
    await _refresh(showLoading: false);
    _scrollToFirstIssue();
  }

  Future<void> _refresh({bool showLoading = false}) async {
    if (showLoading) {
      setState(() => _loading = true);
    }
    try {
      final status = await _service.getBubbleStatus();
      final pause = await _service.checkPauseAppActivity();
      bool notificationGranted;
      try {
        notificationGranted = await _service.checkNotificationPermission();
      } catch (_) {
        notificationGranted = _notificationGranted;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
        _pauseAppActivityStatus = pause;
        _notificationGranted = notificationGranted;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      _setMessage(_errorMessage(error));
    }
  }

  void _scrollToFirstIssue() {
    final missing = _missingSteps;
    if (missing.isEmpty || _stepIndex == SetupStep.success.index) {
      return;
    }
    final key = _permissionKeys[missing.first];
    if (key == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final context = key.currentContext;
      if (context == null) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        alignment: 0.1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  SetupCheck _check(SetupStep step) {
    switch (step) {
      case SetupStep.notifications:
        return _notificationGranted
            ? const SetupCheck(SetupState.verified, 'Notifications are enabled.')
            : const SetupCheck(SetupState.incomplete, 'Notifications are not enabled yet.');
      case SetupStep.overlay:
        return _status.overlayPermissionGranted
            ? const SetupCheck(SetupState.verified, 'Display over other apps is enabled.')
            : const SetupCheck(
                SetupState.incomplete,
                'Display over other apps is not enabled yet.',
              );
      case SetupStep.background:
        return _tristateCheck(
          value: _status.backgroundActivityStatus,
          step: step,
          verifiedDetail: 'Background activity is allowed.',
          confirmedDetail: 'You confirmed background activity is allowed.',
          incompleteDetail: 'Background activity is restricted for Scrollo.',
          missingDetail:
              'Your device does not share a reliable background activity status.',
        );
      case SetupStep.autoStart:
        return _confirmedSteps.contains(SetupStep.autoStart.name)
            ? const SetupCheck(
                SetupState.verified,
                'You confirmed Auto-start is enabled or not available.',
              )
            : const SetupCheck(
                SetupState.needsConfirmation,
                'Auto-start cannot be read by Scrollo. Check it in Settings, then confirm.',
              );
      case SetupStep.pauseApp:
        return _tristateCheck(
          value: _pauseAppActivityStatus,
          step: step,
          verifiedDetail: 'Pause app activity if unused is off.',
          confirmedDetail:
              'You confirmed Pause app activity if unused is off or not available.',
          incompleteDetail: 'Pause app activity if unused is ON for Scrollo.',
          missingDetail:
              'Your device does not share a reliable pause-app-activity status.',
        );
      case SetupStep.restrictedSettings:
        return _confirmedSteps.contains(SetupStep.restrictedSettings.name)
            ? const SetupCheck(
                SetupState.verified,
                'You confirmed restricted settings are allowed for Scrollo.',
              )
            : const SetupCheck(
                SetupState.needsConfirmation,
                'Allow restricted settings from Scrollo’s App Info, then confirm.',
              );
      case SetupStep.accessibility:
        if (_status.accessibilityEnabled && _status.accessibilityServiceRunning) {
          return const SetupCheck(
            SetupState.verified,
            'Scrollo Detection is enabled and connected.',
          );
        }
        if (_status.accessibilityEnabled) {
          return const SetupCheck(
            SetupState.incomplete,
            'Accessibility is enabled, but the detection service is not connected yet. '
                'Wait a moment, then tap Check Again.',
          );
        }
        return const SetupCheck(
          SetupState.incomplete,
          'Scrollo Detection is not enabled yet.',
        );
      case SetupStep.confirmation:
      case SetupStep.success:
        return const SetupCheck(SetupState.verified, '');
    }
  }

  SetupCheck _tristateCheck({
    required String value,
    required SetupStep step,
    required String verifiedDetail,
    required String confirmedDetail,
    required String incompleteDetail,
    required String missingDetail,
  }) {
    if (value == _verifiedValue(step)) {
      return SetupCheck(SetupState.verified, verifiedDetail);
    }
    if (value == 'unknown') {
      return _confirmedSteps.contains(step.name)
          ? SetupCheck(SetupState.verified, confirmedDetail)
          : SetupCheck(SetupState.needsConfirmation, missingDetail);
    }
    return SetupCheck(SetupState.incomplete, incompleteDetail);
  }

  String _verifiedValue(SetupStep step) => switch (step) {
        SetupStep.background => 'allowed',
        SetupStep.pauseApp => 'disabled',
        _ => '',
      };

  bool _canContinue(SetupCheck check) =>
      check.state == SetupState.verified || check.state == SetupState.notRequired;

  List<SetupStep> get _missingSteps => _setupSteps
      .where((step) => !_canContinue(_check(step)))
      .toList(growable: false);

  int get _readyCount => _setupSteps.length - _missingSteps.length;

  Future<void> _saveProgress() async {
    try {
      await _storage.saveProgress(
        step: _stepIndex,
        confirmedSteps: _confirmedSteps,
      );
    } catch (error) {
      _setMessage(_errorMessage(error));
    }
  }

  Future<void> _confirmStep(SetupStep step) async {
    if (!mounted) {
      return;
    }
    setState(() => _confirmedSteps.add(step.name));
    await _saveProgress();
  }

  Future<void> _requestNotificationPermission() async {
    setState(() => _busyStep = SetupStep.notifications);
    try {
      final granted = await _service.requestNotificationPermission();
      if (!mounted) {
        return;
      }
      setState(() => _notificationGranted = granted);
      _setMessage(granted
          ? 'Notifications enabled. Your reminder is ready.'
          : 'Notifications were not enabled. You can change this in Android Settings.');
    } catch (error) {
      if (mounted) {
        _setMessage(_errorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busyStep = null);
      }
    }
  }

  Future<void> _openSettings(SetupStep step) async {
    setState(() => _busyStep = step);
    try {
      switch (step) {
        case SetupStep.overlay:
          await _service.requestOverlayPermission();
        case SetupStep.background:
          await _service.requestBackgroundActivity();
        case SetupStep.autoStart:
          await _service.requestAutoBackgroundStart();
        case SetupStep.pauseApp:
        case SetupStep.restrictedSettings:
          await _service.requestPauseAppActivity();
        case SetupStep.accessibility:
          await _service.requestAccessibilityPermission();
        case SetupStep.notifications:
          await _service.openNotificationSettings();
        case SetupStep.confirmation:
        case SetupStep.success:
          return;
      }
      if (!mounted) {
        return;
      }
      _setMessage('Return to Scrollo after finishing in Android Settings. '
          'Statuses are checked automatically.');
      await _refresh(showLoading: false);
    } catch (error) {
      if (mounted) {
        _setMessage(_errorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busyStep = null);
      }
    }
  }

  Future<void> _confirmAll() async {
    setState(() => _checking = true);
    await _refresh(showLoading: false);
    if (!mounted) {
      return;
    }
    final missing = _missingSteps;
    setState(() => _checking = false);
    if (missing.isEmpty) {
      setState(() => _stepIndex = SetupStep.success.index);
      await _saveProgress();
      return;
    }
    final labels = missing.map((step) => step.title).join(', ');
    _setMessage('Still incomplete: $labels. Review the permissions below.');
  }

  Future<void> _finish() async {
    try {
      await _storage.saveProgress(
        step: SetupStep.success.index,
        confirmedSteps: _confirmedSteps,
      );
      await _storage.setCompleted(completed: true);
    } catch (error) {
      if (mounted) {
        _setMessage(_errorMessage(error));
      }
      return;
    }
    widget.onFinished();
  }

  void _setMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorMessage(Object error) => error is FloatingBubbleException
      ? error.message
      : 'Something went wrong: $error';

  String _buttonLabel(SetupStep step) => switch (step) {
        SetupStep.notifications => 'Grant Notifications',
        SetupStep.overlay => 'Open Display Settings',
        SetupStep.background => 'Open Battery Settings',
        SetupStep.autoStart => 'Open Auto-Start Settings',
        SetupStep.pauseApp => 'Open App Info Settings',
        SetupStep.restrictedSettings => 'Open App Info Settings',
        SetupStep.accessibility => 'Open Accessibility Settings',
        _ => 'Open Settings',
      };

  String _confirmLabel(SetupStep step) => switch (step) {
        SetupStep.autoStart => 'I Turned It On / Not Available',
        SetupStep.restrictedSettings => 'I Allowed Restricted Settings',
        SetupStep.pauseApp => 'I Checked This Setting',
        _ => 'I Checked This Setting',
      };

  @override
  Widget build(BuildContext context) {
    final reopened = widget.startAtConfirmation;
    final showSuccess = _stepIndex == SetupStep.success.index;
    final ready = _readyCount;
    return PopScope(
      canPop: reopened || showSuccess,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !reopened && !showSuccess) {
          _setMessage('Finish the permission setup to continue.');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(reopened ? 'Permissions' : 'Set up Scrollo'),
          actions: [
            if (reopened)
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.green))
              : Column(
                  children: [
                    if (!showSuccess) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Permissions',
                                    style: TextStyle(
                                      color: AppColors.text,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Everything Scrollo needs, in one place.',
                                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            StatusPill(
                              label: '$ready of ${_setupSteps.length} ready',
                              tone: ready == _setupSteps.length
                                  ? StatusTone.success
                                  : StatusTone.warning,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: LinearProgressIndicator(
                          value: ready / _setupSteps.length,
                          minHeight: 4,
                          backgroundColor: AppColors.surface,
                          color: AppColors.green,
                        ),
                      ),
                    ],
                    Expanded(
                      child: showSuccess
                          ? _buildSuccess()
                          : SingleChildScrollView(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final step in _setupSteps)
                                    _buildPermissionCard(step),
                                  const SizedBox(height: 8),
                                  FilledButton(
                                    onPressed: _checking ? null : _confirmAll,
                                    child: Text(_checking
                                        ? 'Checking settings…'
                                        : reopened
                                            ? 'Done'
                                            : 'Finish Setup'),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Return to Scrollo after finishing in Android Settings. '
                                    'Statuses refresh automatically.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard(SetupStep step) {
    final check = _check(step);
    final busy = _busyStep == step;
    final notifications = step == SetupStep.notifications;
    final primaryLabel = busy ? 'Working…' : _buttonLabel(step);
    return _PermissionCard(
      key: _permissionKeys[step],
      step: step,
      check: check,
      primaryLabel: primaryLabel,
      onPrimary: busy
          ? null
          : notifications
              ? _requestNotificationPermission
              : () => _openSettings(step),
      secondaryLabel: notifications ? 'Open Notification Settings' : null,
      onSecondary: busy ? null : notifications ? () => _openSettings(step) : null,
      confirmLabel: _confirmLabel(step),
      onConfirm: check.state == SetupState.needsConfirmation
          ? () => _confirmStep(step)
          : null,
      refreshLabel: step == SetupStep.accessibility && _status.accessibilityEnabled
          ? 'Check Again'
          : null,
      onRefresh: step == SetupStep.accessibility && _status.accessibilityEnabled
          ? () => _refresh(showLoading: false)
          : null,
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 72),
            const SizedBox(height: 20),
            const Text(
              'You’re all set!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Scrollo is ready to track your reels and update your daily progress.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _finish,
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    super.key,
    required this.step,
    required this.check,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.confirmLabel,
    this.onConfirm,
    this.refreshLabel,
    this.onRefresh,
  });

  final SetupStep step;
  final SetupCheck check;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? confirmLabel;
  final VoidCallback? onConfirm;
  final String? refreshLabel;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final granted = check.state == SetupState.verified ||
        check.state == SetupState.notRequired;
    final tone = granted
        ? StatusTone.success
        : check.state == SetupState.incomplete
            ? StatusTone.error
            : StatusTone.warning;
    final color = switch (tone) {
      StatusTone.success => AppColors.green,
      StatusTone.warning => AppColors.warning,
      StatusTone.error => AppColors.danger,
      StatusTone.neutral => AppColors.muted,
    };
    final statusLabel = granted ? 'Granted' : 'Not Granted';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(step.icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  step.title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onPrimary,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(96, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: BorderSide(color: color.withValues(alpha: 0.5)),
                ),
                child: Text(
                  primaryLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                granted ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 7),
              Text(
                statusLabel,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              StatusPill(label: statusLabel, tone: tone),
            ],
          ),
          if (check.detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              check.detail,
              style: TextStyle(color: granted ? AppColors.muted : color, fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          const Text(
            'How to enable',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.settingsPath,
            style: const TextStyle(color: AppColors.text, fontSize: 13, height: 1.5),
          ),
          if (onSecondary != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onSecondary,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(secondaryLabel ?? 'Open Settings'),
              ),
            ),
          ],
          if (onConfirm != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: Text(confirmLabel ?? 'I Checked This Setting'),
            ),
          ],
          if (onRefresh != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(refreshLabel ?? 'Check Again'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

BubbleStatus _emptyStatus() => const BubbleStatus(
      bubbleVisible: false,
      expanded: false,
      overlayPermissionGranted: false,
      serviceRunning: false,
      accessibilityEnabled: false,
      accessibilityServiceRunning: false,
      detectionState: 'checking',
      detectionMessage: 'Checking setup status…',
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
