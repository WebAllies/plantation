#!/usr/bin/env node

/**
 * Backfill ai_scans documents to the new schema introduced for lettuce_v2.
 *
 * Usage:
 *   node ml/migrate_ai_scans_schema.js \
 *     --project iotaquaapp \
 *     --credentials /path/to/service-account.json \
 *     --dry-run
 *
 * Then apply:
 *   node ml/migrate_ai_scans_schema.js \
 *     --project iotaquaapp \
 *     --credentials /path/to/service-account.json
 */

const path = require('path');

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) continue;

    const key = arg.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      out[key] = true;
    } else {
      out[key] = next;
      i += 1;
    }
  }
  return out;
}

function printHelp() {
  process.stdout.write(
    [
      'Usage:',
      '  node ml/migrate_ai_scans_schema.js --project <project-id> [options]',
      '',
      'Options:',
      '  --project <id>              Firebase project id',
      '  --credentials <path>        Service account JSON path',
      '  --dry-run                   Do not write updates',
      '  --batch-size <n>            Page size (default: 250)',
      '  --limit <n>                 Max docs to scan',
      '  --help                      Show this message',
      '',
      'Examples:',
      '  node ml/migrate_ai_scans_schema.js --project iotaquaapp --credentials key.json --dry-run',
      '  node ml/migrate_ai_scans_schema.js --project iotaquaapp --credentials key.json',
      '',
    ].join('\n')
  );
}

function loadFirebaseAdmin() {
  try {
    return require('firebase-admin');
  } catch (_) {
    try {
      return require('../functions/node_modules/firebase-admin');
    } catch (err) {
      throw new Error(
        'firebase-admin not found. Install it or run from repo with functions/node_modules present.'
      );
    }
  }
}

function normalizeClass(raw) {
  const s = String(raw || '').trim().toLowerCase();
  if (!s) return '';
  if (s === 'healthy') return 'healthy';
  if (s === 'unhealthy') return 'unhealthy_legacy';
  return s.replace(/\s+/g, '_').replace(/[^a-z0-9_\-]/g, '');
}

function binaryFromClass(predictedClass, fallbackLabel) {
  const normalized = normalizeClass(predictedClass || fallbackLabel);
  if (normalized === 'healthy') return 'Healthy';
  if (normalized) return 'Unhealthy';

  const fallback = String(fallbackLabel || '').trim().toLowerCase();
  if (fallback === 'healthy') return 'Healthy';
  if (fallback === 'unhealthy') return 'Unhealthy';
  return '';
}

function parseLimit(value) {
  if (!value) return null;
  const parsed = Number.parseInt(String(value), 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return parsed;
}

function parseBatchSize(value, defaultSize) {
  const parsed = Number.parseInt(String(value || ''), 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return defaultSize;
  return parsed;
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help || args.h) {
    printHelp();
    return;
  }
  const dryRun = args['dry-run'] === true;
  const batchSize = parseBatchSize(args['batch-size'], 250);
  const limit = parseLimit(args.limit);

  const projectId =
    args.project || process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID;
  if (!projectId) {
    throw new Error(
      'Missing --project and no FIREBASE_PROJECT_ID/GCLOUD_PROJECT env var set.'
    );
  }

  const admin = loadFirebaseAdmin();
  if (!admin.apps.length) {
    if (args.credentials) {
      // eslint-disable-next-line import/no-dynamic-require, global-require
      const serviceAccount = require(path.resolve(args.credentials));
      admin.initializeApp({
        projectId,
        credential: admin.credential.cert(serviceAccount),
      });
    } else {
      admin.initializeApp({
        projectId,
        credential: admin.credential.applicationDefault(),
      });
    }
  }

  const db = admin.firestore();

  let scanned = 0;
  let updated = 0;
  let unchanged = 0;
  let failures = 0;
  const sampleUpdates = [];

  let lastDoc = null;

  while (true) {
    let query = db.collection('ai_scans').orderBy('__name__').limit(batchSize);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snap = await query.get();
    if (snap.empty) break;

    const batch = db.batch();
    let batchOps = 0;

    for (const doc of snap.docs) {
      scanned += 1;
      const data = doc.data() || {};

      const existingClass = String(data.predictedClass || '').trim();
      const existingBinary = String(data.predictedBinary || '').trim();
      const label = String(data.label || '').trim();

      const inferredClass = normalizeClass(existingClass || label);
      const inferredBinary = binaryFromClass(existingClass || inferredClass, label);

      const confidence =
        typeof data.confidence === 'number' && Number.isFinite(data.confidence)
          ? data.confidence
          : 0.0;

      const topKDefault = inferredClass
        ? [{ label: inferredClass, score: confidence }]
        : [];

      const patch = {};

      if (!data.predictedClass && inferredClass) {
        patch.predictedClass = inferredClass;
      }
      if (!data.predictedBinary && inferredBinary) {
        patch.predictedBinary = inferredBinary;
      }

      if (!data.label && inferredBinary) {
        patch.label = inferredBinary;
      }

      if (!Array.isArray(data.topK)) {
        patch.topK = topKDefault;
      }

      if (!data.modelVersion) {
        patch.modelVersion = 'legacy_migration_v1';
      }

      if (!data.verificationStatus) {
        patch.verificationStatus = 'pending';
      }
      if (!Object.prototype.hasOwnProperty.call(data, 'verifiedLabel')) {
        patch.verifiedLabel = null;
      }
      if (!Object.prototype.hasOwnProperty.call(data, 'verifiedBy')) {
        patch.verifiedBy = null;
      }
      if (!Object.prototype.hasOwnProperty.call(data, 'verifiedAt')) {
        patch.verifiedAt = null;
      }

      if (!Object.prototype.hasOwnProperty.call(data, 'imagePath')) {
        patch.imagePath = null;
      }

      if (!data.captureMetadata || typeof data.captureMetadata !== 'object') {
        patch.captureMetadata = {
          farmId: null,
          deviceId: null,
          captureSessionId: `legacy-${doc.id}`,
          timeOfDay: null,
        };
      } else {
        const cm = data.captureMetadata;
        const cmPatch = {
          farmId: Object.prototype.hasOwnProperty.call(cm, 'farmId') ? cm.farmId : null,
          deviceId: Object.prototype.hasOwnProperty.call(cm, 'deviceId') ? cm.deviceId : null,
          captureSessionId: Object.prototype.hasOwnProperty.call(cm, 'captureSessionId')
            ? cm.captureSessionId
            : `legacy-${doc.id}`,
          timeOfDay: Object.prototype.hasOwnProperty.call(cm, 'timeOfDay')
            ? cm.timeOfDay
            : null,
        };

        const changed =
          cmPatch.farmId !== cm.farmId ||
          cmPatch.deviceId !== cm.deviceId ||
          cmPatch.captureSessionId !== cm.captureSessionId ||
          cmPatch.timeOfDay !== cm.timeOfDay;

        if (changed) {
          patch.captureMetadata = cmPatch;
        }
      }

      if (Object.keys(patch).length === 0) {
        unchanged += 1;
      } else {
        updated += 1;
        if (sampleUpdates.length < 5) {
          sampleUpdates.push({ id: doc.id, patch });
        }

        if (!dryRun) {
          batch.update(doc.ref, patch);
          batchOps += 1;
        }
      }

      if (limit && scanned >= limit) break;
    }

    if (!dryRun && batchOps > 0) {
      try {
        await batch.commit();
      } catch (err) {
        failures += batchOps;
        process.stderr.write(`Batch commit failed: ${err.message}\n`);
      }
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (limit && scanned >= limit) break;
  }

  const summary = {
    projectId,
    dryRun,
    scanned,
    updated,
    unchanged,
    failures,
    sampleUpdates,
    generatedAt: new Date().toISOString(),
  };

  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}

main().catch((err) => {
  process.stderr.write(`Migration failed: ${err.message}\n`);
  process.exit(1);
});
