# Lettuce ML Workspace

This folder contains the local training and export pipeline for the lettuce classifier used by the app.

## Current Class Taxonomy

- `healthy`
- `nitrogen_deficiency`
- `phosphorus_deficiency`
- `potassium_deficiency`
- `fungal_mildew`

Binary mapping in app/reporting:
- `healthy -> Healthy`
- all others -> `Unhealthy`

## Key Files

- `ml/configs/v1.yaml`: data/training config
- `ml/train.py`: train Keras model and save run artifacts
- `ml/calibrate_thresholds.py`: per-class threshold tuning from validation predictions
- `ml/export_tflite.py`: export float16/int8 and choose shipping variant
- `ml/run_pipeline.py`: one-command train -> calibrate -> export -> copy assets
- `ml/quality_audit.py`: remove corrupt/low-quality/duplicate images
- `ml/evaluate.py`: standalone evaluation
- `ml/export_verified_dataset.js`: export verified scans from Firestore + Storage
- `ml/migrate_ai_scans_schema.js`: backfill old AI scan schema

## Environment Setup

```bash
python -m venv ml/.venv
source ml/.venv/bin/activate
pip install -r ml/requirements.txt
```

Optional GPU (if supported by your system):

```bash
pip install --upgrade "tensorflow[and-cuda]>=2.14,<2.17"
```

## Dataset Structure

Expected layout:

- `dataset/images/<label>/*.jpg`
- `dataset/metadata.csv`

Required columns in metadata:
- `image_path`: relative path from `dataset/images` or absolute path
- `label`: one of the 5 labels above
- `captureSessionId`: group id used to avoid split leakage

Example row:

```csv
image_path,label,captureSessionId
nitrogen_deficiency/N_001.jpg,nitrogen_deficiency,nitrogen_s003
```

## Build Dataset From Verified Production Scans

```bash
node ml/export_verified_dataset.js \
  --project <firebase-project-id> \
  --bucket <storage-bucket> \
  --output dataset \
  --credentials /path/to/service-account.json
```

Optional schema migration for old docs:

```bash
node ml/migrate_ai_scans_schema.js \
  --project <firebase-project-id> \
  --credentials /path/to/service-account.json
```

## Training Flow

1. Quality audit (recommended every run):

```bash
python ml/quality_audit.py \
  --metadata dataset/metadata.csv \
  --image-root dataset/images \
  --output-report ml/artifacts/quality_report.csv \
  --output-metadata dataset/metadata.cleaned.csv \
  --drop-exact-duplicates
```

2. Train:

```bash
python ml/train.py --config ml/configs/v1.yaml
```

3. Calibrate thresholds:

```bash
python ml/calibrate_thresholds.py \
  --predictions ml/artifacts/<run>/val_predictions.npz \
  --model-config-template ml/artifacts/<run>/model_config.template.json \
  --output ml/artifacts/<run>/model_config.calibrated.json
```

4. Export TFLite:

```bash
python ml/export_tflite.py \
  --model ml/artifacts/<run>/model_final.keras \
  --labels ml/artifacts/<run>/labels.txt \
  --output-dir ml/artifacts/<run>/tflite \
  --representative-csv ml/artifacts/<run>/train_split.csv \
  --eval-csv ml/artifacts/<run>/test_split.csv \
  --ship-path assets/models/lettuce_model.tflite
```

## One-Command Pipeline

```bash
python ml/run_pipeline.py --config ml/configs/v1.yaml --python python
```

Pipeline steps:
1. Train
2. Threshold calibration
3. TFLite export + variant selection
4. Asset update:
   - `assets/models/lettuce_model.tflite`
   - `assets/models/labels.txt`
   - `assets/models/model_config.json`

## Run Outputs

Each run creates `ml/artifacts/<run_name>/` containing:
- `model_final.keras`
- `summary.json`
- `metrics.json`
- `history.json`
- `train_split.csv`, `val_split.csv`, `test_split.csv`
- `val_predictions.npz`, `test_predictions.npz`
- `model_config.template.json`, `model_config.calibrated.json`
- `tflite/` (export artifacts + `tflite_export_summary.json`)

## Accuracy Notes

- The biggest practical gains usually come from better data, not larger model changes.
- Keep class balance and session diversity high.
- Avoid mixing near-duplicate images across train/val/test.
- Keep label quality strict (2-pass review if possible).

## Troubleshooting

- If training is very slow, confirm whether GPU is available.
- If model collapses to one class, check:
  - class distribution
  - label correctness
  - normalization consistency between training and inference
- If int8 accuracy drops too much, ship float16.
