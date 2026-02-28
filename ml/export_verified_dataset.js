#!/usr/bin/env node

/**
 * Export verified AI scans from Firestore + Storage into a local training dataset.
 *
 * Usage:
 *   node ml/export_verified_dataset.js \
 *     --project iotaquaapp \
 *     --bucket iotaquaapp.firebasestorage.app \
 *     --output ml/dataset \
 *     --credentials /path/to/service-account.json
 */

const fs = require('fs');
const path = require('path');

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const value = argv[i + 1];
    if (!value || value.startsWith('--')) {
      out[key] = true;
    } else {
      out[key] = value;
      i += 1;
    }
  }
  return out;
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

function normalizeLabel(raw) {
  return String(raw || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_')
    .replace(/[^a-z0-9_\-]/g, '');
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function csvEscape(value) {
  const s = String(value ?? '');
  if (s.includes('"') || s.includes(',') || s.includes('\n')) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

function writeCsv(filePath, rows) {
  const lines = rows.map((row) => row.map(csvEscape).join(','));
  fs.writeFileSync(filePath, lines.join('\n') + '\n', 'utf8');
}

async function main() {
  const args = parseArgs(process.argv);

  const projectId = args.project || process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID;
  if (!projectId) {
    throw new Error('Missing --project and no FIREBASE_PROJECT_ID/GCLOUD_PROJECT env var set.');
  }

  const outputDir = path.resolve(args.output || 'ml/dataset');
  const imagesRoot = path.join(outputDir, 'images');
  const metadataPath = path.join(outputDir, 'metadata.csv');
  const summaryPath = path.join(outputDir, 'export_summary.json');

  ensureDir(outputDir);
  ensureDir(imagesRoot);

  const admin = loadFirebaseAdmin();

  const initOptions = { projectId };
  if (args.bucket) {
    initOptions.storageBucket = args.bucket;
  }

  if (!admin.apps.length) {
    if (args.credentials) {
      const credentialsPath = path.resolve(args.credentials);
      // eslint-disable-next-line import/no-dynamic-require, global-require
      const serviceAccount = require(credentialsPath);
      admin.initializeApp({
        ...initOptions,
        credential: admin.credential.cert(serviceAccount),
      });
    } else {
      admin.initializeApp({
        ...initOptions,
        credential: admin.credential.applicationDefault(),
      });
    }
  }

  const db = admin.firestore();
  const bucket = admin.storage().bucket(args.bucket);

  const headers = [
    'scanId',
    'label',
    'localImagePath',
    'imagePath',
    'userId',
    'email',
    'role',
    'modelVersion',
    'deviceId',
    'captureSessionId',
    'timeOfDay',
    'createdAt',
    'verifiedBy',
    'verifiedAt',
  ];

  const rows = [headers];

  let processed = 0;
  let exported = 0;
  let skipped = 0;
  let lastDoc = null;
  const pageSize = 250;

  while (true) {
    let query = db
      .collection('ai_scans')
      .where('verificationStatus', '==', 'verified')
      .orderBy('__name__')
      .limit(pageSize);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      processed += 1;
      const data = doc.data() || {};

      const verifiedLabel = normalizeLabel(data.verifiedLabel || data.predictedClass || data.label);
      const imagePath = String(data.imagePath || '');

      if (!verifiedLabel || !imagePath) {
        skipped += 1;
        continue;
      }

      const classDir = path.join(imagesRoot, verifiedLabel);
      ensureDir(classDir);

      const localFile = path.join(classDir, `${doc.id}.jpg`);
      try {
        await bucket.file(imagePath).download({ destination: localFile });
      } catch (err) {
        skipped += 1;
        // Continue export even when some files are missing or unauthorized.
        continue;
      }

      const captureMetadata = data.captureMetadata || {};
      const createdAt = data.createdAt?.toDate ? data.createdAt.toDate().toISOString() : '';
      const verifiedAt = data.verifiedAt?.toDate ? data.verifiedAt.toDate().toISOString() : '';

      rows.push([
        doc.id,
        verifiedLabel,
        path.relative(outputDir, localFile),
        imagePath,
        String(data.userId || ''),
        String(data.email || ''),
        String(data.role || ''),
        String(data.modelVersion || ''),
        String(captureMetadata.deviceId || ''),
        String(captureMetadata.captureSessionId || ''),
        String(captureMetadata.timeOfDay || ''),
        createdAt,
        String(data.verifiedBy || ''),
        verifiedAt,
      ]);

      exported += 1;
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
  }

  writeCsv(metadataPath, rows);

  const summary = {
    projectId,
    bucket: bucket.name,
    outputDir,
    processed,
    exported,
    skipped,
    metadataCsv: metadataPath,
    generatedAt: new Date().toISOString(),
  };

  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2), 'utf8');
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}

main().catch((err) => {
  process.stderr.write(`Export failed: ${err.message}\n`);
  process.exit(1);
});
