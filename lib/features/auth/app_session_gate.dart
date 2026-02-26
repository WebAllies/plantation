import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:iot_aqua_app/core/security/app_lock_service.dart';
import 'package:iot_aqua_app/features/security/app_lock_page.dart';
import 'package:iot_aqua_app/features/security/pin_setup_page.dart';
import 'package:iot_aqua_app/features/shell/main_shell.dart';

class AppSessionGate extends StatefulWidget {
  final User user;

  const AppSessionGate({super.key, required this.user});

  @override
  State<AppSessionGate> createState() => _AppSessionGateState();
}

class _AppSessionGateState extends State<AppSessionGate>
    with WidgetsBindingObserver {
  final AppLockService _lockService = AppLockService();

  bool _loading = true;
  bool _locked = false;
  bool _needsSetup = false;
  bool _wasBackgrounded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshState(lockAfterRefresh: true);
  }

  @override
  void didUpdateWidget(covariant AppSessionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _refreshState(lockAfterRefresh: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    // If lock/setup flow is already on screen, do not rebuild it on resume.
    // Rebuilding the lock page can re-trigger biometric prompts repeatedly.
    if (_loading || _locked || _needsSetup) return;

    // Only relock after a true background->foreground transition.
    // This avoids relocking on transient lifecycle changes from system prompts.
    if (!_wasBackgrounded) return;
    _wasBackgrounded = false;

    _refreshState(lockAfterRefresh: true);
  }

  Future<void> _refreshState({required bool lockAfterRefresh}) async {
    if (!mounted) return;

    if (kIsWeb) {
      setState(() {
        _loading = false;
        _locked = false;
        _needsSetup = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = widget.user.uid;
      try {
        await _lockService.ensureRemoteDefaults(uid);
      } catch (_) {
        // Keep app usable offline by relying on local lock state.
      }
      final state = await _lockService.getLockState(uid);

      if (!mounted) return;

      setState(() {
        _needsSetup = state.needsSetup;
        _locked = !state.needsSetup && lockAfterRefresh;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _onUnlockSuccess() async {
    if (!mounted) return;
    setState(() {
      _locked = false;
      _error = null;
    });
    _wasBackgrounded = false;
  }

  Future<void> _onPinSetupCompleted() async {
    if (!mounted) return;
    setState(() {
      _needsSetup = false;
      _locked = false;
      _error = null;
    });
    _wasBackgrounded = false;
  }

  Future<void> _onSetupRequiredFromLock() async {
    if (!mounted) return;
    setState(() {
      _needsSetup = true;
      _locked = false;
      _error = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40, color: Colors.red),
                const SizedBox(height: 12),
                Text(
                  'Session gate error:\n$_error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => _refreshState(lockAfterRefresh: true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_needsSetup) {
      return PinSetupPage(
        uid: widget.user.uid,
        appLockService: _lockService,
        onCompleted: _onPinSetupCompleted,
      );
    }

    if (_locked) {
      return AppLockPage(
        uid: widget.user.uid,
        appLockService: _lockService,
        onUnlocked: _onUnlockSuccess,
        onSetupRequired: _onSetupRequiredFromLock,
      );
    }

    return const MainShell();
  }
}
