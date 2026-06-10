#!/usr/bin/env python3
"""Evaluate a trained Keras/TFLite-ready model against a labeled split CSV.

Usage:
  python ml/evaluate.py \
    --model ml/artifacts/<run>/model_final.keras \
    --split-csv ml/artifacts/<run>/test_split.csv \
    --labels ml/artifacts/<run>/labels.txt
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix, f1_score


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="Path to .keras model")
    parser.add_argument("--split-csv", required=True, help="Split CSV path")
    parser.add_argument("--labels", required=True, help="labels.txt path")
    parser.add_argument("--binary-map", help="Optional JSON map {class: Healthy|Unhealthy}")
    parser.add_argument("--output", help="Optional output JSON path")
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--input-size", type=int, default=224)
    parser.add_argument("--image-column", default="resolved_path")
    parser.add_argument("--label-column", default="label")
    return parser.parse_args()


def normalize_label(value: str) -> str:
    return value.strip().lower().replace(" ", "_")


def load_labels(path: Path) -> List[str]:
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def build_dataset(
    paths: np.ndarray,
    labels: np.ndarray,
    input_size: int,
    batch_size: int,
    num_classes: int,
) -> tf.data.Dataset:
    ds = tf.data.Dataset.from_tensor_slices((paths, labels))

    def _load(path: tf.Tensor, label: tf.Tensor) -> Tuple[tf.Tensor, tf.Tensor]:
        image = tf.io.read_file(path)
        image = tf.image.decode_image(image, channels=3, expand_animations=False)
        image = tf.image.resize(image, [input_size, input_size])
        image = tf.cast(image, tf.float32)
        image.set_shape([input_size, input_size, 3])
        one_hot = tf.one_hot(label, depth=num_classes, dtype=tf.float32)
        return image, one_hot

    ds = ds.map(_load, num_parallel_calls=tf.data.AUTOTUNE)
    ds = ds.batch(batch_size)
    ds = ds.prefetch(tf.data.AUTOTUNE)
    return ds


def main() -> None:
    args = parse_args()

    model_path = Path(args.model).resolve()
    split_csv = Path(args.split_csv).resolve()
    labels_path = Path(args.labels).resolve()

    label_names = [normalize_label(v) for v in load_labels(labels_path)]
    label_to_idx = {label: i for i, label in enumerate(label_names)}

    df = pd.read_csv(split_csv)
    if args.image_column not in df.columns:
        raise ValueError(f"Missing image column: {args.image_column}")

    if "label_idx" in df.columns:
        y_true = df["label_idx"].to_numpy(dtype=np.int32)
    else:
        if args.label_column not in df.columns:
            raise ValueError(f"Missing label column: {args.label_column}")
        y_true = (
            df[args.label_column]
            .astype(str)
            .map(normalize_label)
            .map(label_to_idx)
            .to_numpy(dtype=np.int32)
        )

    paths = df[args.image_column].astype(str).to_numpy()
    ds = build_dataset(
        paths=paths,
        labels=y_true,
        input_size=args.input_size,
        batch_size=args.batch_size,
        num_classes=len(label_names),
    )

    model = tf.keras.models.load_model(model_path)
    y_prob = model.predict(ds, verbose=0)
    y_pred = y_prob.argmax(axis=1)

    report = classification_report(
        y_true,
        y_pred,
        target_names=label_names,
        output_dict=True,
        zero_division=0,
    )
    macro_f1 = float(f1_score(y_true, y_pred, average="macro", zero_division=0))
    cm = confusion_matrix(y_true, y_pred).tolist()

    if args.binary_map:
        binary_map = json.loads(Path(args.binary_map).read_text(encoding="utf-8"))
        binary_map = {normalize_label(k): v for k, v in binary_map.items()}
    else:
        binary_map = {label: ("Healthy" if label == "healthy" else "Unhealthy") for label in label_names}

    y_true_binary = np.array([binary_map.get(label_names[i], "Unhealthy") for i in y_true])
    y_pred_binary = np.array([binary_map.get(label_names[i], "Unhealthy") for i in y_pred])
    binary_f1 = float(f1_score(y_true_binary, y_pred_binary, average="macro", zero_division=0))

    metrics = {
        "model": str(model_path),
        "split_csv": str(split_csv),
        "samples": int(len(df)),
        "macro_f1": macro_f1,
        "binary_f1": binary_f1,
        "classification_report": report,
        "confusion_matrix": cm,
    }

    output = Path(args.output).resolve() if args.output else split_csv.with_name("evaluation.json")
    output.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    print(json.dumps({"output": str(output), "macro_f1": macro_f1, "binary_f1": binary_f1}, indent=2))


if __name__ == "__main__":
    main()
