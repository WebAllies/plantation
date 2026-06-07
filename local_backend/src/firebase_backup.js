const admin = require('firebase-admin');

function firestoreRestValue(value) {
  if (value == null) return { nullValue: null };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    if (Number.isInteger(value)) return { integerValue: String(value) };
    return { doubleValue: value };
  }
  if (typeof value === 'string') return { stringValue: value };
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(firestoreRestValue) } };
  }
  if (typeof value === 'object') {
    const fields = {};
    for (const [key, nested] of Object.entries(value)) {
      if (nested !== undefined) fields[key] = firestoreRestValue(nested);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(value) };
}

function firestoreRestFields(payload) {
  const fields = {};
  for (const [key, value] of Object.entries(payload || {})) {
    if (value !== undefined) fields[key] = firestoreRestValue(value);
  }
  return fields;
}

function toDateOrNull(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function firestorePayload(payload) {
  if (!payload || typeof payload !== 'object') return {};
  const copy = { ...payload };
  for (const key of ['lastSeen', 'createdAt', 'updatedAt', 'requestedAt', 'executedAt', 'ts']) {
    if (copy[key] != null) {
      const date = toDateOrNull(copy[key]);
      if (date) copy[key] = date;
    }
  }
  return copy;
}

class FirebaseBackup {
  constructor({
    enabled,
    projectId,
    webApiKey = '',
    backupEmail = '',
    backupPassword = '',
    logger = console,
  }) {
    this.enabled = enabled;
    this.projectId = projectId;
    this.webApiKey = webApiKey;
    this.backupEmail = backupEmail;
    this.backupPassword = backupPassword;
    this.logger = logger;
    this.db = null;
    this.restIdToken = '';
    this.restExpiresAtMs = 0;
  }

  init() {
    if (!this.enabled) {
      this.logger.log('[firebase] backup disabled');
      return;
    }

    if (this.webApiKey && this.backupEmail && this.backupPassword) {
      this.logger.log(`[firebase] backup enabled with REST auth for project ${this.projectId}`);
      return;
    }

    try {
      if (!admin.apps.length) {
        admin.initializeApp({ projectId: this.projectId });
      }
      this.db = admin.firestore();
      this.logger.log(`[firebase] backup enabled with Admin SDK for project ${this.projectId}`);
    } catch (error) {
      this.logger.warn(`[firebase] Admin SDK init failed: ${error.message || error}`);
    }
  }

  async syncItem(item) {
    const payload = firestorePayload(item.payload);
    const deviceId = item.device_id || payload.deviceId;
    if (!deviceId) {
      throw new Error(`Sync item ${item.id} is missing deviceId`);
    }

    if (item.entity_type === 'device_snapshot' || item.entity_type === 'device_patch') {
      await this.setDocument(`devices/${deviceId}`, payload);
      return;
    }

    if (item.entity_type === 'telemetry_reading') {
      await this.setDocument(`devices/${deviceId}/readings/${item.entity_id}`, payload);
      return;
    }

    if (item.entity_type === 'command') {
      await this.setDocument(`devices/${deviceId}/commands/${item.entity_id}`, payload);
      return;
    }

    if (item.entity_type === 'event') {
      await this.setDocument(`devices/${deviceId}/logs/${item.entity_id}`, payload);
      return;
    }

    throw new Error(`Unknown Firebase sync entity type: ${item.entity_type}`);
  }

  async setDocument(path, payload) {
    if (this.db) {
      const parts = path.split('/');
      let ref = this.db.collection(parts[0]).doc(parts[1]);
      for (let i = 2; i < parts.length; i += 2) {
        ref = ref.collection(parts[i]).doc(parts[i + 1]);
      }
      await ref.set(payload, { merge: true });
      return;
    }

    if (!this.webApiKey || !this.backupEmail || !this.backupPassword) {
      throw new Error('No Firebase Admin credentials or REST backup login configured');
    }

    const token = await this.getRestToken();
    const encodedPath = path.split('/').map(encodeURIComponent).join('/');
    const mask = Object.keys(payload)
      .map((key) => `updateMask.fieldPaths=${encodeURIComponent(key)}`)
      .join('&');
    const url =
      `https://firestore.googleapis.com/v1/projects/${this.projectId}` +
      `/databases/(default)/documents/${encodedPath}` +
      (mask ? `?${mask}` : '');

    const response = await fetch(url, {
      method: 'PATCH',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ fields: firestoreRestFields(payload) }),
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`Firestore REST ${response.status}: ${text.slice(0, 500)}`);
    }
  }

  async getRestToken() {
    const now = Date.now();
    if (this.restIdToken && now < this.restExpiresAtMs - 60000) {
      return this.restIdToken;
    }

    const response = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${this.webApiKey}`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          email: this.backupEmail,
          password: this.backupPassword,
          returnSecureToken: true,
        }),
      },
    );

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`Firebase Auth REST ${response.status}: ${text.slice(0, 500)}`);
    }

    const data = await response.json();
    this.restIdToken = data.idToken;
    this.restExpiresAtMs = Date.now() + Number(data.expiresIn || 3600) * 1000;
    return this.restIdToken;
  }
}

async function runFirebaseSyncLoop({ db, firebase, intervalMs, batchSize, logger = console }) {
  if (!firebase.enabled) return;

  const tick = async () => {
    try {
      const items = await db.claimFirebaseSyncItems(batchSize);
      for (const item of items) {
        try {
          await firebase.syncItem(item);
          await db.markFirebaseSyncDone(item.id);
        } catch (error) {
          await db.markFirebaseSyncFailed(item.id, error.message || String(error));
          logger.warn(`[firebase] sync failed queue=${item.id}: ${error.message || error}`);
        }
      }
    } catch (error) {
      logger.warn(`[firebase] sync loop failed: ${error.message || error}`);
    }
  };

  await tick();
  return setInterval(tick, intervalMs);
}

module.exports = { FirebaseBackup, runFirebaseSyncLoop };
