import 'package:flutter/material.dart';

import 'package:iot_aqua_app/core/security/app_lock_service.dart';
import 'package:iot_aqua_app/core/security/biometric_service.dart';

class PinSetupPage extends StatefulWidget {
  final String uid;
  final AppLockService appLockService;
  final Future<void> Function() onCompleted;

  const PinSetupPage({
    super.key,
    required this.uid,
    required this.appLockService,
    required this.onCompleted,
  });

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final BiometricService _biometricService = BiometricService();

  bool _saving = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBiometricCapability();
  }

  Future<void> _loadBiometricCapability() async {
    final available = await _biometricService.isAvailable();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      if (!available) _biometricEnabled = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.appLockService.setPin(
        uid: widget.uid,
        pin: _pinCtrl.text.trim(),
        biometricEnabled: _biometricAvailable && _biometricEnabled,
      );
      await widget.onCompleted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock, size: 48),
                      const SizedBox(height: 8),
                      const Text(
                        'Set App PIN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Create a 6-digit PIN to unlock this device. '
                        'This setup is required.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _pinCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'New PIN',
                          prefixIcon: Icon(Icons.password),
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                        validator: (value) {
                          final pin = (value ?? '').trim();
                          if (!AppLockService.isValidPin(pin)) {
                            return 'PIN must be exactly 6 digits.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'Confirm PIN',
                          prefixIcon: Icon(Icons.password_outlined),
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                        validator: (value) {
                          final confirm = (value ?? '').trim();
                          if (confirm != _pinCtrl.text.trim()) {
                            return 'PIN confirmation does not match.';
                          }
                          return null;
                        },
                      ),
                      if (_biometricAvailable) ...[
                        const SizedBox(height: 6),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _biometricEnabled,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _biometricEnabled = v),
                          title: const Text('Enable biometric unlock'),
                          subtitle: const Text(
                            'Use fingerprint/face as a faster unlock method.',
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save PIN'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
