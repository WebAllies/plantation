#!/usr/bin/env python3
"""Audit dataset image quality and write a cleaned metadata CSV.

Usage:
  python ml/quality_audit.py \
    --metadata dataset/metadata.csv \
    --image-root dataset/images \
    --output-report ml/artifacts/quality_report.csv \
    --output-metadata dataset/metadata.cleaned.csv
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Dict, Tuple

import numpy as np
import pandas as pd
from PIL import Image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--metadata", default="dataset/metadata.csv")
    parser.add_argument("--image-root", default="dataset/images")
    parser.add_argument("--image-column", default="image_path")
    parser.add_argument("--label-column", default="label")
    parser.add_argument("--output-report", default="ml/artifacts/quality_report.csv")
    parser.add_argument("--output-metadata", default="dataset/metadata.cleaned.csv")
    parser.add_argument("--min-width", type=int, default=96)
    parser.add_argument("--min-height", type=int, default=96)
    parser.add_argument("--min-brightness", type=float, default=0.08)
    parser.add_argument("--max-brightness", type=float, default=0.95)
    parser.add_argument(
        "--sharpness-percentile",
        type=float,
        default=3.0,
        help="Drop bottom X percentile by sharpness score (0 disables)",
    )
    parser.add_argument(
        "--drop-exact-duplicates",
        action="store_true",
        help="Drop repeated files with identical content hash",
    )
    return parser.parse_args()


def resolve_image_path(path_value: str, image_root: Path) -> Path:
    p = Path(path_value)
    if p.is_absolute():
        return p
    return (image_root / p).resolve()


def image_metrics(path: Path) -> Tuple[int, int, float, float]:
    with Image.open(path) as img:
        rgb = img.convert("RGB")
        width, height = rgb.size
        gray = np.asarray(rgb.convert("L"), dtype=np.float32)

    brightness = float(np.mean(gray) / 255.0)

    # Lightweight sharpness proxy: Laplacian variance.
    lap = (
        4.0 * gray
        - np.roll(gray, 1, axis=0)
        - np.roll(gray, -1, axis=0)
        - np.roll(gray, 1, axis=1)
        - np.roll(gray, -1, axis=1)
    )
    sharpness = float(np.var(lap))
    return width, height, brightness, sharpness


def file_hash(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    args = parse_args()

    metadata_path = Path(args.metadata).resolve()
    image_root = Path(args.image_root).resolve()
    report_path = Path(args.output_report).resolve()
    output_metadata = Path(args.output_metadata).resolve()

    df = pd.read_csv(metadata_path)
    required = {args.image_column, args.label_column}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"metadata missing required columns: {sorted(missing)}")

    metrics_rows = []
    for _, row in df.iterrows():
        image_rel = str(row[args.image_column])
        label = str(row[args.label_column])
        resolved = resolve_image_path(image_rel, image_root)

        out: Dict = {
            "image_path": image_rel,
            "label": label,
            "resolved_path": str(resolved),
            "exists": resolved.exists(),
            "width": np.nan,
            "height": np.nan,
            "brightness": np.nan,
            "sharpness": np.nan,
            "file_hash": "",
            "reasons": [],
        }

        if not resolved.exists():
            out["reasons"].append("missing_file")
            metrics_rows.append(out)
            continue

        try:
            width, height, brightness, sharpness = image_metrics(resolved)
            out["width"] = width
            out["height"] = height
            out["brightness"] = brightness
            out["sharpness"] = sharpness
        except Exception:
            out["reasons"].append("decode_error")
            metrics_rows.append(out)
            continue

        if args.drop_exact_duplicates:
            try:
                out["file_hash"] = file_hash(resolved)
            except Exception:
                out["reasons"].append("hash_error")

        metrics_rows.append(out)

    metrics = pd.DataFrame(metrics_rows)

    valid_sharp = metrics["sharpness"].dropna()
    sharpness_threshold = None
    if args.sharpness_percentile > 0 and not valid_sharp.empty:
        sharpness_threshold = float(np.percentile(valid_sharp.to_numpy(), args.sharpness_percentile))

    if sharpness_threshold is not None:
        for idx, value in metrics["sharpness"].items():
            if pd.isna(value):
                continue
            if float(value) < sharpness_threshold:
                metrics.at[idx, "reasons"] = metrics.at[idx, "reasons"] + ["low_sharpness"]

    for idx, row in metrics.iterrows():
        if pd.isna(row["width"]) or pd.isna(row["height"]):
            continue
        if int(row["width"]) < args.min_width:
            metrics.at[idx, "reasons"] = metrics.at[idx, "reasons"] + ["low_width"]
        if int(row["height"]) < args.min_height:
            metrics.at[idx, "reasons"] = metrics.at[idx, "reasons"] + ["low_height"]
        if not pd.isna(row["brightness"]):
            b = float(row["brightness"])
            if b < args.min_brightness:
                metrics.at[idx, "reasons"] = metrics.at[idx, "reasons"] + ["too_dark"]
            if b > args.max_brightness:
                metrics.at[idx, "reasons"] = metrics.at[idx, "reasons"] + ["too_bright"]

    if args.drop_exact_duplicates:
        seen = {}
        for idx, row in metrics.iterrows():
            h = str(row["file_hash"]).strip()
            if not h:
                continue
            if h not in seen:
                seen[h] = idx
                continue
            metrics.at[idx, "reasons"] = metrics.at[idx, "reasons"] + ["duplicate_exact"]

    metrics["reasons_json"] = metrics["reasons"].apply(json.dumps)
    metrics["keep"] = metrics["reasons"].apply(lambda reasons: len(reasons) == 0)

    report_path.parent.mkdir(parents=True, exist_ok=True)
    metrics_out = metrics.drop(columns=["reasons"]).rename(columns={"reasons_json": "reasons"})
    metrics_out.to_csv(report_path, index=False)

    kept_paths = set(metrics.loc[metrics["keep"], "image_path"].astype(str).tolist())
    cleaned = df[df[args.image_column].astype(str).isin(kept_paths)].copy()
    output_metadata.parent.mkdir(parents=True, exist_ok=True)
    cleaned.to_csv(output_metadata, index=False)

    before = df[args.label_column].astype(str).value_counts().to_dict()
    after = cleaned[args.label_column].astype(str).value_counts().to_dict()
    dropped = int(len(df) - len(cleaned))

    print(
        json.dumps(
            {
                "metadata": str(metadata_path),
                "report": str(report_path),
                "output_metadata": str(output_metadata),
                "rows_before": int(len(df)),
                "rows_after": int(len(cleaned)),
                "rows_dropped": dropped,
                "sharpness_threshold": sharpness_threshold,
                "counts_before": before,
                "counts_after": after,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()

