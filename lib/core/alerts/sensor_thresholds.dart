enum SensorMetricState { low, high, normal, unknown }

const double kDefaultTemperatureMinC = 22.0;
const double kDefaultTemperatureMaxC = 28.0;
const double kDefaultPhMin = 6.0;
const double kDefaultPhMax = 7.2;
const double kDefaultWaterLevelLowPct = 30.0;
const double kDefaultTdsMinPpm = 800.0;
const double kDefaultTdsMaxPpm = 1200.0;

const bool kDefaultLowTdsAutoDoseEnabled = false;
const int kDefaultPumpMaxRunSec = 300;
const String kDefaultStopTarget = 'tds_max';
const int kDefaultInAppReminderIntervalSec = 15;

class SensorThresholdValues {
  const SensorThresholdValues({
    required this.temperatureMinC,
    required this.temperatureMaxC,
    required this.phMin,
    required this.phMax,
    required this.waterLevelLowPct,
    required this.tdsMinPpm,
    required this.tdsMaxPpm,
  });

  final double temperatureMinC;
  final double temperatureMaxC;
  final double phMin;
  final double phMax;
  final double waterLevelLowPct;
  final double tdsMinPpm;
  final double tdsMaxPpm;

  static const defaults = SensorThresholdValues(
    temperatureMinC: kDefaultTemperatureMinC,
    temperatureMaxC: kDefaultTemperatureMaxC,
    phMin: kDefaultPhMin,
    phMax: kDefaultPhMax,
    waterLevelLowPct: kDefaultWaterLevelLowPct,
    tdsMinPpm: kDefaultTdsMinPpm,
    tdsMaxPpm: kDefaultTdsMaxPpm,
  );

  Map<String, dynamic> toMap() {
    return {
      'temperatureMinC': temperatureMinC,
      'temperatureMaxC': temperatureMaxC,
      'phMin': phMin,
      'phMax': phMax,
      'waterLevelLowPct': waterLevelLowPct,
      'tdsMinPpm': tdsMinPpm,
      'tdsMaxPpm': tdsMaxPpm,
    };
  }

  factory SensorThresholdValues.fromMap(Map<String, dynamic>? data) {
    final fallback = defaults;
    return SensorThresholdValues(
      temperatureMinC: _asDouble(
        data?['temperatureMinC'],
        fallback.temperatureMinC,
      ),
      temperatureMaxC: _asDouble(
        data?['temperatureMaxC'],
        fallback.temperatureMaxC,
      ),
      phMin: _asDouble(data?['phMin'], fallback.phMin),
      phMax: _asDouble(data?['phMax'], fallback.phMax),
      waterLevelLowPct: _asDouble(
        data?['waterLevelLowPct'],
        fallback.waterLevelLowPct,
      ),
      tdsMinPpm: _asDouble(data?['tdsMinPpm'], fallback.tdsMinPpm),
      tdsMaxPpm: _asDouble(data?['tdsMaxPpm'], fallback.tdsMaxPpm),
    );
  }
}

class SensorAutomationSettings {
  const SensorAutomationSettings({
    required this.lowTdsAutoDoseEnabled,
    required this.pumpMaxRunSec,
    required this.stopTarget,
  });

  final bool lowTdsAutoDoseEnabled;
  final int pumpMaxRunSec;
  final String stopTarget;

  static const defaults = SensorAutomationSettings(
    lowTdsAutoDoseEnabled: kDefaultLowTdsAutoDoseEnabled,
    pumpMaxRunSec: kDefaultPumpMaxRunSec,
    stopTarget: kDefaultStopTarget,
  );

  Map<String, dynamic> toMap() {
    return {
      'lowTdsAutoDoseEnabled': lowTdsAutoDoseEnabled,
      'pumpMaxRunSec': pumpMaxRunSec,
      'stopTarget': stopTarget,
    };
  }

  factory SensorAutomationSettings.fromMap(Map<String, dynamic>? data) {
    return SensorAutomationSettings(
      lowTdsAutoDoseEnabled: _asBool(
        data?['lowTdsAutoDoseEnabled'],
        defaults.lowTdsAutoDoseEnabled,
      ),
      pumpMaxRunSec: _asInt(data?['pumpMaxRunSec'], defaults.pumpMaxRunSec),
      stopTarget: (data?['stopTarget'] ?? defaults.stopTarget).toString(),
    );
  }
}

class SensorReminderSettings {
  const SensorReminderSettings({required this.inAppIntervalSec});

  final int inAppIntervalSec;

  static const defaults = SensorReminderSettings(
    inAppIntervalSec: kDefaultInAppReminderIntervalSec,
  );

  Map<String, dynamic> toMap() {
    return {'inAppIntervalSec': inAppIntervalSec};
  }

  factory SensorReminderSettings.fromMap(Map<String, dynamic>? data) {
    return SensorReminderSettings(
      inAppIntervalSec: _asInt(
        data?['inAppIntervalSec'],
        defaults.inAppIntervalSec,
      ),
    );
  }
}

class SensorGlobalSettings {
  const SensorGlobalSettings({
    required this.thresholds,
    required this.automation,
    required this.reminders,
  });

  final SensorThresholdValues thresholds;
  final SensorAutomationSettings automation;
  final SensorReminderSettings reminders;

  static const defaults = SensorGlobalSettings(
    thresholds: SensorThresholdValues.defaults,
    automation: SensorAutomationSettings.defaults,
    reminders: SensorReminderSettings.defaults,
  );

  Map<String, dynamic> toMap() {
    return {
      'thresholds': thresholds.toMap(),
      'automation': automation.toMap(),
      'reminders': reminders.toMap(),
    };
  }

  factory SensorGlobalSettings.fromMap(Map<String, dynamic>? data) {
    final thresholdMap = _asMap(data?['thresholds']);
    final automationMap = _asMap(data?['automation']);
    final remindersMap = _asMap(data?['reminders']);
    return SensorGlobalSettings(
      thresholds: SensorThresholdValues.fromMap(thresholdMap),
      automation: SensorAutomationSettings.fromMap(automationMap),
      reminders: SensorReminderSettings.fromMap(remindersMap),
    );
  }
}

class SensorDeviceOverrideSettings {
  const SensorDeviceOverrideSettings({
    required this.overrideEnabled,
    required this.thresholds,
    required this.lowTdsAutoDoseEnabled,
  });

  final bool overrideEnabled;
  final SensorThresholdValues thresholds;
  final bool lowTdsAutoDoseEnabled;

  static const defaults = SensorDeviceOverrideSettings(
    overrideEnabled: false,
    thresholds: SensorThresholdValues.defaults,
    lowTdsAutoDoseEnabled: kDefaultLowTdsAutoDoseEnabled,
  );

  Map<String, dynamic> toMap() {
    return {
      'overrideEnabled': overrideEnabled,
      'thresholds': thresholds.toMap(),
      'automation': {'lowTdsAutoDoseEnabled': lowTdsAutoDoseEnabled},
    };
  }

  factory SensorDeviceOverrideSettings.fromMap(Map<String, dynamic>? data) {
    final thresholdsMap = _asMap(data?['thresholds']);
    final automationMap = _asMap(data?['automation']);
    return SensorDeviceOverrideSettings(
      overrideEnabled: _asBool(
        data?['overrideEnabled'],
        defaults.overrideEnabled,
      ),
      thresholds: SensorThresholdValues.fromMap(thresholdsMap),
      lowTdsAutoDoseEnabled: _asBool(
        automationMap?['lowTdsAutoDoseEnabled'],
        defaults.lowTdsAutoDoseEnabled,
      ),
    );
  }
}

class SensorMetricEvaluation {
  const SensorMetricEvaluation({
    required this.temperature,
    required this.ph,
    required this.waterLevel,
    required this.tds,
    required this.activeMetrics,
  });

  final SensorMetricState temperature;
  final SensorMetricState ph;
  final SensorMetricState waterLevel;
  final SensorMetricState tds;
  final List<String> activeMetrics;
}

SensorGlobalSettings resolveEffectiveSettings({
  required SensorGlobalSettings globalSettings,
  SensorDeviceOverrideSettings? deviceOverride,
}) {
  final override = deviceOverride;
  if (override == null || !override.overrideEnabled) return globalSettings;
  return SensorGlobalSettings(
    thresholds: override.thresholds,
    automation: SensorAutomationSettings(
      lowTdsAutoDoseEnabled: override.lowTdsAutoDoseEnabled,
      pumpMaxRunSec: globalSettings.automation.pumpMaxRunSec,
      stopTarget: globalSettings.automation.stopTarget,
    ),
    reminders: globalSettings.reminders,
  );
}

Map<String, String> validateThresholdValues(SensorThresholdValues values) {
  final errors = <String, String>{};
  if (values.temperatureMinC >= values.temperatureMaxC) {
    errors['temperatureRange'] = 'Temperature min must be lower than max.';
  }
  if (values.phMin < 0 || values.phMax > 14) {
    errors['phBounds'] = 'pH range must stay within 0.0 to 14.0.';
  }
  if (values.phMin >= values.phMax) {
    errors['phRange'] = 'pH min must be lower than max.';
  }
  if (values.waterLevelLowPct < 0 || values.waterLevelLowPct > 100) {
    errors['waterLevelLowPct'] = 'Water level low must be between 0 and 100.';
  }
  if (values.tdsMinPpm < 0 || values.tdsMaxPpm < 0) {
    errors['tdsNonNegative'] = 'TDS values must be non-negative.';
  }
  if (values.tdsMinPpm >= values.tdsMaxPpm) {
    errors['tdsRange'] = 'TDS min must be lower than max.';
  }
  return errors;
}

SensorMetricEvaluation evaluateMetricStates({
  required SensorThresholdValues thresholds,
  required double? temperatureC,
  required double? ph,
  required double? waterLevelPct,
  required double? tdsPpm,
}) {
  final temperatureState = _evalRange(
    value: temperatureC,
    min: thresholds.temperatureMinC,
    max: thresholds.temperatureMaxC,
  );
  final phState = _evalRange(
    value: ph,
    min: thresholds.phMin,
    max: thresholds.phMax,
  );
  final waterLevelState = _evalLowOnly(
    value: waterLevelPct,
    lowThreshold: thresholds.waterLevelLowPct,
  );
  final tdsState = _evalRange(
    value: tdsPpm,
    min: thresholds.tdsMinPpm,
    max: thresholds.tdsMaxPpm,
  );

  final active = <String>[];
  if (temperatureState == SensorMetricState.low ||
      temperatureState == SensorMetricState.high) {
    active.add('temperature');
  }
  if (phState == SensorMetricState.low || phState == SensorMetricState.high) {
    active.add('ph');
  }
  if (waterLevelState == SensorMetricState.low) {
    active.add('waterLevel');
  }
  if (tdsState == SensorMetricState.low || tdsState == SensorMetricState.high) {
    active.add('tds');
  }

  return SensorMetricEvaluation(
    temperature: temperatureState,
    ph: phState,
    waterLevel: waterLevelState,
    tds: tdsState,
    activeMetrics: active,
  );
}

SensorMetricState _evalRange({
  required double? value,
  required double min,
  required double max,
}) {
  if (value == null) return SensorMetricState.unknown;
  if (value < min) return SensorMetricState.low;
  if (value > max) return SensorMetricState.high;
  return SensorMetricState.normal;
}

SensorMetricState _evalLowOnly({
  required double? value,
  required double lowThreshold,
}) {
  if (value == null) return SensorMetricState.unknown;
  if (value < lowThreshold) return SensorMetricState.low;
  return SensorMetricState.normal;
}

double _asDouble(dynamic value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int _asInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

bool _asBool(dynamic value, bool fallback) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return fallback;
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return null;
}
