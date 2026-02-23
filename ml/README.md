# Lettuce ML Workspace

Local training pipeline for lettuce health/disease classification.

## Files

- `ml/configs/v1.yaml`: training/data split config
- `ml/train.py`: grouped split training (EfficientNetB0)
- `ml/evaluate.py`: standalone evaluation script
- `ml/calibrate_thresholds.py`: per-class threshold calibration
- `ml/export_tflite.py`: float16/int8 export + selection logic
- `ml/export_verified_dataset.js`: export verified scans from Firestore + Storage
- `ml/migrate_ai_scans_schema.js`: backfill old `ai_scans` docs to new schema
- `ml/run_pipeline.py`: one-command train -> calibrate -> export -> asset update
- `ml/init_dataset.py`: create local dataset folder/template CSV

## 1) Environment

```bash
python -m venv ml/.venv
source ml/.venv/bin/activate
pip install -r ml/requirements.txt
```

If TensorFlow does not detect GPU in WSL/Linux, reinstall with CUDA extras:

```bash
pip install --upgrade "tensorflow[and-cuda]>=2.14,<2.17"
```

## 2) Export verified dataset from production

```bash
node ml/export_verified_dataset.js \
  --project iotaquaapp \
  --bucket iotaquaapp.firebasestorage.app \
  --output dataset \
  --credentials /path/to/service-account.json
```

This creates:

- `dataset/images/<label>/*.jpg`
- `dataset/metadata.csv`

If you want to start manually (before export), initialize dataset structure:

```bash
python ml/init_dataset.py --output dataset
```

## 2.5) Backfill old AI scan documents (recommended once)

Dry run:

```bash
node ml/migrate_ai_scans_schema.js \
  --project iotaquaapp \
  --credentials /path/to/service-account.json \
  --dry-run
```

Apply:

```bash
node ml/migrate_ai_scans_schema.js \
  --project iotaquaapp \
  --credentials /path/to/service-account.json
```

## 3) Train

```bash
python ml/train.py --config ml/configs/v1.yaml
```

Outputs are written under `ml/artifacts/<run_name>/`.

Expected metadata columns in `dataset/metadata.csv`:

- `image_path` (relative path like `healthy/img001.jpg` or absolute path)
- `label` (one of 6 class names)
- `captureSessionId` (group id to avoid leakage between train/val/test)

## 4) Calibrate class thresholds

```bash
python ml/calibrate_thresholds.py \
  --predictions ml/artifacts/<run>/val_predictions.npz \
  --model-config-template ml/artifacts/<run>/model_config.template.json \
  --output ml/artifacts/<run>/model_config.calibrated.json
```

## 5) Export TFLite and select shipping variant

```bash
python ml/export_tflite.py \
  --model ml/artifacts/<run>/model_final.keras \
  --labels ml/artifacts/<run>/labels.txt \
  --output-dir ml/artifacts/<run>/tflite \
  --representative-csv ml/artifacts/<run>/train_split.csv \
  --eval-csv ml/artifacts/<run>/test_split.csv \
  --ship-path assets/models/lettuce_model.tflite
```

The script chooses `int8` only when:

- macro-F1 drop vs float16 <= `0.015`
- int8 latency <= `250 ms`

Otherwise it ships float16.

## 6) One-command full pipeline

After dataset is ready, run:

```bash
python ml/run_pipeline.py --config ml/configs/v1.yaml --python python
```

This does:

1. `train.py`
2. threshold calibration
3. TFLite export + int8/float16 selection
4. updates:
   - `assets/models/lettuce_model.tflite`
   - `assets/models/labels.txt`
   - `assets/models/model_config.json`

## Notes

- Firestore export/migration scripts require Google credentials (service account JSON or ADC).
- If `tf.config.list_physical_devices('GPU')` is empty, training will run on CPU.
