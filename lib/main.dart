import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'core/device/device_selection_controller.dart';
import 'firebase_bootstrap.dart';
import 'firebase_environment.dart';

// Theme controller
import 'core/theme/theme_controller.dart';

// Start page
import 'features/onboarding/onboarding_page.dart';

final ThemeController themeController = ThemeController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: FirebaseBootstrap.options);

  await themeController.load();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DeviceSelectionController(),
      child: AnimatedBuilder(
        animation: themeController,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: FirebaseEnvironmentConfig.isStaging
                ? "AquaFarm (Staging)"
                : "AquaFarm",
            themeMode: themeController.mode,
            theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
            darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
            ),
            home: const OnboardingPage(), // ✅ always show onboarding
          );
        },
      ),
    );
  }
}
