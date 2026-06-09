import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;

import 'mqtt_client_factory.dart';

enum MqttLiveState { disconnected, connecting, connected, retrying }

class MqttLiveStatus {
  const MqttLiveStatus({
    required this.state,
    required this.message,
    this.endpoint,
  });

  final MqttLiveState state;
  final String message;
  final String? endpoint;
}

class _MqttCredentialBundle {
  const _MqttCredentialBundle({
    required this.host,
    required this.port,
    required this.useTls,
    required this.useWebSocket,
    required this.websocketPath,
    required this.clientId,
    required this.username,
    required this.password,
    required this.liveTopic,
    required this.statusTopic,
  });

  final String host;
  final int port;
  final bool useTls;
  final bool useWebSocket;
  final String websocketPath;
  final String clientId;
  final String username;
  final String password;
  final String liveTopic;
  final String? statusTopic;

  String get endpointLabel {
    if (useWebSocket) {
      final normalizedPath = websocketPath.isEmpty
          ? '/mqtt'
          : (websocketPath.startsWith('/') ? websocketPath : '/$websocketPath');
      final scheme = useTls ? 'wss' : 'ws';
      return '$scheme://$host:$port$normalizedPath';
    }

    final scheme = useTls ? 'mqtts' : 'mqtt';
    return '$scheme://$host:$port';
  }

  static _MqttCredentialBundle fromMap(
    Map<String, dynamic> json, {
    required String fallbackDeviceId,
    required String fallbackLiveTopic,
    String? fallbackStatusTopic,
  }) {
    final brokerUrl = _asString(json['brokerUrl']);
    var host = _asString(json['brokerHost']) ?? '';
    var port = _asInt(json['brokerPort']);
    var wsPath = _asString(json['wsPath']) ?? '/mqtt';

    var useTls = _asBool(json['useTls']) ?? true;
    var useWebSocket = _asBool(json['useWebSocket']) ?? true;

    if (brokerUrl != null && brokerUrl.isNotEmpty) {
      final uri = Uri.tryParse(brokerUrl);
      if (uri != null && uri.host.isNotEmpty) {
        host = uri.host;
        if (uri.hasPort) {
          port = uri.port;
        }

        if (uri.path.isNotEmpty) {
          wsPath = uri.path;
        }

        if (uri.scheme == 'wss' || uri.scheme == 'ws') {
          useWebSocket = true;
          useTls = uri.scheme == 'wss';
        } else if (uri.scheme == 'mqtts' || uri.scheme == 'mqtt') {
          useWebSocket = false;
          useTls = uri.scheme == 'mqtts';
        }
      }
    }

    if (host.isEmpty) {
      throw StateError(
        'Missing MQTT brokerHost/brokerUrl in credential response',
      );
    }

    final resolvedPort =
        port ?? (useWebSocket ? (useTls ? 443 : 80) : (useTls ? 8883 : 1883));

    final clientId =
        _asString(json['clientId']) ??
        'app-$fallbackDeviceId-${DateTime.now().millisecondsSinceEpoch}';
    final username = _asString(json['username']) ?? '';
    final password =
        _asString(json['password']) ?? _asString(json['token']) ?? '';

    if (username.isEmpty || password.isEmpty) {
      throw StateError('Missing MQTT username/password in credential response');
    }

    final liveTopic = _asString(json['liveTopic']) ?? fallbackLiveTopic;
    final statusTopic = _asString(json['statusTopic']) ?? fallbackStatusTopic;

    return _MqttCredentialBundle(
      host: host,
      port: resolvedPort,
      useTls: useTls,
      useWebSocket: useWebSocket,
      websocketPath: wsPath,
      clientId: clientId,
      username: username,
      password: password,
      liveTopic: liveTopic,
      statusTopic: statusTopic,
    );
  }

  static String? _asString(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static bool? _asBool(dynamic value) {
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

class MqttTelemetryService {
  MqttTelemetryService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  static const String _fallbackBrokerUrl = String.fromEnvironment(
    'MQTT_BROKER_URL',
    defaultValue: '',
  );
  static const String _fallbackBrokerHost = String.fromEnvironment(
    'MQTT_BROKER_HOST',
    defaultValue: '',
  );
  static const int _fallbackBrokerPort = int.fromEnvironment(
    'MQTT_BROKER_PORT',
    defaultValue: 443,
  );
  static const String _fallbackWsPath = String.fromEnvironment(
    'MQTT_WS_PATH',
    defaultValue: '/mqtt',
  );
  static const bool _fallbackUseTls = bool.fromEnvironment(
    'MQTT_USE_TLS',
    defaultValue: true,
  );
  static const bool _fallbackUseWebSocket = bool.fromEnvironment(
    'MQTT_USE_WEBSOCKET',
    defaultValue: true,
  );
  static const String _fallbackUsername = String.fromEnvironment(
    'MQTT_USERNAME',
    defaultValue: '',
  );
  static const String _fallbackPassword = String.fromEnvironment(
    'MQTT_PASSWORD',
    defaultValue: '',
  );

  final FirebaseFunctions _functions;

  final StreamController<Map<String, dynamic>> _telemetryController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<MqttLiveStatus> _statusController =
      StreamController<MqttLiveStatus>.broadcast();

  mqtt.MqttClient? _client;
  StreamSubscription<List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>>>?
  _updatesSub;
  Timer? _retryTimer;

  String? _targetDeviceId;
  String? _targetLiveTopic;
  String? _targetStatusTopic;
  String? _endpoint;

  bool _disposed = false;
  bool _manualDisconnect = false;
  int _generation = 0;
  int _retryAttempt = 0;

  Stream<Map<String, dynamic>> get telemetryStream =>
      _telemetryController.stream;

  Stream<MqttLiveStatus> get statusStream => _statusController.stream;

  Future<void> connect({
    required String deviceId,
    required String liveTopic,
    String? statusTopic,
  }) async {
    if (_disposed) return;

    final normalizedLiveTopic = liveTopic.trim();
    final normalizedStatusTopic = statusTopic?.trim();

    if (normalizedLiveTopic.isEmpty) {
      throw ArgumentError.value(
        liveTopic,
        'liveTopic',
        'Live topic is required',
      );
    }

    final sameTarget =
        _targetDeviceId == deviceId &&
        _targetLiveTopic == normalizedLiveTopic &&
        _targetStatusTopic == normalizedStatusTopic;

    if (sameTarget &&
        _client?.connectionStatus?.state ==
            mqtt.MqttConnectionState.connected) {
      return;
    }

    _targetDeviceId = deviceId;
    _targetLiveTopic = normalizedLiveTopic;
    _targetStatusTopic = normalizedStatusTopic;

    _manualDisconnect = false;
    _retryAttempt = 0;
    _generation += 1;

    _retryTimer?.cancel();
    await _disconnectClient();

    _emitStatus(MqttLiveState.connecting, 'Requesting MQTT credentials...');
    await _connectNow(_generation);
  }

  Future<void> disconnect() async {
    _targetDeviceId = null;
    _targetLiveTopic = null;
    _targetStatusTopic = null;

    _generation += 1;
    _manualDisconnect = true;
    _retryAttempt = 0;

    _retryTimer?.cancel();
    await _disconnectClient();

    _emitStatus(MqttLiveState.disconnected, 'MQTT disconnected');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(disconnect());
    _telemetryController.close();
    _statusController.close();
  }

  Future<void> _connectNow(int generation) async {
    if (_disposed || generation != _generation) return;

    final deviceId = _targetDeviceId;
    final liveTopic = _targetLiveTopic;
    if (deviceId == null || liveTopic == null) return;

    try {
      final credentials = await _resolveCredentials(
        deviceId: deviceId,
        liveTopic: liveTopic,
        statusTopic: _targetStatusTopic,
      );
      if (_disposed || generation != _generation) return;

      final client = createPlatformMqttClient(
        MqttClientFactoryConfig(
          host: credentials.host,
          port: credentials.port,
          clientId: credentials.clientId,
          useTls: credentials.useTls,
          useWebSocket: credentials.useWebSocket,
          websocketPath: credentials.websocketPath,
        ),
      );

      client.keepAlivePeriod = 20;
      client.autoReconnect = false;
      client.logging(on: false);
      client.onDisconnected = _handleDisconnected;
      client.onConnected = _handleConnected;
      client.pongCallback = _handlePong;

      final connMessage = mqtt.MqttConnectMessage()
          .withClientIdentifier(credentials.clientId)
          .startClean()
          .authenticateAs(credentials.username, credentials.password);

      if ((credentials.statusTopic ?? '').isNotEmpty) {
        final willPayload = jsonEncode(<String, dynamic>{
          'deviceId': deviceId,
          'status': 'offline',
          'tsEpochMs': DateTime.now().millisecondsSinceEpoch,
        });

        connMessage
            .withWillTopic(credentials.statusTopic!)
            .withWillMessage(willPayload)
            .withWillQos(mqtt.MqttQos.atLeastOnce);
      }

      client.connectionMessage = connMessage;

      _endpoint = credentials.endpointLabel;
      _client = client;

      _emitStatus(
        MqttLiveState.connecting,
        'Connecting to ${credentials.endpointLabel}...',
      );

      await client.connect(credentials.username, credentials.password);

      if (_disposed || generation != _generation) {
        await _disconnectClient();
        return;
      }

      if (client.connectionStatus?.state !=
          mqtt.MqttConnectionState.connected) {
        throw StateError(
          'Connect failed: ${client.connectionStatus?.state} '
          '(${client.connectionStatus?.returnCode})',
        );
      }

      final subscribed = client.subscribe(
        credentials.liveTopic,
        mqtt.MqttQos.atLeastOnce,
      );

      if (subscribed == null) {
        throw StateError('Subscribe failed for topic ${credentials.liveTopic}');
      }

      _updatesSub = client.updates?.listen(
        _handleUpdates,
        onError: (Object error) {
          _scheduleRetry('MQTT stream error: $error', generation: generation);
        },
      );

      _retryAttempt = 0;
      _emitStatus(
        MqttLiveState.connected,
        'Subscribed to ${credentials.liveTopic}',
      );
    } catch (error) {
      _scheduleRetry('MQTT connect failed: $error', generation: generation);
    }
  }

  Future<void> _disconnectClient() async {
    await _updatesSub?.cancel();
    _updatesSub = null;

    final client = _client;
    _client = null;

    if (client != null) {
      try {
        client.disconnect();
      } catch (_) {
        // no-op
      }
    }
  }

  void _handleUpdates(List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> events) {
    for (final event in events) {
      final message = event.payload;
      if (message is! mqtt.MqttPublishMessage) continue;

      final payload = mqtt.MqttPublishPayload.bytesToStringAsString(
        message.payload.message,
      );

      dynamic decoded;
      try {
        decoded = jsonDecode(payload);
      } catch (_) {
        continue;
      }

      if (decoded is! Map) continue;

      try {
        final mapped = decoded.map<String, dynamic>((
          dynamic key,
          dynamic value,
        ) {
          return MapEntry(key.toString(), value);
        });

        final expectedDeviceId = _targetDeviceId;
        final payloadDeviceId = mapped['deviceId']?.toString().trim();
        if (expectedDeviceId != null &&
            payloadDeviceId != null &&
            payloadDeviceId.isNotEmpty &&
            payloadDeviceId != expectedDeviceId) {
          continue;
        }

        _telemetryController.add(mapped);
      } catch (_) {
        continue;
      }
    }
  }

  void _handleConnected() {
    _retryAttempt = 0;
    _emitStatus(MqttLiveState.connected, 'MQTT connected');
  }

  void _handleDisconnected() {
    if (_disposed || _manualDisconnect || _targetLiveTopic == null) return;
    _scheduleRetry('MQTT disconnected', generation: _generation);
  }

  void _handlePong() {
    if (_disposed) return;
    if (_client?.connectionStatus?.state ==
        mqtt.MqttConnectionState.connected) {
      _emitStatus(MqttLiveState.connected, 'MQTT heartbeat OK');
    }
  }

  void _scheduleRetry(String message, {required int generation}) {
    if (_disposed || _manualDisconnect || generation != _generation) return;

    _retryAttempt += 1;
    final cappedAttempt = min(_retryAttempt, 5);
    final delay = Duration(seconds: 2 + cappedAttempt * 2);

    _emitStatus(
      MqttLiveState.retrying,
      '$message. Retrying in ${delay.inSeconds}s',
    );

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_disposed || _manualDisconnect || generation != _generation) return;
      _connectNow(generation);
    });
  }

  Future<_MqttCredentialBundle> _resolveCredentials({
    required String deviceId,
    required String liveTopic,
    String? statusTopic,
  }) async {
    try {
      final callable = _functions.httpsCallable('issueMqttCredentials');
      final result = await callable.call(<String, dynamic>{
        'deviceId': deviceId,
        'liveTopic': liveTopic,
        'statusTopic': statusTopic,
      });

      final payload = _asMap(result.data);
      return _MqttCredentialBundle.fromMap(
        payload,
        fallbackDeviceId: deviceId,
        fallbackLiveTopic: liveTopic,
        fallbackStatusTopic: statusTopic,
      );
    } on FirebaseFunctionsException {
      final fallback = _fallbackCredentials(
        deviceId: deviceId,
        liveTopic: liveTopic,
        statusTopic: statusTopic,
      );
      if (fallback != null) return fallback;
      rethrow;
    } catch (_) {
      final fallback = _fallbackCredentials(
        deviceId: deviceId,
        liveTopic: liveTopic,
        statusTopic: statusTopic,
      );
      if (fallback != null) return fallback;
      rethrow;
    }
  }

  _MqttCredentialBundle? _fallbackCredentials({
    required String deviceId,
    required String liveTopic,
    String? statusTopic,
  }) {
    final hasUrl = _fallbackBrokerUrl.trim().isNotEmpty;
    final hasHost = _fallbackBrokerHost.trim().isNotEmpty;
    final hasAuth =
        _fallbackUsername.trim().isNotEmpty &&
        _fallbackPassword.trim().isNotEmpty;

    if ((!hasUrl && !hasHost) || !hasAuth) return null;

    return _MqttCredentialBundle.fromMap(
      <String, dynamic>{
        'brokerUrl': hasUrl ? _fallbackBrokerUrl : null,
        'brokerHost': hasHost ? _fallbackBrokerHost : null,
        'brokerPort': _fallbackBrokerPort,
        'wsPath': _fallbackWsPath,
        'useTls': _fallbackUseTls,
        'useWebSocket': _fallbackUseWebSocket,
        'username': _fallbackUsername,
        'password': _fallbackPassword,
        'clientId': 'app-$deviceId-${DateTime.now().millisecondsSinceEpoch}',
        'liveTopic': liveTopic,
        'statusTopic': statusTopic,
      },
      fallbackDeviceId: deviceId,
      fallbackLiveTopic: liveTopic,
      fallbackStatusTopic: statusTopic,
    );
  }

  void _emitStatus(MqttLiveState state, String message) {
    if (_disposed) return;
    _statusController.add(
      MqttLiveStatus(state: state, message: message, endpoint: _endpoint),
    );
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map<String, dynamic>((dynamic key, dynamic value) {
        return MapEntry(key.toString(), value);
      });
    }

    throw StateError('Expected map response from issueMqttCredentials');
  }
}
