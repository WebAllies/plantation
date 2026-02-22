const admin = require('firebase-admin');
const jwt = require('jsonwebtoken');
const { setGlobalOptions } = require('firebase-functions/v2');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
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
