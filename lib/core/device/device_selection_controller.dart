import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

const Duration kDeviceOfflineAfter = Duration(seconds: 12);

class DeviceSummary {
  final String id;
  final String name;
  final bool online;
  final DateTime? lastSeen;

  const DeviceSummary({
    required this.id,
    required this.name,
    required this.online,
    required this.lastSeen,
  });
}

class DeviceSelectionController extends ChangeNotifier {
  final FirebaseFirestore? _db;
  final FirebaseAuth? _auth;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _deviceSub;
  Timer? _staleTimer;
  int _streamGeneration = 0;
  bool _isSignedIn = false;

  List<DeviceSummary> _devices = const [];
  String? _selectedDeviceId;
  bool _loading = true;
  String? _error;

  DeviceSelectionController({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    bool autoListen = true,
  }) : _db = autoListen ? (firestore ?? FirebaseFirestore.instance) : firestore,
       _auth = autoListen ? (auth ?? FirebaseAuth.instance) : auth {
    if (!autoListen) return;

    final authClient = _auth;
    if (authClient == null) return;

    _authSub = authClient.authStateChanges().listen(_handleAuthChanged);
    _handleSignedInChange(authClient.currentUser != null);
  }

  List<DeviceSummary> get devices => _devices;
  String? get selectedDeviceId => _selectedDeviceId;
  bool get isLoading => _loading;
  String? get error => _error;

  void selectDevice(String id) {
    if (_selectedDeviceId == id) return;
    _selectedDeviceId = id;
    notifyListeners();
  }

  void _handleAuthChanged(User? user) {
    _handleSignedInChange(user != null);
  }

  void _handleSignedInChange(bool signedIn) {
    final generation = ++_streamGeneration;
    _isSignedIn = signedIn;
    _stopDeviceStream();

    if (!signedIn) {
      _devices = const [];
      _selectedDeviceId = null;
      _loading = false;
      _error = null;
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    _startDeviceStream(generation);
  }

  void _startDeviceStream(int generation) {
    final db = _db;
    if (db == null) return;

    _deviceSub = db
        .collection('devices')
        .orderBy('lastSeen', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            if (generation != _streamGeneration) return;
            _onSnapshot(snapshot);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (generation != _streamGeneration) return;
            _onError(error, stackTrace);
          },
        );
    _staleTimer?.cancel();
    _staleTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _refreshStaleDevices();
    });
  }

  void _stopDeviceStream() {
    _deviceSub?.cancel();
    _deviceSub = null;
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final now = DateTime.now();
    final parsed = snapshot.docs.map((doc) {
      final data = doc.data();
      final name = (data['name'] ?? doc.id).toString();
      final ts = data['lastSeen'];
      final lastSeen = ts is Timestamp ? ts.toDate() : null;
      final online =
          (data['online'] ?? false) == true && _isRecentlySeen(lastSeen, now);
      return DeviceSummary(
        id: doc.id,
        name: name,
        online: online,
        lastSeen: lastSeen,
      );
    }).toList();

    _applyDevices(parsed);
  }

  bool _isRecentlySeen(DateTime? lastSeen, [DateTime? now]) {
    if (lastSeen == null) return false;
    return (now ?? DateTime.now()).difference(lastSeen) <= kDeviceOfflineAfter;
  }

  void _refreshStaleDevices() {
    var changed = false;
    final refreshed = _devices.map((device) {
      if (!device.online || _isRecentlySeen(device.lastSeen)) {
        return device;
      }
      changed = true;
      return DeviceSummary(
        id: device.id,
        name: device.name,
        online: false,
        lastSeen: device.lastSeen,
      );
    }).toList();

    if (!changed) return;
    _applyDevices(refreshed);
  }

  void _applyDevices(List<DeviceSummary> parsed) {
    final onlineFirst = <DeviceSummary>[];
    final offline = <DeviceSummary>[];
    for (final d in parsed) {
      if (d.online) {
        onlineFirst.add(d);
      } else {
        offline.add(d);
      }
    }
    final sorted = [...onlineFirst, ...offline];

    _devices = sorted;
    _loading = false;
    _error = null;

    if (_devices.isEmpty) {
      _selectedDeviceId = null;
    } else if (_selectedDeviceId == null ||
        !_devices.any((d) => d.id == _selectedDeviceId)) {
      _selectedDeviceId = _devices.first.id;
    }

    notifyListeners();
  }

  void _onError(Object error, StackTrace _) {
    if (!_isSignedIn) {
      if (_error != null || _loading) {
        _loading = false;
        _error = null;
        notifyListeners();
      }
      return;
    }

    _loading = false;
    _error = error.toString();
    notifyListeners();
  }

  @visibleForTesting
  void debugSetState({
    required bool loading,
    required String? error,
    required List<DeviceSummary> devices,
    required String? selectedDeviceId,
  }) {
    _loading = loading;
    _error = error;
    _devices = devices;
    _selectedDeviceId = selectedDeviceId;
    notifyListeners();
  }

  @visibleForTesting
  void debugHandleAuthChange({required bool signedIn}) {
    _handleSignedInChange(signedIn);
  }

  @visibleForTesting
  int get debugStreamGeneration => _streamGeneration;

  @visibleForTesting
  void debugApplySnapshotForGeneration({
    required int generation,
    required List<DeviceSummary> devices,
  }) {
    if (generation != _streamGeneration) return;
    _applyDevices(devices);
  }

  @visibleForTesting
  void debugApplyErrorForGeneration({
    required int generation,
    required Object error,
  }) {
    if (generation != _streamGeneration) return;
    _onError(error, StackTrace.empty);
  }

  @override
  void dispose() {
    _stopDeviceStream();
    _authSub?.cancel();
    super.dispose();
  }
}
