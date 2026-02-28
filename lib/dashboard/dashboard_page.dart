import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:iot_aqua_app/core/device/device_selector_header.dart';
import 'package:iot_aqua_app/core/realtime/mqtt_telemetry_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum _SocketState { disconnected, connecting, connected, retrying }

enum _LiveTransport { firestore, mqtt, websocketLegacy }

class _TelemetryFrame {
  final String deviceId;
  final int? tsMs;
  final double? temperatureC;
  final double? ph;
  final double? waterLevelPct;
  final double? tdsPpm;
  final bool? pumpState;
  final bool? valveState;
  final int? rssi;

  const _TelemetryFrame({
    required this.deviceId,
    this.tsMs,
    this.temperatureC,
    this.ph,
    this.waterLevelPct,
    this.tdsPpm,
    this.pumpState,
    this.valveState,
    this.rssi,
  });

  factory _TelemetryFrame.fromJson(
    Map<String, dynamic> json, {
    _TelemetryFrame? fallback,
  }) {
    return _TelemetryFrame(
      deviceId:
          _toStringValue(json['deviceId']) ?? fallback?.deviceId ?? 'unknown',
      tsMs:
          _toIntValue(json['tsEpochMs']) ??
          _toIntValue(json['tsMs']) ??
          fallback?.tsMs,
      temperatureC:
          _toDoubleValue(json['temperatureC']) ?? fallback?.temperatureC,
      ph: _toDoubleValue(json['ph']) ?? fallback?.ph,
      waterLevelPct:
          _toDoubleValue(json['waterLevelPct']) ?? fallback?.waterLevelPct,
      tdsPpm: _toDoubleValue(json['tdsPpm']) ?? fallback?.tdsPpm,
      pumpState: _toBoolValue(json['pumpState']) ?? fallback?.pumpState,
      valveState: _toBoolValue(json['valveState']) ?? fallback?.valveState,
      rssi: _toIntValue(json['rssi']) ?? fallback?.rssi,
    );
  }

  factory _TelemetryFrame.fromFirestore(
    Map<String, dynamic> data, {
    _TelemetryFrame? fallback,
  }) {
    final lastSeen = data['lastSeen'];
    int? tsMs =
        _toIntValue(data['tsEpochMs']) ??
        _toIntValue(data['tsMs']) ??
        fallback?.tsMs;
    if (lastSeen is Timestamp) {
      tsMs = lastSeen.toDate().millisecondsSinceEpoch;
    }

    return _TelemetryFrame(
      deviceId:
          _toStringValue(data['deviceId']) ?? fallback?.deviceId ?? 'unknown',
      tsMs: tsMs,
      temperatureC:
          _toDoubleValue(data['temperatureC']) ?? fallback?.temperatureC,
      ph: _toDoubleValue(data['ph']) ?? fallback?.ph,
      waterLevelPct:
          _toDoubleValue(data['waterLevelPct']) ?? fallback?.waterLevelPct,
      tdsPpm: _toDoubleValue(data['tdsPpm']) ?? fallback?.tdsPpm,
      pumpState: _toBoolValue(data['pumpState']) ?? fallback?.pumpState,
      valveState: _toBoolValue(data['valveState']) ?? fallback?.valveState,
      rssi: _toIntValue(data['rssi']) ?? fallback?.rssi,
    );
  }

  static String? _toStringValue(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }

  static int? _toIntValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _toDoubleValue(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool? _toBoolValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.selectedDeviceId});

  final String? selectedDeviceId;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DocumentReference<Map<String, dynamic>>? get _deviceRef {
    final id = widget.selectedDeviceId;
    if (id == null) return null;
    return FirebaseFirestore.instance.collection('devices').doc(id);
  }

  final DateFormat _timeFormatter = DateFormat('dd MMM yyyy, HH:mm:ss');
  final MqttTelemetryService _mqttService = MqttTelemetryService();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _reconnectTimer;

  StreamSubscription<Map<String, dynamic>>? _mqttFrameSub;
  StreamSubscription<MqttLiveStatus>? _mqttStatusSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _alertStateSub;

  _TelemetryFrame? _liveFrame;
  DateTime? _lastLiveAt;
  int? _lastLiveTsMs;
  Timer? _alertReminderTimer;
  List<String> _activeAlertMetrics = const [];
  Map<String, dynamic>? _alertStateData;

  _SocketState _socketState = _SocketState.disconnected;
  String _socketMessage = 'Waiting for simulator endpoint';
  _LiveTransport _activeTransport = _LiveTransport.firestore;

  String? _activeWsUrl;
  String? _queuedWsUrl;

  String? _activeMqttTopic;
  String? _activeMqttStatusTopic;
  String? _queuedMqttTopic;
  String? _queuedMqttStatusTopic;

  @override
  void initState() {
    super.initState();
    _bindAlertState(widget.selectedDeviceId);
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _detachSocket();
    _mqttFrameSub?.cancel();
    _mqttStatusSub?.cancel();
    _alertStateSub?.cancel();
    _alertReminderTimer?.cancel();
    _mqttFrameSub = null;
    _mqttStatusSub = null;
    _alertStateSub = null;
    _mqttService.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDeviceId != widget.selectedDeviceId) {
      _reconnectTimer?.cancel();
      _detachSocket();
      unawaited(_detachMqtt());

      _activeWsUrl = null;
      _queuedWsUrl = null;
      _activeMqttTopic = null;
      _activeMqttStatusTopic = null;
      _queuedMqttTopic = null;
      _queuedMqttStatusTopic = null;

      _liveFrame = null;
      _lastLiveAt = null;
      _lastLiveTsMs = null;

      _activeTransport = _LiveTransport.firestore;
      _socketState = _SocketState.disconnected;
      _socketMessage = 'Waiting for simulator endpoint';
      _bindAlertState(widget.selectedDeviceId);
    }
  }

  void _bindAlertState(String? deviceId) {
    _alertStateSub?.cancel();
    _alertStateSub = null;

    _activeAlertMetrics = const [];
    _alertStateData = null;
    _syncAlertReminderTimer();

    if (deviceId == null) return;

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
    final hasActiveAlerts = _activeAlertMetrics.isNotEmpty;
    if (!hasActiveAlerts) {
      _alertReminderTimer?.cancel();
      _alertReminderTimer = null;
      return;
    }

    if (_alertReminderTimer != null) return;
    _alertReminderTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _showAlertReminder();
    });
  }

  void _showAlertReminder() {
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

  String _metricValueForAlert(String metric, _TelemetryFrame frame) {
    switch (metric) {
      case 'temperature':
        return _fmtDouble(frame.temperatureC, '°C');
      case 'ph':
        return _fmtDouble(frame.ph, '');
      case 'waterLevel':
        return _fmtDouble(frame.waterLevelPct, '%');
      case 'tds':
        return _fmtDouble(frame.tdsPpm, 'ppm');
      default:
        return '--';
    }
  }
      Widget _weatherDashboardCard(String deviceId) {
      final docRef = FirebaseFirestore.instance
          .collection('devices')
          .doc(deviceId)
          .collection('weather')
          .doc('latest');

      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData || snap.data?.data() == null) {
            return const Card(
              child: ListTile(
                leading: Icon(Icons.cloud_outlined),
                title: Text('Weather Forecast'),
                subtitle: Text('No weather data yet. Open Weather AI and refresh.'),
              ),
            );
          }

          final d = snap.data!.data()!;

          DateTime? updatedAt;
          final raw = d['updatedAt'];
          if (raw is Timestamp) updatedAt = raw.toDate();

          final location = (d['locationName'] ?? 'Unknown').toString();
          final maxTemp = (d['maxTempC'] as num?)?.toDouble() ?? 0;
          final rainChance = (d['chanceOfRain'] as num?)?.toDouble() ?? 0;
          final precip = (d['totalPrecipMm'] as num?)?.toDouble() ?? 0;

          final updatedText = updatedAt == null
              ? '—'
              : DateFormat('dd MMM, HH:mm').format(updatedAt);

          IconData icon = Icons.cloud_outlined;
          if (rainChance >= 60 || precip >= 5) {
            icon = Icons.umbrella;
          } else if (maxTemp >= 30) {
            icon = Icons.wb_sunny;
          }

          return Card(
            child: ListTile(
              leading: Icon(icon),
              title: const Text('Weather Forecast (Next 24h)'),
              subtitle: Text(
                '$location • Updated: $updatedText\n'
                'Max: ${maxTemp.toStringAsFixed(1)}°C  •  Rain: ${rainChance.toStringAsFixed(0)}%  •  Precip: ${precip.toStringAsFixed(1)}mm',
              ),
              isThreeLine: true,
            ),
          );
        },
      );
    }

  Widget _activeAlertCard(_TelemetryFrame frame) {
    final source = (_alertStateData?['effectiveSource'] ?? 'global')
        .toString()
        .trim();
    final chips = _activeAlertMetrics
        .map(
          (metric) => Chip(
            avatar: const Icon(Icons.warning_amber_rounded, color: Colors.red),
            label: Text(
              '${_prettyMetric(metric)}: ${_metricValueForAlert(metric, frame)}',
            ),
          ),
        )
        .toList(growable: false);

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
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ),
      ),
    );
  }

  void _queueWsUrlSync(String? rawWsUrl) {
    final normalized = (rawWsUrl == null || rawWsUrl.trim().isEmpty)
        ? null
        : rawWsUrl.trim();

    if (normalized == _activeWsUrl || normalized == _queuedWsUrl) return;
    _queuedWsUrl = normalized;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = _queuedWsUrl;
      _queuedWsUrl = null;
      if (next == _activeWsUrl) return;
      _switchSocket(next);
    });
  }

  void _queueMqttSync({required String? rawTopic, String? rawStatusTopic}) {
    final normalizedTopic = (rawTopic == null || rawTopic.trim().isEmpty)
        ? null
        : rawTopic.trim();
    final normalizedStatusTopic =
        (rawStatusTopic == null || rawStatusTopic.trim().isEmpty)
        ? null
        : rawStatusTopic.trim();

    final matchesActive =
        normalizedTopic == _activeMqttTopic &&
        normalizedStatusTopic == _activeMqttStatusTopic;
    final matchesQueued =
        normalizedTopic == _queuedMqttTopic &&
        normalizedStatusTopic == _queuedMqttStatusTopic;

    if (matchesActive || matchesQueued) return;

    _queuedMqttTopic = normalizedTopic;
    _queuedMqttStatusTopic = normalizedStatusTopic;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nextTopic = _queuedMqttTopic;
      final nextStatusTopic = _queuedMqttStatusTopic;
      _queuedMqttTopic = null;
      _queuedMqttStatusTopic = null;

      final sameTarget =
          nextTopic == _activeMqttTopic &&
          nextStatusTopic == _activeMqttStatusTopic;
      if (sameTarget) return;

      unawaited(_switchMqtt(nextTopic, nextStatusTopic));
    });
  }

  Future<void> _switchMqtt(String? topic, String? statusTopic) async {
    _reconnectTimer?.cancel();
    _detachSocket();

    if (topic == null) {
      await _detachMqtt();
      if (!mounted) return;

      setState(() {
        _activeMqttTopic = null;
        _activeMqttStatusTopic = null;

        if (_activeTransport == _LiveTransport.mqtt || _activeWsUrl == null) {
          _activeTransport = _LiveTransport.firestore;
          _socketState = _SocketState.disconnected;
          _socketMessage = 'Waiting for mqttTopicLive in Firestore';
        }
      });
      return;
    }

    await _detachMqtt();
    if (!mounted) return;

    final deviceId = widget.selectedDeviceId;
    if (deviceId == null) return;

    setState(() {
      _activeMqttTopic = topic;
      _activeMqttStatusTopic = statusTopic;
      _activeWsUrl = null;
      _activeTransport = _LiveTransport.mqtt;
      _lastLiveTsMs = null;
      _socketState = _SocketState.connecting;
      _socketMessage = 'Connecting to MQTT topic $topic';
    });

    _mqttFrameSub = _mqttService.telemetryStream.listen(_onMqttData);
    _mqttStatusSub = _mqttService.statusStream.listen(_onMqttStatus);

    unawaited(
      _mqttService.connect(
        deviceId: deviceId,
        liveTopic: topic,
        statusTopic: statusTopic,
      ),
    );
  }

  Future<void> _detachMqtt() async {
    await _mqttFrameSub?.cancel();
    _mqttFrameSub = null;

    await _mqttStatusSub?.cancel();
    _mqttStatusSub = null;

    await _mqttService.disconnect();
  }

  void _switchSocket(String? wsUrl) {
    _reconnectTimer?.cancel();
    unawaited(_detachMqtt());
    _detachSocket();

    if (wsUrl == null) {
      setState(() {
        _activeWsUrl = null;
        _socketState = _SocketState.disconnected;
        _activeTransport = _LiveTransport.firestore;
        _socketMessage = 'Waiting for wsUrl in Firestore';
      });
      return;
    }

    final uri = Uri.tryParse(wsUrl);
    if (uri == null || (uri.scheme != 'ws' && uri.scheme != 'wss')) {
      setState(() {
        _activeWsUrl = wsUrl;
        _socketState = _SocketState.disconnected;
        _activeTransport = _LiveTransport.websocketLegacy;
        _socketMessage = 'Invalid wsUrl format: $wsUrl';
      });
      return;
    }

    setState(() {
      _activeWsUrl = wsUrl;
      _activeTransport = _LiveTransport.websocketLegacy;
      _lastLiveTsMs = null;
      _socketState = _SocketState.connecting;
      _socketMessage = 'Connecting to $wsUrl';
    });

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _socketSub = channel.stream.listen(
        _onSocketData,
        onError: _onSocketError,
        onDone: _onSocketDone,
        cancelOnError: false,
      );
    } catch (error) {
      _handleSocketFailure('Connect error: $error');
    }
  }

  void _detachSocket() {
    _socketSub?.cancel();
    _socketSub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _onSocketData(dynamic event) {
    String payload;
    if (event is String) {
      payload = event;
    } else if (event is List<int>) {
      payload = utf8.decode(event, allowMalformed: true);
    } else {
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    _applyLivePayload(decoded, sourceLabel: 'WebSocket');
  }

  void _onMqttData(Map<String, dynamic> payload) {
    _applyLivePayload(payload, sourceLabel: 'MQTT');
  }

  void _onMqttStatus(MqttLiveStatus status) {
    if (!mounted || _activeTransport != _LiveTransport.mqtt) return;

    setState(() {
      _socketState = _mapMqttState(status.state);
      _socketMessage = status.message;
    });
  }

  void _applyLivePayload(
    Map<String, dynamic> decoded, {
    required String sourceLabel,
  }) {
    final frame = _TelemetryFrame.fromJson(decoded, fallback: _liveFrame);
    final selectedDeviceId = widget.selectedDeviceId;

    // Ignore frames that explicitly belong to another device.
    if (selectedDeviceId != null &&
        frame.deviceId != 'unknown' &&
        frame.deviceId != selectedDeviceId) {
      return;
    }

    final incomingTs = frame.tsMs;
    if (incomingTs != null &&
        _lastLiveTsMs != null &&
        incomingTs < _lastLiveTsMs!) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _liveFrame = frame;
      _lastLiveAt = DateTime.now();
      if (incomingTs != null) {
        _lastLiveTsMs = incomingTs;
      }
      _socketState = _SocketState.connected;
      _socketMessage = 'Live $sourceLabel stream active';
    });
  }

  _SocketState _mapMqttState(MqttLiveState state) {
    switch (state) {
      case MqttLiveState.connected:
        return _SocketState.connected;
      case MqttLiveState.connecting:
        return _SocketState.connecting;
      case MqttLiveState.retrying:
        return _SocketState.retrying;
      case MqttLiveState.disconnected:
        return _SocketState.disconnected;
    }
  }

  void _onSocketError(Object error) {
    _handleSocketFailure('Socket error: $error');
  }

  void _onSocketDone() {
    _handleSocketFailure('Socket closed, retrying');
  }

  void _handleSocketFailure(String message) {
    _detachSocket();
    if (!mounted) return;

    setState(() {
      _socketState = _activeWsUrl == null
          ? _SocketState.disconnected
          : _SocketState.retrying;
      _socketMessage = message;
    });

    if (_activeWsUrl != null && _reconnectTimer == null) {
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        _reconnectTimer = null;
        if (!mounted) return;
        _switchSocket(_activeWsUrl);
      });
    }
  }

  String _stateLabel() {
    switch (_socketState) {
      case _SocketState.connected:
        return 'Connected';
      case _SocketState.connecting:
        return 'Connecting';
      case _SocketState.retrying:
        return 'Retrying';
      case _SocketState.disconnected:
        return 'Disconnected';
    }
  }

  String _transportLabel() {
    switch (_activeTransport) {
      case _LiveTransport.mqtt:
        return 'MQTT';
      case _LiveTransport.websocketLegacy:
        return 'WebSocket (Legacy)';
      case _LiveTransport.firestore:
        return 'Firestore Fallback';
    }
  }

  Color _stateColor() {
    switch (_socketState) {
      case _SocketState.connected:
        return Colors.green;
      case _SocketState.connecting:
        return Colors.orange;
      case _SocketState.retrying:
        return Colors.deepOrange;
      case _SocketState.disconnected:
        return Colors.grey;
    }
  }

  String _fmtDouble(double? value, String unit, {int digits = 2}) {
    if (value == null) return '--';
    final text = value.toStringAsFixed(digits);
    if (unit.isEmpty) return text;
    return '$text $unit';
  }

  String _fmtInt(int? value, String unit) {
    if (value == null) return '--';
    return '$value $unit';
  }

  String _effectiveEndpoint({String? wsUrl, String? mqttTopicLive}) {
    switch (_activeTransport) {
      case _LiveTransport.mqtt:
        return _activeMqttTopic ?? mqttTopicLive ?? 'Not available yet';
      case _LiveTransport.websocketLegacy:
        return _activeWsUrl ?? wsUrl ?? 'Not available yet';
      case _LiveTransport.firestore:
        return mqttTopicLive ?? wsUrl ?? 'Not available yet';
    }
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceId = widget.selectedDeviceId;
    if (deviceId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Live Dashboard'),
          bottom: const DeviceSelectorHeaderBottom(),
        ),
        body: const Center(
          child: Text(
            'No devices found. Flash an ESP32 with a unique DEVICE_ID and connect it.',
          ),
        ),
      );
    }

    final ref = _deviceRef;
    if (ref == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Dashboard'),
        bottom: const DeviceSelectorHeaderBottom(),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        key: ValueKey<String>('dashboard-device-$deviceId'),
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snap.hasData || !snap.data!.exists) {
            return Center(child: Text('Device not found: devices/$deviceId'));
          }

          final data = snap.data!.data() ?? <String, dynamic>{};
          final wsUrl = data['wsUrl']?.toString();
          final mqttTopicLive = data['mqttTopicLive']?.toString();
          final mqttStatusTopic = data['mqttStatusTopic']?.toString();
          final mqttEnabled =
              _TelemetryFrame._toBoolValue(data['mqttEnabled']) ?? false;
          final realtimeTransport = (data['realtimeTransport'] ?? '')
              .toString()
              .toLowerCase()
              .trim();

          final prefersMqtt = realtimeTransport == 'mqtt' && mqttEnabled;
          final hasMqttTopic =
              mqttTopicLive != null && mqttTopicLive.trim().isNotEmpty;

          if (prefersMqtt && hasMqttTopic) {
            _queueWsUrlSync(null);
            _queueMqttSync(
              rawTopic: mqttTopicLive,
              rawStatusTopic: mqttStatusTopic,
            );
          } else if (prefersMqtt) {
            _queueWsUrlSync(null);
            _queueMqttSync(rawTopic: null, rawStatusTopic: null);
          } else {
            _queueMqttSync(rawTopic: null, rawStatusTopic: null);
            _queueWsUrlSync(wsUrl);
          }

          final firestoreFrame = _TelemetryFrame.fromFirestore(
            data,
            fallback: _liveFrame,
          );
          final activeFrame = _liveFrame ?? firestoreFrame;

          final pumpOn = activeFrame.pumpState ?? false;
          final valveOpen = activeFrame.valveState ?? false;
          final firestoreTs = data['lastSeen'];
          final firestoreSeen = firestoreTs is Timestamp
              ? firestoreTs.toDate()
              : null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(Icons.wifi_tethering, color: _stateColor()),
                  title: Text('Live Stream: ${_stateLabel()}'),
                  subtitle: Text(_socketMessage),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Transport / Endpoint'),
                  subtitle: Text(
                    '${_transportLabel()}\n${_effectiveEndpoint(wsUrl: wsUrl, mqttTopicLive: mqttTopicLive)}',
                  ),
                  isThreeLine: true,
                ),
              ),
              
              const SizedBox(height: 12),
              _weatherDashboardCard(deviceId),

              if (_activeAlertMetrics.isNotEmpty) ...[
                const SizedBox(height: 12),
                _activeAlertCard(activeFrame),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 170,
                    child: _metricCard(
                      icon: Icons.thermostat,
                      label: 'Temperature',
                      value: _fmtDouble(activeFrame.temperatureC, '°C'),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _metricCard(
                      icon: Icons.science_outlined,
                      label: 'pH',
                      value: _fmtDouble(activeFrame.ph, ''),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _metricCard(
                      icon: Icons.water_drop_outlined,
                      label: 'Water Level',
                      value: _fmtDouble(activeFrame.waterLevelPct, '%'),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _metricCard(
                      icon: Icons.opacity_outlined,
                      label: 'TDS',
                      value: _fmtDouble(activeFrame.tdsPpm, 'ppm'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        avatar: Icon(
                          pumpOn ? Icons.flash_on : Icons.flash_off,
                          color: pumpOn ? Colors.green : Colors.grey,
                        ),
                        label: Text('Pump: ${pumpOn ? 'ON' : 'OFF'}'),
                      ),
                      Chip(
                        avatar: Icon(
                          valveOpen
                              ? Icons.settings_input_component
                              : Icons.block,
                          color: valveOpen ? Colors.green : Colors.grey,
                        ),
                        label: Text('Valve: ${valveOpen ? 'OPEN' : 'CLOSED'}'),
                      ),
                      Chip(
                        avatar: const Icon(Icons.network_check),
                        label: Text(
                          'RSSI: ${_fmtInt(activeFrame.rssi, 'dBm')}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.update),
                  title: const Text('Last Live Update'),
                  subtitle: Text(
                    _lastLiveAt == null
                        ? 'No live messages yet'
                        : _timeFormatter.format(_lastLiveAt!),
                  ),
                ),
              ),
              if (_socketState != _SocketState.connected) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.amber.shade50,
                  child: ListTile(
                    leading: const Icon(Icons.storage),
                    title: const Text('Fallback: Firestore Snapshot'),
                    subtitle: Text(
                      firestoreSeen == null
                          ? 'Using latest cached fields from device document'
                          : 'Last Firestore heartbeat: ${_timeFormatter.format(firestoreSeen)}',
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
