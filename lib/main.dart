import 'package:flutter/material.dart';

import 'package:reelcount/screens/home_screen.dart';
import 'package:reelcount/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReelCountApp());
}

class ReelCountApp extends StatelessWidget {
  const ReelCountApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReelCount',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}
