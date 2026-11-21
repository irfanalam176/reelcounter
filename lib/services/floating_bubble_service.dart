import 'dart:async';

import 'package:flutter/services.dart';

class FloatingBubbleMethod {
  static const checkOverlayPermission = 'checkOverlayPermission';
  static const requestOverlayPermission = 'requestOverlayPermission';
  static const startFloatingBubble = 'startFloatingBubble';
  static const stopFloatingBubble = 'stopFloatingBubble';
  static const showFloatingBubble = 'showFloatingBubble';
  static const hideFloatingBubble = 'hideFloatingBubble';
  static const expandFloatingBubble = 'expandFloatingBubble';
  static const collapseFloatingBubble = 'collapseFloatingBubble';
  static const resetCounter = 'resetCounter';
  static const getCounter = 'getCounter';
  static const getBubbleStatus = 'getBubbleStatus';
  static const recordWatchedVideo = 'recordWatchedVideo';
  static const checkAccessibilityPermission = 'checkAccessibilityPermission';
  static const requestAccessibilityPermission = 'requestAccessibilityPermission';
}

class FloatingBubbleEventName {
  static const counterChanged = 'counterChanged';
  static const bubbleStarted = 'bubbleStarted';
  static const bubbleStopped = 'bubbleStopped';
  static const bubbleShown = 'bubbleShown';
  static const bubbleHidden = 'bubbleHidden';
  static const bubbleExpanded = 'bubbleExpanded';
  static const bubbleCollapsed = 'bubbleCollapsed';
  static const overlayPermissionChanged = 'overlayPermissionChanged';
  static const trackingStatusChanged = 'trackingStatusChanged';
}

enum ReelPlatform {
  instagram('instagram'),
  youtube('youtube'),
  facebook('facebook'),
  tiktok('tiktok'),
  snapchat('snapchat');

  final String key;

  const ReelPlatform(this.key);

  static ReelPlatform fromKey(String key) =>
      values.firstWhere((platform) => platform.key == key);
}

enum BubbleEventType {
  counterChanged(FloatingBubbleEventName.counterChanged),
  bubbleStarted(FloatingBubbleEventName.bubbleStarted),
  bubbleStopped(FloatingBubbleEventName.bubbleStopped),
  bubbleShown(FloatingBubbleEventName.bubbleShown),
  bubbleHidden(FloatingBubbleEventName.bubbleHidden),
  bubbleExpanded(FloatingBubbleEventName.bubbleExpanded),
  bubbleCollapsed(FloatingBubbleEventName.bubbleCollapsed),
  overlayPermissionChanged(FloatingBubbleEventName.overlayPermissionChanged),
  trackingStatusChanged(FloatingBubbleEventName.trackingStatusChanged);

  final String value;

  const BubbleEventType(this.value);

  static BubbleEventType fromValue(String value) =>
      values.firstWhere((type) => type.value == value);
}

class FloatingBubbleException implements Exception {
  const FloatingBubbleException(this.code, this.message, [this.details]);

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'FloatingBubbleException($code): $message';
}

class BubbleCounter {
  const BubbleCounter({
    required this.total,
    required this.instagram,
    required this.youtube,
    required this.facebook,
    required this.tiktok,
    required this.snapchat,
    required this.date,
  });

  final int total;
  final int instagram;
  final int youtube;
  final int facebook;
  final int tiktok;
  final int snapchat;
  final String date;

  factory BubbleCounter.fromMap(Object? value) {
    final map = _readMap(value, 'counter');
    return BubbleCounter(
      total: _readInt(map, 'total'),
      instagram: _readInt(map, ReelPlatform.instagram.key),
      youtube: _readInt(map, ReelPlatform.youtube.key),
      facebook: _readInt(map, ReelPlatform.facebook.key),
      tiktok: _readInt(map, ReelPlatform.tiktok.key),
      snapchat: _readInt(map, ReelPlatform.snapchat.key),
      date: _readString(map, 'date'),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'total': total,
        ReelPlatform.instagram.key: instagram,
        ReelPlatform.youtube.key: youtube,
        ReelPlatform.facebook.key: facebook,
        ReelPlatform.tiktok.key: tiktok,
        ReelPlatform.snapchat.key: snapchat,
        'date': date,
      };

  int countFor(ReelPlatform platform) => switch (platform) {
        ReelPlatform.instagram => instagram,
        ReelPlatform.youtube => youtube,
        ReelPlatform.facebook => facebook,
        ReelPlatform.tiktok => tiktok,
        ReelPlatform.snapchat => snapchat,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BubbleCounter &&
          total == other.total &&
          instagram == other.instagram &&
          youtube == other.youtube &&
          facebook == other.facebook &&
          tiktok == other.tiktok &&
          snapchat == other.snapchat &&
          date == other.date;

  @override
  int get hashCode => Object.hash(
        total,
        instagram,
        youtube,
        facebook,
        tiktok,
        snapchat,
        date,
      );

  @override
  String toString() => 'BubbleCounter(total: $total, date: $date)';
}

class BubbleStatus {
  const BubbleStatus({
    required this.bubbleVisible,
    required this.expanded,
    required this.overlayPermissionGranted,
    required this.serviceRunning,
    required this.counter,
    this.accessibilityEnabled = false,
    this.accessibilityServiceRunning = false,
    this.detectionState = 'waiting',
    this.detectionMessage = 'Tracking engine not connected',
  });

  final bool bubbleVisible;
  final bool expanded;
  final bool overlayPermissionGranted;
  final bool serviceRunning;
  final bool accessibilityEnabled;
  final bool accessibilityServiceRunning;
  final String detectionState;
  final String detectionMessage;
  final BubbleCounter counter;

  bool get trackingEngineConnected => accessibilityServiceRunning;

  String get trackingState => detectionState;

  String get trackingMessage => detectionMessage;

  bool get trackingActive => bubbleVisible && detectionState == 'active';

  factory BubbleStatus.fromMap(Object? value) {
    final map = _readMap(value, 'status');
    return BubbleStatus(
      bubbleVisible: _readBool(map, 'bubbleVisible'),
      expanded: _readBool(map, 'expanded'),
      overlayPermissionGranted: _readBool(map, 'overlayPermissionGranted'),
      serviceRunning: _readBool(map, 'serviceRunning'),
      counter: BubbleCounter.fromMap(map['counter']),
      accessibilityEnabled: _readBoolOr(map, 'accessibilityEnabled', false),
      accessibilityServiceRunning: _readBoolOr(
        map,
        'accessibilityServiceRunning',
        _readBoolOr(map, 'trackingEngineConnected', false),
      ),
      detectionState: _readStringOr(
        map,
        'detectionState',
        _readStringOr(map, 'trackingState', 'waiting'),
      ),
      detectionMessage: _readStringOr(
        map,
        'detectionMessage',
        _readStringOr(map, 'trackingMessage', 'Tracking engine not connected'),
      ),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'bubbleVisible': bubbleVisible,
        'expanded': expanded,
        'overlayPermissionGranted': overlayPermissionGranted,
        'serviceRunning': serviceRunning,
        'accessibilityEnabled': accessibilityEnabled,
        'accessibilityServiceRunning': accessibilityServiceRunning,
        'detectionState': detectionState,
        'detectionMessage': detectionMessage,
        'trackingEngineConnected': trackingEngineConnected,
        'trackingState': trackingState,
        'trackingMessage': trackingMessage,
        'trackingActive': trackingActive,
        'counter': counter.toMap(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BubbleStatus &&
          bubbleVisible == other.bubbleVisible &&
          expanded == other.expanded &&
          overlayPermissionGranted == other.overlayPermissionGranted &&
          serviceRunning == other.serviceRunning &&
          accessibilityEnabled == other.accessibilityEnabled &&
          accessibilityServiceRunning == other.accessibilityServiceRunning &&
          detectionState == other.detectionState &&
          detectionMessage == other.detectionMessage &&
          counter == other.counter;

  @override
  int get hashCode => Object.hash(
        bubbleVisible,
        expanded,
        overlayPermissionGranted,
        serviceRunning,
        accessibilityEnabled,
        accessibilityServiceRunning,
        detectionState,
        detectionMessage,
        counter,
      );

  @override
  String toString() => 'BubbleStatus($detectionState)';
}

class VideoRecordResult {
  const VideoRecordResult({
    required this.recorded,
    required this.duplicate,
    required this.counter,
  });

  final bool recorded;
  final bool duplicate;
  final BubbleCounter counter;

  factory VideoRecordResult.fromMap(Object? value) {
    final map = _readMap(value, 'videoRecordResult');
    return VideoRecordResult(
      recorded: _readBool(map, 'recorded'),
      duplicate: _readBool(map, 'duplicate'),
      counter: BubbleCounter.fromMap(map['counter']),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'recorded': recorded,
        'duplicate': duplicate,
        'counter': counter.toMap(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoRecordResult &&
          recorded == other.recorded &&
          duplicate == other.duplicate &&
          counter == other.counter;

  @override
  int get hashCode => Object.hash(recorded, duplicate, counter);

  @override
  String toString() =>
      'VideoRecordResult(recorded: $recorded, duplicate: $duplicate)';
}

class BubbleEvent {
  const BubbleEvent({required this.type, required this.status});

  final BubbleEventType type;
  final BubbleStatus status;

  factory BubbleEvent.fromMap(Object? value) {
    final map = _readMap(value, 'event');
    return BubbleEvent(
      type: BubbleEventType.fromValue(_readString(map, 'type')),
      status: BubbleStatus.fromMap(map['status']),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'type': type.value,
        'status': status.toMap(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BubbleEvent && type == other.type && status == other.status;

  @override
  int get hashCode => Object.hash(type, status);

  @override
  String toString() => 'BubbleEvent(${type.value})';
}

class FloatingBubbleService {
  FloatingBubbleService({MethodChannel? methodChannel, EventChannel? eventChannel})
      : _methodChannel = methodChannel ?? const MethodChannel(methodChannelName),
        _eventChannel = eventChannel ?? const EventChannel(eventChannelName);

  static const methodChannelName = 'com.reelcount.app/floating_bubble';
  static const eventChannelName = 'com.reelcount.app/floating_bubble_events';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<BubbleEvent> get events =>
      _eventChannel.receiveBroadcastStream().transform<BubbleEvent>(
            StreamTransformer<Object?, BubbleEvent>.fromHandlers(
              handleData: (data, sink) {
                try {
                  sink.add(BubbleEvent.fromMap(data));
                } catch (error, stackTrace) {
                  sink.addError(error, stackTrace);
                }
              },
              handleError: (Object error, StackTrace stackTrace, sink) {
                sink.addError(_mapPlatformError(error), stackTrace);
              },
            ),
          );

  Future<bool> checkOverlayPermission() =>
      _invoke(FloatingBubbleMethod.checkOverlayPermission, _readBoolValue);

  Future<bool> requestOverlayPermission() =>
      _invoke(FloatingBubbleMethod.requestOverlayPermission, _readBoolValue);

  Future<bool> startFloatingBubble() =>
      _invoke(FloatingBubbleMethod.startFloatingBubble, _readBoolValue);

  Future<bool> stopFloatingBubble() =>
      _invoke(FloatingBubbleMethod.stopFloatingBubble, _readBoolValue);

  Future<bool> showFloatingBubble() =>
      _invoke(FloatingBubbleMethod.showFloatingBubble, _readBoolValue);

  Future<bool> hideFloatingBubble() =>
      _invoke(FloatingBubbleMethod.hideFloatingBubble, _readBoolValue);

  Future<bool> expandFloatingBubble() =>
      _invoke(FloatingBubbleMethod.expandFloatingBubble, _readBoolValue);

  Future<bool> collapseFloatingBubble() =>
      _invoke(FloatingBubbleMethod.collapseFloatingBubble, _readBoolValue);

  Future<BubbleCounter> resetCounter() =>
      _invoke(FloatingBubbleMethod.resetCounter, BubbleCounter.fromMap);

  Future<BubbleCounter> getCounter() =>
      _invoke(FloatingBubbleMethod.getCounter, BubbleCounter.fromMap);

  Future<BubbleStatus> getBubbleStatus() =>
      _invoke(FloatingBubbleMethod.getBubbleStatus, BubbleStatus.fromMap);

  Future<bool> checkAccessibilityPermission() =>
      _invoke(FloatingBubbleMethod.checkAccessibilityPermission, _readBoolValue);

  Future<bool> requestAccessibilityPermission() =>
      _invoke(FloatingBubbleMethod.requestAccessibilityPermission, _readBoolValue);

  Future<VideoRecordResult> recordWatchedVideo(
    ReelPlatform platform, {
    String? eventId,
  }) =>
      _invoke(
        FloatingBubbleMethod.recordWatchedVideo,
        VideoRecordResult.fromMap,
        <String, Object?>{
          'platform': platform.key,
          'eventId': ?eventId,
        },
      );

  Future<T> _invoke<T>(
    String method,
    T Function(Object? value) decoder, [
    Object? arguments,
  ]) async {
    try {
      final value = await _methodChannel.invokeMethod<Object?>(method, arguments);
      return decoder(value);
    } on PlatformException catch (error) {
      throw FloatingBubbleException(
        error.code,
        error.message ?? 'Floating bubble operation failed',
        error.details,
      );
    } on MissingPluginException catch (error) {
      throw FloatingBubbleException(
        'CHANNEL_UNAVAILABLE',
        error.message ?? 'Floating bubble channel is unavailable',
      );
    }
  }

  Object _mapPlatformError(Object error) {
    if (error is PlatformException) {
      return FloatingBubbleException(
        error.code,
        error.message ?? 'Floating bubble event failed',
        error.details,
      );
    }
    return error;
  }
}

Map<Object?, Object?> _readMap(Object? value, String name) {
  if (value is Map) {
    return value.map((key, item) => MapEntry<Object?, Object?>(key, item));
  }
  throw FormatException('Expected map for $name', value);
}

int _readInt(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('Expected int for $key', value);
}

String _readString(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is String) {
    return value;
  }
  throw FormatException('Expected string for $key', value);
}

bool _readBool(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected bool for $key', value);
}

bool _readBoolOr(Map<Object?, Object?> map, String key, bool fallback) {
  final value = map[key];
  return value is bool ? value : fallback;
}

String _readStringOr(Map<Object?, Object?> map, String key, String fallback) {
  final value = map[key];
  return value is String ? value : fallback;
}

bool _readBoolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected bool result', value);
}
