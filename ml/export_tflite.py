#!/usr/bin/env python3
"""Export float16 and int8 TFLite variants and optionally choose shipping model.

Usage:
  python ml/export_tflite.py \
    --model ml/artifacts/<run>/model_final.keras \
    --labels ml/artifacts/<run>/labels.txt \
    --output-dir ml/artifacts/<run>/tflite \
    --representative-csv ml/artifacts/<run>/train_split.csv \
    --eval-csv ml/artifacts/<run>/test_split.csv
"""

from __future__ import annotations

import argparse
import json
import shutil
import time
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.metrics import f1_score


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="Path to Keras model")
    parser.add_argument("--labels", required=True, help="labels.txt path")
    parser.add_argument("--output-dir", required=True, help="Directory for exported .tflite files")
    parser.add_argument("--representative-csv", help="CSV used for int8 representative dataset")
    parser.add_argument("--eval-csv", help="CSV for macro-F1 and latency checks")
    parser.add_argument("--image-column", default="resolved_path")
    parser.add_argument("--label-column", default="label")
    parser.add_argument("--input-size", type=int, default=224)
    parser.add_argument("--latency-budget-ms", type=float, default=250.0)
    parser.add_argument("--max-macro-f1-drop", type=float, default=0.015)
    parser.add_argument("--ship-path", help="Optional destination for selected model (e.g. assets/models/lettuce_model.tflite)")
    return parser.parse_args()


def normalize_label(value: str) -> str:
    return value.strip().lower().replace(" ", "_")


def load_labels(path: Path) -> List[str]:
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def preprocess_image(path: str, input_size: int) -> np.ndarray:
    image_bytes = tf.io.read_file(path)
    image = tf.image.decode_image(image_bytes, channels=3, expand_animations=False)
    image = tf.image.resize(image, [input_size, input_size])
    image = tf.cast(image, tf.float32)
    return image.numpy()


def representative_data_gen(csv_path: Path, image_col: str, input_size: int) -> Iterable[List[np.ndarray]]:
    df = pd.read_csv(csv_path)
    if image_col not in df.columns:
        raise ValueError(f"Missing image column in representative CSV: {image_col}")

    paths = df[image_col].astype(str).head(300).to_list()
    for path in paths:
        if not Path(path).exists():
            continue
        image = preprocess_image(path, input_size)
        image = np.expand_dims(image, axis=0).astype(np.float32)
        yield [image]


def make_converter(model: tf.keras.Model) -> tf.lite.TFLiteConverter:
    if not model.inputs:
        raise ValueError("Model has no inputs")

    input_shape = list(model.inputs[0].shape)
    if len(input_shape) < 2:
        raise ValueError(f"Unexpected input shape: {input_shape}")

    # TFLite export is for on-device single-image inference (batch=1).
    signature_shape = [1 if dim is None else int(dim) for dim in input_shape]
    signature_shape[0] = 1

    @tf.function(
        input_signature=[
            tf.TensorSpec(
                shape=signature_shape,
                dtype=model.inputs[0].dtype,
                name="input_image",
            )
        ]
    )
    def serving_fn(x: tf.Tensor) -> tf.Tensor:
        return model(x, training=False)

    concrete_fn = serving_fn.get_concrete_function()
    return tf.lite.TFLiteConverter.from_concrete_functions([concrete_fn], model)


def export_float16(model: tf.keras.Model, output_path: Path) -> None:
    converter = make_converter(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_model = converter.convert()
    output_path.write_bytes(tflite_model)


def export_int8(model: tf.keras.Model, output_path: Path, rep_gen: Iterable[List[np.ndarray]]) -> None:
    converter = make_converter(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.representative_dataset = lambda: rep_gen
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.int8
    converter.inference_output_type = tf.int8
    tflite_model = converter.convert()
    output_path.write_bytes(tflite_model)


def quantize_input(image: np.ndarray, input_detail: Dict) -> np.ndarray:
    dtype = input_detail["dtype"]
    if dtype == np.float32:
        return image.astype(np.float32)

    scale, zero_point = input_detail["quantization"]
    if scale and scale > 0:
        q = np.round(image / scale + zero_point)
    else:
        q = image

    if dtype == np.int8:
        return np.clip(q, -128, 127).astype(np.int8)
    if dtype == np.uint8:
        return np.clip(q, 0, 255).astype(np.uint8)

    raise ValueError(f"Unsupported input dtype: {dtype}")


def dequantize_output(output: np.ndarray, output_detail: Dict) -> np.ndarray:
    dtype = output_detail["dtype"]
    if dtype == np.float32:
        return output.astype(np.float32)

    scale, zero_point = output_detail["quantization"]
    if scale and scale > 0:
        return ((output.astype(np.float32) - zero_point) * scale).astype(np.float32)

    return output.astype(np.float32)


def evaluate_tflite(
    model_path: Path,
    eval_csv: Path,
    labels: List[str],
    image_col: str,
    label_col: str,
    input_size: int,
) -> Dict[str, float]:
    label_to_idx = {normalize_label(label): i for i, label in enumerate(labels)}

    df = pd.read_csv(eval_csv)
    if image_col not in df.columns:
        raise ValueError(f"Missing image column in eval CSV: {image_col}")
    if label_col not in df.columns and "label_idx" not in df.columns:
        raise ValueError(f"Missing label column in eval CSV: {label_col} or label_idx")

    if "label_idx" in df.columns:
        y_true = df["label_idx"].to_numpy(dtype=np.int32)
    else:
        y_true = (
            df[label_col]
            .astype(str)
            .map(normalize_label)
            .map(label_to_idx)
            .to_numpy(dtype=np.int32)
        )

    paths = df[image_col].astype(str).to_list()

    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]

    y_pred: List[int] = []
    latencies: List[float] = []

    for path in paths:
        if not Path(path).exists():
            continue

        image = preprocess_image(path, input_size)
        image = np.expand_dims(image, axis=0)
        model_input = quantize_input(image, input_detail)

        interpreter.set_tensor(input_detail["index"], model_input)

        t0 = time.perf_counter()
        interpreter.invoke()
        t1 = time.perf_counter()

        output = interpreter.get_tensor(output_detail["index"])
        output = dequantize_output(output, output_detail)
        scores = output.reshape(-1)
        y_pred.append(int(np.argmax(scores)))
        latencies.append((t1 - t0) * 1000.0)

    if not y_pred:
        raise RuntimeError("No predictions produced during TFLite evaluation")

    y_true_eval = y_true[: len(y_pred)]
    macro_f1 = float(f1_score(y_true_eval, np.array(y_pred), average="macro", zero_division=0))
    mean_latency = float(np.mean(latencies))

    return {
        "macro_f1": macro_f1,
        "mean_latency_ms": mean_latency,
        "num_samples": int(len(y_pred)),
    }


def choose_variant(
    float16_metrics: Optional[Dict[str, float]],
    int8_metrics: Optional[Dict[str, float]],
    max_macro_f1_drop: float,
    latency_budget_ms: float,
) -> str:
    if not float16_metrics or not int8_metrics:
        return "float16"

    f16 = float16_metrics["macro_f1"]
    i8 = int8_metrics["macro_f1"]
    i8_latency = int8_metrics["mean_latency_ms"]

    if i8 >= (f16 - max_macro_f1_drop) and i8_latency <= latency_budget_ms:
        return "int8"
    return "float16"


def main() -> None:
    args = parse_args()

    model_path = Path(args.model).resolve()
    labels_path = Path(args.labels).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    labels = load_labels(labels_path)
    model = tf.keras.models.load_model(model_path, compile=False)

    float16_path = output_dir / "lettuce_model_float16.tflite"
    int8_path = output_dir / "lettuce_model_int8.tflite"

    export_float16(model, float16_path)

    int8_exported = False
    if args.representative_csv:
        rep_csv = Path(args.representative_csv).resolve()
        rep_gen = representative_data_gen(rep_csv, args.image_column, args.input_size)
        try:
            export_int8(model, int8_path, rep_gen)
            int8_exported = True
        except Exception as exc:
            print(f"[WARN] int8 export failed: {exc}")

    float16_metrics = None
    int8_metrics = None

    if args.eval_csv:
        eval_csv = Path(args.eval_csv).resolve()
        float16_metrics = evaluate_tflite(
            model_path=float16_path,
            eval_csv=eval_csv,
            labels=labels,
            image_col=args.image_column,
            label_col=args.label_column,
            input_size=args.input_size,
        )

        if int8_exported:
            int8_metrics = evaluate_tflite(
                model_path=int8_path,
                eval_csv=eval_csv,
                labels=labels,
                image_col=args.image_column,
                label_col=args.label_column,
                input_size=args.input_size,
            )

    selected = choose_variant(
        float16_metrics=float16_metrics,
        int8_metrics=int8_metrics,
        max_macro_f1_drop=args.max_macro_f1_drop,
        latency_budget_ms=args.latency_budget_ms,
    )

    selected_path = int8_path if selected == "int8" and int8_exported else float16_path

    if args.ship_path:
        ship_path = Path(args.ship_path).resolve()
        ship_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(selected_path, ship_path)

    summary = {
        "float16_model": str(float16_path),
        "int8_model": str(int8_path) if int8_exported else None,
        "selected_variant": selected if int8_exported else "float16",
        "selected_model": str(selected_path),
        "float16_metrics": float16_metrics,
        "int8_metrics": int8_metrics,
        "latency_budget_ms": args.latency_budget_ms,
        "max_macro_f1_drop": args.max_macro_f1_drop,
    }

    (output_dir / "tflite_export_summary.json").write_text(
        json.dumps(summary, indent=2),
        encoding="utf-8",
    )

    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
