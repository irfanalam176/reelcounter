import 'package:flutter_test/flutter_test.dart';

import 'package:reelcount/services/floating_bubble_service.dart';

void main() {
  final counter = <String, Object?>{
    'total': 3,
    'instagram': 3,
    'youtube': 0,
    'facebook': 0,
    'tiktok': 0,
    'snapchat': 0,
    'date': '2026-11-19',
  };

  BubbleStatus statusFor({
    required bool bubbleVisible,
    required bool accessibilityEnabled,
    required bool serviceRunning,
    required String detectionState,
  }) =>
      BubbleStatus.fromMap(<String, Object?>{
        'bubbleVisible': bubbleVisible,
        'expanded': false,
        'overlayPermissionGranted': true,
        'serviceRunning': serviceRunning,
        'accessibilityEnabled': accessibilityEnabled,
        'accessibilityServiceRunning': serviceRunning && detectionState == 'active',
        'detectionState': detectionState,
        'detectionMessage': 'state: $detectionState',
        'counter': counter,
      });

  test('bubble visibility alone does not make tracking active', () {
    final status = statusFor(
      bubbleVisible: true,
      accessibilityEnabled: false,
      serviceRunning: true,
      detectionState: 'waiting',
    );

    expect(status.serviceRunning, isTrue);
    expect(status.bubbleVisible, isTrue);
    expect(status.accessibilityEnabled, isFalse);
    expect(status.detectionState, 'waiting');
    expect(status.trackingActive, isFalse);
  });

  test('detection alone does not make tracking active', () {
    final status = statusFor(
      bubbleVisible: false,
      accessibilityEnabled: true,
      serviceRunning: false,
      detectionState: 'active',
    );

    expect(status.detectionState, 'active');
    expect(status.trackingActive, isFalse);
  });

  test('tracking requires an active detector and a visible bubble', () {
    final status = statusFor(
      bubbleVisible: true,
      accessibilityEnabled: true,
      serviceRunning: true,
      detectionState: 'active',
    );

    expect(status.trackingEngineConnected, isTrue);
    expect(status.trackingState, 'active');
    expect(status.trackingActive, isTrue);
  });

  test('detection errors are reported separately from bubble state', () {
    final status = statusFor(
      bubbleVisible: true,
      accessibilityEnabled: true,
      serviceRunning: true,
      detectionState: 'error',
    );

    expect(status.detectionState, 'error');
    expect(status.detectionMessage, 'state: error');
    expect(status.trackingActive, isFalse);
  });
}
