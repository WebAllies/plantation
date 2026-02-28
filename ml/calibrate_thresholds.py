#!/usr/bin/env python3
"""Calibrate class-specific confidence thresholds from validation predictions.

Usage:
  python ml/calibrate_thresholds.py \
    --predictions ml/artifacts/<run>/val_predictions.npz \
    --model-config-template ml/artifacts/<run>/model_config.template.json \
    --output ml/artifacts/<run>/model_config.calibrated.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, List

import numpy as np
from sklearn.metrics import f1_score


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--predictions", required=True, help="NPZ with y_true, y_pred, labels")
    parser.add_argument("--output", required=True, help="Output calibrated config JSON")
    parser.add_argument(
        "--model-config-template",
        required=True,
        help="Template config JSON produced by training",
    )
    parser.add_argument(
        "--min-threshold",
        type=float,
        default=0.40,
        help="Lower bound for threshold search",
    )
    parser.add_argument(
        "--max-threshold",
        type=float,
        default=0.90,
        help="Upper bound for threshold search",
    )
    parser.add_argument(
        "--step",
        type=float,
        default=0.01,
        help="Threshold grid step",
    )
    return parser.parse_args()


def best_threshold(y_true_binary: np.ndarray, y_score: np.ndarray, grid: np.ndarray) -> float:
    best_t = 0.60
    best_f1 = -1.0

    for t in grid:
        y_pred_binary = (y_score >= t).astype(np.int32)
        f1 = f1_score(y_true_binary, y_pred_binary, zero_division=0)
        if f1 > best_f1:
            best_f1 = f1
            best_t = float(t)

    return float(round(best_t, 2))


def main() -> None:
    args = parse_args()

    pred_path = Path(args.predictions).resolve()
    template_path = Path(args.model_config_template).resolve()
    output_path = Path(args.output).resolve()

    loaded = np.load(pred_path, allow_pickle=True)
    y_true = loaded["y_true"].astype(np.int32)
    y_prob = loaded["y_pred"].astype(np.float32)
    labels = [str(v) for v in loaded["labels"].tolist()]

    if y_prob.ndim != 2:
        raise ValueError("y_pred must be [N, C] probability matrix")

    if y_prob.shape[0] != y_true.shape[0]:
        raise ValueError("y_true and y_pred sample counts do not match")

    if y_prob.shape[1] != len(labels):
        raise ValueError("Number of labels must match y_pred columns")

    grid = np.arange(args.min_threshold, args.max_threshold + args.step, args.step)

    thresholds: Dict[str, float] = {}
    for class_idx, class_name in enumerate(labels):
        y_true_binary = (y_true == class_idx).astype(np.int32)
        y_score = y_prob[:, class_idx]
        thresholds[class_name] = best_threshold(y_true_binary, y_score, grid)

    template = json.loads(template_path.read_text(encoding="utf-8"))
    template["classThresholds"] = thresholds

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(template, indent=2), encoding="utf-8")

    summary = {
        "predictions": str(pred_path),
        "output": str(output_path),
        "classThresholds": thresholds,
    }
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
