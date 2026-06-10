import 'package:flutter_test/flutter_test.dart';
import 'package:iot_aqua_app/core/security/app_lock_models.dart';
import 'package:iot_aqua_app/core/security/app_lock_service.dart';
import 'package:iot_aqua_app/core/security/pin_crypto.dart';

class _MemoryStore implements AppLockStore {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }
}

class _FakeRemoteStore implements AppLockRemoteStore {
  final Map<String, AppLockRemoteConfig> _configs =
      <String, AppLockRemoteConfig>{};
  bool throwOnFetch = false;

  @override
  Future<void> ensureDefaults(String uid) async {
    _configs.putIfAbsent(uid, AppLockRemoteConfig.defaults);
  }

  @override
  Future<AppLockRemoteConfig> fetchConfig(String uid) async {
    if (throwOnFetch) {
      throw Exception('remote fetch failed');
    }
    return _configs[uid] ?? AppLockRemoteConfig.defaults();
  }

  @override
  Future<void> setBiometricPreferred(String uid, bool value) async {
    final current = _configs[uid] ?? AppLockRemoteConfig.defaults();
    _configs[uid] = AppLockRemoteConfig(
      enforced: current.enforced,
      pinVersion: current.pinVersion,
      pinPolicy: current.pinPolicy,
      biometricPreferred: value,
    );
  }

  void setPinVersion(String uid, int version) {
    final current = _configs[uid] ?? AppLockRemoteConfig.defaults();
    _configs[uid] = AppLockRemoteConfig(
      enforced: current.enforced,
      pinVersion: version,
      pinPolicy: current.pinPolicy,
      biometricPreferred: current.biometricPreferred,
    );
  }
}

void main() {
  group('AppLockService', () {
    late _MemoryStore store;
    late _FakeRemoteStore remote;
    late AppLockService service;
    const uid = 'u1';

    setUp(() async {
      store = _MemoryStore();
      remote = _FakeRemoteStore();
      service = AppLockService(
        store: store,
        remoteStore: remote,
        pinCrypto: PinCrypto(),
      );
      await remote.ensureDefaults(uid);
    });

    test('setPin then verify success', () async {
      await service.setPin(uid: uid, pin: '123456', biometricEnabled: true);

      final result = await service.verifyPin(uid: uid, pin: '123456');
      expect(result.status, AppLockVerifyStatus.success);
    });

    test('wrong pin increments attempts and then starts cooldown', () async {
      await service.setPin(uid: uid, pin: '123456', biometricEnabled: false);

      for (var i = 0; i < 4; i++) {
        final r = await service.verifyPin(uid: uid, pin: '000000');
        expect(r.status, AppLockVerifyStatus.invalidPin);
      }

      final cooldownResult = await service.verifyPin(uid: uid, pin: '000000');
      expect(cooldownResult.status, AppLockVerifyStatus.cooldownActive);
      expect(cooldownResult.cooldownRemainingSeconds, greaterThan(0));
    });

    test('cooldown cleared allows valid verify again', () async {
      await service.setPin(uid: uid, pin: '123456', biometricEnabled: false);

      for (var i = 0; i < 5; i++) {
        await service.verifyPin(uid: uid, pin: '000000');
      }

      await store.write(
        'app_lock.$uid.lockout_until_ms',
        DateTime.now()
            .toUtc()
            .subtract(const Duration(seconds: 1))
            .millisecondsSinceEpoch
            .toString(),
      );

      final state = await service.getLockState(uid);
      expect(state.cooldownRemainingSeconds, 0);

      final ok = await service.verifyPin(uid: uid, pin: '123456');
      expect(ok.status, AppLockVerifyStatus.success);
    });

    test('pin version mismatch forces setup', () async {
      await service.setPin(uid: uid, pin: '123456', biometricEnabled: false);

      remote.setPinVersion(uid, 2);
      final state = await service.getLockState(uid);

      expect(state.needsSetup, isTrue);

      final verify = await service.verifyPin(uid: uid, pin: '123456');
      expect(verify.status, AppLockVerifyStatus.setupRequired);
    });

    test('remote fetch failure does not clear local pin', () async {
      await service.setPin(uid: uid, pin: '123456', biometricEnabled: false);
      remote.setPinVersion(uid, 2);
      await service.setPin(uid: uid, pin: '123456', biometricEnabled: false);

      remote.throwOnFetch = true;
      final state = await service.getLockState(uid);
      expect(state.needsSetup, isFalse);

      final verify = await service.verifyPin(uid: uid, pin: '123456');
      expect(verify.status, AppLockVerifyStatus.success);
    });

    test(
      'clearLocalPinForLogout forces setup and clears local lock data',
      () async {
        await service.setPin(uid: uid, pin: '123456', biometricEnabled: true);
        await store.write('app_lock.$uid.failed_attempts', '4');
        await store.write(
          'app_lock.$uid.lockout_until_ms',
          DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch
              .toString(),
        );
        await store.write('app_lock.$uid.pin_version', '9');

        await service.clearLocalPinForLogout(uid);

        expect(await store.read('app_lock.$uid.pin_hash'), isNull);
        expect(await store.read('app_lock.$uid.pin_salt'), isNull);
        expect(await store.read('app_lock.$uid.pin_version'), isNull);
        expect(await store.read('app_lock.$uid.biometric_enabled'), isNull);
        expect(await store.read('app_lock.$uid.failed_attempts'), '0');
        expect(await store.read('app_lock.$uid.lockout_until_ms'), '0');

        final state = await service.getLockState(uid);
        expect(state.needsSetup, isTrue);
      },
    );

    test('clearLocalPinForLogout can preserve biometric preference', () async {
      await service.setPin(uid: uid, pin: '123456', biometricEnabled: true);

      await service.clearLocalPinForLogout(
        uid,
        clearBiometricPreference: false,
      );

      expect(await store.read('app_lock.$uid.pin_hash'), isNull);
      expect(await store.read('app_lock.$uid.biometric_enabled'), '1');
    });
  });
}
