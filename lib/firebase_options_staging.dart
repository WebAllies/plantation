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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBx01YAex6ENzhlGUEbAsa94pGtDSNu_is',
    appId: '1:247703648498:web:172360d8d0c665b407b86b',
    messagingSenderId: '247703648498',
    projectId: 'iotaquaapp-staging',
    authDomain: 'iotaquaapp-staging.firebaseapp.com',
    storageBucket: 'iotaquaapp-staging.firebasestorage.app',
    measurementId: 'G-BLCKJG6PY1',
  );

  // Replace placeholders by generating this file from your staging project.

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD3HBEHparkzVJf7BSjgVGQsRZxcCA3ewY',
    appId: '1:247703648498:android:9a457a08d6923e0007b86b',
    messagingSenderId: '247703648498',
    projectId: 'iotaquaapp-staging',
    storageBucket: 'iotaquaapp-staging.firebasestorage.app',
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
    apiKey: 'AIzaSyAc8lbPfO3SzysrpanfsM7ffc_B0KcY6eo',
    appId: '1:247703648498:ios:299655d10e2bcba507b86b',
    messagingSenderId: '247703648498',
    projectId: 'iotaquaapp-staging',
    storageBucket: 'iotaquaapp-staging.firebasestorage.app',
    iosBundleId: 'com.example.iotAquaApp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBx01YAex6ENzhlGUEbAsa94pGtDSNu_is',
    appId: '1:247703648498:web:5d8c188369727cd207b86b',
    messagingSenderId: '247703648498',
    projectId: 'iotaquaapp-staging',
    authDomain: 'iotaquaapp-staging.firebaseapp.com',
    storageBucket: 'iotaquaapp-staging.firebasestorage.app',
    measurementId: 'G-Z12N503TXT',
  );

}