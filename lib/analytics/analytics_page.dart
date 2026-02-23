import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:iot_aqua_app/core/device/device_selection_controller.dart';
import 'package:iot_aqua_app/core/device/device_selector_header.dart';

const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key, this.selectedDeviceId});

  final String? selectedDeviceId;

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final DateFormat _timeFormatter = DateFormat('dd MMM yyyy, HH:mm:ss');

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _alertStateSub;
  Timer? _alertReminderTimer;
  String? _boundDeviceId;
  List<String> _activeAlertMetrics = const [];
  Map<String, dynamic>? _alertStateData;

  @override
  void initState() {
    super.initState();
    if (!_isFlutterTest && widget.selectedDeviceId != null) {
      _bindAlertState(widget.selectedDeviceId);
    }
  }

  @override
  void didUpdateWidget(covariant AnalyticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isFlutterTest &&
        oldWidget.selectedDeviceId != widget.selectedDeviceId &&
        widget.selectedDeviceId != null) {
      _bindAlertState(widget.selectedDeviceId);
    }
  }

  @override
  void dispose() {
    _alertStateSub?.cancel();
    _alertReminderTimer?.cancel();
    super.dispose();
  }

  void _bindAlertState(String? deviceId) {
    if (_isFlutterTest) return;
    if (_boundDeviceId == deviceId) return;

    _alertStateSub?.cancel();
    _alertStateSub = null;
    _boundDeviceId = deviceId;
    _activeAlertMetrics = const [];
    _alertStateData = null;
    _syncAlertReminderTimer();

    if (deviceId == null) {
      return;
    }

    _alertStateSub = FirebaseFirestore.instance
        .collection('devices')
        .doc(deviceId)
        .collection('alert_state')
        .doc('current')
        .snapshots()
        .listen((snap) {
          final data = snap.data();
          final rawMetrics = data?['activeMetrics'];
          final metrics = rawMetrics is Iterable
              ? rawMetrics
                    .map((e) => e.toString())
                    .where((e) => e.trim().isNotEmpty)
                    .toList(growable: false)
              : const <String>[];

          if (!mounted) return;
          setState(() {
            _alertStateData = data;
            _activeAlertMetrics = metrics;
          });
          _syncAlertReminderTimer();
        });
  }

  void _syncAlertReminderTimer() {
    if (_activeAlertMetrics.isEmpty) {
      _alertReminderTimer?.cancel();
      _alertReminderTimer = null;
      return;
    }

    if (_alertReminderTimer != null) return;
    _alertReminderTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _activeAlertMetrics.isEmpty) return;
      final labels = _activeAlertMetrics.map(_prettyMetric).join(', ');
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Active sensor alerts: $labels'),
            duration: const Duration(seconds: 3),
          ),
        );
    });
  }

  String _prettyMetric(String metric) {
    switch (metric) {
      case 'temperature':
        return 'Temperature';
      case 'ph':
        return 'pH';
      case 'waterLevel':
        return 'Water Level';
      case 'tds':
        return 'TDS';
      default:
        return metric;
    }
  }

  String _fmtDouble(dynamic value, String unit) {
    if (value is! num) return '--';
    final text = value.toDouble().toStringAsFixed(2);
    if (unit.isEmpty) return text;
    return '$text $unit';
  }

  String _latestValueForMetric(String metric) {
    final latestValues = _asMap(_alertStateData?['latestValues']);
    switch (metric) {
      case 'temperature':
        return _fmtDouble(latestValues['temperatureC'], '°C');
      case 'ph':
        return _fmtDouble(latestValues['ph'], '');
      case 'waterLevel':
        return _fmtDouble(latestValues['waterLevelPct'], '%');
      case 'tds':
        return _fmtDouble(latestValues['tdsPpm'], 'ppm');
      default:
        return '--';
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return const <String, dynamic>{};
  }

  Widget _activeAlertsCard() {
    final source = (_alertStateData?['effectiveSource'] ?? 'global').toString();
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active Alerts (${_activeAlertMetrics.length})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Threshold source: $source'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _activeAlertMetrics
                  .map(
                    (metric) => Chip(
                      avatar: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red,
                      ),
                      label: Text(
                        '${_prettyMetric(metric)}: ${_latestValueForMetric(metric)}',
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  IconData _eventIcon(String eventType) {
    switch (eventType) {
      case 'recovered':
        return Icons.check_circle_outline;
      case 'auto_dose_started':
        return Icons.play_circle_outline;
      case 'auto_dose_completed':
        return Icons.task_alt;
      case 'auto_dose_timeout':
        return Icons.timer_off_outlined;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  Color _eventColor(String eventType) {
    switch (eventType) {
      case 'recovered':
      case 'auto_dose_completed':
        return Colors.green;
      case 'auto_dose_started':
        return Colors.blue;
      case 'auto_dose_timeout':
        return Colors.deepOrange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerDeviceId = context
        .watch<DeviceSelectionController>()
        .selectedDeviceId;
    final deviceId = widget.selectedDeviceId ?? providerDeviceId;

    if (!_isFlutterTest && deviceId != _boundDeviceId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _bindAlertState(deviceId);
      });
    }

    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 3)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Analytics"),
        bottom: const DeviceSelectorHeaderBottom(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Alerts',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (deviceId == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No device selected. Pick a greenhouse to view alert details.',
                ),
              ),
            )
          else ...[
            if (_activeAlertMetrics.isNotEmpty) _activeAlertsCard(),
            if (_activeAlertMetrics.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  title: Text('No active alerts'),
                  subtitle: Text(
                    'All monitored sensor values are within range.',
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recent Alerts (Last 3 Days)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (_isFlutterTest)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No alert events in the last 3 days.'),
                      )
                    else
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('devices')
                            .doc(deviceId)
                            .collection('alerts')
                            .where('createdAt', isGreaterThan: cutoff)
                            .orderBy('createdAt', descending: true)
                            .limit(100)
                            .snapshots(),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting &&
                              !snap.hasData) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final docs = snap.data?.docs ?? const [];
                          if (docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'No alert events in the last 3 days.',
                              ),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final data = docs[i].data();
                              final ts = data['createdAt'];
                              final dateTime = ts is Timestamp
                                  ? ts.toDate()
                                  : null;
                              final eventType = (data['eventType'] ?? '')
                                  .toString();
                              final metric = (data['metric'] ?? '').toString();
                              final message = (data['message'] ?? '')
                                  .toString();

                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  _eventIcon(eventType),
                                  color: _eventColor(eventType),
                                ),
                                title: Text(
                                  '${eventType.isEmpty ? 'event' : eventType} · ${metric.isEmpty ? 'metric' : metric}',
                                ),
                                subtitle: Text(
                                  '${dateTime == null ? '—' : _timeFormatter.format(dateTime)}\n$message',
                                ),
                                isThreeLine: true,
                              );
                            },
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            "Data Analytics",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Analytics visualizations can be added below while keeping alerts visible at the top.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
