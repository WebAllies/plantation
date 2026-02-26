import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_lock_models.dart';
import 'pin_crypto.dart';

abstract class AppLockStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureAppLockStore implements AppLockStore {
  final FlutterSecureStorage _storage;

  SecureAppLockStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

abstract class AppLockRemoteStore {
  Future<AppLockRemoteConfig> fetchConfig(String uid);
  Future<void> ensureDefaults(String uid);
  Future<void> setBiometricPreferred(String uid, bool value);
}

class FirestoreAppLockRemoteStore implements AppLockRemoteStore {
  final FirebaseFirestore _db;

  FirestoreAppLockRemoteStore({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return _db.collection('users').doc(uid);
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  @override
  Future<void> ensureDefaults(String uid) async {
    final ref = _userRef(uid);
    final snap = await ref.get();

    final defaults = AppLockRemoteConfig.defaults();
    final defaultMap = <String, dynamic>{
      'enforced': defaults.enforced,
      'pinVersion': defaults.pinVersion,
      'pinPolicy': defaults.pinPolicy,
      'biometricPreferred': defaults.biometricPreferred,
      'resetAt': null,
      'resetByUid': null,
      'resetByRole': null,
    };

    if (!snap.exists) {
      await ref.set({
        'security': {'appLock': defaultMap},
      }, SetOptions(merge: true));
      return;
    }

    final data = snap.data() ?? <String, dynamic>{};
    final security = _asMap(data['security']);
    final appLock = _asMap(security['appLock']);

    final patch = <String, dynamic>{};
    if (!appLock.containsKey('enforced')) {
      patch['security.appLock.enforced'] = defaults.enforced;
    }
    if (!appLock.containsKey('pinVersion')) {
      patch['security.appLock.pinVersion'] = defaults.pinVersion;
    }
    if (!appLock.containsKey('pinPolicy')) {
      patch['security.appLock.pinPolicy'] = defaults.pinPolicy;
    }
    if (!appLock.containsKey('biometricPreferred')) {
      patch['security.appLock.biometricPreferred'] =
          defaults.biometricPreferred;
    }
    if (!appLock.containsKey('resetAt')) {
      patch['security.appLock.resetAt'] = null;
    }
    if (!appLock.containsKey('resetByUid')) {
      patch['security.appLock.resetByUid'] = null;
    }
    if (!appLock.containsKey('resetByRole')) {
      patch['security.appLock.resetByRole'] = null;
    }

    if (patch.isNotEmpty) {
      await ref.update(patch);
    }
  }

  @override
  Future<AppLockRemoteConfig> fetchConfig(String uid) async {
    final snap = await _userRef(uid).get();
    if (!snap.exists) return AppLockRemoteConfig.defaults();

    final data = snap.data() ?? <String, dynamic>{};
    final security = _asMap(data['security']);
    final appLock = _asMap(security['appLock']);

    final defaults = AppLockRemoteConfig.defaults();
    final enforced = appLock['enforced'] is bool
        ? appLock['enforced'] as bool
        : defaults.enforced;
    final pinVersion = appLock['pinVersion'] is int
        ? appLock['pinVersion'] as int
        : defaults.pinVersion;
    final pinPolicy = appLock['pinPolicy'] is String
        ? appLock['pinPolicy'] as String
        : defaults.pinPolicy;
    final biometricPreferred = appLock['biometricPreferred'] is bool
        ? appLock['biometricPreferred'] as bool
        : defaults.biometricPreferred;

    return AppLockRemoteConfig(
      enforced: enforced,
      pinVersion: pinVersion,
      pinPolicy: pinPolicy,
      biometricPreferred: biometricPreferred,
    );
  }

  @override
  Future<void> setBiometricPreferred(String uid, bool value) async {
    await _userRef(uid).set({
      'security': {
        'appLock': {'biometricPreferred': value},
      },
    }, SetOptions(merge: true));
  }
}

class AppLockService {
  static const int maxAttemptsBeforeCooldown = 5;
  static const int cooldownSeconds = 30;

  final AppLockStore _store;
  final AppLockRemoteStore _remote;
  final PinCrypto _pinCrypto;

  AppLockService({
    AppLockStore? store,
    AppLockRemoteStore? remoteStore,
    PinCrypto? pinCrypto,
  }) : _store = store ?? SecureAppLockStore(),
       _remote = remoteStore ?? FirestoreAppLockRemoteStore(),
       _pinCrypto = pinCrypto ?? PinCrypto();

  static bool isValidPin(String pin) {
    return RegExp(r'^\d{6}$').hasMatch(pin);
  }

  String _k(String uid, String suffix) => 'app_lock.$uid.$suffix';

  Future<int> _readInt(String key, {int fallback = 0}) async {
    final raw = await _store.read(key);
    return int.tryParse(raw ?? '') ?? fallback;
  }

  Future<void> _writeInt(String key, int value) {
    return _store.write(key, value.toString());
  }

  Future<void> ensureRemoteDefaults(String uid) async {
    await _remote.ensureDefaults(uid);
  }

  Future<AppLockState> getLockState(String uid) async {
    final remoteDefaults = AppLockRemoteConfig.defaults();
    AppLockRemoteConfig remoteConfig = remoteDefaults;
    var remoteLoaded = false;
    try {
      remoteConfig = await _remote.fetchConfig(uid);
      remoteLoaded = true;
    } catch (_) {
      remoteConfig = remoteDefaults;
    }

    var localVersion = await _readInt(
      _k(uid, 'pin_version'),
      fallback: remoteConfig.pinVersion,
    );
    String? localHash = await _store.read(_k(uid, 'pin_hash'));

    // Remote version bump forces local PIN re-setup.
    // Only enforce this when remote config was successfully fetched.
    if (remoteLoaded && localVersion != remoteConfig.pinVersion) {
      await _clearLocalPin(uid);
      localVersion = remoteConfig.pinVersion;
      await _writeInt(_k(uid, 'pin_version'), localVersion);
      localHash = null;
    }

    final lockoutUntilMs = await _readInt(_k(uid, 'lockout_until_ms'));
    final failedAttempts = await _readInt(_k(uid, 'failed_attempts'));

    final lockoutUntil = lockoutUntilMs <= 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lockoutUntilMs, isUtc: true);

    final biometricRaw = await _store.read(_k(uid, 'biometric_enabled'));
    final biometricEnabled = biometricRaw == null
        ? remoteConfig.biometricPreferred
        : biometricRaw == '1';
    if (biometricRaw == null) {
      await _store.write(
        _k(uid, 'biometric_enabled'),
        biometricEnabled ? '1' : '0',
      );
    }

    final needsSetup = remoteConfig.enforced && localHash == null;

    return AppLockState(
      needsSetup: needsSetup,
      biometricEnabled: biometricEnabled,
      failedAttempts: failedAttempts,
      lockoutUntil: lockoutUntil,
      localPinVersion: localVersion,
      remoteConfig: remoteConfig,
    );
  }

  Future<void> setBiometricPreference(String uid, bool enabled) async {
    await _store.write(_k(uid, 'biometric_enabled'), enabled ? '1' : '0');
    try {
      await _remote.setBiometricPreferred(uid, enabled);
    } catch (_) {}
  }

  Future<void> setPin({
    required String uid,
    required String pin,
    required bool biometricEnabled,
  }) async {
    if (!isValidPin(pin)) {
      throw ArgumentError('PIN must be exactly 6 digits.');
    }

    AppLockRemoteConfig remoteConfig = AppLockRemoteConfig.defaults();
    try {
      remoteConfig = await _remote.fetchConfig(uid);
    } catch (_) {}

    final hashBundle = await _pinCrypto.hashPin(pin);
    await _store.write(_k(uid, 'pin_hash'), hashBundle.hashBase64);
    await _store.write(_k(uid, 'pin_salt'), hashBundle.saltBase64);
    await _writeInt(_k(uid, 'pin_version'), remoteConfig.pinVersion);
    await _writeInt(_k(uid, 'failed_attempts'), 0);
    await _writeInt(_k(uid, 'lockout_until_ms'), 0);
    await setBiometricPreference(uid, biometricEnabled);
  }

  Future<void> _clearLocalPin(String uid) async {
    await _store.delete(_k(uid, 'pin_hash'));
    await _store.delete(_k(uid, 'pin_salt'));
    await _writeInt(_k(uid, 'failed_attempts'), 0);
    await _writeInt(_k(uid, 'lockout_until_ms'), 0);
  }

  Future<void> resetPinOnDevice(String uid) async {
    var version = await _readInt(_k(uid, 'pin_version'), fallback: 1);
    try {
      final remote = await _remote.fetchConfig(uid);
      version = remote.pinVersion;
    } catch (_) {}

    await _clearLocalPin(uid);
    await _writeInt(_k(uid, 'pin_version'), version);
  }

  Future<AppLockVerifyResult> verifyPin({
    required String uid,
    required String pin,
  }) async {
    if (!isValidPin(pin)) {
      return const AppLockVerifyResult(status: AppLockVerifyStatus.invalidPin);
    }

    final state = await getLockState(uid);
    if (state.needsSetup) {
      return const AppLockVerifyResult(
        status: AppLockVerifyStatus.setupRequired,
      );
    }

    final cooldown = state.cooldownRemainingSeconds;
    if (cooldown > 0) {
      return AppLockVerifyResult(
        status: AppLockVerifyStatus.cooldownActive,
        cooldownRemainingSeconds: cooldown,
      );
    }

    final expectedHash = await _store.read(_k(uid, 'pin_hash'));
    final salt = await _store.read(_k(uid, 'pin_salt'));
    if (expectedHash == null || salt == null) {
      return const AppLockVerifyResult(
        status: AppLockVerifyStatus.setupRequired,
      );
    }

    final matches = await _pinCrypto.verifyPin(
      pin: pin,
      expectedHashBase64: expectedHash,
      saltBase64: salt,
    );

    if (matches) {
      await _writeInt(_k(uid, 'failed_attempts'), 0);
      await _writeInt(_k(uid, 'lockout_until_ms'), 0);
      return AppLockVerifyResult.success();
    }

    final nextFailedAttempts = state.failedAttempts + 1;
    if (nextFailedAttempts >= maxAttemptsBeforeCooldown) {
      final lockoutUntil = DateTime.now()
          .toUtc()
          .add(const Duration(seconds: cooldownSeconds))
          .millisecondsSinceEpoch;
      await _writeInt(_k(uid, 'failed_attempts'), 0);
      await _writeInt(_k(uid, 'lockout_until_ms'), lockoutUntil);
      return const AppLockVerifyResult(
        status: AppLockVerifyStatus.cooldownActive,
        cooldownRemainingSeconds: cooldownSeconds,
      );
    }

    await _writeInt(_k(uid, 'failed_attempts'), nextFailedAttempts);
    final attemptsRemaining = maxAttemptsBeforeCooldown - nextFailedAttempts;
    return AppLockVerifyResult(
      status: AppLockVerifyStatus.invalidPin,
      attemptsRemaining: attemptsRemaining,
    );
  }
}
