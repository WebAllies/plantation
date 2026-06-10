import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:iot_aqua_app/core/local/local_backend_config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Sends device commands over a single persistent WebSocket to the local
/// backend. Reusing the already-open connection avoids the per-press HTTP
/// connection/handshake cost, so a button press reaches the ESP32 faster.
///
/// This is best-effort: [sendCommand] returns `false` when the socket is not
/// connected so the caller can fall back to the HTTP command path.
class LocalBackendCommandSocket {
  LocalBackendCommandSocket._({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  static final LocalBackendCommandSocket instance =
      LocalBackendCommandSocket._();

  final FirebaseAuth _auth;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Future<void>? _connecting;
  String? _deviceId;
  bool _connected = false;
  int _seq = 0;

  /// How long to wait for the server's `command_result` before giving up and
  /// letting the caller fall back to HTTP. Also guards against a backend that
  /// predates WebSocket command support (it simply never acks).
  static const Duration _ackTimeout = Duration(milliseconds: 1200);
  final Map<String, Completer<bool>> _pendingAcks = <String, Completer<bool>>{};
  final StreamController<Map<String, dynamic>> _commandEvents =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Per-connection capability: null = unknown (probe), true = backend acks WS
  /// commands, false = it doesn't (skip WS, go straight to HTTP). Reset on each
  /// reconnect so a freshly deployed backend is picked up automatically.
  bool? _wsCommandsSupported;

  bool get isConnected => _connected;
  Stream<Map<String, dynamic>> get commandEvents => _commandEvents.stream;

  /// Opens (or reuses) a connection scoped to [deviceId]. Safe to call often —
  /// it no-ops when already connected to the same device.
  Future<void> ensureConnected(String deviceId) async {
    if (!LocalBackendConfig.hasWebSocket) return;
    if (_connected && _deviceId == deviceId) return;
    if (_connecting != null && _deviceId == deviceId) return _connecting;

    if (_deviceId != deviceId) {
      await _close();
    }
    _deviceId = deviceId;
    _connecting = _connect(deviceId);
    try {
      await _connecting;
    } finally {
      _connecting = null;
    }
  }

  Future<void> _connect(String deviceId) async {
    final raw = LocalBackendConfig.websocketUrlForDevice(deviceId);
    if (raw == null) return;
    final parsed = Uri.tryParse(raw);
    if (parsed == null) return;
    var uri = parsed;

    try {
      final token = await _auth.currentUser?.getIdToken();
      if (token != null && token.isNotEmpty) {
        uri = uri.replace(
          queryParameters: {...uri.queryParameters, 'token': token},
        );
      }
    } catch (_) {
      // Connect unauthenticated; backend allows it while auth is not required.
    }

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _sub = channel.stream.listen(
        _onMessage,
        onError: (_) => _markDisconnected(),
        onDone: _markDisconnected,
        cancelOnError: false,
      );
      await channel.ready;
      _connected = true;
    } catch (_) {
      _markDisconnected();
    }
  }

  /// Sends a command frame. Returns `true` only when it was written to a live
  /// socket; `false` tells the caller to use the HTTP fallback.
  Future<bool> sendCommand({
    required String deviceId,
    required String type,
    bool? targetState,
    int? durationSec,
  }) async {
    await ensureConnected(deviceId);
    final channel = _channel;
    if (!_connected || channel == null) return false;
    // This backend connection already proved it ignores WS commands; don't
    // pay the ack-timeout again — let the caller use HTTP.
    if (_wsCommandsSupported == false) return false;

    final payload = <String, dynamic>{'type': type};
    if (targetState != null) payload['targetState'] = targetState;
    if (durationSec != null) {
      payload['durationSec'] = durationSec;
      payload['durationMs'] = durationSec * 1000;
    }

    final requestId = 'app-${++_seq}';
    final completer = Completer<bool>();
    _pendingAcks[requestId] = completer;

    try {
      channel.sink.add(
        jsonEncode({
          'type': 'command',
          'deviceId': deviceId,
          'requestId': requestId,
          'payload': payload,
        }),
      );
    } catch (_) {
      _pendingAcks.remove(requestId);
      _markDisconnected();
      return false;
    }

    // Wait for the server to confirm. No ack (timeout) means either the server
    // is unreachable or too old to support WS commands -> use HTTP fallback.
    try {
      return await completer.future.timeout(_ackTimeout);
    } catch (_) {
      // No ack in time: assume this backend lacks WS command support (only if
      // we haven't already seen a successful ack on this connection).
      _wsCommandsSupported ??= false;
      return false;
    } finally {
      _pendingAcks.remove(requestId);
    }
  }

  void _onMessage(dynamic event) {
    if (event is! String) return;
    dynamic decoded;
    try {
      decoded = jsonDecode(event);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;

    if (decoded['type'] == 'command') {
      final payload = decoded['payload'];
      if (payload is Map) {
        _commandEvents.add(Map<String, dynamic>.from(payload));
      }
      return;
    }

    if (decoded['type'] != 'command_result') return;

    // Receiving any command_result proves the backend supports WS commands.
    _wsCommandsSupported = true;

    final requestId = decoded['requestId']?.toString();
    if (requestId == null) return;
    final completer = _pendingAcks.remove(requestId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(decoded['ok'] == true);
    }
  }

  void _markDisconnected() {
    _connected = false;
    for (final completer in _pendingAcks.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _pendingAcks.clear();
  }

  Future<void> _close() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _connected = false;
    _wsCommandsSupported = null;
    _markDisconnected();
  }
}
