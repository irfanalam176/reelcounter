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

  Future<void> tapFirst(WidgetTester tester, String text) async {
    final finder = find.text(text).first;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> completeSetup(WidgetTester tester) async {
    await tapText(tester, 'I Turned It On / Not Available');
    await tapText(tester, 'I Allowed Restricted Settings');
    await tapText(tester, 'Finish Setup');
  }

  testWidgets('all permissions appear on one screen', (tester) async {
    final service = FakeOnboardingService();
    final storage = InMemoryOnboardingStorage();
    await tester.pumpWidget(
      ReelCountApp(service: service, storage: storage),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Display Over Other Apps'), findsOneWidget);
    expect(find.text('Background Activity & Battery'), findsOneWidget);
    expect(find.text('Auto Background Start'), findsOneWidget);
    expect(find.text('Pause App Activity If Unused'), findsOneWidget);
    expect(find.text('Allow Restricted Settings'), findsOneWidget);
    expect(find.text('Accessibility Service'), findsOneWidget);
    expect(find.text('STEP 1 OF 7'), findsNothing);
    expect(find.text('Have you completed all these configurations?'), findsNothing);
    expect(
      find.text('Settings → Accessibility → Downloaded Apps → Scrollo → Enable'),
      findsOneWidget,
    );
  });

  testWidgets('every grant button opens the correct settings', (tester) async {
    final service = FakeOnboardingService();
    await tester.pumpWidget(
      ReelCountApp(service: service, storage: InMemoryOnboardingStorage()),
    );
    await tester.pumpAndSettle();

    await tapText(tester, 'Grant Notifications');
    await tapText(tester, 'Open Display Settings');
    await tapText(tester, 'Open Battery Settings');
    await tapText(tester, 'Open Auto-Start Settings');
    await tapFirst(tester, 'Open App Info Settings');
    await tapText(tester, 'Open Accessibility Settings');

    expect(service.calls, contains(FloatingBubbleMethod.requestNotificationPermission));
    expect(service.calls, contains(FloatingBubbleMethod.requestOverlayPermission));
    expect(service.calls, contains(FloatingBubbleMethod.requestBackgroundActivity));
    expect(service.calls, contains(FloatingBubbleMethod.requestAutoBackgroundStart));
    expect(service.calls, contains(FloatingBubbleMethod.requestPauseAppActivity));
    expect(service.calls, contains(FloatingBubbleMethod.requestAccessibilityPermission));
  });

  testWidgets('restricted settings stays an advanced confirmation requirement', (
    tester,
  ) async {
    final service = FakeOnboardingService();
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

    expect(
      find.textContaining('Settings → Apps → Scrollo → Three-dot menu'),
      findsOneWidget,
    );
    expect(find.text('I Allowed Restricted Settings'), findsOneWidget);

    await tapText(tester, 'I Allowed Restricted Settings');

    expect(storage.confirmed, contains(SetupStep.restrictedSettings.name));
    expect(find.text('I Allowed Restricted Settings'), findsNothing);
    expect(service.calls, isEmpty);
  });

  testWidgets('final check identifies incomplete settings without marking them granted', (
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

    await tapText(tester, 'Done');

    expect(
      find.text('Display over other apps is not enabled yet.'),
      findsOneWidget,
    );
    expect(find.textContaining('Still incomplete'), findsOneWidget);
    expect(find.textContaining('all set'), findsNothing);
    expect(storage.completed, isFalse);
  });

  testWidgets('successful onboarding is remembered and opens the clean dashboard', (
    tester,
  ) async {
    final service = FakeOnboardingService()..accessibilityEnabled = true;
    final storage = InMemoryOnboardingStorage();
    await tester.pumpWidget(
      ReelCountApp(service: service, storage: storage),
    );
    await tester.pumpAndSettle();

    await completeSetup(tester);

    expect(find.textContaining('all set'), findsOneWidget);

    await tapText(tester, 'Next');

    expect(storage.completed, isTrue);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Enable Accessibility'), findsNothing);
  });

  testWidgets('reopening after completed setup opens permissions instead of success', (
    tester,
  ) async {
    final service = FakeOnboardingService()..accessibilityEnabled = false;
    final storage = InMemoryOnboardingStorage(
      completed: true,
      step: SetupStep.success.index,
    );
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

    expect(find.text('Everything Scrollo needs, in one place.'), findsOneWidget);
    expect(find.text('Accessibility Service'), findsOneWidget);
    expect(find.text('You’re all set!'), findsNothing);

    final scrollView = find.byType(SingleChildScrollView);
    expect(
      tester.widget<SingleChildScrollView>(scrollView).controller?.offset ?? 0,
      greaterThan(0),
    );
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
  Future<List<BubbleCounter>> getDailyHistory() async => const [];

  @override
  Future<DailyReminderSettings> getDailyReminder() async => const DailyReminderSettings(
        enabled: false,
        hour: 20,
        minute: 0,
        permissionGranted: true,
      );

  @override
  Future<String> checkPauseAppActivity() async => pauseAppActivityStatus;

  @override
  Future<bool> checkNotificationPermission() async => true;

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

  @override
  Future<bool> requestNotificationPermission() async {
    calls.add(FloatingBubbleMethod.requestNotificationPermission);
    return true;
  }

  @override
  Future<bool> openNotificationSettings() async {
    calls.add(FloatingBubbleMethod.openNotificationSettings);
    return true;
  }
}
