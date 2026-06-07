import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:iot_aqua_app/core/local/local_backend_config.dart';

class LocalBackendCommandService {
  LocalBackendCommandService({FirebaseAuth? auth, http.Client? client})
    : _auth = auth ?? FirebaseAuth.instance,
      _client = client ?? http.Client();

  final FirebaseAuth _auth;
  final http.Client _client;

  Future<bool> sendCommand({
    required String deviceId,
    required String type,
    bool? targetState,
    int? durationSec,
  }) async {
    final uri = LocalBackendConfig.apiUri('/api/devices/$deviceId/commands');
    if (uri == null) return false;

    final payload = <String, dynamic>{'type': type};
    if (targetState != null) payload['targetState'] = targetState;
    if (durationSec != null) {
      payload['durationSec'] = durationSec;
      payload['durationMs'] = durationSec * 1000;
    }

    return _sendJson('POST', uri, payload);
  }

  Future<bool> patchDevice({
    required String deviceId,
    String? controlMode,
    Map<String, dynamic>? automation,
  }) async {
    final uri = LocalBackendConfig.apiUri('/api/devices/$deviceId');
    if (uri == null) return false;

    final payload = <String, dynamic>{};
    if (controlMode != null) payload['controlMode'] = controlMode;
    if (automation != null) payload['automation'] = automation;

    return _sendJson('PATCH', uri, payload);
  }

  Future<bool> _sendJson(
    String method,
    Uri uri,
    Map<String, dynamic> payload,
  ) async {
    try {
      final headers = <String, String>{'content-type': 'application/json'};

      final token = await _auth.currentUser?.getIdToken();
      if (token != null && token.isNotEmpty) {
        headers['authorization'] = 'Bearer $token';
      }

      final body = jsonEncode(payload);
      final response = method == 'PATCH'
          ? await _client
                .patch(uri, headers: headers, body: body)
                .timeout(const Duration(seconds: 4))
          : await _client
                .post(uri, headers: headers, body: body)
                .timeout(const Duration(seconds: 4));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
