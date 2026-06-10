# Lettuce ML Workspace

This folder contains the local training pipeline that produces the on-device TFLite model used by the app.

## Goal
Train a high-accuracy lettuce classifier locally (CPU/GPU), calibrate confidence thresholds, export TFLite, and copy final assets into `assets/models/`.

## Current Label Taxonomy (5 Classes)
- `healthy`
- `nitrogen_deficiency`
- `phosphorus_deficiency`
- `potassium_deficiency`
- `fungal_mildew`

Binary compatibility used by app:
- `healthy -> Healthy`
- others -> `Unhealthy`

## Pipeline Files
- `ml/configs/v1.yaml`: training config and split rules
- `ml/train.py`: model training + evaluation artifacts
- `ml/calibrate_thresholds.py`: per-class threshold search on validation outputs
- `ml/export_tflite.py`: float16/int8 export + variant selection
- `ml/run_pipeline.py`: train -> calibrate -> export -> copy assets
- `ml/quality_audit.py`: remove bad/corrupt/duplicate images
- `ml/evaluate.py`: additional evaluation script
- `ml/init_dataset.py`: initialize dataset folders + metadata template
- `ml/export_verified_dataset.js`: export verified images from Firebase for retraining
- `ml/migrate_ai_scans_schema.js`: migrate old scan docs to new schema

## Recommended Training Environment
- Python 3.10+
- NVIDIA GPU (optional but strongly recommended)
- CUDA-compatible TensorFlow build if using GPU

Create virtual environment:

```bash
python -m venv ml/.venv
# Linux/macOS
source ml/.venv/bin/activate
# Windows PowerShell
# .\\ml\\.venv\\Scripts\\Activate.ps1
pip install -r ml/requirements.txt
```

Optional GPU TensorFlow install:

```bash
pip install --upgrade "tensorflow[and-cuda]>=2.14,<2.17"
```

Check GPU visibility:

```bash
python -c "import tensorflow as tf; print(tf.config.list_physical_devices('GPU'))"
```

## Dataset Location And Structure
`dataset/` is git-ignored by default.

Expected structure:

```text
dataset/
  images/
    healthy/
    nitrogen_deficiency/
    phosphorus_deficiency/
    potassium_deficiency/
    fungal_mildew/
  metadata.csv
```

Initialize structure:

```bash
python ml/init_dataset.py --output dataset
```

## Metadata Format
`metadata.csv` requires at least these columns:
- `image_path`: relative path from `dataset/images` (preferred)
- `label`: one of the 5 labels above
- `captureSessionId`: session/group id used to prevent leakage between train/val/test

Example:

```csv
image_path,label,captureSessionId
nitrogen_deficiency/N_001.jpg,nitrogen_deficiency,nitrogen_s003
```

## How Split Logic Works (Important)
Configured in `ml/configs/v1.yaml`:
- Split ratio: 70% train / 15% val / 15% test
- Group column: `captureSessionId`
- Strategy: grouped split (`per_label_grouped`)

This means:
- Images from the same `captureSessionId` stay in one split only.
- This prevents leakage from near-duplicate photos.

## If Your Raw Nutrient Dataset Is Mixed (N/P/K Prefix)
If source folder has nutrient deficiency images with prefix conventions:
- `N*` -> `nitrogen_deficiency`
- `P*` -> `phosphorus_deficiency`
- `K*` -> `potassium_deficiency`

Move/copy those files into the correct class folder before generating metadata rows.

## Data Quality Pass (Run Before Training)
Run audit to drop missing/corrupt/very low-quality/duplicate images:

```bash
python ml/quality_audit.py \
  --metadata dataset/metadata.csv \
  --image-root dataset/images \
  --output-report ml/artifacts/quality_report.csv \
  --output-metadata dataset/metadata.cleaned.csv \
  --drop-exact-duplicates
```

Use `dataset/metadata.cleaned.csv` for training.

## Training Configuration (Current Defaults)
From `ml/configs/v1.yaml`:
- Backbone: EfficientNetB0 transfer learning
- Input size: 224
- Batch size: 32
- Stage A: 12 epochs (frozen backbone)
- Stage B: 15 epochs (fine-tune top layers)
- Unfreeze layers: 40
- Dropout: 0.30
- Label smoothing: 0.02
- Oversampling: enabled (`p75`, max multiplier 3.0)
- Normalization: `[0,255]`

Augmentations include horizontal flip, mild rotation/zoom/brightness/contrast, and blur probability.

## Train Manually (Step By Step)

```bash
python ml/train.py --config ml/configs/v1.yaml
```

After training, outputs are created in:
- `ml/artifacts/<run_name>/`

Key artifacts:
- `model_final.keras`
- `metrics.json`
- `summary.json`
- `history.json`
- `train_split.csv`, `val_split.csv`, `test_split.csv`
- `val_predictions.npz`, `test_predictions.npz`
- `labels.txt`
- `model_config.template.json`

### Calibrate thresholds

```bash
python ml/calibrate_thresholds.py \
  --predictions ml/artifacts/<run>/val_predictions.npz \
  --model-config-template ml/artifacts/<run>/model_config.template.json \
  --output ml/artifacts/<run>/model_config.calibrated.json
```

### Export TFLite

```bash
python ml/export_tflite.py \
  --model ml/artifacts/<run>/model_final.keras \
  --labels ml/artifacts/<run>/labels.txt \
  --output-dir ml/artifacts/<run>/tflite \
  --representative-csv ml/artifacts/<run>/train_split.csv \
  --eval-csv ml/artifacts/<run>/test_split.csv \
  --ship-path assets/models/lettuce_model.tflite
```

Variant selection logic:
- Export both float16 and int8 (if representative dataset works)
- Choose int8 only when:
  - macro-F1 drop <= configured limit (`max-macro-f1-drop`, default 0.015)
  - mean latency <= budget (`latency-budget-ms`, default 250)
- Otherwise float16 is selected

### Copy labels + calibrated model config to app assets

```bash
cp ml/artifacts/<run>/labels.txt assets/models/labels.txt
cp ml/artifacts/<run>/model_config.calibrated.json assets/models/model_config.json
```

## One-Command Pipeline (Recommended)
Runs everything and updates app assets automatically:

```bash
python ml/run_pipeline.py --config ml/configs/v1.yaml --python python
```

Pipeline stages:
1. train
2. threshold calibration
3. TFLite export + variant selection
4. asset copy to `assets/models/`

## Retraining From Production Feedback (Verified Scans)
Export verified scans from Firebase:

```bash
node ml/export_verified_dataset.js \
  --project <firebase-project-id> \
  --bucket <storage-bucket> \
  --output dataset \
  --credentials /path/to/service-account.json
```

If old `ai_scans` docs need migration:

```bash
node ml/migrate_ai_scans_schema.js \
  --project <firebase-project-id> \
  --credentials /path/to/service-account.json
```

## Accuracy And Data Guidelines
- Target at least ~1000 images per class for stable performance.
- Keep capture diversity high (device, lighting, background, growth stage).
- Never split same capture session across train/val/test.
- Use strict labeling review for uncertain samples.
- Keep real field images in every training cycle.

## App Integration Contract
The app expects:
- `assets/models/lettuce_model.tflite`
- `assets/models/labels.txt`
- `assets/models/model_config.json`

`model_config.json` must include:
- `modelVersion`
- `inputSize`
- `normalization`
- `classThresholds`
- `binaryMap`

## Troubleshooting

Training is slow
- Confirm GPU is detected.
- Reduce image size or batch size if needed.

Model predicts mostly one class
- Check class imbalance.
- Check label noise.
- Check normalization mismatch between training and app inference.

int8 export fails
- Run with float16 only (still valid for shipping).
- Confirm representative CSV has readable files.

App confidence behavior seems wrong
- Re-check calibrated thresholds in `model_config.json`.
- Ensure `labels.txt` order exactly matches model output order.

