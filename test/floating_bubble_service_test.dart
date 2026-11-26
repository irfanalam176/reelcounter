import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reelcount/services/floating_bubble_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final methodChannel = MethodChannel(FloatingBubbleService.methodChannelName);
  final eventChannel = EventChannel(FloatingBubbleService.eventChannelName);

  late FloatingBubbleService service;
  late List<MethodCall> calls;
  late Map<String, Object?> counterMap;
  late Map<String, Object?> statusMap;
  late Map<String, Object?> recordResultMap;

  setUp(() {
    calls = <MethodCall>[];
    counterMap = <String, Object?>{
      'total': 9,
      'instagram': 2,
      'youtube': 3,
      'facebook': 1,
      'tiktok': 2,
      'snapchat': 1,
      'date': '2026-11-19',
    };
    statusMap = <String, Object?>{
      'bubbleVisible': true,
      'expanded': false,
      'overlayPermissionGranted': true,
      'serviceRunning': true,
      'backgroundActivityStatus': 'allowed',
      'accessibilityEnabled': true,
      'accessibilityServiceRunning': true,
      'detectionState': 'active',
      'detectionMessage': 'Tracking active',
      'trackingEngineConnected': true,
      'trackingState': 'active',
      'trackingMessage': 'Tracking active',
      'trackingActive': true,
      'counter': counterMap,
    };
    recordResultMap = <String, Object?>{
      'recorded': true,
      'duplicate': false,
      'counter': counterMap,
    };
    service = FloatingBubbleService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case FloatingBubbleMethod.checkOverlayPermission:
        case FloatingBubbleMethod.requestOverlayPermission:
        case FloatingBubbleMethod.startFloatingBubble:
        case FloatingBubbleMethod.stopFloatingBubble:
        case FloatingBubbleMethod.showFloatingBubble:
        case FloatingBubbleMethod.hideFloatingBubble:
        case FloatingBubbleMethod.expandFloatingBubble:
        case FloatingBubbleMethod.collapseFloatingBubble:
        case FloatingBubbleMethod.checkAccessibilityPermission:
        case FloatingBubbleMethod.requestAccessibilityPermission:
        case FloatingBubbleMethod.requestBackgroundActivity:
        case FloatingBubbleMethod.requestAutoBackgroundStart:
        case FloatingBubbleMethod.requestPauseAppActivity:
          return true;
        case FloatingBubbleMethod.checkBackgroundActivity:
          return 'allowed';
        case FloatingBubbleMethod.checkPauseAppActivity:
          return 'enabled';
        case FloatingBubbleMethod.resetCounter:
        case FloatingBubbleMethod.getCounter:
          return counterMap;
        case FloatingBubbleMethod.getDailyTarget:
          return 30;
        case FloatingBubbleMethod.setDailyTarget:
          return call.arguments;
        case FloatingBubbleMethod.getBubbleStatus:
          return statusMap;
        case FloatingBubbleMethod.getDailyHistory:
          return <Object?>[counterMap];
        case FloatingBubbleMethod.checkNotificationPermission:
        case FloatingBubbleMethod.requestNotificationPermission:
        case FloatingBubbleMethod.openNotificationSettings:
          return true;
        case FloatingBubbleMethod.getDailyReminder:
        case FloatingBubbleMethod.setDailyReminder:
          return <String, Object?>{
            'enabled': true,
            'hour': 20,
            'minute': 30,
            'permissionGranted': true,
          };
        case FloatingBubbleMethod.recordWatchedVideo:
          return recordResultMap;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventChannel, null);
  });

  group('FloatingBubbleService methods', () {
    test('checkOverlayPermission', () async {
      expect(await service.checkOverlayPermission(), isTrue);
      expect(calls.single.method, FloatingBubbleMethod.checkOverlayPermission);
      expect(calls.single.arguments, isNull);
    });

    test('requestOverlayPermission', () async {
      expect(await service.requestOverlayPermission(), isTrue);
      expect(calls.single.method, FloatingBubbleMethod.requestOverlayPermission);
    });

    test('startFloatingBubble', () async {
      expect(await service.startFloatingBubble(), isTrue);
      expect(calls.single.method, FloatingBubbleMethod.startFloatingBubble);
    });

    test('stopFloatingBubble', () async {
      expect(await service.stopFloatingBubble(), isTrue);
      expect(calls.single.method, FloatingBubbleMethod.stopFloatingBubble);
    });

    test('showFloatingBubble', () async {
      expect(await service.showFloatingBubble(), isTrue);
      expect(calls.single.method, FloatingBubbleMethod.showFloatingBubble);
    });

    test('hideFloatingBubble', () async {
      expect(await service.hideFloatingBubble(), isTrue);
      expect(calls.single.method, FloatingBubbleMethod.hideFloatingBubble);
    });

    test('expandFloatingBubble', () async {
      expect(await service.expandFloatingBubble(), isTrue);
      expect(calls.single.method, FloatingBubbleMethod.expandFloatingBubble);
    });

    test('collapseFloatingBubble', () async {
      expect(await service.collapseFloatingBubble(), isTrue);
      expect(calls.single.method, FloatingBubbleMethod.collapseFloatingBubble);
    });

    test('resetCounter', () async {
      expect(await service.resetCounter(), BubbleCounter.fromMap(counterMap));
      expect(calls.single.method, FloatingBubbleMethod.resetCounter);
    });

    test('getCounter', () async {
      expect(await service.getCounter(), BubbleCounter.fromMap(counterMap));
      expect(calls.single.method, FloatingBubbleMethod.getCounter);
    });

    test('daily target methods', () async {
      expect(await service.getDailyTarget(), 30);
      expect(await service.setDailyTarget(45), 45);
      expect(
        calls.map((call) => call.method),
        <String>[
          FloatingBubbleMethod.getDailyTarget,
          FloatingBubbleMethod.setDailyTarget,
        ],
      );
      expect(calls.last.arguments, 45);
    });

    test('getBubbleStatus', () async {
      final status = await service.getBubbleStatus();
      expect(status, BubbleStatus.fromMap(statusMap));
      expect(status.backgroundActivityStatus, 'allowed');
      expect(status.accessibilityEnabled, isTrue);
      expect(status.accessibilityServiceRunning, isTrue);
      expect(status.detectionState, 'active');
      expect(status.trackingActive, isTrue);
      expect(calls.single.method, FloatingBubbleMethod.getBubbleStatus);
    });

    test('accessibility permission methods', () async {
      expect(await service.checkAccessibilityPermission(), isTrue);
      expect(await service.requestAccessibilityPermission(), isTrue);
      expect(
        calls.map((call) => call.method),
        <String>[
          FloatingBubbleMethod.checkAccessibilityPermission,
          FloatingBubbleMethod.requestAccessibilityPermission,
        ],
      );
    });

    test('background activity methods', () async {
      expect(await service.checkBackgroundActivity(), 'allowed');
      expect(await service.requestBackgroundActivity(), isTrue);
      expect(
        calls.map((call) => call.method),
        <String>[
          FloatingBubbleMethod.checkBackgroundActivity,
          FloatingBubbleMethod.requestBackgroundActivity,
        ],
      );
    });

    test('settings shortcut methods', () async {
      expect(await service.requestAutoBackgroundStart(), isTrue);
      expect(await service.checkPauseAppActivity(), 'enabled');
      expect(await service.requestPauseAppActivity(), isTrue);
      expect(
        calls.map((call) => call.method),
        <String>[
          FloatingBubbleMethod.requestAutoBackgroundStart,
          FloatingBubbleMethod.checkPauseAppActivity,
          FloatingBubbleMethod.requestPauseAppActivity,
        ],
      );
    });

    test('history and reminder methods', () async {
      final history = await service.getDailyHistory();
      expect(history, hasLength(1));
      expect(history.single, BubbleCounter.fromMap(counterMap));

      expect(await service.checkNotificationPermission(), isTrue);
      expect(await service.requestNotificationPermission(), isTrue);
      expect(await service.openNotificationSettings(), isTrue);

      final reminder = await service.setDailyReminder(
        enabled: true,
        hour: 20,
        minute: 30,
      );
      expect(reminder.enabled, isTrue);
      expect(reminder.hour, 20);
      expect(reminder.minute, 30);
      expect(reminder.timeLabel, '08:30 PM');
      expect(reminder.permissionGranted, isTrue);
      expect(reminder.copyWith(enabled: false).enabled, isFalse);
      expect(
        calls.map((call) => call.method),
        <String>[
          FloatingBubbleMethod.getDailyHistory,
          FloatingBubbleMethod.checkNotificationPermission,
          FloatingBubbleMethod.requestNotificationPermission,
          FloatingBubbleMethod.openNotificationSettings,
          FloatingBubbleMethod.setDailyReminder,
        ],
      );
      expect(
        calls.last.arguments,
        <String, Object?>{'enabled': true, 'hour': 20, 'minute': 30},
      );
    });

    test('parses legacy status maps without new fields', () async {
      final legacy = <String, Object?>{
        ...statusMap,
        'backgroundActivityStatus': null,
        'accessibilityEnabled': null,
        'accessibilityServiceRunning': null,
        'detectionState': null,
        'detectionMessage': null,
        'trackingEngineConnected': false,
        'trackingState': 'waiting',
        'trackingMessage': 'Tracking engine not connected',
        'trackingActive': false,
      };
      final status = BubbleStatus.fromMap(legacy);
      expect(status.backgroundActivityStatus, 'unknown');
      expect(status.accessibilityEnabled, isFalse);
      expect(status.detectionState, 'waiting');
      expect(status.trackingActive, isFalse);
    });

    test('recordWatchedVideo', () async {
      final result = await service.recordWatchedVideo(
        ReelPlatform.youtube,
        eventId: 'reel-42',
      );
      expect(result, VideoRecordResult.fromMap(recordResultMap));
      expect(result.recorded, isTrue);
      expect(result.duplicate, isFalse);
      expect(calls.single.method, FloatingBubbleMethod.recordWatchedVideo);
      expect(
        calls.single.arguments,
        <String, Object?>{'platform': 'youtube', 'eventId': 'reel-42'},
      );
    });

    test('maps platform errors to FloatingBubbleException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(
          code: 'OVERLAY_PERMISSION_MISSING',
          message: 'Permission missing',
          details: 'settings',
        );
      });

      expect(
        service.startFloatingBubble(),
        throwsA(
          isA<FloatingBubbleException>()
              .having((error) => error.code, 'code', 'OVERLAY_PERMISSION_MISSING')
              .having((error) => error.message, 'message', 'Permission missing'),
        ),
      );
    });
  });

  group('FloatingBubbleService events', () {
    test('maps event payloads and cancels the listener', () async {
      var canceled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(<String, Object?>{
              'type': FloatingBubbleEventName.counterChanged,
              'status': statusMap,
            });
            events.success(<String, Object?>{
              'type': FloatingBubbleEventName.trackingStatusChanged,
              'status': statusMap,
            });
          },
          onCancel: (arguments) {
            canceled = true;
          },
        ),
      );

      final received = <BubbleEvent>[];
      final subscription = service.events.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      expect(
        received.map((event) => event.type),
        <BubbleEventType>[
          BubbleEventType.counterChanged,
          BubbleEventType.trackingStatusChanged,
        ],
      );
      expect(received.first.status.counter, BubbleCounter.fromMap(counterMap));

      await subscription.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(canceled, isTrue);
    });

    test('maps event errors to FloatingBubbleException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.error(code: 'EVENT_FAILED', message: 'Event failed');
          },
        ),
      );

      final errors = <Object>[];
      final subscription = service.events.listen((_) {}, onError: errors.add);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.single, isA<FloatingBubbleException>());
      expect((errors.single as FloatingBubbleException).code, 'EVENT_FAILED');
      await subscription.cancel();
    });
  });
}
