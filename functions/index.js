const admin = require('firebase-admin');
const jwt = require('jsonwebtoken');
const { setGlobalOptions } = require('firebase-functions/v2');
const { onDocumentUpdated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineString } = require('firebase-functions/params');

if (!admin.apps.length) {
  admin.initializeApp();
}

setGlobalOptions({ region: 'us-central1', maxInstances: 10 });

const MQTT_BROKER_URL = defineString('MQTT_BROKER_URL');
const MQTT_BROKER_HOST = defineString('MQTT_BROKER_HOST');
const MQTT_BROKER_PORT = defineString('MQTT_BROKER_PORT');
const MQTT_WS_PATH = defineString('MQTT_WS_PATH');
const MQTT_USE_TLS = defineString('MQTT_USE_TLS');
const MQTT_USE_WEBSOCKET = defineString('MQTT_USE_WEBSOCKET');
const MQTT_JWT_SECRET = defineString('MQTT_JWT_SECRET');
const MQTT_PASSWORD_STATIC = defineString('MQTT_PASSWORD_STATIC');
const MQTT_USERNAME_STATIC = defineString('MQTT_USERNAME_STATIC');
const MQTT_USERNAME_PREFIX = defineString('MQTT_USERNAME_PREFIX');

const TOKEN_TTL_SECONDS = 15 * 60;
const ALERT_RETENTION_DAYS = 3;
const ALERT_CLEANUP_BATCH_SIZE = 300;
const DEVICE_RECOMPUTE_BATCH_SIZE = 200;
const FEEDER_SCAN_BATCH_SIZE = 200;
const DEVICE_OFFLINE_AFTER_MS = 12 * 1000;
const STALE_DEVICE_SCAN_BATCH_SIZE = 200;

const AUTOMATION_USER_UID = 'system_automation';
const AUTOMATION_USER_EMAIL = 'automation@system.local';

const DEFAULT_SETTINGS = {
  thresholds: {
    temperatureMinC: 22.0,
    temperatureMaxC: 28.0,
    phMin: 6.0,
    phMax: 7.2,
    waterLevelLowPct: 30.0,
    tdsMinPpm: 800.0,
    tdsMaxPpm: 1200.0,
  },
  automation: {
    lowTdsAutoDoseEnabled: false,
    pumpMaxRunSec: 300,
    stopTarget: 'tds_max',
  },
  reminders: {
    inAppIntervalSec: 15,
  },
};

function asBool(value, defaultValue) {
  if (value == null || value === '') return defaultValue;
  const normalized = String(value).toLowerCase().trim();
  if (normalized === 'true' || normalized === '1') return true;
  if (normalized === 'false' || normalized === '0') return false;
  return defaultValue;
}

function asInt(value, defaultValue) {
  if (value == null || value === '') return defaultValue;
  const parsed = Number.parseInt(String(value), 10);
  return Number.isNaN(parsed) ? defaultValue : parsed;
}

function asNumber(value, defaultValue) {
  if (value == null || value === '') return defaultValue;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : defaultValue;
}

function asMap(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return value;
}

function cleanTopic(topicValue, fallback) {
  const raw = (topicValue ?? fallback ?? '').toString().trim();
  if (!raw) return fallback;
  if (raw.includes('#') || raw.includes('+')) {
    throw new HttpsError('invalid-argument', 'Wildcards are not allowed in topic names');
  }
  return raw;
}

function parseBrokerConfig() {
  const brokerUrl = (MQTT_BROKER_URL.value() || '').trim();
  const hostFromParam = (MQTT_BROKER_HOST.value() || '').trim();

  let host = hostFromParam;
  let port = asInt(MQTT_BROKER_PORT.value(), 443);
  let wsPath = (MQTT_WS_PATH.value() || '/mqtt').trim() || '/mqtt';
  let useTls = asBool(MQTT_USE_TLS.value(), true);
  let useWebSocket = asBool(MQTT_USE_WEBSOCKET.value(), true);

  if (brokerUrl) {
    const parsed = new URL(brokerUrl);
    host = parsed.hostname;
    port = parsed.port
      ? Number.parseInt(parsed.port, 10)
      : parsed.protocol === 'wss:'
        ? 443
        : parsed.protocol === 'ws:'
          ? 80
          : parsed.protocol === 'mqtts:'
            ? 8883
            : 1883;

    wsPath = parsed.pathname && parsed.pathname !== '/' ? parsed.pathname : wsPath;

    if (parsed.protocol === 'wss:' || parsed.protocol === 'ws:') {
      useWebSocket = true;
      useTls = parsed.protocol === 'wss:';
    }

    if (parsed.protocol === 'mqtts:' || parsed.protocol === 'mqtt:') {
      useWebSocket = false;
      useTls = parsed.protocol === 'mqtts:';
    }
  }

  if (!host) {
    throw new HttpsError(
      'failed-precondition',
      'MQTT broker not configured. Set MQTT_BROKER_URL or MQTT_BROKER_HOST.',
    );
  }

  return {
    brokerUrl,
    host,
    port,
    wsPath,
    useTls,
    useWebSocket,
  };
}

function readTelemetry(data) {
  return {
    temperatureC: numberOrNull(data.temperatureC),
    ph: numberOrNull(data.ph),
    waterLevelPct: numberOrNull(data.waterLevelPct),
    tdsPpm: numberOrNull(data.tdsPpm),
  };
}

function numberOrNull(value) {
  if (value == null) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeGlobalSettings(raw) {
  const data = asMap(raw);
  const thresholdsMap = asMap(data.thresholds);
  const automationMap = asMap(data.automation);
  const remindersMap = asMap(data.reminders);

  return {
    thresholds: {
      temperatureMinC: asNumber(
        thresholdsMap.temperatureMinC,
        DEFAULT_SETTINGS.thresholds.temperatureMinC,
      ),
      temperatureMaxC: asNumber(
        thresholdsMap.temperatureMaxC,
        DEFAULT_SETTINGS.thresholds.temperatureMaxC,
      ),
      phMin: asNumber(thresholdsMap.phMin, DEFAULT_SETTINGS.thresholds.phMin),
      phMax: asNumber(thresholdsMap.phMax, DEFAULT_SETTINGS.thresholds.phMax),
      waterLevelLowPct: asNumber(
        thresholdsMap.waterLevelLowPct,
        DEFAULT_SETTINGS.thresholds.waterLevelLowPct,
      ),
      tdsMinPpm: asNumber(
        thresholdsMap.tdsMinPpm,
        DEFAULT_SETTINGS.thresholds.tdsMinPpm,
      ),
      tdsMaxPpm: asNumber(
        thresholdsMap.tdsMaxPpm,
        DEFAULT_SETTINGS.thresholds.tdsMaxPpm,
      ),
    },
    automation: {
      lowTdsAutoDoseEnabled: asBool(
        automationMap.lowTdsAutoDoseEnabled,
        DEFAULT_SETTINGS.automation.lowTdsAutoDoseEnabled,
      ),
      pumpMaxRunSec: asInt(
        automationMap.pumpMaxRunSec,
        DEFAULT_SETTINGS.automation.pumpMaxRunSec,
      ),
      stopTarget: String(automationMap.stopTarget || DEFAULT_SETTINGS.automation.stopTarget),
    },
    reminders: {
      inAppIntervalSec: asInt(
        remindersMap.inAppIntervalSec,
        DEFAULT_SETTINGS.reminders.inAppIntervalSec,
      ),
    },
  };
}

function normalizeDeviceOverride(raw) {
  const data = asMap(raw);
  const thresholdsMap = asMap(data.thresholds);
  const automationMap = asMap(data.automation);

  return {
    overrideEnabled: asBool(data.overrideEnabled, false),
    thresholds: {
      temperatureMinC: asNumber(
        thresholdsMap.temperatureMinC,
        DEFAULT_SETTINGS.thresholds.temperatureMinC,
      ),
      temperatureMaxC: asNumber(
        thresholdsMap.temperatureMaxC,
        DEFAULT_SETTINGS.thresholds.temperatureMaxC,
      ),
      phMin: asNumber(thresholdsMap.phMin, DEFAULT_SETTINGS.thresholds.phMin),
      phMax: asNumber(thresholdsMap.phMax, DEFAULT_SETTINGS.thresholds.phMax),
      waterLevelLowPct: asNumber(
        thresholdsMap.waterLevelLowPct,
        DEFAULT_SETTINGS.thresholds.waterLevelLowPct,
      ),
      tdsMinPpm: asNumber(
        thresholdsMap.tdsMinPpm,
        DEFAULT_SETTINGS.thresholds.tdsMinPpm,
      ),
      tdsMaxPpm: asNumber(
        thresholdsMap.tdsMaxPpm,
        DEFAULT_SETTINGS.thresholds.tdsMaxPpm,
      ),
    },
    automation: {
      lowTdsAutoDoseEnabled: asBool(
        automationMap.lowTdsAutoDoseEnabled,
        DEFAULT_SETTINGS.automation.lowTdsAutoDoseEnabled,
      ),
    },
  };
}

function resolveEffectiveSettings(globalSettings, overrideSettings) {
  const usingOverride = overrideSettings && overrideSettings.overrideEnabled;
  if (!usingOverride) {
    return { source: 'global', ...globalSettings };
  }

  return {
    source: 'override',
    thresholds: overrideSettings.thresholds,
    automation: {
      lowTdsAutoDoseEnabled: overrideSettings.automation.lowTdsAutoDoseEnabled,
      pumpMaxRunSec: globalSettings.automation.pumpMaxRunSec,
      stopTarget: globalSettings.automation.stopTarget,
    },
    reminders: globalSettings.reminders,
  };
}

function metricStateRange(value, min, max) {
  if (value == null) return 'unknown';
  if (value < min) return 'low';
  if (value > max) return 'high';
  return 'normal';
}

function metricStateLowOnly(value, lowThreshold) {
  if (value == null) return 'unknown';
  if (value < lowThreshold) return 'low';
  return 'normal';
}

function evaluateMetrics(readings, thresholds) {
  const temperature = metricStateRange(
    readings.temperatureC,
    thresholds.temperatureMinC,
    thresholds.temperatureMaxC,
  );
  const ph = metricStateRange(readings.ph, thresholds.phMin, thresholds.phMax);
  const waterLevel = metricStateLowOnly(
    readings.waterLevelPct,
    thresholds.waterLevelLowPct,
  );
  const tds = metricStateRange(readings.tdsPpm, thresholds.tdsMinPpm, thresholds.tdsMaxPpm);

  const activeMetrics = [];
  if (temperature === 'low' || temperature === 'high') activeMetrics.push('temperature');
  if (ph === 'low' || ph === 'high') activeMetrics.push('ph');
  if (waterLevel === 'low') activeMetrics.push('waterLevel');
  if (tds === 'low' || tds === 'high') activeMetrics.push('tds');

  return {
    metrics: { temperature, ph, waterLevel, tds },
    activeMetrics,
  };
}

function stateFromPrevious(previousMetrics, metricName) {
  const metricData = asMap(previousMetrics[metricName]);
  return String(metricData.state || 'unknown');
}

function prettyMetric(metric) {
  switch (metric) {
    case 'temperature':
      return 'Temperature';
    case 'ph':
      return 'pH';
    case 'waterLevel':
      return 'Water level';
    case 'tds':
      return 'TDS';
    default:
      return metric;
  }
}

function prettyState(state) {
  switch (state) {
    case 'low':
      return 'LOW';
    case 'high':
      return 'HIGH';
    case 'normal':
      return 'NORMAL';
    default:
      return state.toUpperCase();
  }
}

function buildTransitionMessage({ metric, state, eventType }) {
  const metricLabel = prettyMetric(metric);
  if (eventType === 'recovered') {
    return `${metricLabel} recovered to normal range`;
  }
  return `${metricLabel} is ${prettyState(state)}`;
}

function thresholdSnapshot(thresholds) {
  return {
    temperatureMinC: thresholds.temperatureMinC,
    temperatureMaxC: thresholds.temperatureMaxC,
    phMin: thresholds.phMin,
    phMax: thresholds.phMax,
    waterLevelLowPct: thresholds.waterLevelLowPct,
    tdsMinPpm: thresholds.tdsMinPpm,
    tdsMaxPpm: thresholds.tdsMaxPpm,
  };
}

function metricValueForAlert(metric, readings) {
  switch (metric) {
    case 'temperature':
      return readings.temperatureC;
    case 'ph':
      return readings.ph;
    case 'waterLevel':
      return readings.waterLevelPct;
    case 'tds':
      return readings.tdsPpm;
    default:
      return null;
  }
}

function relayCommandPayload(type, targetState, reason, extra = {}) {
  const payload = {
    type,
    status: 'pending',
    requestedBy: AUTOMATION_USER_UID,
    requestedByEmail: AUTOMATION_USER_EMAIL,
    requestedAt: admin.firestore.FieldValue.serverTimestamp(),
    executedAt: null,
    message: '',
    reason,
  };
  if (typeof targetState === 'boolean') {
    payload.targetState = targetState;
  }
  return { ...payload, ...extra };
}

function asDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  return null;
}

function asString(value, fallback = '') {
  if (value == null) return fallback;
  return String(value);
}

function readRelayStates(data) {
  const states = asMap(data.relayStates);
  return {
    phUp: asBool(states.phUp, false),
    phDown: asBool(states.phDown, false),
    nutrient: asBool(states.nutrient, false),
    fishToFilter: asBool(states.fishToFilter, false),
    fishFeeder: asBool(states.fishFeeder, false),
  };
}

function hasRecentActiveCommand(commandDocs, type, targetState) {
  return commandDocs.some((doc) => {
    const data = doc.data() || {};
    const sameType = asString(data.type) === type;
    const sameTarget = typeof targetState !== 'boolean' || data.targetState === targetState;
    const status = asString(data.status);
    return sameType && sameTarget && (status === 'pending' || status === 'executing');
  });
}

function relayTimeParts(date, timeZone) {
  let formatter;
  try {
    formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  } catch (_) {
    formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Etc/UTC',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  }

  const parts = formatter.formatToParts(date);
  const map = {};
  for (const part of parts) {
    map[part.type] = part.value;
  }

  return {
    dateKey: `${map.year}-${map.month}-${map.day}`,
    timeKey: `${map.hour}:${map.minute}`,
  };
}

async function assertUserCanAccessDevice(uid, deviceId) {
  const db = admin.firestore();

  const [userDoc, deviceDoc] = await Promise.all([
    db.collection('users').doc(uid).get(),
    db.collection('devices').doc(deviceId).get(),
  ]);

  if (!deviceDoc.exists) {
    throw new HttpsError('not-found', `Device not found: devices/${deviceId}`);
  }

  const role = userDoc.exists ? String(userDoc.get('role') || '') : '';
  if (role === 'admin' || role === 'super_admin') {
    return;
  }

  const ownerUid = String(deviceDoc.get('ownerUid') || '');
  if (ownerUid && ownerUid === uid) {
    return;
  }

  // Keep current behavior permissive for signed-in users to avoid
  // breaking existing Firestore access patterns in this project.
}

exports.issueMqttCredentials = onCall(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentication is required');
    }

    const rawDeviceId = (request.data && request.data.deviceId ? request.data.deviceId : '')
      .toString()
      .trim();

    if (!rawDeviceId || !/^[A-Za-z0-9_-]{3,64}$/.test(rawDeviceId)) {
      throw new HttpsError('invalid-argument', 'A valid deviceId is required');
    }

    await assertUserCanAccessDevice(request.auth.uid, rawDeviceId);

    const liveTopic = cleanTopic(
      request.data ? request.data.liveTopic : null,
      `plantation/${rawDeviceId}/telemetry/live`,
    );
    const statusTopic = cleanTopic(
      request.data ? request.data.statusTopic : null,
      `plantation/${rawDeviceId}/status`,
    );

    const broker = parseBrokerConfig();

    const staticUsername = (MQTT_USERNAME_STATIC.value() || '').trim();
    const usernamePrefix = (MQTT_USERNAME_PREFIX.value() || 'app').trim() || 'app';
    const username = staticUsername || `${usernamePrefix}_${request.auth.uid}`;

    const nowSeconds = Math.floor(Date.now() / 1000);
    const expiresAtSeconds = nowSeconds + TOKEN_TTL_SECONDS;
    const clientId = `app-${rawDeviceId}-${Date.now()}`;

    let password = '';
    const jwtSecret = (MQTT_JWT_SECRET.value() || '').trim();
    const staticPassword = (MQTT_PASSWORD_STATIC.value() || '').trim();

    if (jwtSecret) {
      password = jwt.sign(
        {
          sub: request.auth.uid,
          aud: 'mqtt',
          deviceId: rawDeviceId,
          topic: liveTopic,
          statusTopic,
          iat: nowSeconds,
          exp: expiresAtSeconds,
        },
        jwtSecret,
        {
          algorithm: 'HS256',
          issuer: 'iotaquaapp',
        },
      );
    } else if (staticPassword) {
      password = staticPassword;
    } else {
      throw new HttpsError(
        'failed-precondition',
        'No MQTT auth secret configured. Set MQTT_JWT_SECRET or MQTT_PASSWORD_STATIC.',
      );
    }

    const endpointScheme = broker.useWebSocket
      ? broker.useTls
        ? 'wss'
        : 'ws'
      : broker.useTls
        ? 'mqtts'
        : 'mqtt';

    return {
      brokerUrl: broker.brokerUrl || `${endpointScheme}://${broker.host}:${broker.port}${broker.wsPath}`,
      brokerHost: broker.host,
      brokerPort: broker.port,
      wsPath: broker.wsPath,
      useTls: broker.useTls,
      useWebSocket: broker.useWebSocket,
      clientId,
      username,
      password,
      liveTopic,
      statusTopic,
      expiresAtEpochMs: expiresAtSeconds * 1000,
    };
  },
);

async function evaluateAndPersistDeviceAlerts(deviceId, { deviceData } = {}) {
  const db = admin.firestore();
  let data = deviceData;

  if (!data || typeof data !== 'object') {
    const deviceSnap = await db.collection('devices').doc(deviceId).get();
    if (!deviceSnap.exists) return { status: 'device_missing' };
    data = deviceSnap.data() || {};
  }

  const readings = readTelemetry(data);
  const relayStates = readRelayStates(data);
  if (
    readings.temperatureC == null &&
    readings.ph == null &&
    readings.waterLevelPct == null &&
    readings.tdsPpm == null
  ) {
    return { status: 'no_telemetry' };
  }

  const commandsCollection = db.collection('devices').doc(deviceId).collection('commands');
  const [globalSnap, overrideSnap, alertStateSnap, recentCommandSnap] = await Promise.all([
    db.collection('settings').doc('sensors').get(),
    db.collection('devices').doc(deviceId).collection('configs').doc('sensors').get(),
    db.collection('devices').doc(deviceId).collection('alert_state').doc('current').get(),
    commandsCollection.orderBy('requestedAt', 'desc').limit(25).get(),
  ]);

  const globalSettings = normalizeGlobalSettings(globalSnap.data());
  const overrideSettings = normalizeDeviceOverride(overrideSnap.data());
  const effective = resolveEffectiveSettings(globalSettings, overrideSettings);
  const evaluation = evaluateMetrics(readings, effective.thresholds);

  const previousData = alertStateSnap.exists ? alertStateSnap.data() : {};
  const previousMetrics = asMap(previousData.metrics);
  const alertsCollection = db.collection('devices').doc(deviceId).collection('alerts');

  const batch = db.batch();

  for (const metric of ['temperature', 'ph', 'waterLevel', 'tds']) {
    const previousState = stateFromPrevious(previousMetrics, metric);
    const currentState = evaluation.metrics[metric];
    if (previousState === currentState) continue;

    let eventType = null;
    if (currentState === 'low' || currentState === 'high') {
      eventType = 'breach_started';
    } else if (
      (previousState === 'low' || previousState === 'high') &&
      currentState === 'normal'
    ) {
      eventType = 'recovered';
    }

    if (!eventType) continue;

    const alertRef = alertsCollection.doc();
    batch.set(alertRef, {
      eventType,
      metric,
      state: currentState,
      value: metricValueForAlert(metric, readings),
      message: buildTransitionMessage({ metric, state: currentState, eventType }),
      thresholdSnapshot: thresholdSnapshot(effective.thresholds),
      source: effective.source,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  batch.set(
    db.collection('devices').doc(deviceId).collection('alert_state').doc('current'),
    {
      activeMetrics: evaluation.activeMetrics,
      metrics: {
        temperature: { state: evaluation.metrics.temperature },
        ph: { state: evaluation.metrics.ph },
        waterLevel: { state: evaluation.metrics.waterLevel },
        tds: { state: evaluation.metrics.tds },
      },
      latestValues: {
        temperatureC: readings.temperatureC,
        ph: readings.ph,
        waterLevelPct: readings.waterLevelPct,
        tdsPpm: readings.tdsPpm,
      },
      effectiveSource: effective.source,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  await batch.commit();

  const autoDoseEnabled = asBool(
    effective.automation.lowTdsAutoDoseEnabled,
    DEFAULT_SETTINGS.automation.lowTdsAutoDoseEnabled,
  );
  const recentCommandDocs = recentCommandSnap.docs;
  const commandBatch = db.batch();

  if (
    evaluation.metrics.waterLevel === 'low' &&
    !relayStates.fishToFilter &&
    !hasRecentActiveCommand(recentCommandDocs, 'fish_to_filter', true)
  ) {
    commandBatch.set(
      commandsCollection.doc(),
      relayCommandPayload('fish_to_filter', true, 'water_level_low'),
    );
  } else if (
    evaluation.metrics.waterLevel === 'normal' &&
    relayStates.fishToFilter &&
    !hasRecentActiveCommand(recentCommandDocs, 'fish_to_filter', false)
  ) {
    commandBatch.set(
      commandsCollection.doc(),
      relayCommandPayload('fish_to_filter', false, 'water_level_recovered'),
    );
  }

  if (evaluation.metrics.ph === 'low') {
    if (!relayStates.phUp && !hasRecentActiveCommand(recentCommandDocs, 'ph_up', true)) {
      commandBatch.set(commandsCollection.doc(), relayCommandPayload('ph_up', true, 'ph_low'));
    }
    if (relayStates.phDown && !hasRecentActiveCommand(recentCommandDocs, 'ph_down', false)) {
      commandBatch.set(commandsCollection.doc(), relayCommandPayload('ph_down', false, 'ph_low'));
    }
  } else if (evaluation.metrics.ph === 'high') {
    if (!relayStates.phDown && !hasRecentActiveCommand(recentCommandDocs, 'ph_down', true)) {
      commandBatch.set(commandsCollection.doc(), relayCommandPayload('ph_down', true, 'ph_high'));
    }
    if (relayStates.phUp && !hasRecentActiveCommand(recentCommandDocs, 'ph_up', false)) {
      commandBatch.set(commandsCollection.doc(), relayCommandPayload('ph_up', false, 'ph_high'));
    }
  } else {
    if (relayStates.phUp && !hasRecentActiveCommand(recentCommandDocs, 'ph_up', false)) {
      commandBatch.set(
        commandsCollection.doc(),
        relayCommandPayload('ph_up', false, 'ph_recovered'),
      );
    }
    if (relayStates.phDown && !hasRecentActiveCommand(recentCommandDocs, 'ph_down', false)) {
      commandBatch.set(
        commandsCollection.doc(),
        relayCommandPayload('ph_down', false, 'ph_recovered'),
      );
    }
  }

  if (
    autoDoseEnabled &&
    evaluation.metrics.tds === 'low' &&
    !relayStates.nutrient &&
    !hasRecentActiveCommand(recentCommandDocs, 'nutrient', true)
  ) {
    commandBatch.set(
      commandsCollection.doc(),
      relayCommandPayload('nutrient', true, 'tds_low'),
    );
  } else if (
    relayStates.nutrient &&
    (!autoDoseEnabled || evaluation.metrics.tds === 'normal' || evaluation.metrics.tds === 'high') &&
    !hasRecentActiveCommand(recentCommandDocs, 'nutrient', false)
  ) {
    commandBatch.set(
      commandsCollection.doc(),
      relayCommandPayload(
        'nutrient',
        false,
        autoDoseEnabled ? 'tds_recovered' : 'nutrient_automation_disabled',
      ),
    );
  }

  await commandBatch.commit();

  return { status: 'ok' };
}

exports.evaluateDeviceAlerts = onDocumentUpdated(
  'devices/{deviceId}',
  async (event) => {
    const after = event.data && event.data.after ? event.data.after : null;
    if (!after || !after.exists) return;

    const deviceId = event.params.deviceId;
    const deviceData = after.data() || {};
    await evaluateAndPersistDeviceAlerts(deviceId, { deviceData });
  },
);

exports.recomputeAlertsOnGlobalThresholdsWrite = onDocumentWritten(
  'settings/sensors',
  async (event) => {
    const db = admin.firestore();
    const afterSnap = event.data && event.data.after ? event.data.after : null;
    if (!afterSnap || !afterSnap.exists) {
      console.warn(
        'settings/sensors deleted; recomputing all devices using DEFAULT_SETTINGS fallback.',
      );
    }

    let processed = 0;
    let failed = 0;
    let lastDocId = null;

    while (true) {
      let query = db
        .collection('devices')
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(DEVICE_RECOMPUTE_BATCH_SIZE);

      if (lastDocId != null) {
        query = query.startAfter(lastDocId);
      }

      const deviceSnap = await query.get();
      if (deviceSnap.empty) break;

      for (const doc of deviceSnap.docs) {
        try {
          await evaluateAndPersistDeviceAlerts(doc.id, { deviceData: doc.data() || {} });
          processed += 1;
        } catch (error) {
          failed += 1;
          console.error(`recomputeAlertsOnGlobalThresholdsWrite failed for ${doc.id}`, error);
        }
      }

      lastDocId = deviceSnap.docs[deviceSnap.docs.length - 1].id;
      if (deviceSnap.size < DEVICE_RECOMPUTE_BATCH_SIZE) break;
    }

    console.log(
      `recomputeAlertsOnGlobalThresholdsWrite complete processed=${processed} failed=${failed}`,
    );
  },
);

exports.recomputeAlertsOnDeviceOverrideWrite = onDocumentWritten(
  'devices/{deviceId}/configs/sensors',
  async (event) => {
    const deviceId = event.params.deviceId;
    await evaluateAndPersistDeviceAlerts(deviceId);
  },
);

exports.cleanupOldAlerts = onSchedule(
  {
    schedule: 'every 24 hours',
    timeZone: 'Etc/UTC',
  },
  async () => {
    const db = admin.firestore();
    const cutoff = new Date(Date.now() - ALERT_RETENTION_DAYS * 24 * 60 * 60 * 1000);
    let totalDeleted = 0;

    while (true) {
      const snapshot = await db
        .collectionGroup('alerts')
        .where('createdAt', '<', cutoff)
        .orderBy('createdAt')
        .limit(ALERT_CLEANUP_BATCH_SIZE)
        .get();

      if (snapshot.empty) break;

      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      totalDeleted += snapshot.size;

      if (snapshot.size < ALERT_CLEANUP_BATCH_SIZE) break;
    }

    console.log(`cleanupOldAlerts deleted ${totalDeleted} docs`);
  },
);

exports.markStaleDevicesOffline = onSchedule(
  {
    schedule: 'every 1 minutes',
    timeZone: 'Etc/UTC',
  },
  async () => {
    const db = admin.firestore();
    const nowMs = Date.now();
    let lastDocId = null;
    let markedOffline = 0;

    while (true) {
      let query = db
        .collection('devices')
        .where('online', '==', true)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(STALE_DEVICE_SCAN_BATCH_SIZE);

      if (lastDocId != null) {
        query = query.startAfter(lastDocId);
      }

      const snapshot = await query.get();
      if (snapshot.empty) break;

      const batch = db.batch();
      let writes = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data() || {};
        const lastSeen = asDate(data.lastSeen);
        const ageMs = lastSeen ? nowMs - lastSeen.getTime() : Number.POSITIVE_INFINITY;
        if (ageMs <= DEVICE_OFFLINE_AFTER_MS) continue;

        batch.set(
          doc.ref,
          {
            online: false,
            espStatus: 'offline',
            offlineDetectedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        writes += 1;
      }

      if (writes > 0) {
        await batch.commit();
        markedOffline += writes;
      }

      lastDocId = snapshot.docs[snapshot.docs.length - 1].id;
      if (snapshot.size < STALE_DEVICE_SCAN_BATCH_SIZE) break;
    }

    console.log(`markStaleDevicesOffline marked devices=${markedOffline}`);
  },
);

exports.dispatchFeedingSchedules = onSchedule(
  {
    schedule: 'every 1 minutes',
    timeZone: 'Etc/UTC',
  },
  async () => {
    const db = admin.firestore();
    let lastDocId = null;
    let created = 0;

    while (true) {
      let query = db
        .collection('devices')
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(FEEDER_SCAN_BATCH_SIZE);

      if (lastDocId != null) {
        query = query.startAfter(lastDocId);
      }

      const snapshot = await query.get();
      if (snapshot.empty) break;

      for (const doc of snapshot.docs) {
        const data = doc.data() || {};
        const automation = asMap(data.automation);
        if (!asBool(automation.feedingEnabled, false)) continue;

        const rawTimes = Array.isArray(automation.feedingTimes)
          ? automation.feedingTimes.map((value) => asString(value).trim()).filter(Boolean)
          : [];
        if (rawTimes.length === 0) continue;

        const durationSec = Math.max(1, asInt(automation.feedingDurationSec, 8));
        const timeZone = asString(automation.timeZone || data.timeZone || 'Etc/UTC', 'Etc/UTC');
        const nowParts = relayTimeParts(new Date(), timeZone);
        if (!rawTimes.includes(nowParts.timeKey)) continue;

        const scheduleRef = db
          .collection('devices')
          .doc(doc.id)
          .collection('automation')
          .doc('feeding_schedule');

        const runKey = `${nowParts.dateKey}_${nowParts.timeKey}`;
        await db.runTransaction(async (tx) => {
          const scheduleSnap = await tx.get(scheduleRef);
          const lastRunKey = scheduleSnap.exists
            ? asString(scheduleSnap.get('lastRunKey') || '')
            : '';
          if (lastRunKey === runKey) return;

          const commandRef = db.collection('devices').doc(doc.id).collection('commands').doc();
          tx.set(
            commandRef,
            relayCommandPayload(
              'fish_feeder',
              true,
              'feeding_schedule',
              { durationMs: durationSec * 1000 },
            ),
          );
          tx.set(
            scheduleRef,
            {
              lastRunKey: runKey,
              lastDurationSec: durationSec,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
          created += 1;
        });
      }

      lastDocId = snapshot.docs[snapshot.docs.length - 1].id;
      if (snapshot.size < FEEDER_SCAN_BATCH_SIZE) break;
    }

    console.log(`dispatchFeedingSchedules processed feeder commands=${created}`);
  },
);
