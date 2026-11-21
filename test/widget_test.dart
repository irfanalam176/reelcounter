import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reelcount/main.dart';
import 'package:reelcount/screens/home_screen.dart';
import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final methodChannel = MethodChannel(FloatingBubbleService.methodChannelName);
  final eventChannel = EventChannel(FloatingBubbleService.eventChannelName);

  late Map<String, Object?> counter;
  late Map<String, Object?> status;

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
  }) {
    final bubbleVisible = bubbleRunning;
    final active = detectionState == 'active';
    final message = active ? 'Tracking active' : 'Tracking engine not connected';
    return <String, Object?>{
      'bubbleVisible': bubbleVisible,
      'expanded': false,
      'overlayPermissionGranted': true,
      'serviceRunning': bubbleRunning,
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

  setUp(() {
    counter = buildCounter(total: 127, instagram: 42);
    status = buildStatus(
      counterMap: counter,
      bubbleRunning: true,
      accessibilityEnabled: false,
      detectionState: 'waiting',
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case FloatingBubbleMethod.getCounter:
          return counter;
        case FloatingBubbleMethod.getBubbleStatus:
          return status;
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
    await tester.pumpWidget(const ReelCountApp());
    await tester.pumpAndSettle();

    expect(find.text('ReelCount'), findsWidgets);
    expect(find.text('127'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('Enable Accessibility'), findsOneWidget);
    expect(find.text('Overlay permission ready'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.remove), findsNothing);
    expect(find.text('+1'), findsNothing);
    expect(find.text('-1'), findsNothing);
  });

  testWidgets('tracking is active only with detection and bubble', (tester) async {
    status = buildStatus(
      counterMap: counter,
      bubbleRunning: true,
      accessibilityEnabled: true,
      detectionState: 'active',
    );

    await tester.pumpWidget(const ReelCountApp());
    await tester.pumpAndSettle();

    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Active'), findsNWidgets(2));
    expect(find.text('Inactive'), findsNothing);
    expect(find.text('Enable Accessibility'), findsNothing);
  });

  testWidgets('detection events update the dashboard immediately', (tester) async {
    final controller = StreamController<BubbleEvent>();
    addTearDown(controller.close);
    final service = EventEmittingService(controller, counter);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: HomeScreen(service: service)),
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
    expect(find.text('Active'), findsNWidgets(2));
    expect(find.text('Inactive'), findsNothing);
  });

  testWidgets('reset requires confirmation', (tester) async {
    await tester.pumpWidget(const ReelCountApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text("Reset Today's Statistics"));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Reset Today's Statistics"));
    await tester.pumpAndSettle();

    expect(find.text("Reset today's statistics?"), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
  });
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
  Future<BubbleStatus> getBubbleStatus() async => BubbleStatus.fromMap(<String, Object?>{
        'bubbleVisible': true,
        'expanded': false,
        'overlayPermissionGranted': true,
        'serviceRunning': true,
        'accessibilityEnabled': false,
        'accessibilityServiceRunning': false,
        'detectionState': 'waiting',
        'detectionMessage': 'Tracking engine not connected',
        'counter': initialCounter,
      });
}
