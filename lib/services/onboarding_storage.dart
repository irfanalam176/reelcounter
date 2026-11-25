import 'package:shared_preferences/shared_preferences.dart';

abstract class OnboardingStorage {
  Future<bool> isCompleted();
  Future<int> currentStep();
  Future<Set<String>> confirmedSteps();
  Future<void> saveProgress({
    required int step,
    required Set<String> confirmedSteps,
  });
  Future<void> setCompleted({required bool completed});
  Future<void> clear();
}

class SharedPreferencesOnboardingStorage implements OnboardingStorage {
  SharedPreferencesOnboardingStorage({this.preferences});

  static const completedKey = 'onboarding_completed';
  static const stepKey = 'onboarding_step';
  static const confirmedStepsKey = 'onboarding_confirmed_steps';

  final SharedPreferences? preferences;

  Future<SharedPreferences> get _store async {
    final injected = preferences;
    if (injected != null) {
      return injected;
    }
    return SharedPreferences.getInstance();
  }

  @override
  Future<bool> isCompleted() async => (await _store).getBool(completedKey) ?? false;

  @override
  Future<int> currentStep() async => (await _store).getInt(stepKey) ?? 0;

  @override
  Future<Set<String>> confirmedSteps() async =>
      (await _store).getStringList(confirmedStepsKey)?.toSet() ?? <String>{};

  @override
  Future<void> saveProgress({
    required int step,
    required Set<String> confirmedSteps,
  }) async {
    final preferences = await _store;
    await preferences.setInt(stepKey, step);
    await preferences.setStringList(confirmedStepsKey, confirmedSteps.toList());
  }

  @override
  Future<void> setCompleted({required bool completed}) async =>
      (await _store).setBool(completedKey, completed);

  @override
  Future<void> clear() async {
    final preferences = await _store;
    await preferences.remove(completedKey);
    await preferences.remove(stepKey);
    await preferences.remove(confirmedStepsKey);
  }
}
