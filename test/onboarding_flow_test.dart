import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reelcount/main.dart';
import 'package:reelcount/screens/onboarding_screen.dart';
import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/services/onboarding_storage.dart';
import 'package:reelcount/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> completeWizard(WidgetTester tester) async {
    await tapText(tester, 'Start Setup');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'I Turned It On / Not Available');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    expect(find.textContaining('ReelCount uses Accessibility'), findsOneWidget);
  }

  testWidgets('onboarding starts with notifications and keeps accessibility last', (
    tester,
  ) async {
    final service = FakeOnboardingService();
    final storage = InMemoryOnboardingStorage();
    await tester.pumpWidget(
      ReelCountApp(service: service, storage: storage),
    );
    await tester.pumpAndSettle();

    expect(find.text('STEP 1 OF 6'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Accessibility Service'), findsNothing);
    expect(find.text('Open Accessibility Settings'), findsNothing);

    await completeWizard(tester);

    await tapText(tester, 'Open Accessibility Settings');

    expect(service.calls.last, FloatingBubbleMethod.requestAccessibilityPermission);
    expect(
      service.calls.indexOf(FloatingBubbleMethod.requestAccessibilityPermission),
      greaterThan(service.calls.indexOf(FloatingBubbleMethod.requestOverlayPermission)),
    );
    expect(find.text('Have you completed all these configurations?'), findsNothing);
  });

  testWidgets('final confirmation identifies incomplete settings and sends user back', (
    tester,
  ) async {
    final service = FakeOnboardingService()..overlayGranted = false;
    final storage = InMemoryOnboardingStorage();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: OnboardingFlow(
          service: service,
          storage: storage,
          startAtConfirmation: true,
          onFinished: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Have you completed all these configurations?'), findsOneWidget);
    expect(find.textContaining('still need attention'), findsOneWidget);

    await tapText(tester, 'Yes, Everything Is Done');

    expect(find.text('Display Over Other Apps'), findsWidgets);
    expect(
      find.text('Display over other apps is not enabled yet.'),
      findsOneWidget,
    );
    expect(find.textContaining('all set'), findsNothing);
  });

  testWidgets('successful onboarding is remembered and opens the clean dashboard', (
    tester,
  ) async {
    final service = FakeOnboardingService();
    final storage = InMemoryOnboardingStorage();
    await tester.pumpWidget(
      ReelCountApp(service: service, storage: storage),
    );
    await tester.pumpAndSettle();

    await completeWizard(tester);
    await tapText(tester, 'Open Accessibility Settings');
    await tapText(tester, 'Continue');

    expect(find.text('Have you completed all these configurations?'), findsOneWidget);
    await tapText(tester, 'Yes, Everything Is Done');
    expect(find.textContaining('all set'), findsOneWidget);

    await tapText(tester, 'Next');

    expect(storage.completed, isTrue);
    expect(find.text('Setup & Permissions'), findsOneWidget);
    expect(find.text('Enable Accessibility'), findsNothing);
  });
}

class InMemoryOnboardingStorage implements OnboardingStorage {
  InMemoryOnboardingStorage({this.completed = false, this.step = 0});

  bool completed;
  int step;
  Set<String> confirmed = <String>{};

  @override
  Future<bool> isCompleted() async => completed;

  @override
  Future<int> currentStep() async => step;

  @override
  Future<Set<String>> confirmedSteps() async => confirmed;

  @override
  Future<void> saveProgress({
    required int step,
    required Set<String> confirmedSteps,
  }) async {
    this.step = step;
    confirmed = confirmedSteps;
  }

  @override
  Future<void> setCompleted({required bool completed}) async {
    this.completed = completed;
  }

  @override
  Future<void> clear() async {
    completed = false;
    step = 0;
    confirmed = <String>{};
  }
}

class FakeOnboardingService extends FloatingBubbleService {
  FakeOnboardingService()
      : super(
          methodChannel: const MethodChannel('test_onboarding_method_channel'),
          eventChannel: const EventChannel('test_onboarding_event_channel'),
        );

  final calls = <String>[];
  bool overlayGranted = true;
  bool accessibilityEnabled = false;
  String backgroundActivityStatus = 'allowed';
  String pauseAppActivityStatus = 'disabled';

  final counter = const BubbleCounter(
    total: 7,
    instagram: 3,
    youtube: 2,
    facebook: 1,
    tiktok: 1,
    snapchat: 0,
    date: '2026-11-22',
  );

  @override
  Stream<BubbleEvent> get events => const Stream.empty();

  @override
  Future<BubbleCounter> getCounter() async => counter;

  @override
  Future<int> getDailyTarget() async => 0;

  @override
  Future<int> setDailyTarget(int target) async => target;

  @override
  Future<String> checkPauseAppActivity() async => pauseAppActivityStatus;

  @override
  Future<BubbleStatus> getBubbleStatus() async => BubbleStatus(
        bubbleVisible: false,
        expanded: false,
        overlayPermissionGranted: overlayGranted,
        serviceRunning: false,
        backgroundActivityStatus: backgroundActivityStatus,
        accessibilityEnabled: accessibilityEnabled,
        accessibilityServiceRunning: accessibilityEnabled,
        counter: counter,
      );

  @override
  Future<bool> requestOverlayPermission() async {
    calls.add(FloatingBubbleMethod.requestOverlayPermission);
    overlayGranted = true;
    return true;
  }

  @override
  Future<bool> requestBackgroundActivity() async {
    calls.add(FloatingBubbleMethod.requestBackgroundActivity);
    backgroundActivityStatus = 'allowed';
    return true;
  }

  @override
  Future<bool> requestAutoBackgroundStart() async {
    calls.add(FloatingBubbleMethod.requestAutoBackgroundStart);
    return true;
  }

  @override
  Future<bool> requestPauseAppActivity() async {
    calls.add(FloatingBubbleMethod.requestPauseAppActivity);
    pauseAppActivityStatus = 'disabled';
    return true;
  }

  @override
  Future<bool> requestAccessibilityPermission() async {
    calls.add(FloatingBubbleMethod.requestAccessibilityPermission);
    accessibilityEnabled = true;
    return true;
  }
}
