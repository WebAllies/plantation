import 'package:firebase_core/firebase_core.dart';

import 'firebase_environment.dart';
import 'firebase_options_production.dart' as production;
import 'firebase_options_staging.dart' as staging;

class FirebaseBootstrap {
  static FirebaseOptions get options {
    if (FirebaseEnvironmentConfig.isStaging) {
      final candidate = staging.DefaultFirebaseOptions.currentPlatform;
      if (!_looksConfigured(candidate)) {
        throw StateError(
          'Staging Firebase options are not configured. '
          'Run: flutterfire configure --project <staging-project-id> '
          '--out lib/firebase_options_staging.dart',
        );
      }
      return candidate;
    }

    return production.DefaultFirebaseOptions.currentPlatform;
  }

  static bool _looksConfigured(FirebaseOptions options) {
    bool valid(String value) {
      final trimmed = value.trim();
      return trimmed.isNotEmpty && !trimmed.contains('REPLACE_ME');
    }

    return valid(options.projectId) &&
        valid(options.appId) &&
        valid(options.apiKey) &&
        valid(options.messagingSenderId);
  }
}
