import 'package:mqtt_client/mqtt_client.dart';

import 'mqtt_client_factory_io.dart'
    if (dart.library.html) 'mqtt_client_factory_web.dart' as platform;

class MqttClientFactoryConfig {
  const MqttClientFactoryConfig({
    required this.host,
    required this.port,
    required this.clientId,
    required this.useTls,
    required this.useWebSocket,
    required this.websocketPath,
  });

  final String host;
  final int port;
  final String clientId;
  final bool useTls;
  final bool useWebSocket;
  final String websocketPath;
}

MqttClient createPlatformMqttClient(MqttClientFactoryConfig config) {
  return platform.createPlatformMqttClient(config);
}
