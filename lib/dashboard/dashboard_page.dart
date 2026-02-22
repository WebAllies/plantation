import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum _SocketState { disconnected, connecting, connected, retrying }

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
      tsMs: _toIntValue(json['tsMs']) ?? fallback?.tsMs,
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
    int? tsMs = _toIntValue(data['tsMs']) ?? fallback?.tsMs;
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

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _reconnectTimer;

  _TelemetryFrame? _liveFrame;
  DateTime? _lastLiveAt;

  _SocketState _socketState = _SocketState.disconnected;
  String _socketMessage = "Waiting for simulator endpoint";

  String? _activeWsUrl;
  String? _queuedWsUrl;

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _detachSocket();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDeviceId != widget.selectedDeviceId) {
      _reconnectTimer?.cancel();
      _detachSocket();
      _activeWsUrl = null;
      _queuedWsUrl = null;
      _liveFrame = null;
      _lastLiveAt = null;
      _socketState = _SocketState.disconnected;
      _socketMessage = "Waiting for simulator endpoint";
    }
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

  void _switchSocket(String? wsUrl) {
    _reconnectTimer?.cancel();
    _detachSocket();

    if (wsUrl == null) {
      setState(() {
        _activeWsUrl = null;
        _socketState = _SocketState.disconnected;
        _socketMessage = "Waiting for wsUrl in Firestore";
      });
      return;
    }

    final uri = Uri.tryParse(wsUrl);
    if (uri == null || (uri.scheme != 'ws' && uri.scheme != 'wss')) {
      setState(() {
        _activeWsUrl = wsUrl;
        _socketState = _SocketState.disconnected;
        _socketMessage = "Invalid wsUrl format: $wsUrl";
      });
      return;
    }

    setState(() {
      _activeWsUrl = wsUrl;
      _socketState = _SocketState.connecting;
      _socketMessage = "Connecting to $wsUrl";
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
      _handleSocketFailure("Connect error: $error");
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

    if (!mounted) return;
    setState(() {
      _liveFrame = _TelemetryFrame.fromJson(decoded, fallback: _liveFrame);
      _lastLiveAt = DateTime.now();
      _socketState = _SocketState.connected;
      _socketMessage = "Live WebSocket stream active";
    });
  }

  void _onSocketError(Object error) {
    _handleSocketFailure("Socket error: $error");
  }

  void _onSocketDone() {
    _handleSocketFailure("Socket closed, retrying");
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
        return "Connected";
      case _SocketState.connecting:
        return "Connecting";
      case _SocketState.retrying:
        return "Retrying";
      case _SocketState.disconnected:
        return "Disconnected";
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
    return "$text $unit";
  }

  String _fmtInt(int? value, String unit) {
    if (value == null) return '--';
    return "$value $unit";
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
        appBar: AppBar(title: const Text("Live Dashboard")),
        body: const Center(
          child: Text(
            "No devices found. Flash an ESP32 with a unique DEVICE_ID and connect it.",
          ),
        ),
      );
    }

    final ref = _deviceRef;
    if (ref == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Live Dashboard")),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snap.hasData || !snap.data!.exists) {
            return Center(child: Text("Device not found: devices/$deviceId"));
          }

          final data = snap.data!.data() ?? <String, dynamic>{};
          final wsUrl = data['wsUrl']?.toString();
          _queueWsUrlSync(wsUrl);

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
                  title: Text("WebSocket: ${_stateLabel()}"),
                  subtitle: Text(_socketMessage),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text("Endpoint"),
                  subtitle: Text(_activeWsUrl ?? wsUrl ?? "Not available yet"),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 170,
                    child: _metricCard(
                      icon: Icons.thermostat,
                      label: "Temperature",
                      value: _fmtDouble(activeFrame.temperatureC, "°C"),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _metricCard(
                      icon: Icons.science_outlined,
                      label: "pH",
                      value: _fmtDouble(activeFrame.ph, ""),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _metricCard(
                      icon: Icons.water_drop_outlined,
                      label: "Water Level",
                      value: _fmtDouble(activeFrame.waterLevelPct, "%"),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _metricCard(
                      icon: Icons.opacity_outlined,
                      label: "TDS",
                      value: _fmtDouble(activeFrame.tdsPpm, "ppm"),
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
                        label: Text("Pump: ${pumpOn ? "ON" : "OFF"}"),
                      ),
                      Chip(
                        avatar: Icon(
                          valveOpen
                              ? Icons.settings_input_component
                              : Icons.block,
                          color: valveOpen ? Colors.green : Colors.grey,
                        ),
                        label: Text("Valve: ${valveOpen ? "OPEN" : "CLOSED"}"),
                      ),
                      Chip(
                        avatar: const Icon(Icons.network_check),
                        label: Text(
                          "RSSI: ${_fmtInt(activeFrame.rssi, "dBm")}",
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
                  title: const Text("Last Live Update"),
                  subtitle: Text(
                    _lastLiveAt == null
                        ? "No WebSocket messages yet"
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
                    title: const Text("Fallback: Firestore Snapshot"),
                    subtitle: Text(
                      firestoreSeen == null
                          ? "Using latest cached fields from device document"
                          : "Last Firestore heartbeat: ${_timeFormatter.format(firestoreSeen)}",
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
