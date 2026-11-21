# AGENTS.md

## Facts / commands
- Flutter package `reelcount` (Dart imports `package:reelcount/...`); Android namespace/applicationId and channel prefix `com.reelcount.app`, despite folder `reelcounter`.
- `README.md` is the untouched Flutter template; trust `pubspec.yaml`, Gradle, and source. No CI, task runner, codegen, or repo-local OpenCode config.
- `flutter analyze` is lint+typecheck. From repo root: `flutter pub get` after pubspec changes, then `flutter analyze`, `flutter test`, `flutter build apk --release`.
- Device work: `flutter build apk --debug`, `adb install -r build\app\outputs\flutter-apk\app-debug.apk`. Focused: `flutter test test/floating_bubble_service_test.dart --plain-name "recordWatchedVideo"`.
- `android/app/build.gradle.kts` signs release with debug config; don't call the APK production-signed.

## Wiring / invariants
- `lib/main.dart` -> `lib/screens/home_screen.dart`; `HomeScreen` takes injectable `FloatingBubbleService` and refreshes on resume. Native is the source of truth; Dart mirrors counter/status from the bridge, never owns counts.
- Only Flutter bridge: `lib/services/floating_bubble_service.dart`. Native: `MainActivity.kt` -> `FloatingBubbleChannel` -> overlay (`overlay/FloatingBubbleService.kt`) and detection (`tracking/ReelDetectionAccessibilityService.kt` -> `VideoCounterManager.kt` -> `BubblePreferences.kt`).
- Fixed channels `com.reelcount.app/floating_bubble` and `com.reelcount.app/floating_bubble_events`; keep Dart constants (`FloatingBubbleMethod`/`FloatingBubbleEventName`), Kotlin constants (`FloatingBubbleChannel.Method`/`Event`), and tests in sync. No `updateCounter`/`incrementCounter`/`decrementCounter`.
- No manual count controls. Detection records via `VideoCounterManager.recordWatchedVideo(platformKey, eventId)`; bridge exposes `recordWatchedVideo(platform, {eventId})`. Platform keys: `instagram|youtube|facebook|tiktok|snapchat`; native dedupes `eventId`. Expanded bubble only has Collapse/Hide.
- Daily counters in SharedPreferences `reelcounter_bubble`; date rollover clears counts + processed IDs, bubble positions persist. `BubbleCounts.total` is derived, not independent.
- Overlay needs `SYSTEM_ALERT_WINDOW` + Android 8+; keep `foregroundServiceType="specialUse"` subtype `floating_bubble_counter` and permission checks.
- Accessibility config must keep `flagReportViewIds|flagIncludeNotImportantViews|flagRetrieveInteractiveWindows`, `canRetrieveWindowContent=true`; window/content events are debounced ~500ms, scroll events immediate.

## Live detection / tests
- Real detection is verified on-device: `adb logcat -c; adb logcat -s ReelDetection VideoCounterManager BubbleUpdate`. Success: `VIEWER_DETECTED` -> `VIDEO_CONTENT_IDENTIFIED` -> `DUPLICATE_CHECK` -> `REEL_RECORDED` -> `COUNTER_UPDATED`/`BUBBLE_UPDATED`; failures emit `VIEWER_DETECTION_FAILED` plus `TREE`/`SCROLLABLE` diagnostics.
- Xiaomi test device blocks `adb shell input`/`keyevent` and `settings put secure`; user must scroll and toggle accessibility manually. Service does not auto-rebind after reinstall/`am force-stop`.
- `uiautomator dump` is the reference for viewer nodes. Normal apps need fullscreen scrollable node with media; Snapchat Spotlight has no scrollable node (`opera_viewer`/`spotlight_container`), Facebook ids are `(name removed)` and rely on caption-like `contentDescription` with `#` while feedGuard rejects feeds.
- Never derive identity from arbitrary UI text (`Create a reel` gave constant Instagram `eventId` and duplicate rejection); use author/caption fields or structural identity with scroll epoch + session nonce.
- Channel tests mock `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger`; event tests use `MockStreamHandler`. Widget tests assert no `+1`/`-1`, confirmation-only reset, and independent bubble/accessibility/detection statuses.
