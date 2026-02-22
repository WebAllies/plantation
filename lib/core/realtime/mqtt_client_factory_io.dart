import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'mqtt_client_factory.dart';

MqttClient createPlatformMqttClient(MqttClientFactoryConfig config) {
  final normalizedPath = config.websocketPath.isEmpty
      ? '/mqtt'
      : (config.websocketPath.startsWith('/')
            ? config.websocketPath
            : '/${config.websocketPath}');

  final client = config.useWebSocket
      ? MqttServerClient(
          '${config.useTls ? 'wss' : 'ws'}://${config.host}$normalizedPath',
          config.clientId,
        )
      : MqttServerClient.withPort(
          config.host,
          config.clientId,
          config.port,
        );

  // For websockets, TLS is encoded in ws:// vs wss:// URL.
  // `secure=true` is only for raw TCP TLS (mqtts).
  client.secure = !config.useWebSocket && config.useTls;
  client.autoReconnect = false;
  client.keepAlivePeriod = 20;
  client.logging(on: false);
  client.port = config.port;

  if (config.useWebSocket) {
    client.useWebSocket = true;
  }

  return client;
}
