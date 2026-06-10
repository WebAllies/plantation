#!/usr/bin/env python3
"""Run training pipeline end-to-end with one command.

Pipeline:
1) train.py
2) calibrate_thresholds.py
3) export_tflite.py
4) optionally copy calibrated config + labels to assets
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import yaml


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="ml/configs/v1.yaml")
    parser.add_argument("--python", default="python")
    parser.add_argument("--run-dir", help="Reuse an existing run dir instead of retraining")
    parser.add_argument(
        "--ship-path",
        default="assets/models/lettuce_model.tflite",
        help="Where to copy selected TFLite model",
    )
    parser.add_argument(
        "--skip-train",
        action="store_true",
        help="Skip train step (requires --run-dir)",
    )
    parser.add_argument(
        "--skip-export",
        action="store_true",
        help="Skip TFLite export step",
    )
    parser.add_argument(
        "--skip-asset-copy",
        action="store_true",
        help="Do not overwrite assets/models/{labels.txt,model_config.json}",
    )
    return parser.parse_args()


def run_cmd(cmd: List[str], cwd: Path, env: Optional[Dict[str, str]] = None) -> None:
    print(f"\n[RUN] {' '.join(cmd)}")
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    subprocess.run(cmd, cwd=str(cwd), check=True, env=merged_env)


def load_config(path: Path) -> Dict:
    with path.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def find_latest_run(root: Path, prefix: str) -> Path:
    candidates = [p for p in root.glob(f"{prefix}_*") if p.is_dir()]
    if not candidates:
        raise RuntimeError(f"No run dirs found in {root} with prefix {prefix}_*")
    candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return candidates[0]


def copy_if_exists(src: Path, dst: Path) -> None:
    if not src.exists():
        raise RuntimeError(f"Missing expected artifact: {src}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    print(f"[COPY] {src} -> {dst}")


def main() -> None:
    args = parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    config_path = (repo_root / args.config).resolve()
    cfg = load_config(config_path)

    output_root = (repo_root / cfg["output"]["root_dir"]).resolve()
    run_prefix = cfg["output"].get("run_name_prefix", "lettuce_v2")

    if args.skip_train and not args.run_dir:
        raise ValueError("--skip-train requires --run-dir")

    run_dir: Optional[Path] = None

    if args.run_dir:
        run_dir = Path(args.run_dir).resolve()
        if not run_dir.exists():
            raise RuntimeError(f"run dir does not exist: {run_dir}")

    if not args.skip_train:
        run_cmd([args.python, "ml/train.py", "--config", str(config_path)], cwd=repo_root)
        run_dir = find_latest_run(output_root, run_prefix)

    if run_dir is None:
        raise RuntimeError("Could not determine run dir")

    calibrated_config = run_dir / "model_config.calibrated.json"
    template_config = run_dir / "model_config.template.json"

    run_cmd(
        [
            args.python,
            "ml/calibrate_thresholds.py",
            "--predictions",
            str(run_dir / "val_predictions.npz"),
            "--model-config-template",
            str(template_config),
            "--output",
            str(calibrated_config),
        ],
        cwd=repo_root,
    )

    export_summary_path = None
    if not args.skip_export:
        tflite_dir = run_dir / "tflite"
        run_cmd(
            [
                args.python,
                "ml/export_tflite.py",
                "--model",
                str(run_dir / "model_final.keras"),
                "--labels",
                str(run_dir / "labels.txt"),
                "--output-dir",
                str(tflite_dir),
                "--representative-csv",
                str(run_dir / "train_split.csv"),
                "--eval-csv",
                str(run_dir / "test_split.csv"),
                "--ship-path",
                str((repo_root / args.ship_path).resolve()),
            ],
            cwd=repo_root,
        )
        export_summary_path = tflite_dir / "tflite_export_summary.json"

    if not args.skip_asset_copy:
        copy_if_exists(run_dir / "labels.txt", repo_root / "assets/models/labels.txt")
        copy_if_exists(calibrated_config, repo_root / "assets/models/model_config.json")

    summary = {
        "completedAt": datetime.utcnow().isoformat() + "Z",
        "config": str(config_path),
        "runDir": str(run_dir),
        "calibratedConfig": str(calibrated_config),
        "tfliteExportSummary": str(export_summary_path) if export_summary_path else None,
        "assetsUpdated": not args.skip_asset_copy,
    }

    print("\n[PIPELINE DONE]")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
