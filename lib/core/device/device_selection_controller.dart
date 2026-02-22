import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
  final FirebaseFirestore _db;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  List<DeviceSummary> _devices = const [];
  String? _selectedDeviceId;
  bool _loading = true;
  String? _error;

  DeviceSelectionController({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance {
    _sub = _db
        .collection('devices')
        .orderBy('lastSeen', descending: true)
        .snapshots()
        .listen(_onSnapshot, onError: _onError);
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

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final parsed = snapshot.docs.map((doc) {
      final data = doc.data();
      final name = (data['name'] ?? doc.id).toString();
      final online = (data['online'] ?? false) == true;
      final ts = data['lastSeen'];
      final lastSeen = ts is Timestamp ? ts.toDate() : null;
      return DeviceSummary(
        id: doc.id,
        name: name,
        online: online,
        lastSeen: lastSeen,
      );
    }).toList();

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
    _loading = false;
    _error = error.toString();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
