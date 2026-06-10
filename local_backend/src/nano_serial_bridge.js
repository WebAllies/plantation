const { SerialPort, ReadlineParser } = require('serialport');

const portName = process.env.NANO_SERIAL_PORT || 'COM11';
const baudRate = Number.parseInt(process.env.NANO_SERIAL_BAUD || '115200', 10);
const deviceId = process.env.DEVICE_ID || 'esp32_aquaponics_01';
const backendUrl =
  process.env.LOCAL_BACKEND_HTTP_URL || 'http://116.203.96.119:8080';
const publishIntervalMs = Number.parseInt(process.env.NANO_PUBLISH_INTERVAL_MS || '1000', 10);

const keyMap = {
  PH: 'ph',
  TDS: 'tdsPpm',
  PHUP: 'phUpTankLevelPct',
  PHDOWN: 'phDownTankLevelPct',
  NUTRIENT: 'nutrientTankLevelPct',
};

const state = {
  ph: null,
  tdsPpm: null,
  phUpTankLevelPct: null,
  phDownTankLevelPct: null,
  nutrientTankLevelPct: null,
  rawLines: [],
  lastLineAt: null,
  publishTimer: null,
  sampleCount: 0,
  heartbeatSeq: 0,
};

function nowMs() {
  return Date.now();
}

function parseMachineLine(line) {
  const sep = line.indexOf(':');
  if (sep <= 0) return false;
  const key = line.slice(0, sep).trim().toUpperCase();
  const field = keyMap[key];
  if (!field) return false;

  const value = Number.parseFloat(line.slice(sep + 1).trim());
  if (!Number.isFinite(value)) return false;

  state[field] = Math.round(value * 100) / 100;
  state.lastLineAt = new Date();
  return true;
}

function requiredMissing() {
  const missing = [];
  for (const [nanoKey, field] of Object.entries(keyMap)) {
    if (state[field] == null) missing.push(nanoKey);
  }
  return missing;
}

function buildPayload() {
  const missing = requiredMissing();
  state.sampleCount += 1;
  state.heartbeatSeq += 1;
  const payload = {
    deviceId,
    tsEpochMs: String(nowMs()),
    nanoOnline: state.lastLineAt != null,
    nanoTransport: 'usb_bridge',
    nanoError:
      missing.length === 0 ? '' : `USB bridge missing readings: ${missing.join(',')}`,
    sensorStatus:
      `nano=usb_bridge,ph=${state.ph == null ? 'stale' : 'ok'}` +
      `,tds=${state.tdsPpm == null ? 'stale' : 'ok'}` +
      `,phUp=${state.phUpTankLevelPct == null ? 'stale' : 'ok'}` +
      `,phDown=${state.phDownTankLevelPct == null ? 'stale' : 'ok'}` +
      `,nutrient=${state.nutrientTankLevelPct == null ? 'stale' : 'ok'}`,
    lastReadOk: missing.length === 0,
    sampleCount: state.sampleCount,
    heartbeatSeq: state.heartbeatSeq,
  };

  for (const field of Object.values(keyMap)) {
    if (state[field] != null) payload[field] = state[field];
  }

  return payload;
}

async function publish() {
  state.publishTimer = null;
  const payload = buildPayload();
  const url = `${backendUrl.replace(/\/$/, '')}/api/devices/${encodeURIComponent(
    deviceId,
  )}/nano-telemetry`;

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`HTTP ${response.status}: ${text.slice(0, 200)}`);
  }

  console.log(
    `[nano-bridge] published ${deviceId}: ` +
      `ph=${payload.ph ?? '--'} tds=${payload.tdsPpm ?? '--'} ` +
      `phUp=${payload.phUpTankLevelPct ?? '--'} ` +
      `phDown=${payload.phDownTankLevelPct ?? '--'} ` +
      `nutrient=${payload.nutrientTankLevelPct ?? '--'} ` +
      `ok=${payload.lastReadOk}`,
  );
}

function schedulePublish() {
  if (state.publishTimer) return;
  state.publishTimer = setTimeout(() => {
    publish().catch((error) => {
      console.warn(`[nano-bridge] publish failed: ${error.message || error}`);
    });
  }, publishIntervalMs);
}

function main() {
  console.log(
    `[nano-bridge] opening ${portName} at ${baudRate}; device=${deviceId}; backend=${backendUrl}`,
  );

  const port = new SerialPort({ path: portName, baudRate });
  const parser = port.pipe(new ReadlineParser({ delimiter: '\n' }));

  port.on('open', () => console.log(`[nano-bridge] serial open ${portName}`));
  port.on('error', (error) => console.error(`[nano-bridge] serial error: ${error.message || error}`));

  parser.on('data', (raw) => {
    const line = String(raw).trim();
    if (!line) return;
    console.log(`[nano] ${line}`);
    if (parseMachineLine(line)) schedulePublish();
  });
}

main();
