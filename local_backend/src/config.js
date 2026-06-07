const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.join(__dirname, '..', '.env') });

function asBool(value, defaultValue) {
  if (value == null || value === '') return defaultValue;
  const normalized = String(value).trim().toLowerCase();
  if (normalized === 'true' || normalized === '1' || normalized === 'yes') return true;
  if (normalized === 'false' || normalized === '0' || normalized === 'no') return false;
  return defaultValue;
}

function asInt(value, defaultValue) {
  if (value == null || value === '') return defaultValue;
  const parsed = Number.parseInt(String(value), 10);
  return Number.isFinite(parsed) ? parsed : defaultValue;
}

module.exports = {
  databaseUrl:
    process.env.DATABASE_URL || 'postgres://plantation:plantation@127.0.0.1:5432/plantation',
  httpPort: asInt(process.env.HTTP_PORT, 8080),
  mqttPort: asInt(process.env.MQTT_PORT, 1883),
  requireFirebaseAuth: asBool(process.env.LOCAL_BACKEND_REQUIRE_AUTH, false),
  firebaseBackupEnabled: asBool(process.env.FIREBASE_BACKUP_ENABLED, true),
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID || 'iotaquaapp',
  firebaseWebApiKey: process.env.FIREBASE_WEB_API_KEY || '',
  firebaseBackupEmail: process.env.FIREBASE_BACKUP_EMAIL || '',
  firebaseBackupPassword: process.env.FIREBASE_BACKUP_PASSWORD || '',
  deviceOfflineAfterMs: asInt(process.env.DEVICE_OFFLINE_AFTER_MS, 12 * 1000),
  firebaseSyncIntervalMs: asInt(process.env.FIREBASE_SYNC_INTERVAL_MS, 2000),
  firebaseSyncBatchSize: asInt(process.env.FIREBASE_SYNC_BATCH_SIZE, 50),
};
