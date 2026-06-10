import 'dart:async';

import 'package:flutter/material.dart';

import 'package:iot_aqua_app/core/security/app_lock_models.dart';
import 'package:iot_aqua_app/core/security/app_lock_service.dart';
import 'package:iot_aqua_app/core/security/biometric_service.dart';

class AppLockPage extends StatefulWidget {
  final String uid;
  final AppLockService appLockService;
  final Future<void> Function() onUnlocked;
  final Future<void> Function() onSetupRequired;

  const AppLockPage({
    super.key,
    required this.uid,
    required this.appLockService,
    required this.onUnlocked,
    required this.onSetupRequired,
  });

  @override
  State<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends State<AppLockPage> {
  final _pinCtrl = TextEditingController();
  final BiometricService _biometricService = BiometricService();

  bool _loading = true;
  bool _unlocking = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _autoBiometricAttempted = false;
  int _cooldownRemainingSeconds = 0;
  String? _error;
  Timer? _cooldownTicker;

  @override
  void initState() {
    super.initState();
    _loadState(tryBiometric: true);
  }

  @override
  void dispose() {
    _cooldownTicker?.cancel();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadState({required bool tryBiometric}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final state = await widget.appLockService.getLockState(widget.uid);
    if (!mounted) return;

    if (state.needsSetup) {
      await widget.onSetupRequired();
      return;
    }

    final available = await _biometricService.isAvailable();
    if (!mounted) return;

    _scheduleCooldownTicker(state);
    setState(() {
      _cooldownRemainingSeconds = state.cooldownRemainingSeconds;
      _biometricEnabled = state.biometricEnabled;
      _biometricAvailable = available;
      _loading = false;
    });

    if (tryBiometric &&
        !_autoBiometricAttempted &&
        _biometricEnabled &&
        _biometricAvailable &&
        _cooldownRemainingSeconds <= 0) {
      _autoBiometricAttempted = true;
      await _tryBiometric();
    }
  }

  void _scheduleCooldownTicker(AppLockState state) {
    _cooldownTicker?.cancel();
    if (state.cooldownRemainingSeconds <= 0) return;

    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final now = DateTime.now().toUtc();
      final until = state.lockoutUntil;
      if (until == null || !until.isAfter(now)) {
        timer.cancel();
        setState(() => _cooldownRemainingSeconds = 0);
        return;
      }

      final next = ((until.difference(now).inMilliseconds + 999) ~/ 1000);
      setState(() => _cooldownRemainingSeconds = next);
    });
  }

  Future<void> _tryBiometric() async {
    if (_unlocking) return;
    setState(() => _unlocking = true);

    final ok = await _biometricService.authenticate(
      reason: 'Authenticate to unlock AquaFarm',
    );

    if (!mounted) return;
    setState(() => _unlocking = false);

    if (ok) {
      await widget.onUnlocked();
      return;
    }

    setState(() {
      _error = 'Biometric authentication failed. Use your PIN.';
    });
  }

  Future<void> _unlockWithPin() async {
    if (_unlocking) return;
    if (_cooldownRemainingSeconds > 0) return;

    final pin = _pinCtrl.text.trim();
    setState(() {
      _unlocking = true;
      _error = null;
    });

    final result = await widget.appLockService.verifyPin(
      uid: widget.uid,
      pin: pin,
    );
    if (!mounted) return;

    setState(() => _unlocking = false);

    switch (result.status) {
      case AppLockVerifyStatus.success:
        _pinCtrl.clear();
        await widget.onUnlocked();
        return;
      case AppLockVerifyStatus.setupRequired:
        await widget.onSetupRequired();
        return;
      case AppLockVerifyStatus.cooldownActive:
        setState(() {
          _cooldownRemainingSeconds = result.cooldownRemainingSeconds;
          _error =
              'Too many attempts. Try again in ${result.cooldownRemainingSeconds}s.';
        });
        await _loadState(tryBiometric: false);
        return;
      case AppLockVerifyStatus.invalidPin:
        setState(() {
          _error = result.attemptsRemaining > 0
              ? 'Wrong PIN. ${result.attemptsRemaining} attempts left.'
              : 'Wrong PIN.';
        });
        return;
      case AppLockVerifyStatus.error:
        setState(() {
          _error = result.errorMessage ?? 'Unlock failed. Try again.';
        });
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_clock, size: 48),
                    const SizedBox(height: 10),
                    const Text(
                      'Unlock App',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your 6-digit PIN to continue.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'PIN',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.password),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _unlockWithPin(),
                    ),
                    if (_cooldownRemainingSeconds > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Locked for $_cooldownRemainingSeconds seconds due to failed attempts.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: (_unlocking || _cooldownRemainingSeconds > 0)
                          ? null
                          : _unlockWithPin,
                      child: _unlocking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Unlock'),
                    ),
                    if (_biometricEnabled && _biometricAvailable) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: (_unlocking || _cooldownRemainingSeconds > 0)
                            ? null
                            : _tryBiometric,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Use biometrics'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
