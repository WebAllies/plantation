// File intended for staging Firebase project.
//
// Generate real staging values with FlutterFire CLI:
// flutterfire configure --project <staging-project-id> --out lib/firebase_options_staging.dart
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // Replace placeholders by generating this file from your staging project.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE_ME_STAGING_API_KEY',
    appId: 'REPLACE_ME_STAGING_APP_ID',
    messagingSenderId: 'REPLACE_ME_STAGING_SENDER_ID',
    projectId: 'REPLACE_ME_STAGING_PROJECT_ID',
    authDomain: 'REPLACE_ME_STAGING_AUTH_DOMAIN',
    storageBucket: 'REPLACE_ME_STAGING_STORAGE_BUCKET',
    measurementId: 'REPLACE_ME_STAGING_MEASUREMENT_ID',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_ME_STAGING_API_KEY',
    appId: 'REPLACE_ME_STAGING_APP_ID',
    messagingSenderId: 'REPLACE_ME_STAGING_SENDER_ID',
    projectId: 'REPLACE_ME_STAGING_PROJECT_ID',
    storageBucket: 'REPLACE_ME_STAGING_STORAGE_BUCKET',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_ME_STAGING_API_KEY',
    appId: 'REPLACE_ME_STAGING_APP_ID',
    messagingSenderId: 'REPLACE_ME_STAGING_SENDER_ID',
    projectId: 'REPLACE_ME_STAGING_PROJECT_ID',
    storageBucket: 'REPLACE_ME_STAGING_STORAGE_BUCKET',
    iosBundleId: 'REPLACE_ME_STAGING_IOS_BUNDLE_ID',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'REPLACE_ME_STAGING_API_KEY',
    appId: 'REPLACE_ME_STAGING_APP_ID',
    messagingSenderId: 'REPLACE_ME_STAGING_SENDER_ID',
    projectId: 'REPLACE_ME_STAGING_PROJECT_ID',
    storageBucket: 'REPLACE_ME_STAGING_STORAGE_BUCKET',
    iosBundleId: 'REPLACE_ME_STAGING_IOS_BUNDLE_ID',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'REPLACE_ME_STAGING_API_KEY',
    appId: 'REPLACE_ME_STAGING_APP_ID',
    messagingSenderId: 'REPLACE_ME_STAGING_SENDER_ID',
    projectId: 'REPLACE_ME_STAGING_PROJECT_ID',
    authDomain: 'REPLACE_ME_STAGING_AUTH_DOMAIN',
    storageBucket: 'REPLACE_ME_STAGING_STORAGE_BUCKET',
    measurementId: 'REPLACE_ME_STAGING_MEASUREMENT_ID',
  );
}
