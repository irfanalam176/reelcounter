import 'package:flutter/material.dart';

import 'package:reelcount/screens/home_screen.dart';
import 'package:reelcount/screens/onboarding_screen.dart';
import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/services/onboarding_storage.dart';
import 'package:reelcount/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReelCountApp());
}

class ReelCountApp extends StatefulWidget {
  const ReelCountApp({super.key, this.service, this.storage});

  final FloatingBubbleService? service;
  final OnboardingStorage? storage;

  @override
  State<ReelCountApp> createState() => _ReelCountAppState();
}

class _ReelCountAppState extends State<ReelCountApp> {
  late final OnboardingStorage _storage;
  bool? _onboardingComplete;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? SharedPreferencesOnboardingStorage();
    _loadOnboardingState();
  }

  Future<void> _loadOnboardingState() async {
    try {
      final complete = await _storage.isCompleted();
      if (!mounted) {
        return;
      }
      setState(() {
        _onboardingComplete = complete;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loadError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReelCount',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Could not load app settings',
                  style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_loadError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loadOnboardingState,
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return switch (_onboardingComplete) {
      null => const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.green)),
        ),
      false => OnboardingFlow(
          service: widget.service,
          storage: _storage,
          onFinished: () => setState(() => _onboardingComplete = true),
        ),
      true => HomeScreen(service: widget.service, storage: _storage),
    };
  }
}
