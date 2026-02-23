import 'package:flutter_test/flutter_test.dart';
import 'package:iot_aqua_app/ai/tflite_service.dart';

void main() {
  group('ModelConfig', () {
    test('parses class thresholds and binary map from json', () {
      const json = '''
      {
        "modelVersion": "lettuce_v2",
        "inputSize": 224,
        "normalization": "[-1,1]",
        "classThresholds": {
          "healthy": 0.62,
          "tipburn": 0.58
        },
        "binaryMap": {
          "healthy": "Healthy",
          "tipburn": "Unhealthy"
        }
      }
      ''';

      final config = ModelConfig.fromJsonString(json);

      expect(config.modelVersion, 'lettuce_v2');
      expect(config.inputSize, 224);
      expect(config.thresholdForClass('healthy'), 0.62);
      expect(config.thresholdForClass('tipburn'), 0.58);
      expect(config.binaryLabelForClass('healthy'), 'Healthy');
      expect(config.binaryLabelForClass('tipburn'), 'Unhealthy');
    });

    test('uses safe defaults for unknown classes', () {
      final config = ModelConfig.defaults();

      expect(config.thresholdForClass('unknown_class'), 0.60);
      expect(config.binaryLabelForClass('unknown_class'), 'Unhealthy');
      expect(config.binaryLabelForClass('healthy'), 'Healthy');
    });
  });
}
