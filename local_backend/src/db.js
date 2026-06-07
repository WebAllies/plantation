const fs = require('fs/promises');
const path = require('path');
const { Pool } = require('pg');

function asNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function asInt(value) {
  const parsed = Number.parseInt(String(value), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function asBool(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (normalized === 'true' || normalized === '1') return true;
    if (normalized === 'false' || normalized === '0') return false;
  }
  return null;
}

function asObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function dateFromPayload(payload) {
  const raw = payload.tsEpochMs ?? payload.tsMs;
  const ms = typeof raw === 'string' ? Number.parseInt(raw, 10) : Number(raw);
  if (Number.isFinite(ms) && ms > 1000000000) {
    return new Date(ms);
  }
  return new Date();
}

function camelDeviceRow(row) {
  if (!row) return null;
  return {
    deviceId: row.id,
    name: row.name,
    online: row.online,
    espStatus: row.esp_status,
    controlMode: row.control_mode,
    automation: row.automation || {},
    relayStates: row.relay_states || {},
    lastPayload: row.last_payload || {},
    rssi: row.rssi,
    lastSeen: row.last_seen,
    offlineDetectedAt: row.offline_detected_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function deviceBackupPayload(row) {
  const device = camelDeviceRow(row);
  if (!device) return {};
  const lastPayload = asObject(device.lastPayload);
  return {
    ...lastPayload,
    deviceId: device.deviceId,
    name: device.name,
    online: device.online,
    espStatus: device.espStatus,
    controlMode: device.controlMode,
    automation: device.automation,
    relayStates: device.relayStates,
    rssi: device.rssi,
    lastSeen: device.lastSeen,
    offlineDetectedAt: device.offlineDetectedAt,
    localBackendPrimary: true,
    updatedAt: device.updatedAt,
  };
}

function commandPayload(row) {
  return {
    id: row.id,
    commandId: row.id,
    deviceId: row.device_id,
    type: row.type,
    targetState: row.target_state,
    durationMs: row.duration_ms,
    status: row.status,
    requestedBy: row.requested_by,
    requestedByEmail: row.requested_by_email,
    requestedAt: row.requested_at,
    executedAt: row.executed_at,
    message: row.message || '',
    localBackendPrimary: true,
  };
}

class LocalDatabase {
  constructor({ databaseUrl }) {
    this.pool = new Pool({ connectionString: databaseUrl });
  }

  async close() {
    await this.pool.end();
  }

  async migrate() {
    const migrationPath = path.join(__dirname, '..', 'migrations', '001_init.sql');
    const sql = await fs.readFile(migrationPath, 'utf8');
    await this.pool.query(sql);
  }

  async enqueueFirebaseSync(client, entityType, entityId, deviceId, payload) {
    await client.query(
      `INSERT INTO firebase_sync_queue(entity_type, entity_id, device_id, payload)
       VALUES ($1, $2, $3, $4::jsonb)`,
      [entityType, String(entityId), deviceId || null, JSON.stringify(payload || {})],
    );
  }

  async ensureDevice(deviceId, { name = 'Aquaponics ESP32' } = {}) {
    const result = await this.pool.query(
      `INSERT INTO devices(id, name, updated_at)
       VALUES ($1, $2, now())
       ON CONFLICT (id) DO UPDATE SET updated_at = now()
       RETURNING *`,
      [deviceId, name],
    );
    return camelDeviceRow(result.rows[0]);
  }

  async listDevices() {
    const result = await this.pool.query(
      `SELECT * FROM devices
       ORDER BY online DESC, last_seen DESC NULLS LAST, id ASC`,
    );
    return result.rows.map(camelDeviceRow);
  }

  async getDevice(deviceId) {
    const result = await this.pool.query('SELECT * FROM devices WHERE id = $1', [deviceId]);
    return camelDeviceRow(result.rows[0]);
  }

  async storeTelemetry(deviceId, payload) {
    const normalized = { ...asObject(payload), deviceId };
    const ts = dateFromPayload(normalized);
    const relayStates = asObject(normalized.relayStates);
    const client = await this.pool.connect();

    try {
      await client.query('BEGIN');
      const deviceResult = await client.query(
        `INSERT INTO devices(
          id, name, online, esp_status, last_seen, offline_detected_at,
          last_payload, relay_states, rssi, updated_at
        )
        VALUES ($1, $2, TRUE, 'online', $3, NULL, $4::jsonb, $5::jsonb, $6, now())
        ON CONFLICT (id) DO UPDATE SET
          online = TRUE,
          esp_status = 'online',
          last_seen = EXCLUDED.last_seen,
          offline_detected_at = NULL,
          last_payload = EXCLUDED.last_payload,
          relay_states = EXCLUDED.relay_states,
          rssi = EXCLUDED.rssi,
          updated_at = now()
        RETURNING *`,
        [
          deviceId,
          normalized.name || 'Aquaponics ESP32',
          ts,
          JSON.stringify(normalized),
          JSON.stringify(relayStates),
          asInt(normalized.rssi),
        ],
      );

      const readingResult = await client.query(
        `INSERT INTO telemetry_readings(
          device_id, ts, temperature_c, ph, water_level_pct, tds_ppm,
          ph_up_tank_level_pct, ph_down_tank_level_pct, nutrient_tank_level_pct,
          sensor_status, last_read_ok, sample_count, heartbeat_seq,
          relay_states, payload
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14::jsonb, $15::jsonb)
        RETURNING id, created_at`,
        [
          deviceId,
          ts,
          asNumber(normalized.temperatureC),
          asNumber(normalized.ph),
          asNumber(normalized.waterLevelPct),
          asNumber(normalized.tdsPpm),
          asNumber(normalized.phUpTankLevelPct),
          asNumber(normalized.phDownTankLevelPct),
          asNumber(normalized.nutrientTankLevelPct),
          normalized.sensorStatus || null,
          asBool(normalized.lastReadOk),
          asInt(normalized.sampleCount),
          asInt(normalized.heartbeatSeq),
          JSON.stringify(relayStates),
          JSON.stringify(normalized),
        ],
      );

      const reading = readingResult.rows[0];
      await this.enqueueFirebaseSync(
        client,
        'device_snapshot',
        deviceId,
        deviceId,
        deviceBackupPayload(deviceResult.rows[0]),
      );
      await this.enqueueFirebaseSync(
        client,
        'telemetry_reading',
        reading.id,
        deviceId,
        {
          ...normalized,
          ts,
          createdAt: reading.created_at,
          localBackendPrimary: true,
        },
      );

      await client.query('COMMIT');
      return {
        device: camelDeviceRow(deviceResult.rows[0]),
        readingId: reading.id,
        payload: normalized,
      };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async updateDeviceStatus(deviceId, statusPayload) {
    const payload = { ...asObject(statusPayload), deviceId };
    const status = String(payload.status || payload.espStatus || '').toLowerCase();
    const online = status !== 'offline';
    const seenAt = dateFromPayload(payload);
    const client = await this.pool.connect();

    try {
      await client.query('BEGIN');
      const result = await client.query(
        `INSERT INTO devices(id, online, esp_status, last_seen, last_payload, updated_at)
         VALUES ($1, $2, $3, $4, $5::jsonb, now())
         ON CONFLICT (id) DO UPDATE SET
           online = EXCLUDED.online,
           esp_status = EXCLUDED.esp_status,
           last_seen = CASE WHEN EXCLUDED.online THEN EXCLUDED.last_seen ELSE devices.last_seen END,
           offline_detected_at = CASE WHEN EXCLUDED.online THEN NULL ELSE now() END,
           last_payload = devices.last_payload || EXCLUDED.last_payload,
           updated_at = now()
         RETURNING *`,
        [deviceId, online, online ? 'online' : 'offline', seenAt, JSON.stringify(payload)],
      );
      await this.enqueueFirebaseSync(
        client,
        'device_snapshot',
        deviceId,
        deviceId,
        deviceBackupPayload(result.rows[0]),
      );
      await client.query('COMMIT');
      return camelDeviceRow(result.rows[0]);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async patchDevice(deviceId, patch) {
    const allowed = asObject(patch);
    const automation = allowed.automation == null ? null : asObject(allowed.automation);
    const controlMode = allowed.controlMode == null ? null : String(allowed.controlMode);
    const client = await this.pool.connect();

    try {
      await client.query('BEGIN');
      const result = await client.query(
        `INSERT INTO devices(id, control_mode, automation, updated_at)
         VALUES ($1, COALESCE($2, 'manual'), COALESCE($3::jsonb, '{}'::jsonb), now())
         ON CONFLICT (id) DO UPDATE SET
           control_mode = COALESCE($2, devices.control_mode),
           automation = CASE
             WHEN $3::jsonb IS NULL THEN devices.automation
             ELSE devices.automation || $3::jsonb
           END,
           updated_at = now()
         RETURNING *`,
        [
          deviceId,
          controlMode,
          automation == null ? null : JSON.stringify(automation),
        ],
      );
      const payload = deviceBackupPayload(result.rows[0]);
      await this.enqueueFirebaseSync(client, 'device_patch', deviceId, deviceId, payload);
      await client.query('COMMIT');
      return camelDeviceRow(result.rows[0]);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async createCommand(deviceId, command, user) {
    await this.ensureDevice(deviceId);
    const rawDurationMs =
      command.durationMs != null
        ? command.durationMs
        : command.durationSec != null
          ? Number(command.durationSec) * 1000
          : null;
    const payload = {
      deviceId,
      type: String(command.type || ''),
      targetState: command.targetState,
      durationMs: rawDurationMs,
      requestedBy: user?.uid || command.requestedBy || '',
      requestedByEmail: user?.email || command.requestedByEmail || '',
    };

    if (!payload.type) {
      throw new Error('Command type is required');
    }

    const result = await this.pool.query(
      `INSERT INTO device_commands(
        device_id, type, target_state, duration_ms, status, payload,
        requested_by, requested_by_email
      )
      VALUES ($1, $2, $3, $4, 'pending', $5::jsonb, $6, $7)
      RETURNING *`,
      [
        deviceId,
        payload.type,
        asBool(payload.targetState),
        payload.durationMs == null ? null : asInt(payload.durationMs),
        JSON.stringify(payload),
        payload.requestedBy,
        payload.requestedByEmail,
      ],
    );

    const row = result.rows[0];
    const backup = commandPayload(row);
    await this.pool.query(
      `INSERT INTO firebase_sync_queue(entity_type, entity_id, device_id, payload)
       VALUES ('command', $1, $2, $3::jsonb)`,
      [row.id, deviceId, JSON.stringify(backup)],
    );

    return backup;
  }

  async updateCommandFromAck(deviceId, ack) {
    const commandId = ack.commandId || ack.id;
    if (!commandId) return null;
    const status = String(ack.status || '').trim() || 'executed';
    const message = String(ack.message || '');
    const executed = status === 'executed' || status === 'failed';

    const result = await this.pool.query(
      `UPDATE device_commands
       SET status = $3,
           message = $4,
           executed_at = CASE WHEN $5 THEN now() ELSE executed_at END,
           updated_at = now(),
           payload = payload || $6::jsonb
       WHERE id = $1 AND device_id = $2
       RETURNING *`,
      [commandId, deviceId, status, message, executed, JSON.stringify(asObject(ack))],
    );

    const row = result.rows[0];
    if (!row) return null;
    const payload = commandPayload(row);
    await this.pool.query(
      `INSERT INTO firebase_sync_queue(entity_type, entity_id, device_id, payload)
       VALUES ('command', $1, $2, $3::jsonb)`,
      [row.id, deviceId, JSON.stringify(payload)],
    );
    return payload;
  }

  async createEvent(deviceId, event) {
    await this.ensureDevice(deviceId);
    const result = await this.pool.query(
      `INSERT INTO device_events(device_id, level, event, detail, payload)
       VALUES ($1, $2, $3, $4, $5::jsonb)
       RETURNING *`,
      [
        deviceId,
        event.level || 'info',
        event.event || 'event',
        event.detail || '',
        JSON.stringify(asObject(event.payload)),
      ],
    );

    const row = result.rows[0];
    const payload = {
      deviceId,
      level: row.level,
      event: row.event,
      detail: row.detail,
      payload: row.payload || {},
      ts: row.created_at,
      localBackendPrimary: true,
    };
    await this.pool.query(
      `INSERT INTO firebase_sync_queue(entity_type, entity_id, device_id, payload)
       VALUES ('event', $1, $2, $3::jsonb)`,
      [row.id, deviceId, JSON.stringify(payload)],
    );
    return payload;
  }

  async markStaleDevicesOffline(offlineAfterMs) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await client.query(
        `UPDATE devices
         SET online = FALSE,
             esp_status = 'offline',
             offline_detected_at = now(),
             updated_at = now()
         WHERE online = TRUE
           AND (last_seen IS NULL OR last_seen < now() - ($1::text)::interval)
         RETURNING *`,
        [`${offlineAfterMs} milliseconds`],
      );
      for (const row of result.rows) {
        await this.enqueueFirebaseSync(
          client,
          'device_snapshot',
          row.id,
          row.id,
          deviceBackupPayload(row),
        );
      }
      await client.query('COMMIT');
      return result.rows.map(camelDeviceRow);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async claimFirebaseSyncItems(limit) {
    const result = await this.pool.query(
      `UPDATE firebase_sync_queue q
       SET status = 'syncing',
           attempts = attempts + 1
       WHERE q.id IN (
         SELECT id FROM firebase_sync_queue
         WHERE status = 'pending'
         ORDER BY id
         LIMIT $1
         FOR UPDATE SKIP LOCKED
       )
       RETURNING *`,
      [limit],
    );
    return result.rows;
  }

  async markFirebaseSyncDone(id) {
    await this.pool.query(
      `UPDATE firebase_sync_queue
       SET status = 'synced', synced_at = now(), last_error = NULL
       WHERE id = $1`,
      [id],
    );
  }

  async markFirebaseSyncFailed(id, error) {
    await this.pool.query(
      `UPDATE firebase_sync_queue
       SET status = 'pending', last_error = $2
       WHERE id = $1`,
      [id, String(error).slice(0, 1000)],
    );
  }
}

module.exports = {
  LocalDatabase,
  asBool,
  asInt,
  asNumber,
  asObject,
};
