const express = require('express');
const cors = require('cors');
const { authMiddleware } = require('./auth');

function createHttpApi({ db, hub, mqtt, requireAuth }) {
  const app = express();

  app.use(cors());
  app.use(express.json({ limit: '1mb' }));
  app.use(authMiddleware({ requireAuth }));

  app.get('/health', async (_req, res) => {
    res.json({
      ok: true,
      localBackend: true,
      time: new Date().toISOString(),
    });
  });

  app.get('/api/devices', async (_req, res, next) => {
    try {
      res.json({ devices: await db.listDevices() });
    } catch (error) {
      next(error);
    }
  });

  app.get('/api/devices/:deviceId', async (req, res, next) => {
    try {
      const device = await db.getDevice(req.params.deviceId);
      if (!device) {
        res.status(404).json({ error: 'Device not found' });
        return;
      }
      res.json({ device });
    } catch (error) {
      next(error);
    }
  });

  app.patch('/api/devices/:deviceId', async (req, res, next) => {
    try {
      const device = await db.patchDevice(req.params.deviceId, req.body || {});
      hub.broadcast('device_patch', { deviceId: req.params.deviceId, ...device });
      res.json({ device });
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/devices/:deviceId/commands', async (req, res, next) => {
    try {
      const command = await db.createCommand(req.params.deviceId, req.body || {}, req.user);
      mqtt.publishCommand(command);
      hub.broadcast('command', command);
      res.status(201).json({ command });
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/devices/:deviceId/telemetry', async (req, res, next) => {
    try {
      const stored = await db.storeTelemetry(req.params.deviceId, req.body || {});
      hub.broadcast('telemetry', stored.payload);
      res.status(201).json({ readingId: stored.readingId });
    } catch (error) {
      next(error);
    }
  });

  app.use((error, _req, res, _next) => {
    res.status(500).json({ error: error.message || String(error) });
  });

  return app;
}

module.exports = { createHttpApi };
