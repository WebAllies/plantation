import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:http/http.dart' as http;

class NanoUsbBridgeService extends ChangeNotifier {
  NanoUsbBridgeService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  List<String> ports = const [];
  String? selectedPort;
  int baudRate = 115200;
  String backendUrl = 'http://116.203.96.119:8080';
  String deviceId = 'esp32_aquaponics_01';

  bool isRunning = false;
  String status = 'Stopped';
  String? error;
  DateTime? lastLineAt;
  DateTime? lastPublishAt;
  final Map<String, double> readings = <String, double>{};
  final List<String> logs = <String>[];

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _sub;
  Timer? _publishTimer;
  String _lineBuffer = '';
  int _sampleCount = 0;
  int _heartbeatSeq = 0;

  static const Map<String, String> _fieldForNanoKey = <String, String>{
    'PH': 'ph',
    'TDS': 'tdsPpm',
    'PHUP': 'phUpTankLevelPct',
    'PHDOWN': 'phDownTankLevelPct',
    'NUTRIENT': 'nutrientTankLevelPct',
  };

  void refreshPorts() {
    try {
      ports = SerialPort.availablePorts;
      if (selectedPort == null || !ports.contains(selectedPort)) {
        selectedPort = ports.isEmpty ? null : ports.first;
      }
      _log('Ports: ${ports.isEmpty ? 'none' : ports.join(', ')}');
      notifyListeners();
    } catch (e) {
      error = e.toString();
      _log('Port scan failed: $e');
      notifyListeners();
    }
  }

  void setPort(String? value) {
    selectedPort = value;
    notifyListeners();
  }

  void setBaudRate(int value) {
    baudRate = value;
    notifyListeners();
  }

  void setBackendUrl(String value) {
    backendUrl = value.trim();
    notifyListeners();
  }

  void setDeviceId(String value) {
    deviceId = value.trim();
    notifyListeners();
  }

  Future<void> start() async {
    if (isRunning) return;
    final portName = selectedPort;
    if (portName == null || portName.isEmpty) {
      error = 'Choose a COM port first';
      notifyListeners();
      return;
    }
    if (deviceId.isEmpty) {
      error = 'Choose a device first';
      notifyListeners();
      return;
    }

    error = null;
    readings.clear();
    _lineBuffer = '';
    _sampleCount = 0;
    _heartbeatSeq = 0;

    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      error = SerialPort.lastError?.message ?? 'Could not open $portName';
      _log(error!);
      notifyListeners();
      return;
    }

    final config = SerialPortConfig()
      ..baudRate = baudRate
      ..bits = 8
      ..stopBits = 1
      ..parity = SerialPortParity.none;
    port.config = config;

    _port = port;
    _reader = SerialPortReader(port);
    _sub = _reader!.stream.listen(
      _onBytes,
      onError: (Object e, StackTrace st) {
        error = e.toString();
        _log('Serial error: $e');
        notifyListeners();
      },
      cancelOnError: false,
    );
    _publishTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_publish());
    });

    isRunning = true;
    status = 'Running on $portName @ $baudRate';
    _log(status);
    notifyListeners();
  }

  Future<void> stop() async {
    _publishTimer?.cancel();
    _publishTimer = null;
    await _sub?.cancel();
    _sub = null;
    _reader?.close();
    _reader = null;
    _port?.close();
    _port = null;
    isRunning = false;
    status = 'Stopped';
    _log(status);
    notifyListeners();
  }

  void _onBytes(Uint8List bytes) {
    final chunk = utf8.decode(bytes, allowMalformed: true);
    for (final codeUnit in chunk.codeUnits) {
      final ch = String.fromCharCode(codeUnit);
      if (ch == '\r') continue;
      if (ch == '\n') {
        final line = _lineBuffer.trim();
        _lineBuffer = '';
        if (line.isNotEmpty) _handleLine(line);
      } else {
        _lineBuffer += ch;
        if (_lineBuffer.length > 160) _lineBuffer = '';
      }
    }
  }

  void _handleLine(String line) {
    lastLineAt = DateTime.now();
    _log(line);

    final sep = line.indexOf(':');
    if (sep <= 0) {
      notifyListeners();
      return;
    }

    final key = line.substring(0, sep).trim().toUpperCase();
    final field = _fieldForNanoKey[key];
    if (field == null) {
      notifyListeners();
      return;
    }

    final value = double.tryParse(line.substring(sep + 1).trim());
    if (value == null || value.isNaN || value.isInfinite) {
      notifyListeners();
      return;
    }

    readings[field] = double.parse(value.toStringAsFixed(2));
    notifyListeners();
  }

  Future<void> _publish() async {
    if (!isRunning ||
        readings.isEmpty ||
        deviceId.isEmpty ||
        backendUrl.isEmpty) {
      return;
    }

    final missing = <String>[];
    for (final entry in _fieldForNanoKey.entries) {
      if (!readings.containsKey(entry.value)) missing.add(entry.key);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    _sampleCount += 1;
    _heartbeatSeq += 1;
    final payload = <String, dynamic>{
      'deviceId': deviceId,
      'tsEpochMs': now.toString(),
      'nanoOnline': true,
      'nanoTransport': 'windows_app_usb_bridge',
      'nanoError': missing.isEmpty
          ? ''
          : 'Windows bridge missing readings: ${missing.join(',')}',
      'sensorStatus':
          'nano=windows_app_usb_bridge,ph=${readings.containsKey('ph') ? 'ok' : 'stale'}'
          ',tds=${readings.containsKey('tdsPpm') ? 'ok' : 'stale'}'
          ',phUp=${readings.containsKey('phUpTankLevelPct') ? 'ok' : 'stale'}'
          ',phDown=${readings.containsKey('phDownTankLevelPct') ? 'ok' : 'stale'}'
          ',nutrient=${readings.containsKey('nutrientTankLevelPct') ? 'ok' : 'stale'}',
      'lastReadOk': missing.isEmpty,
      'sampleCount': _sampleCount,
      'heartbeatSeq': _heartbeatSeq,
      ...readings,
    };

    final base = backendUrl.endsWith('/')
        ? backendUrl.substring(0, backendUrl.length - 1)
        : backendUrl;
    final uri = Uri.parse(
      '$base/api/devices/${Uri.encodeComponent(deviceId)}/nano-telemetry',
    );

    try {
      final response = await _client.post(
        uri,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      lastPublishAt = DateTime.now();
      error = null;
      _log('Published to $deviceId');
      notifyListeners();
    } catch (e) {
      error = e.toString();
      _log('Publish failed: $e');
      notifyListeners();
    }
  }

  void _log(String message) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    logs.insert(0, '[$stamp] $message');
    if (logs.length > 120) logs.removeRange(120, logs.length);
  }

  @override
  void dispose() {
    unawaited(stop());
    _client.close();
    super.dispose();
  }
}
