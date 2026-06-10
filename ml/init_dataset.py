#!/usr/bin/env python3
"""Initialize local dataset directory structure and metadata template."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

DEFAULT_CLASSES = [
    "healthy",
    "nitrogen_deficiency",
    "phosphorus_deficiency",
    "potassium_deficiency",
    "nutrient_deficiency",
    "fungal_mildew",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="dataset", help="Dataset root directory")
    parser.add_argument(
        "--overwrite-metadata",
        action="store_true",
        help="Overwrite metadata.csv if it already exists",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output_root = Path(args.output).resolve()
    images_root = output_root / "images"
    metadata_csv = output_root / "metadata.csv"

    for label in DEFAULT_CLASSES:
        (images_root / label).mkdir(parents=True, exist_ok=True)

    if metadata_csv.exists() and not args.overwrite_metadata:
        print(f"metadata.csv already exists: {metadata_csv}")
    else:
        with metadata_csv.open("w", newline="", encoding="utf-8") as fh:
            writer = csv.writer(fh)
            writer.writerow(["image_path", "label", "captureSessionId"])
        print(f"wrote template: {metadata_csv}")

    print("dataset initialized")
    print(f"root: {output_root}")
    print(f"images: {images_root}")


if __name__ == "__main__":
    main()
