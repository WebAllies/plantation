class AppLockRemoteConfig {
  final bool enforced;
  final int pinVersion;
  final String pinPolicy;
  final bool biometricPreferred;

  const AppLockRemoteConfig({
    required this.enforced,
    required this.pinVersion,
    required this.pinPolicy,
    required this.biometricPreferred,
  });

  factory AppLockRemoteConfig.defaults() {
    return const AppLockRemoteConfig(
      enforced: true,
      pinVersion: 1,
      pinPolicy: 'v1_6digit_cooldown',
      biometricPreferred: true,
    );
  }
}

class AppLockState {
  final bool needsSetup;
  final bool biometricEnabled;
  final int failedAttempts;
  final DateTime? lockoutUntil;
  final int localPinVersion;
  final AppLockRemoteConfig remoteConfig;

  const AppLockState({
    required this.needsSetup,
    required this.biometricEnabled,
    required this.failedAttempts,
    required this.lockoutUntil,
    required this.localPinVersion,
    required this.remoteConfig,
  });

  int get cooldownRemainingSeconds {
    if (lockoutUntil == null) return 0;
    final now = DateTime.now().toUtc();
    if (!lockoutUntil!.isAfter(now)) return 0;
    final diffMs = lockoutUntil!.difference(now).inMilliseconds;
    return ((diffMs + 999) ~/ 1000).clamp(0, 1 << 30);
  }
}

enum AppLockVerifyStatus {
  success,
  invalidPin,
  cooldownActive,
  setupRequired,
  error,
}

class AppLockVerifyResult {
  final AppLockVerifyStatus status;
  final int cooldownRemainingSeconds;
  final int attemptsRemaining;
  final String? errorMessage;

  const AppLockVerifyResult({
    required this.status,
    this.cooldownRemainingSeconds = 0,
    this.attemptsRemaining = 0,
    this.errorMessage,
  });

  factory AppLockVerifyResult.success() {
    return const AppLockVerifyResult(status: AppLockVerifyStatus.success);
  }
}
