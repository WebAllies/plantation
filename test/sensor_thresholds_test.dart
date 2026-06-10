import 'package:flutter_test/flutter_test.dart';
import 'package:iot_aqua_app/core/alerts/sensor_thresholds.dart';

void main() {
  group('sensor thresholds validation', () {
    test('defaults are valid', () {
      final errors = validateThresholdValues(SensorThresholdValues.defaults);
      expect(errors, isEmpty);
    });

    test('invalid ranges produce errors', () {
      const values = SensorThresholdValues(
        temperatureMinC: 29,
        temperatureMaxC: 20,
        phMin: 8.2,
        phMax: 7.8,
        waterLevelLowPct: 120,
        tdsMinPpm: 1200,
        tdsMaxPpm: 1000,
      );

      final errors = validateThresholdValues(values);
      expect(errors.containsKey('temperatureRange'), isTrue);
      expect(errors.containsKey('phRange'), isTrue);
      expect(errors.containsKey('waterLevelLowPct'), isTrue);
      expect(errors.containsKey('tdsRange'), isTrue);
    });
  });

  group('effective settings', () {
    test(
      'override settings replace thresholds and override automation toggle',
      () {
        const global = SensorGlobalSettings(
          thresholds: SensorThresholdValues(
            temperatureMinC: 22,
            temperatureMaxC: 28,
            phMin: 6,
            phMax: 7.2,
            waterLevelLowPct: 30,
            tdsMinPpm: 800,
            tdsMaxPpm: 1200,
          ),
          automation: SensorAutomationSettings(
            lowTdsAutoDoseEnabled: false,
            pumpMaxRunSec: 300,
            stopTarget: 'tds_max',
          ),
          reminders: SensorReminderSettings(inAppIntervalSec: 15),
        );

        const override = SensorDeviceOverrideSettings(
          overrideEnabled: true,
          thresholds: SensorThresholdValues(
            temperatureMinC: 20,
            temperatureMaxC: 24,
            phMin: 5.8,
            phMax: 6.8,
            waterLevelLowPct: 35,
            tdsMinPpm: 900,
            tdsMaxPpm: 1300,
          ),
          lowTdsAutoDoseEnabled: true,
        );

        final effective = resolveEffectiveSettings(
          globalSettings: global,
          deviceOverride: override,
        );

        expect(effective.thresholds.temperatureMinC, 20);
        expect(effective.thresholds.tdsMaxPpm, 1300);
        expect(effective.automation.lowTdsAutoDoseEnabled, isTrue);
        expect(effective.automation.pumpMaxRunSec, 300);
      },
    );
  });

  group('metric evaluation', () {
    test('evaluation reports expected metric states', () {
      const thresholds = SensorThresholdValues(
        temperatureMinC: 22,
        temperatureMaxC: 28,
        phMin: 6,
        phMax: 7.2,
        waterLevelLowPct: 30,
        tdsMinPpm: 800,
        tdsMaxPpm: 1200,
      );

      final result = evaluateMetricStates(
        thresholds: thresholds,
        temperatureC: 21.5,
        ph: 7.6,
        waterLevelPct: 25,
        tdsPpm: 900,
      );

      expect(result.temperature, SensorMetricState.low);
      expect(result.ph, SensorMetricState.high);
      expect(result.waterLevel, SensorMetricState.low);
      expect(result.tds, SensorMetricState.normal);
      expect(
        result.activeMetrics,
        equals(<String>['temperature', 'ph', 'waterLevel']),
      );
    });
  });
}
