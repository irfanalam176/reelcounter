import 'dart:async';

import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/services/onboarding_storage.dart';
import 'package:reelcount/theme/app_theme.dart';

enum SetupStep {
  notifications,
  overlay,
  background,
  autoStart,
  pauseApp,
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
        SetupStep.accessibility => 'Accessibility Service',
        SetupStep.confirmation => 'Confirm Your Setup',
        SetupStep.success => 'Setup Complete',
      };

  String get description => switch (this) {
        SetupStep.notifications =>
          'ReelCount does not currently ask for notification permission. '
              'If Android asks for it when you install or update the app, allow it. '
              'Otherwise, there is nothing to change on this step.',
        SetupStep.overlay =>
          'This lets the counting bubble appear on top of Instagram, YouTube, Facebook, '
              'TikTok, Snapchat, and other apps while you watch reels.',
        SetupStep.background =>
          'Android can stop apps that run in the background. ReelCount needs background '
              'activity and unrestricted battery usage so the bubble and tracking keep '
              'working when you switch between apps.',
        SetupStep.autoStart =>
          'Some Android devices block apps from starting background services by '
              'themselves. Allowing Auto-start helps ReelCount come back after a restart.',
        SetupStep.pauseApp =>
          'Android can pause apps you have not used for a while. Turn this OFF for '
              'ReelCount so detection is not paused while you are watching reels.',
        SetupStep.accessibility =>
          'ReelCount uses Accessibility to recognize when you navigate between Reels '
              'and Shorts. This allows it to track your scrolling activity and update '
              'your daily progress.',
        SetupStep.confirmation => '',
        SetupStep.success => '',
      };

  String get settingsPath => switch (this) {
        SetupStep.notifications =>
          'Settings  >  Apps  >  ReelCount  >  Notifications\n'
              'Only needed if your Android shows a notification prompt.',
        SetupStep.overlay =>
          'Settings  >  Apps  >  ReelCount  >  Display over other apps\n'
              'Turn on “Allow display over other apps”.',
        SetupStep.background =>
          'Settings  >  Apps  >  ReelCount  >  Battery\n'
              'Choose “Unrestricted” and allow background activity.',
        SetupStep.autoStart =>
          'Settings  >  Apps  >  ReelCount  >  Auto-start\n'
              'Some devices call this Auto-launch or Autostart. Turn it ON.',
        SetupStep.pauseApp =>
          'Settings  >  Apps  >  ReelCount  >  Pause app activity if unused\n'
              'Turn the switch OFF.',
        SetupStep.accessibility =>
          'Settings  >  Accessibility  >  Downloaded services\n'
              'Tap “ReelCount Detection”, then turn on “Use service”.',
        SetupStep.confirmation => '',
        SetupStep.success => '',
      };

  IconData get icon => switch (this) {
        SetupStep.notifications => Icons.notifications_none_rounded,
        SetupStep.overlay => Icons.layers_outlined,
        SetupStep.background => Icons.battery_charging_full_outlined,
        SetupStep.autoStart => Icons.flash_on_outlined,
        SetupStep.pauseApp => Icons.pause_circle_outline,
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
    SetupStep.accessibility,
  ];

  late final FloatingBubbleService _service;
  late final OnboardingStorage _storage;
  int _stepIndex = 0;
  Set<String> _confirmedSteps = <String>{};
  BubbleStatus _status = _emptyStatus();
  String _pauseAppActivityStatus = 'unknown';
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
            : savedStep.clamp(0, _setupSteps.length);
      });
    } catch (error) {
      _setMessage('Could not load saved setup progress: $error');
    }
    await _refresh(showLoading: false);
  }

  Future<void> _refresh({bool showLoading = false}) async {
    if (showLoading) {
      setState(() => _loading = true);
    }
    try {
      final status = await _service.getBubbleStatus();
      final pause = await _service.checkPauseAppActivity();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
        _pauseAppActivityStatus = pause;
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

  SetupCheck _check(SetupStep step) {
    switch (step) {
      case SetupStep.notifications:
        return const SetupCheck(
          SetupState.notRequired,
          'Not required on this version of ReelCount.',
        );
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
          incompleteDetail: 'Background activity is restricted for ReelCount.',
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
                'Auto-start cannot be read by ReelCount. Check it in Settings, then confirm.',
              );
      case SetupStep.pauseApp:
        return _tristateCheck(
          value: _pauseAppActivityStatus,
          step: step,
          verifiedDetail: 'Pause app activity if unused is off.',
          confirmedDetail:
              'You confirmed Pause app activity if unused is off or not available.',
          incompleteDetail: 'Pause app activity if unused is ON for ReelCount.',
          missingDetail:
              'Your device does not share a reliable pause-app-activity status.',
        );
      case SetupStep.accessibility:
        if (_status.accessibilityEnabled && _status.accessibilityServiceRunning) {
          return const SetupCheck(
            SetupState.verified,
            'ReelCount Detection is enabled and connected.',
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
          'ReelCount Detection is not enabled yet.',
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

  Future<void> _goToStep(int index) async {
    try {
      await _storage.saveProgress(
        step: index,
        confirmedSteps: _confirmedSteps,
      );
    } catch (error) {
      _setMessage(_errorMessage(error));
    }
    if (!mounted) {
      return;
    }
    setState(() => _stepIndex = index);
  }

  Future<void> _confirmCurrentStep() async {
    final step = _setupSteps[_stepIndex];
    _confirmedSteps.add(step.name);
    await _goToStep(_stepIndex);
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
          await _service.requestPauseAppActivity();
        case SetupStep.accessibility:
          await _service.requestAccessibilityPermission();
        case SetupStep.notifications:
        case SetupStep.confirmation:
        case SetupStep.success:
          return;
      }
      if (!mounted) {
        return;
      }
      _setMessage('Return to ReelCount after finishing in Android Settings. '
          'The status will be checked automatically.');
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

  Future<void> _next() async {
    if (_stepIndex < _setupSteps.length) {
      await _goToStep(_stepIndex + 1);
    }
  }

  Future<void> _confirmAll() async {
    setState(() => _checking = true);
    await _refresh(showLoading: false);
    final missing = _missingSteps;
    if (!mounted) {
      return;
    }
    setState(() => _checking = false);
    if (missing.isEmpty) {
      await _goToStep(SetupStep.success.index);
      return;
    }
    final labels = missing.map((step) => step.title).join(', ');
    _setMessage('Still incomplete: $labels. Opening the first step to review.');
    await _goToStep(_setupSteps.indexOf(missing.first));
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
        SetupStep.overlay => 'Open Display Settings',
        SetupStep.background => 'Open Battery Settings',
        SetupStep.autoStart => 'Open Auto-Start Settings',
        SetupStep.pauseApp => 'Open App Info Settings',
        SetupStep.accessibility => 'Open Accessibility Settings',
        _ => 'Open Settings',
      };

  @override
  Widget build(BuildContext context) {
    final canPop = widget.startAtConfirmation || _stepIndex == SetupStep.success.index;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !canPop) {
          _setMessage('Finish the setup wizard to continue.');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Set up ReelCount'),
          actions: [
            if (widget.startAtConfirmation)
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              LinearProgressIndicator(
                value: _stepIndex >= SetupStep.confirmation.index
                    ? 1
                    : (_stepIndex + 1) / (_setupSteps.length + 1),
                minHeight: 4,
                backgroundColor: AppColors.surface,
                color: AppColors.green,
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.green))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                        child: _stepIndex == SetupStep.confirmation.index
                            ? _buildConfirmation()
                            : _stepIndex == SetupStep.success.index
                                ? _buildSuccess()
                                : _buildStep(_setupSteps[_stepIndex]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(SetupStep step) {
    final check = _check(step);
    final busy = _busyStep == step;
    final hasSettings = step != SetupStep.notifications;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepIllustration(icon: step.icon, state: check.state),
        const SizedBox(height: 24),
        Text(
          'STEP ${_stepIndex + 1} OF ${_setupSteps.length}',
          style: const TextStyle(
            color: AppColors.green,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          step.title,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          step.description,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 15,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        _InstructionCard(path: step.settingsPath),
        const SizedBox(height: 16),
        _StatusBanner(check: check),
        if (hasSettings) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : () => _openSettings(step),
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(busy ? 'Opening settings…' : _buttonLabel(step)),
          ),
        ],
        if (check.state == SetupState.needsConfirmation) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _confirmCurrentStep,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: Text(step == SetupStep.autoStart
                ? 'I Turned It On / Not Available'
                : 'I Checked This Setting'),
          ),
        ],
        if (step == SetupStep.accessibility && _status.accessibilityEnabled) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _refresh(showLoading: false),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Check Again'),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _canContinue(check) ? _next : null,
          child: Text(step == SetupStep.notifications ? 'Start Setup' : 'Continue'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Press the Android back button or swipe from the edge to return here. '
          'ReelCount checks the status automatically when you come back.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildConfirmation() {
    final missing = _missingSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.fact_check_outlined,
          color: AppColors.green,
          size: 58,
        ),
        const SizedBox(height: 18),
        const Text(
          'Have you completed all these configurations?',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          missing.isEmpty
              ? 'Everything looks ready. Tap Yes to do one final check.'
              : '${missing.length} item(s) still need attention. Tap a row to review it.',
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
        ),
        const SizedBox(height: 20),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final step in _setupSteps)
                _ChecklistRow(
                  step: step,
                  check: _check(step),
                  onTap: _canContinue(_check(step))
                      ? null
                      : () => _goToStep(_setupSteps.indexOf(step)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _checking ? null : _confirmAll,
          child: Text(_checking ? 'Checking settings…' : 'Yes, Everything Is Done'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _goToStep(
            missing.isEmpty
                ? SetupStep.notifications.index
                : _setupSteps.indexOf(missing.first),
          ),
          icon: const Icon(Icons.rate_review_outlined, size: 18),
          label: const Text('I Need to Review Settings'),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 36),
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.greenDark,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.green, width: 2),
          ),
          child: const Icon(Icons.check_rounded, color: AppColors.green, size: 72),
        ),
        const SizedBox(height: 32),
        const Text(
          'You’re all set!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.text,
            fontSize: 30,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'ReelCount is ready to track your reels and update your daily progress.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 36),
        FilledButton(
          onPressed: _finish,
          child: const Text('Next'),
        ),
      ],
    );
  }

}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.step,
    required this.check,
    required this.onTap,
  });

  final SetupStep step;
  final SetupCheck check;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ok = _canContinue(check);
    return ListTile(
      onTap: onTap,
      leading: Icon(
        ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
        color: ok ? AppColors.green : AppColors.danger,
      ),
      title: Text(
        step.title,
        style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        ok ? _stateLabel(check.state) : '${_stateLabel(check.state)} — tap to review',
        style: TextStyle(color: ok ? AppColors.muted : AppColors.danger, fontSize: 12),
      ),
      trailing: ok
          ? const Icon(Icons.check, color: AppColors.green)
          : const Text('Review', style: TextStyle(color: AppColors.danger, fontSize: 12)),
    );
  }

  bool _canContinue(SetupCheck check) =>
      check.state == SetupState.verified || check.state == SetupState.notRequired;

  String _stateLabel(SetupState state) => switch (state) {
        SetupState.notRequired => 'Not required',
        SetupState.verified => 'Done',
        SetupState.needsConfirmation => 'Needs confirmation',
        SetupState.incomplete => 'Incomplete',
      };
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.check});

  final SetupCheck check;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (check.state) {
      SetupState.verified => (
          AppColors.green,
          Icons.verified_rounded,
          'Verified — you can continue.'
        ),
      SetupState.notRequired => (
          AppColors.muted,
          Icons.info_outline_rounded,
          'No action needed on this device.'
        ),
      SetupState.needsConfirmation => (
          Color(0xFFFBBF24),
          Icons.help_outline_rounded,
          'Confirmation needed'
        ),
      SetupState.incomplete => (
          AppColors.danger,
          Icons.warning_amber_rounded,
          'Not completed yet'
        ),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  check.detail,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.settings_outlined, color: AppColors.brain, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              path,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepIllustration extends StatelessWidget {
  const _StepIllustration({required this.icon, required this.state});

  final IconData icon;
  final SetupState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      SetupState.verified => AppColors.green,
      SetupState.notRequired => AppColors.brain,
      SetupState.needsConfirmation => const Color(0xFFFBBF24),
      SetupState.incomplete => AppColors.danger,
    };
    return Container(
      height: 132,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceLight, AppColors.surface],
        ),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 34,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.android_rounded, color: AppColors.muted, size: 46),
            ),
          ),
          const Positioned(
            left: 104,
            top: 28,
            child: Icon(Icons.arrow_forward_rounded, color: AppColors.green, size: 22),
          ),
          Positioned(
            right: 34,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(icon, color: color, size: 44),
            ),
          ),
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
