import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'core/device/device_selection_controller.dart';
import 'firebase_bootstrap.dart';
import 'firebase_environment.dart';

// Theme controller
import 'core/theme/theme_controller.dart';

// Start page
import 'features/auth/app_auth_root.dart';

final ThemeController themeController = ThemeController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? startupError;
  StackTrace? startupStack;
  try {
    await Firebase.initializeApp(
      options: FirebaseBootstrap.options,
    ).timeout(const Duration(seconds: 20));
    await themeController.load().timeout(const Duration(seconds: 10));
  } catch (e, st) {
    startupError = e;
    startupStack = st;
    debugPrint('Startup error: $e');
    debugPrint('$st');
  }

  runApp(MyApp(startupError: startupError, startupStack: startupStack));
}

class MyApp extends StatelessWidget {
  final Object? startupError;
  final StackTrace? startupStack;

  const MyApp({super.key, this.startupError, this.startupStack});

  @override
  Widget build(BuildContext context) {
    if (startupError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _StartupErrorPage(error: startupError!, stack: startupStack),
      );
    }

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
            home: const AppAuthRoot(),
          );
        },
      ),
    );
  }
}

class _StartupErrorPage extends StatelessWidget {
  final Object error;
  final StackTrace? stack;

  const _StartupErrorPage({required this.error, this.stack});

  @override
  Widget build(BuildContext context) {
    final env = FirebaseEnvironmentConfig.name;
    return Scaffold(
      appBar: AppBar(title: const Text('Startup Error')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: SelectableText(
            'Environment: $env\n\n'
            'App failed during startup.\n\n'
            'Likely cause on Android: `google-services.json` project does not '
            'match the selected FIREBASE_ENV options.\n\n'
            'Error:\n$error\n\n'
            'Stack:\n${stack ?? 'n/a'}',
          ),
        ),
      ),
    );
  }
}
