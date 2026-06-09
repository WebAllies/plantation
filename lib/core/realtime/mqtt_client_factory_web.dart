import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

import 'mqtt_client_factory.dart';

MqttClient createPlatformMqttClient(MqttClientFactoryConfig config) {
  final normalizedPath = config.websocketPath.isEmpty
      ? '/mqtt'
      : (config.websocketPath.startsWith('/')
            ? config.websocketPath
            : '/${config.websocketPath}');

  final scheme = config.useTls ? 'wss' : 'ws';
  final uri = '$scheme://${config.host}:${config.port}$normalizedPath';

  final client = MqttBrowserClient(uri, config.clientId);
  client.autoReconnect = false;
  client.keepAlivePeriod = 20;
  client.logging(on: false);

  return client;
}
