CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT 'Aquaponics ESP32',
  online BOOLEAN NOT NULL DEFAULT FALSE,
  esp_status TEXT NOT NULL DEFAULT 'offline',
  control_mode TEXT NOT NULL DEFAULT 'manual',
  automation JSONB NOT NULL DEFAULT '{}'::jsonb,
  relay_states JSONB NOT NULL DEFAULT '{}'::jsonb,
  last_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  rssi INTEGER,
  last_seen TIMESTAMPTZ,
  offline_detected_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS telemetry_readings (
  id BIGSERIAL PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  ts TIMESTAMPTZ NOT NULL DEFAULT now(),
  temperature_c DOUBLE PRECISION,
  ph DOUBLE PRECISION,
  water_level_pct DOUBLE PRECISION,
  tds_ppm DOUBLE PRECISION,
  ph_up_tank_level_pct DOUBLE PRECISION,
  ph_down_tank_level_pct DOUBLE PRECISION,
  nutrient_tank_level_pct DOUBLE PRECISION,
  sensor_status TEXT,
  last_read_ok BOOLEAN,
  sample_count BIGINT,
  heartbeat_seq BIGINT,
  relay_states JSONB NOT NULL DEFAULT '{}'::jsonb,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS telemetry_readings_device_ts_idx
  ON telemetry_readings(device_id, ts DESC);

ALTER TABLE telemetry_readings
  ALTER COLUMN sample_count TYPE BIGINT,
  ALTER COLUMN heartbeat_seq TYPE BIGINT;

CREATE TABLE IF NOT EXISTS device_commands (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  target_state BOOLEAN,
  duration_ms INTEGER,
  status TEXT NOT NULL DEFAULT 'pending',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  requested_by TEXT,
  requested_by_email TEXT,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  executed_at TIMESTAMPTZ,
  message TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS device_commands_device_requested_idx
  ON device_commands(device_id, requested_at DESC);

CREATE TABLE IF NOT EXISTS device_events (
  id BIGSERIAL PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  level TEXT NOT NULL,
  event TEXT NOT NULL,
  detail TEXT NOT NULL DEFAULT '',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS device_events_device_created_idx
  ON device_events(device_id, created_at DESC);

CREATE TABLE IF NOT EXISTS firebase_sync_queue (
  id BIGSERIAL PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  device_id TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  synced_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS firebase_sync_queue_pending_idx
  ON firebase_sync_queue(status, id)
  WHERE status = 'pending';
