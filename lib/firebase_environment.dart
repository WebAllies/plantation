enum FirebaseEnvironment {
  production,
  staging,
}

class FirebaseEnvironmentConfig {
  static const String _envValue = String.fromEnvironment(
    'FIREBASE_ENV',
    defaultValue: 'production',
  );

  static FirebaseEnvironment get current {
    switch (_envValue.trim().toLowerCase()) {
      case 'staging':
      case 'stage':
        return FirebaseEnvironment.staging;
      case 'production':
      case 'prod':
      default:
        return FirebaseEnvironment.production;
    }
  }

  static bool get isStaging => current == FirebaseEnvironment.staging;

  static String get name {
    switch (current) {
      case FirebaseEnvironment.staging:
        return 'staging';
      case FirebaseEnvironment.production:
        return 'production';
    }
  }
}
