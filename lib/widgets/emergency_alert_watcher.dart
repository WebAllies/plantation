import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

class EmergencyAlertWatcher extends StatefulWidget {
  final Widget child;
  final String deviceId;

  const EmergencyAlertWatcher({
    super.key,
    required this.child,
    required this.deviceId,
  });

  @override
  State<EmergencyAlertWatcher> createState() => _EmergencyAlertWatcherState();
}

class _EmergencyAlertWatcherState extends State<EmergencyAlertWatcher> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _alertSub;
  Timer? _snoozeTimer;

  bool _dialogOpen = false;
  bool _emergencyAlertsEnabled = true;
  String? _lastAlertFingerprint;

  @override
  void initState() {
    super.initState();
    _listenToEmergencyState();
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _snoozeTimer?.cancel();
    super.dispose();
  }

  void _listenToEmergencyState() {
    _alertSub = FirebaseFirestore.instance
        .collection('devices')
        .doc(widget.deviceId)
        .collection('alert_state')
        .doc('current')
        .snapshots()
        .listen((doc) async {
      await _loadEmergencySetting();

      if (!_emergencyAlertsEnabled) return;

      final data = doc.data();
      if (data == null) return;

      final activeMetricsRaw = data['activeMetrics'];
      final activeMetrics = activeMetricsRaw is List
          ? activeMetricsRaw.map((e) => e.toString()).toList()
          : <String>[];

      if (activeMetrics.isEmpty) {
        _lastAlertFingerprint = null;
        _snoozeTimer?.cancel();
        return;
      }

      final latestValues = (data['latestValues'] is Map<String, dynamic>)
          ? data['latestValues'] as Map<String, dynamic>
          : <String, dynamic>{};

      final metrics = (data['metrics'] is Map<String, dynamic>)
          ? data['metrics'] as Map<String, dynamic>
          : <String, dynamic>{};

      final issueText = _buildIssueText(
        activeMetrics: activeMetrics,
        latestValues: latestValues,
        metrics: metrics,
      );

      final fingerprint =
          "${widget.deviceId}_${activeMetrics.join('_')}_$issueText";

      if (_dialogOpen) return;

      if (_lastAlertFingerprint != fingerprint) {
        _lastAlertFingerprint = fingerprint;
        _triggerEmergencyDialog(issueText);
      }
    });
  }

  Future<void> _loadEmergencySetting() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('system')
          .doc('settings')
          .get();

      final data = doc.data() ?? {};
      _emergencyAlertsEnabled = data['emergencyAlertsEnabled'] is bool
          ? data['emergencyAlertsEnabled'] as bool
          : true;
    } catch (_) {
      _emergencyAlertsEnabled = true;
    }
  }

  String _buildIssueText({
    required List<String> activeMetrics,
    required Map<String, dynamic> latestValues,
    required Map<String, dynamic> metrics,
  }) {
    final lines = <String>[];

    for (final metric in activeMetrics) {
      final metricData = metrics[metric];
      final state = (metricData is Map && metricData['state'] != null)
          ? metricData['state'].toString().toUpperCase()
          : 'ABNORMAL';

      final latest = latestValues[_mapMetricToLatestValueKey(metric)];

      lines.add(
        "${_prettyMetric(metric)} is $state"
        "${latest != null ? " (current value: $latest)" : ""}",
      );
    }

    return lines.join("\n");
  }

  String _mapMetricToLatestValueKey(String metric) {
    switch (metric) {
      case 'temperature':
        return 'temperatureC';
      case 'tds':
        return 'tdsPpm';
      case 'waterLevel':
        return 'waterLevelPct';
      default:
        return metric;
    }
  }

  String _prettyMetric(String metric) {
    switch (metric) {
      case 'ph':
        return 'pH';
      case 'tds':
        return 'TDS';
      case 'temperature':
        return 'Temperature';
      case 'waterLevel':
        return 'Water Level';
      default:
        return metric;
    }
  }

  Future<void> _triggerEmergencyDialog(String issueText) async {
    _dialogOpen = true;
    await _vibrateEmergency();

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red),
                SizedBox(width: 8),
                Expanded(child: Text("Emergency Alert")),
              ],
            ),
            content: Text(
              "Device: ${widget.deviceId}\n\n"
              "Issue detected:\n$issueText\n\n"
              "You must fix the issue. If it remains unresolved, the alert will appear again in 2 minutes.",
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text("OK"),
              ),
            ],
          ),
        );
      },
    );

    _dialogOpen = false;
    _startSnoozeCheck();
  }

  void _startSnoozeCheck() {
    _snoozeTimer?.cancel();

    _snoozeTimer = Timer(const Duration(minutes: 2), () async {
      await _loadEmergencySetting();
      if (!_emergencyAlertsEnabled) return;

      final doc = await FirebaseFirestore.instance
          .collection('devices')
          .doc(widget.deviceId)
          .collection('alert_state')
          .doc('current')
          .get();

      final data = doc.data();
      if (data == null) return;

      final activeMetricsRaw = data['activeMetrics'];
      final activeMetrics = activeMetricsRaw is List
          ? activeMetricsRaw.map((e) => e.toString()).toList()
          : <String>[];

      if (activeMetrics.isEmpty) {
        _lastAlertFingerprint = null;
        return;
      }

      final latestValues = (data['latestValues'] is Map<String, dynamic>)
          ? data['latestValues'] as Map<String, dynamic>
          : <String, dynamic>{};

      final metrics = (data['metrics'] is Map<String, dynamic>)
          ? data['metrics'] as Map<String, dynamic>
          : <String, dynamic>{};

      final issueText = _buildIssueText(
        activeMetrics: activeMetrics,
        latestValues: latestValues,
        metrics: metrics,
      );

      if (!_dialogOpen && mounted) {
        _triggerEmergencyDialog(issueText);
      }
    });
  }

  Future<void> _vibrateEmergency() async {
    try {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) return;

      final hasCustom = await Vibration.hasCustomVibrationsSupport() ?? false;

      if (hasCustom) {
        Vibration.vibrate(pattern: [0, 700, 300, 700, 300, 1000]);
      } else {
        Vibration.vibrate(duration: 1200);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}