import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:iot_aqua_app/core/device/device_selector_header.dart';
import 'package:iot_aqua_app/core/device/device_selection_controller.dart';
import 'package:iot_aqua_app/core/local/local_backend_config.dart';
import 'package:iot_aqua_app/core/realtime/mqtt_telemetry_service.dart';
import 'package:iot_aqua_app/widgets/emergency_alert_watcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum _SocketState { disconnected, connecting, connected, retrying }

enum _LiveTransport { firestore, mqtt, websocketLegacy, localBackend }

class _TelemetryFrame {
  final String deviceId;
  final int? tsMs;
  final double? temperatureC;
  final double? ph;
  final double? waterLevelPct;
  final double? tdsPpm;
  final double? phUpTankLevelPct;
  final double? phDownTankLevelPct;
  final double? nutrientTankLevelPct;
  final String? sensorStatus;
  final bool? lastReadOk;
  final bool? nanoOnline;
  final int? nanoLastSeenMs;
  final int? nanoAgeMs;
  final String? nanoError;
  final int? sampleCount;
  final Map<String, bool> relayStates;
  final String? relaySummary;
  final int? rssi;

  const _TelemetryFrame({
    required this.deviceId,
    this.tsMs,
    this.temperatureC,
    this.ph,
    this.waterLevelPct,
    this.tdsPpm,
    this.phUpTankLevelPct,
    this.phDownTankLevelPct,
    this.nutrientTankLevelPct,
    this.sensorStatus,
    this.lastReadOk,
    this.nanoOnline,
    this.nanoLastSeenMs,
    this.nanoAgeMs,
    this.nanoError,
    this.sampleCount,
    this.relayStates = const {},
    this.relaySummary,
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
      phUpTankLevelPct:
          _toDoubleValue(json['phUpTankLevelPct']) ??
          fallback?.phUpTankLevelPct,
      phDownTankLevelPct:
          _toDoubleValue(json['phDownTankLevelPct']) ??
          fallback?.phDownTankLevelPct,
      nutrientTankLevelPct:
          _toDoubleValue(json['nutrientTankLevelPct']) ??
          fallback?.nutrientTankLevelPct,
      sensorStatus:
          _toStringValue(json['sensorStatus']) ?? fallback?.sensorStatus,
      lastReadOk: _toBoolValue(json['lastReadOk']) ?? fallback?.lastReadOk,
      nanoOnline: _toBoolValue(json['nanoOnline']) ?? fallback?.nanoOnline,
      nanoLastSeenMs:
          _toIntValue(json['nanoLastSeenMs']) ?? fallback?.nanoLastSeenMs,
      nanoAgeMs: _toIntValue(json['nanoAgeMs']) ?? fallback?.nanoAgeMs,
      nanoError: _toStringValue(json['nanoError']) ?? fallback?.nanoError,
      sampleCount: _toIntValue(json['sampleCount']) ?? fallback?.sampleCount,
      relayStates:
          _toBoolMap(json['relayStates']) ??
          fallback?.relayStates ??
          const <String, bool>{},
      relaySummary:
          _toStringValue(json['relaySummary']) ?? fallback?.relaySummary,
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
      phUpTankLevelPct:
          _toDoubleValue(data['phUpTankLevelPct']) ??
          fallback?.phUpTankLevelPct,
      phDownTankLevelPct:
          _toDoubleValue(data['phDownTankLevelPct']) ??
          fallback?.phDownTankLevelPct,
      nutrientTankLevelPct:
          _toDoubleValue(data['nutrientTankLevelPct']) ??
          fallback?.nutrientTankLevelPct,
      sensorStatus:
          _toStringValue(data['sensorStatus']) ?? fallback?.sensorStatus,
      lastReadOk: _toBoolValue(data['lastReadOk']) ?? fallback?.lastReadOk,
      nanoOnline: _toBoolValue(data['nanoOnline']) ?? fallback?.nanoOnline,
      nanoLastSeenMs:
          _toIntValue(data['nanoLastSeenMs']) ?? fallback?.nanoLastSeenMs,
      nanoAgeMs: _toIntValue(data['nanoAgeMs']) ?? fallback?.nanoAgeMs,
      nanoError: _toStringValue(data['nanoError']) ?? fallback?.nanoError,
      sampleCount: _toIntValue(data['sampleCount']) ?? fallback?.sampleCount,
      relayStates:
          _toBoolMap(data['relayStates']) ??
          fallback?.relayStates ??
          const <String, bool>{},
      relaySummary:
          _toStringValue(data['relaySummary']) ?? fallback?.relaySummary,
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

  static Map<String, bool>? _toBoolMap(dynamic value) {
    if (value is! Map) return null;
    final out = <String, bool>{};
    value.forEach((key, raw) {
      final parsed = _toBoolValue(raw);
      if (parsed != null) {
        out[key.toString()] = parsed;
      }
    });
    return out;
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
  Timer? _staleUiTimer;

  StreamSubscription<Map<String, dynamic>>? _mqttFrameSub;
  StreamSubscription<MqttLiveStatus>? _mqttStatusSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _alertStateSub;

  _TelemetryFrame? _liveFrame;
  DateTime? _lastLiveAt;
  int? _lastLiveTsMs;
  List<String> _activeAlertMetrics = const [];
  Map<String, dynamic>? _alertStateData;

  _SocketState _socketState = _SocketState.disconnected;
  String _socketMessage = 'Waiting for simulator endpoint';
  _LiveTransport _activeTransport = _LiveTransport.firestore;

  String? _activeWsUrl;
  String? _queuedWsUrl;
  _LiveTransport? _queuedWsTransport;

  String? _activeMqttTopic;
  String? _activeMqttStatusTopic;
  String? _queuedMqttTopic;
  String? _queuedMqttStatusTopic;

  @override
  void initState() {
    super.initState();
    _bindAlertState(widget.selectedDeviceId);
    _staleUiTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _staleUiTimer?.cancel();
    _detachSocket();
    _mqttFrameSub?.cancel();
    _mqttStatusSub?.cancel();
    _alertStateSub?.cancel();
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
      _queuedWsTransport = null;
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
          return _infoCard(
            icon: Icons.cloud_outlined,
            title: 'Weather Forecast',
            subtitle: 'No weather data yet. Open Weather AI and refresh.',
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

        return _infoCard(
          icon: icon,
          title: 'Weather Forecast (Next 24h)',
          subtitle:
              '$location • Updated: $updatedText\n'
              'Max: ${maxTemp.toStringAsFixed(1)}°C  •  Rain: ${rainChance.toStringAsFixed(0)}%  •  Precip: ${precip.toStringAsFixed(1)}mm',
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
          (metric) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.shade100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_prettyMetric(metric)}: ${_metricValueForAlert(metric, frame)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        )
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Active Alerts',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Threshold source: $source',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }

  void _queueWsUrlSync(
    String? rawWsUrl, {
    _LiveTransport transport = _LiveTransport.websocketLegacy,
  }) {
    final normalized = (rawWsUrl == null || rawWsUrl.trim().isEmpty)
        ? null
        : rawWsUrl.trim();

    if (normalized == _activeWsUrl && _activeTransport == transport) return;
    if (normalized == _queuedWsUrl && _queuedWsTransport == transport) return;
    _queuedWsUrl = normalized;
    _queuedWsTransport = transport;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = _queuedWsUrl;
      final nextTransport =
          _queuedWsTransport ?? _LiveTransport.websocketLegacy;
      _queuedWsUrl = null;
      _queuedWsTransport = null;
      if (next == _activeWsUrl && _activeTransport == nextTransport) return;
      _switchSocket(next, transport: nextTransport);
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

  void _switchSocket(
    String? wsUrl, {
    _LiveTransport transport = _LiveTransport.websocketLegacy,
  }) {
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
        _activeTransport = transport;
        _socketMessage = 'Invalid wsUrl format: $wsUrl';
      });
      return;
    }

    setState(() {
      _activeWsUrl = wsUrl;
      _activeTransport = transport;
      _lastLiveTsMs = null;
      _socketState = _SocketState.connecting;
      _socketMessage = 'Connecting to $wsUrl';
    });

    unawaited(_openChannel(wsUrl, uri, transport));
  }

  /// Opens the live WebSocket. For the realtime server transport the Firebase ID
  /// token is attached as a `token` query param so the server can authenticate
  /// the connection. The token is never attached to legacy/third-party URLs.
  Future<void> _openChannel(
    String wsUrl,
    Uri uri,
    _LiveTransport transport,
  ) async {
    var connectUri = uri;
    if (transport == _LiveTransport.localBackend &&
        !uri.queryParameters.containsKey('token')) {
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null && token.isNotEmpty) {
          connectUri = uri.replace(
            queryParameters: {...uri.queryParameters, 'token': token},
          );
        }
      } catch (_) {
        // Fall back to an unauthenticated connection; the backend currently
        // allows it (LOCAL_BACKEND_REQUIRE_AUTH=false).
      }
    }

    // Guard against a newer switch having superseded this one while awaiting
    // the token.
    if (!mounted || _activeWsUrl != wsUrl) return;

    try {
      final channel = WebSocketChannel.connect(connectUri);
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
    if (decoded is! Map) return;

    final mapped = _toStringDynamicMap(decoded);
    final type = mapped?['type']?.toString();
    final wrappedPayload = _toStringDynamicMap(mapped?['payload']);

    if (type == 'telemetry' && wrappedPayload != null) {
      _applyLivePayload(wrappedPayload, sourceLabel: 'Realtime Server');
      return;
    }

    if (type == 'device_status' && wrappedPayload != null) {
      final online = _TelemetryFrame._toBoolValue(wrappedPayload['online']);
      if (!mounted || online == null) return;
      setState(() {
        _socketState = online
            ? _SocketState.connected
            : _SocketState.disconnected;
        _socketMessage = online
            ? 'Local backend heartbeat active'
            : 'Local backend marked ESP offline';
        if (online) _lastLiveAt = DateTime.now();
      });
      return;
    }

    if (type == 'hello' ||
        type == 'stream_heartbeat' ||
        type == 'command' ||
        type == 'device_patch') {
      return;
    }

    if (mapped == null) return;
    _applyLivePayload(mapped, sourceLabel: 'WebSocket');
  }

  Map<String, dynamic>? _toStringDynamicMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map<String, dynamic>((dynamic key, dynamic value) {
        return MapEntry(key.toString(), value);
      });
    }
    return null;
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
        _switchSocket(_activeWsUrl, transport: _activeTransport);
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
      case _LiveTransport.localBackend:
        return 'Realtime Server';
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

  bool _hasNanoError(_TelemetryFrame frame) {
    if (frame.nanoOnline == false) return true;
    final error = frame.nanoError?.trim();
    return error != null && error.isNotEmpty;
  }

  String _nanoHealthSubtitle(_TelemetryFrame frame) {
    final online = frame.nanoOnline;
    final ageMs = frame.nanoAgeMs;
    final ageText = ageMs == null || ageMs < 0
        ? 'No valid Nano packet yet'
        : 'Last Nano packet ${ageMs}ms ago';
    final error = frame.nanoError?.trim();
    if (online == false) {
      return error == null || error.isEmpty
          ? 'Arduino Nano is offline. $ageText.'
          : '$error\n$ageText.';
    }
    if (error != null && error.isNotEmpty) {
      return '$error\n$ageText.';
    }
    if (online == true) return 'Arduino Nano UART online. $ageText.';
    return 'Waiting for Nano health from ESP32.';
  }

  String _effectiveEndpoint({String? wsUrl, String? mqttTopicLive}) {
    switch (_activeTransport) {
      case _LiveTransport.mqtt:
        return _activeMqttTopic ?? mqttTopicLive ?? 'Not available yet';
      case _LiveTransport.websocketLegacy:
        return _activeWsUrl ?? wsUrl ?? 'Not available yet';
      case _LiveTransport.localBackend:
        return _activeWsUrl ?? 'Realtime server not configured';
      case _LiveTransport.firestore:
        return mqttTopicLive ?? wsUrl ?? 'Not available yet';
    }
  }

  bool _isRecentlySeen(DateTime? seenAt) {
    if (seenAt == null) return false;
    return DateTime.now().difference(seenAt) <= kDeviceOfflineAfter;
  }

  String _trendLabel(double? value, {double low = 0, double high = 0}) {
    if (value == null) return 'No Data';
    if (high != 0 && value > high) return 'Rising';
    if (low != 0 && value < low) return 'Low';
    return 'Stable';
  }

  IconData _trendIcon(String trend) {
    switch (trend) {
      case 'Rising':
        return Icons.trending_up_rounded;
      case 'Low':
        return Icons.trending_down_rounded;
      case 'Stable':
        return Icons.arrow_forward_rounded;
      default:
        return Icons.remove_rounded;
    }
  }

  Color _trendBgColor(String trend) {
    switch (trend) {
      case 'Rising':
        return const Color(0xFFE7F6EA);
      case 'Low':
        return const Color(0xFFFFF1F0);
      case 'Stable':
        return const Color(0xFFF1F3F4);
      default:
        return const Color(0xFFF1F3F4);
    }
  }

  Color _trendTextColor(String trend) {
    switch (trend) {
      case 'Rising':
        return const Color(0xFF2E7D32);
      case 'Low':
        return const Color(0xFFD84315);
      case 'Stable':
        return Colors.black54;
      default:
        return Colors.black54;
    }
  }

  Widget _miniTrendLine() {
    return SizedBox(
      height: 50,
      child: CustomPaint(
        painter: _MiniLinePainter(),
        size: const Size(double.infinity, 50),
      ),
    );
  }

  Widget _dashboardMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required String trend,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4EC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _trendBgColor(trend),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _trendIcon(trend),
                      size: 16,
                      color: _trendTextColor(trend),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trend,
                      style: TextStyle(
                        color: _trendTextColor(trend),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black54,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111111),
            ),
          ),
          const Spacer(),
          _miniTrendLine(),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4EC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor ?? const Color(0xFF2E7D32)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black54, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE7F6EA) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: active ? const Color(0xFF2E7D32) : Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: active ? const Color(0xFF2E7D32) : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceId = widget.selectedDeviceId;
    final liveRecentlySeen = _isRecentlySeen(_lastLiveAt);
    final headerOnline =
        _socketState == _SocketState.connected && liveRecentlySeen;
    if (deviceId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        appBar: AppBar(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('AquaFarm Monitor'),
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

    return EmergencyAlertWatcher(
      deviceId: deviceId,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7F8),
        appBar: AppBar(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'AquaFarm Monitor',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    color: headerOnline
                        ? const Color(0xFF9BE59B)
                        : Colors.red.shade300,
                    size: 10,
                  ),
                  const SizedBox(width: 6),
                  Text(headerOnline ? 'Online' : 'Offline'),
                ],
              ),
            ),
          ],
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
            final localBackendWsUrl = LocalBackendConfig.websocketUrlForDevice(
              deviceId,
            );

            final prefersMqtt = realtimeTransport == 'mqtt' && mqttEnabled;
            final hasMqttTopic =
                mqttTopicLive != null && mqttTopicLive.trim().isNotEmpty;

            if (localBackendWsUrl != null) {
              _queueMqttSync(rawTopic: null, rawStatusTopic: null);
              _queueWsUrlSync(
                localBackendWsUrl,
                transport: _LiveTransport.localBackend,
              );
            } else if (prefersMqtt && hasMqttTopic) {
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

            final firestoreTs = data['lastSeen'];
            final firestoreSeen = firestoreTs is Timestamp
                ? firestoreTs.toDate()
                : null;
            final firestoreOnline =
                (data['online'] ?? false) == true &&
                _isRecentlySeen(firestoreSeen);
            final liveFrame = liveRecentlySeen ? _liveFrame : null;
            final effectiveLastSeen = liveRecentlySeen
                ? _lastLiveAt
                : firestoreSeen;
            final firestoreFrame = _TelemetryFrame.fromFirestore(
              data,
              fallback: liveFrame,
            );
            final activeFrame = liveFrame ?? firestoreFrame;
            final deviceOnline = liveRecentlySeen || firestoreOnline;
            final relaySummary =
                activeFrame.relaySummary ??
                (activeFrame.relayStates.isEmpty
                    ? 'No relay state available'
                    : activeFrame.relayStates.entries
                          .map((e) => '${e.key}: ${e.value ? "ON" : "OFF"}')
                          .join('\n'));
            final feederRunning =
                activeFrame.relayStates['fishFeeder'] ??
                activeFrame.relayStates['fish_feeder'] ??
                false;

            final phTrend = _trendLabel(activeFrame.ph, low: 6.0, high: 7.5);
            final waterTrend = _trendLabel(
              activeFrame.waterLevelPct,
              low: 35,
              high: 85,
            );
            final tdsTrend = _trendLabel(
              activeFrame.tdsPpm,
              low: 400,
              high: 1000,
            );
            final phUpTankTrend = _trendLabel(
              activeFrame.phUpTankLevelPct,
              low: 20,
            );
            final phDownTankTrend = _trendLabel(
              activeFrame.phDownTankLevelPct,
              low: 20,
            );
            final nutrientTankTrend = _trendLabel(
              activeFrame.nutrientTankLevelPct,
              low: 20,
            );
            final hasNanoError = _hasNanoError(activeFrame);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoCard(
                    icon: Icons.wifi_tethering,
                    iconColor: deviceOnline
                        ? _stateColor()
                        : const Color(0xFFD84315),
                    title:
                        'Live Stream: ${deviceOnline ? _stateLabel() : 'Offline'}',
                    subtitle:
                        'Transport: ${_transportLabel()}\n'
                        '${deviceOnline ? _socketMessage : 'No telemetry heartbeat from ESP32'}\n'
                        'Last seen: ${effectiveLastSeen == null ? '--' : _timeFormatter.format(effectiveLastSeen)}',
                  ),
                  const SizedBox(height: 14),
                  _infoCard(
                    icon: Icons.link,
                    title: 'Endpoint',
                    subtitle: _effectiveEndpoint(
                      wsUrl: wsUrl,
                      mqttTopicLive: mqttTopicLive,
                    ),
                  ),
                  if (hasNanoError) ...[
                    const SizedBox(height: 14),
                    _infoCard(
                      icon: Icons.sensors_off,
                      iconColor: const Color(0xFFD84315),
                      title: 'Arduino Nano Data Error',
                      subtitle: _nanoHealthSubtitle(activeFrame),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _infoCard(
                    icon: Icons.power,
                    title: 'Relay States',
                    subtitle: relaySummary,
                  ),
                  const SizedBox(height: 18),

                  const Text(
                    'Sensor Readings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 14),

                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.65,
                    children: [
                      _dashboardMetricCard(
                        icon: Icons.science_outlined,
                        title: 'pH Level',
                        value: _fmtDouble(activeFrame.ph, 'pH'),
                        trend: phTrend,
                        iconColor: const Color(0xFF2E7D32),
                      ),
                      _dashboardMetricCard(
                        icon: Icons.bolt_outlined,
                        title: 'Electrical\nConductivity',
                        value: _fmtDouble(activeFrame.tdsPpm, 'ppm'),
                        trend: tdsTrend,
                        iconColor: const Color(0xFF2E7D32),
                      ),
                      _dashboardMetricCard(
                        icon: Icons.water_drop_outlined,
                        title: 'Water Level',
                        value: _fmtDouble(activeFrame.waterLevelPct, '%'),
                        trend: waterTrend,
                        iconColor: const Color(0xFF2E7D32),
                      ),
                      _dashboardMetricCard(
                        icon: Icons.local_drink_outlined,
                        title: 'pH Up Tank',
                        value: _fmtDouble(activeFrame.phUpTankLevelPct, '%'),
                        trend: phUpTankTrend,
                        iconColor: const Color(0xFF1565C0),
                      ),
                      _dashboardMetricCard(
                        icon: Icons.local_drink,
                        title: 'pH Down Tank',
                        value: _fmtDouble(activeFrame.phDownTankLevelPct, '%'),
                        trend: phDownTankTrend,
                        iconColor: const Color(0xFF6A1B9A),
                      ),
                      _dashboardMetricCard(
                        icon: Icons.grass_outlined,
                        title: 'Nutrient Tank',
                        value: _fmtDouble(
                          activeFrame.nutrientTankLevelPct,
                          '%',
                        ),
                        trend: nutrientTankTrend,
                        iconColor: const Color(0xFF558B2F),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                  _infoCard(
                    icon: activeFrame.lastReadOk == false || hasNanoError
                        ? Icons.error_outline
                        : Icons.sensors,
                    iconColor: activeFrame.lastReadOk == false || hasNanoError
                        ? const Color(0xFFD84315)
                        : const Color(0xFF2E7D32),
                    title: 'Sensor Health',
                    subtitle:
                        'Status: ${activeFrame.sensorStatus ?? 'No status yet'}\n'
                        '${_nanoHealthSubtitle(activeFrame)}\n'
                        'Samples: ${activeFrame.sampleCount?.toString() ?? '--'}\n'
                        'Last read: ${activeFrame.lastReadOk == false || hasNanoError ? 'Check sensors' : 'OK'}',
                  ),

                  const SizedBox(height: 18),
                  _weatherDashboardCard(deviceId),

                  if (_activeAlertMetrics.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _activeAlertCard(activeFrame),
                  ],

                  const SizedBox(height: 18),
                  const Text(
                    'System Status',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x11000000),
                          blurRadius: 12,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _statusChip(
                          icon: deviceOnline ? Icons.wifi : Icons.wifi_off,
                          label: 'ESP: ${deviceOnline ? 'ONLINE' : 'OFFLINE'}',
                          active: deviceOnline,
                        ),
                        _statusChip(
                          icon: feederRunning
                              ? Icons.restaurant
                              : Icons.restaurant_outlined,
                          label:
                              'Feeder: ${feederRunning ? 'RUNNING' : 'READY'}',
                          active: feederRunning,
                        ),
                        _statusChip(
                          icon: Icons.network_check,
                          label: 'RSSI: ${_fmtInt(activeFrame.rssi, 'dBm')}',
                          active: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),
                  _infoCard(
                    icon: Icons.update,
                    title: 'Last Seen',
                    subtitle: effectiveLastSeen == null
                        ? 'No telemetry heartbeat yet'
                        : _timeFormatter.format(effectiveLastSeen),
                  ),

                  if (_socketState != _SocketState.connected) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.amber.shade100),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.storage, color: Colors.orange),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              firestoreSeen == null
                                  ? 'Using latest cached fields from device document'
                                  : 'Fallback: Firestore snapshot\nLast Firestore heartbeat: ${_timeFormatter.format(firestoreSeen)}',
                              style: const TextStyle(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MiniLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = const Color(0x142E7D32)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFF2E7D32)
      ..strokeWidth = 2.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(0, size.height * 0.72);
    path.quadraticBezierTo(
      size.width * 0.12,
      size.height * 0.58,
      size.width * 0.25,
      size.height * 0.55,
    );
    path.quadraticBezierTo(
      size.width * 0.38,
      size.height * 0.48,
      size.width * 0.52,
      size.height * 0.56,
    );
    path.quadraticBezierTo(
      size.width * 0.68,
      size.height * 0.68,
      size.width * 0.82,
      size.height * 0.52,
    );
    path.quadraticBezierTo(
      size.width * 0.92,
      size.height * 0.48,
      size.width,
      size.height * 0.54,
    );

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
