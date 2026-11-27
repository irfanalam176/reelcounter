import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reelcount/main.dart';
import 'package:reelcount/screens/home_screen.dart';
import 'package:reelcount/screens/onboarding_screen.dart';
import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/services/onboarding_storage.dart';
import 'package:reelcount/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final methodChannel = MethodChannel(FloatingBubbleService.methodChannelName);
  final eventChannel = EventChannel(FloatingBubbleService.eventChannelName);

  late Map<String, Object?> counter;
  late Map<String, Object?> status;
  late List<Object?> history;
  final methodCalls = <String>[];

  Map<String, Object?> buildCounter({required int total, required int instagram}) =>
      <String, Object?>{
        'total': total,
        'instagram': instagram,
        'youtube': 35,
        'facebook': 20,
        'tiktok': 18,
        'snapchat': 12,
        'date': '2026-11-19',
      };

  Map<String, Object?> buildStatus({
    required Map<String, Object?> counterMap,
    required bool bubbleRunning,
    required bool accessibilityEnabled,
    required String detectionState,
    String backgroundActivityStatus = 'allowed',
    bool overlayPermissionGranted = true,
  }) {
    final bubbleVisible = bubbleRunning;
    final active = detectionState == 'active';
    final message = active ? 'Tracking active' : 'Tracking engine not connected';
    return <String, Object?>{
      'bubbleVisible': bubbleVisible,
      'expanded': false,
      'overlayPermissionGranted': overlayPermissionGranted,
      'serviceRunning': bubbleRunning,
      'backgroundActivityStatus': backgroundActivityStatus,
      'accessibilityEnabled': accessibilityEnabled,
      'accessibilityServiceRunning': accessibilityEnabled && active,
      'detectionState': detectionState,
      'detectionMessage': message,
      'trackingEngineConnected': accessibilityEnabled && active,
      'trackingState': detectionState,
      'trackingMessage': message,
      'trackingActive': active && bubbleVisible,
      'counter': counterMap,
    };
  }

  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.pumpWidget(
      ReelCountApp(
        key: UniqueKey(),
        storage: InMemoryOnboardingStorage(completed: true),
      ),
    );
    await tester.pumpAndSettle();
  }

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

  Future<void> openSetupDashboard(WidgetTester tester) async {
    await tapText(tester, 'Setup & Permissions');
    expect(find.text('Everything Scrollo needs, in one place.'), findsOneWidget);
  }

  setUp(() {
    methodCalls.clear();
    counter = buildCounter(total: 127, instagram: 42);
    status = buildStatus(
      counterMap: counter,
      bubbleRunning: true,
      accessibilityEnabled: false,
      detectionState: 'waiting',
    );
    history = <Object?>[
      buildCounter(total: 110, instagram: 38),
      <String, Object?>{
        'total': 96,
        'instagram': 30,
        'youtube': 28,
        'facebook': 18,
        'tiktok': 12,
        'snapchat': 8,
        'date': '2026-11-18',
      },
    ];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      methodCalls.add(call.method);
      switch (call.method) {
        case FloatingBubbleMethod.getCounter:
          return counter;
        case FloatingBubbleMethod.getDailyTarget:
          return 50;
        case FloatingBubbleMethod.setDailyTarget:
          return call.arguments;
        case FloatingBubbleMethod.getBubbleStatus:
          return status;
        case FloatingBubbleMethod.checkPauseAppActivity:
          return 'enabled';
        case FloatingBubbleMethod.getDailyHistory:
          return history;
        case FloatingBubbleMethod.getDailyReminder:
          return <String, Object?>{
            'enabled': false,
            'hour': 20,
            'minute': 0,
            'permissionGranted': true,
          };
        case FloatingBubbleMethod.checkNotificationPermission:
          return true;
        default:
          return true;
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, events) {},
        onCancel: (arguments) {},
      ),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventChannel, null);
  });

  testWidgets('dashboard reports independent statuses', (tester) async {
    await pumpDashboard(tester);

    expect(find.text('Scrollo'), findsWidgets);
    expect(find.text('127'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Running · Visible'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('Setup & Permissions'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.textContaining('Daily limit 50'), findsOneWidget);
    expect(find.text('Enable Accessibility'), findsNothing);
    expect(find.text('Overlay permission ready'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.remove), findsNothing);
    expect(find.text('+1'), findsNothing);
    expect(find.text('-1'), findsNothing);
  });

  testWidgets('setup statuses refresh after returning from settings', (tester) async {
    status = buildStatus(
      counterMap: counter,
      bubbleRunning: true,
      accessibilityEnabled: true,
      detectionState: 'active',
      overlayPermissionGranted: false,
    );
    await pumpDashboard(tester);
    await openSetupDashboard(tester);

    expect(
      find.text('Display over other apps is not enabled yet.'),
      findsOneWidget,
    );

    status = buildStatus(
      counterMap: counter,
      bubbleRunning: true,
      accessibilityEnabled: true,
      detectionState: 'active',
      overlayPermissionGranted: true,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(
      find.text('Display over other apps is not enabled yet.'),
      findsNothing,
    );
    expect(find.text('Display over other apps is enabled.'), findsOneWidget);
  });

  testWidgets('setup and permissions reopens the permissions screen after completion', (
    tester,
  ) async {
    await tester.pumpWidget(
      ReelCountApp(
        key: UniqueKey(),
        storage: InMemoryOnboardingStorage(
          completed: true,
          step: SetupStep.success.index,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tapText(tester, 'Setup & Permissions');

    expect(find.text('Everything Scrollo needs, in one place.'), findsOneWidget);
    expect(find.text('Accessibility Service'), findsOneWidget);
    expect(find.text('You’re all set!'), findsNothing);
  });

  testWidgets('bottom navigation opens insights, history, and settings', (tester) async {
    await pumpDashboard(tester);

    await tapText(tester, 'Insights');
    expect(find.text('Insights'), findsWidgets);
    expect(find.text('LAST 7 DAYS'), findsOneWidget);
    expect(find.text('PLATFORM MIX'), findsOneWidget);

    await tapText(tester, 'History');
    expect(find.text('DAILY LOG'), findsOneWidget);
    expect(find.text('96'), findsOneWidget);

    await tapText(tester, 'Settings');
    expect(find.text('Daily reminder'), findsWidgets);
    expect(find.text('Notification access'), findsOneWidget);
    expect(find.text('Reset all statistics'), findsOneWidget);
  });

  testWidgets('background setup status and settings action', (tester) async {
    status = buildStatus(
      counterMap: counter,
      bubbleRunning: true,
      accessibilityEnabled: true,
      detectionState: 'active',
      backgroundActivityStatus: 'restricted',
    );
    await pumpDashboard(tester);
    await openSetupDashboard(tester);

    expect(
      find.text('Background activity is restricted for Scrollo.'),
      findsOneWidget,
    );
    await tapText(tester, 'Open Battery Settings');
    expect(methodCalls, contains(FloatingBubbleMethod.requestBackgroundActivity));

    status = buildStatus(
      counterMap: counter,
      bubbleRunning: true,
      accessibilityEnabled: true,
      detectionState: 'active',
      backgroundActivityStatus: 'unknown',
    );
    await pumpDashboard(tester);
    await openSetupDashboard(tester);

    expect(
      find.text('Your device does not share a reliable background activity status.'),
      findsOneWidget,
    );
    expect(find.text('I Checked This Setting'), findsOneWidget);
  });

  testWidgets('background setting shortcuts open system settings', (tester) async {
    await pumpDashboard(tester);
    await openSetupDashboard(tester);

    await tapText(tester, 'Open Auto-Start Settings');
    expect(methodCalls, contains(FloatingBubbleMethod.requestAutoBackgroundStart));

    await tapFirst(tester, 'Open App Info Settings');
    expect(methodCalls, contains(FloatingBubbleMethod.requestPauseAppActivity));
  });

  testWidgets('daily target drives progress', (tester) async {
    await pumpDashboard(tester);

    await tapText(tester, 'Settings');
    await tester.enterText(find.byType(TextField), '30');
    await tester.pumpAndSettle();
    await tapText(tester, 'Save daily limit');

    expect(methodCalls, contains(FloatingBubbleMethod.setDailyTarget));
    await tapText(tester, 'Home');
    expect(find.textContaining('Daily limit 30'), findsOneWidget);
    expect(find.textContaining('% used'), findsOneWidget);
  });

  testWidgets('start bubble requires every permission', (tester) async {
    status = buildStatus(
      counterMap: counter,
      bubbleRunning: false,
      accessibilityEnabled: false,
      detectionState: 'waiting',
    );
    await pumpDashboard(tester);

    FilledButton startButton() => tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Start tracking'),
            matching: find.byType(FilledButton),
          ),
        );

    expect(startButton().onPressed, isNull);
    expect(
      find.textContaining('Grant overlay and accessibility access in Setup'),
      findsOneWidget,
    );

    status = buildStatus(
      counterMap: counter,
      bubbleRunning: false,
      accessibilityEnabled: true,
      detectionState: 'active',
    );
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();

    expect(startButton().onPressed, isNotNull);
    expect(find.textContaining('Grant overlay and accessibility access in Setup'), findsNothing);
  });

  testWidgets('tracking is active only with detection and bubble', (tester) async {
    status = buildStatus(
      counterMap: counter,
      bubbleRunning: true,
      accessibilityEnabled: true,
      detectionState: 'active',
    );

    await pumpDashboard(tester);

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Inactive'), findsNothing);
    expect(find.text('Enable Accessibility'), findsNothing);
  });

  testWidgets('detection events update the dashboard immediately', (tester) async {
    final controller = StreamController<BubbleEvent>();
    addTearDown(controller.close);
    final service = EventEmittingService(controller, counter);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeScreen(
          service: service,
          storage: InMemoryOnboardingStorage(completed: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('127'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);

    final updatedCounter = buildCounter(total: 128, instagram: 43);
    controller.add(
      BubbleEvent(
        type: BubbleEventType.counterChanged,
        status: BubbleStatus.fromMap(
          buildStatus(
            counterMap: updatedCounter,
            bubbleRunning: true,
            accessibilityEnabled: true,
            detectionState: 'active',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('128'), findsOneWidget);
    expect(find.text('43'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Inactive'), findsNothing);
  });

  testWidgets('reset requires confirmation', (tester) async {
    await pumpDashboard(tester);
    await tapText(tester, 'Settings');
    await tapText(tester, 'Reset all statistics');

    expect(find.text("Reset today's statistics?"), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
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

class EventEmittingService extends FloatingBubbleService {
  EventEmittingService(this.controller, this.initialCounter)
      : super(
          methodChannel: const MethodChannel('test_detection_method_channel'),
          eventChannel: const EventChannel('test_detection_event_channel'),
        );

  final StreamController<BubbleEvent> controller;
  final Map<String, Object?> initialCounter;

  @override
  Stream<BubbleEvent> get events => controller.stream;

  @override
  Future<BubbleCounter> getCounter() async => BubbleCounter.fromMap(initialCounter);

  @override
  Future<int> getDailyTarget() async => 0;

  @override
  Future<int> setDailyTarget(int target) async => target;

  @override
  Future<String> checkPauseAppActivity() async => 'disabled';

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
  Future<bool> checkNotificationPermission() async => true;

  @override
  Future<BubbleStatus> getBubbleStatus() async => BubbleStatus.fromMap(<String, Object?>{
        'bubbleVisible': true,
        'expanded': false,
        'overlayPermissionGranted': true,
        'serviceRunning': true,
        'backgroundActivityStatus': 'allowed',
        'accessibilityEnabled': false,
        'accessibilityServiceRunning': false,
        'detectionState': 'waiting',
        'detectionMessage': 'Tracking engine not connected',
        'counter': initialCounter,
      });
}
