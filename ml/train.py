#!/usr/bin/env python3
"""Train lettuce disease classifier (EfficientNetB0) with grouped split.

Usage:
  python ml/train.py --config ml/configs/v1.yaml
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import numpy as np
import pandas as pd
import tensorflow as tf
import yaml
from sklearn.metrics import classification_report, confusion_matrix, f1_score
from sklearn.model_selection import train_test_split
from sklearn.utils.class_weight import compute_class_weight


@dataclass
class SplitFrames:
    train: pd.DataFrame
    val: pd.DataFrame
    test: pd.DataFrame


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, help="Path to YAML config")
    return parser.parse_args()


def load_config(path: Path) -> Dict:
    with path.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def set_seed(seed: int) -> None:
    np.random.seed(seed)
    tf.keras.utils.set_random_seed(seed)


def normalize_label(value: str) -> str:
    return value.strip().lower().replace(" ", "_")


def can_stratify(values: Iterable[str]) -> bool:
    counts = pd.Series(list(values)).value_counts()
    return len(counts) > 1 and (counts >= 2).all()


def _split_ratios(split_cfg: Dict) -> Tuple[float, float, float]:
    train_ratio = float(split_cfg.get("train", 0.70))
    val_ratio = float(split_cfg.get("val", 0.15))
    test_ratio = float(split_cfg.get("test", 0.15))

    if not math.isclose(train_ratio + val_ratio + test_ratio, 1.0, abs_tol=1e-6):
        raise ValueError("Split ratios must sum to 1.0")
    return train_ratio, val_ratio, test_ratio


def _allocate_group_counts(
    n_groups: int,
    train_ratio: float,
    val_ratio: float,
    test_ratio: float,
) -> Tuple[int, int, int]:
    if n_groups <= 0:
        return 0, 0, 0

    raw = np.array([train_ratio, val_ratio, test_ratio], dtype=np.float64) * float(n_groups)
    counts = np.floor(raw).astype(np.int32)
    remainder = int(n_groups - int(counts.sum()))

    if remainder > 0:
        order = np.argsort(-(raw - counts))
        for idx in order[:remainder]:
            counts[idx] += 1

    mins = np.array(
        [
            1 if n_groups >= 1 else 0,  # train
            1 if n_groups >= 3 else 0,  # val
            1 if n_groups >= 2 else 0,  # test
        ],
        dtype=np.int32,
    )

    for i in range(3):
        while counts[i] < mins[i]:
            donor = int(np.argmax(counts - mins))
            if donor == i or counts[donor] <= mins[donor]:
                break
            counts[donor] -= 1
            counts[i] += 1

    return int(counts[0]), int(counts[1]), int(counts[2])


def _dominant_group_labels(df: pd.DataFrame, group_col: str, label_col: str) -> pd.DataFrame:
    grouped = (
        df.groupby(group_col)[label_col]
        .agg(
            dominant_label=lambda s: s.mode().iloc[0] if not s.mode().empty else s.iloc[0],
            unique_labels=lambda s: int(s.nunique()),
        )
        .reset_index()
    )
    return grouped


def split_by_group_global(
    df: pd.DataFrame,
    group_col: str,
    label_col: str,
    split_cfg: Dict,
    seed: int,
) -> SplitFrames:
    train_ratio, val_ratio, test_ratio = _split_ratios(split_cfg)

    grouped = _dominant_group_labels(df, group_col=group_col, label_col=label_col)

    groups = grouped[group_col].to_numpy()
    group_labels = grouped["dominant_label"].to_numpy()

    stratify_primary = group_labels if can_stratify(group_labels) else None

    train_groups, holdout_groups = train_test_split(
        groups,
        test_size=(1.0 - train_ratio),
        random_state=seed,
        stratify=stratify_primary,
    )

    holdout_df = grouped[grouped[group_col].isin(holdout_groups)]
    holdout_labels = holdout_df[label_col].to_numpy()
    stratify_secondary = holdout_labels if can_stratify(holdout_labels) else None

    val_fraction_in_holdout = val_ratio / (val_ratio + test_ratio)

    val_groups, test_groups = train_test_split(
        holdout_groups,
        test_size=(1.0 - val_fraction_in_holdout),
        random_state=seed,
        stratify=stratify_secondary,
    )

    train_df = df[df[group_col].isin(train_groups)].copy()
    val_df = df[df[group_col].isin(val_groups)].copy()
    test_df = df[df[group_col].isin(test_groups)].copy()

    return SplitFrames(train=train_df, val=val_df, test=test_df)


def split_by_group_per_label(
    df: pd.DataFrame,
    group_col: str,
    label_col: str,
    split_cfg: Dict,
    seed: int,
) -> SplitFrames:
    train_ratio, val_ratio, test_ratio = _split_ratios(split_cfg)

    grouped = _dominant_group_labels(df, group_col=group_col, label_col=label_col)
    mixed_groups = grouped[grouped["unique_labels"] > 1]
    if not mixed_groups.empty:
        print(
            "[split] warning: found mixed-label groups; using dominant label per group. "
            f"mixed_groups={len(mixed_groups)}"
        )

    rng = np.random.default_rng(seed)
    train_groups: List[str] = []
    val_groups: List[str] = []
    test_groups: List[str] = []

    for label in sorted(grouped["dominant_label"].unique()):
        label_groups = grouped[grouped["dominant_label"] == label][group_col].astype(str).to_list()
        if not label_groups:
            continue

        rng.shuffle(label_groups)
        n_train, n_val, n_test = _allocate_group_counts(
            n_groups=len(label_groups),
            train_ratio=train_ratio,
            val_ratio=val_ratio,
            test_ratio=test_ratio,
        )

        train_groups.extend(label_groups[:n_train])
        val_groups.extend(label_groups[n_train : n_train + n_val])
        test_groups.extend(label_groups[n_train + n_val : n_train + n_val + n_test])

    train_df = df[df[group_col].astype(str).isin(set(train_groups))].copy()
    val_df = df[df[group_col].astype(str).isin(set(val_groups))].copy()
    test_df = df[df[group_col].astype(str).isin(set(test_groups))].copy()

    return SplitFrames(train=train_df, val=val_df, test=test_df)


def split_by_group(
    df: pd.DataFrame,
    group_col: str,
    label_col: str,
    split_cfg: Dict,
    seed: int,
    strategy: str = "per_label_grouped",
) -> SplitFrames:
    strategy_norm = strategy.strip().lower().replace("-", "_")
    if strategy_norm in {"per_label_grouped", "per_class_grouped", "label_grouped"}:
        return split_by_group_per_label(
            df=df,
            group_col=group_col,
            label_col=label_col,
            split_cfg=split_cfg,
            seed=seed,
        )
    return split_by_group_global(
        df=df,
        group_col=group_col,
        label_col=label_col,
        split_cfg=split_cfg,
        seed=seed,
    )


def resolve_image_path(path_value: str, image_root: Path) -> Path:
    candidate = Path(path_value)
    if candidate.is_absolute():
        return candidate
    return (image_root / candidate).resolve()


def add_image_paths(df: pd.DataFrame, image_col: str, image_root: Path) -> pd.DataFrame:
    out = df.copy()
    out["resolved_path"] = out[image_col].apply(
        lambda p: str(resolve_image_path(str(p), image_root))
    )
    out = out[out["resolved_path"].apply(lambda p: Path(p).exists())].copy()
    if out.empty:
        raise RuntimeError("No images found after path resolution")
    return out


def filter_decodable_images(df: pd.DataFrame) -> pd.DataFrame:
    keep_mask = []
    dropped = 0

    for path in df["resolved_path"].astype(str):
        try:
            raw = tf.io.read_file(path)
            _ = tf.image.decode_image(raw, channels=3, expand_animations=False)
            keep_mask.append(True)
        except Exception:
            keep_mask.append(False)
            dropped += 1

    out = df[keep_mask].copy()
    if out.empty:
        raise RuntimeError("No decodable images left after validation")

    if dropped > 0:
        print(f"[data] dropped {dropped} invalid/corrupt images during decode validation")

    return out


def make_label_index(allowed_labels: List[str]) -> Dict[str, int]:
    return {label: i for i, label in enumerate(allowed_labels)}


def summarize_split_coverage(
    splits: SplitFrames,
    label_col: str,
    allowed_labels: List[str],
) -> None:
    for name, split_df in {
        "train": splits.train,
        "val": splits.val,
        "test": splits.test,
    }.items():
        counts = split_df[label_col].value_counts().to_dict()
        missing = [label for label in allowed_labels if counts.get(label, 0) == 0]
        summary = ", ".join([f"{label}:{counts.get(label, 0)}" for label in allowed_labels])
        print(f"[split] {name}: {summary}")
        if missing:
            print(f"[split] warning: {name} missing labels: {missing}")


def _oversample_target_count(counts: pd.Series, strategy: str) -> int:
    strategy_norm = strategy.strip().lower()
    if strategy_norm == "max":
        return int(counts.max())
    if strategy_norm == "mean":
        return int(math.ceil(float(counts.mean())))
    if strategy_norm in {"p75", "q75"}:
        return int(math.ceil(float(counts.quantile(0.75))))
    if strategy_norm in {"p90", "q90"}:
        return int(math.ceil(float(counts.quantile(0.90))))
    return int(counts.max())


def oversample_train_split(
    train_df: pd.DataFrame,
    label_col: str,
    seed: int,
    target_strategy: str = "p75",
    max_multiplier: float = 3.0,
) -> pd.DataFrame:
    counts = train_df[label_col].value_counts()
    if counts.empty or len(counts) <= 1:
        return train_df

    target = _oversample_target_count(counts, strategy=target_strategy)
    rng = np.random.default_rng(seed)
    frames: List[pd.DataFrame] = []

    for label, label_df in train_df.groupby(label_col):
        current = int(len(label_df))
        cap = int(math.ceil(current * max_multiplier))
        desired = max(current, min(target, cap))

        if desired > current:
            sample_idx = rng.choice(label_df.index.to_numpy(), size=(desired - current), replace=True)
            frames.append(label_df)
            frames.append(label_df.loc[sample_idx].copy())
        else:
            frames.append(label_df)

    out = pd.concat(frames, axis=0, ignore_index=True)
    out = out.sample(frac=1.0, random_state=seed).reset_index(drop=True)

    print(
        "[train] oversample applied: "
        f"strategy={target_strategy}, max_multiplier={max_multiplier}, "
        f"samples_before={len(train_df)}, samples_after={len(out)}"
    )
    return out


def gaussian_blur_3x3(image: tf.Tensor) -> tf.Tensor:
    kernel = tf.constant(
        [[1.0, 2.0, 1.0], [2.0, 4.0, 2.0], [1.0, 2.0, 1.0]], dtype=tf.float32
    )
    kernel = kernel / tf.reduce_sum(kernel)
    kernel = tf.reshape(kernel, [3, 3, 1, 1])
    kernel = tf.tile(kernel, [1, 1, 3, 1])

    image4d = tf.expand_dims(image, axis=0)
    out = tf.nn.depthwise_conv2d(image4d, kernel, strides=[1, 1, 1, 1], padding="SAME")
    return tf.squeeze(out, axis=0)


def make_dataset(
    df: pd.DataFrame,
    num_classes: int,
    input_size: int,
    batch_size: int,
    aug_cfg: Dict,
    seed: int,
    training: bool,
) -> tf.data.Dataset:
    paths = df["resolved_path"].astype(str).to_numpy()
    labels = df["label_idx"].to_numpy(dtype=np.int32)

    ds = tf.data.Dataset.from_tensor_slices((paths, labels))
    if training:
        ds = ds.shuffle(min(len(paths), 4096), seed=seed, reshuffle_each_iteration=True)

    rotation = float(aug_cfg.get("rotation", 0.0))
    zoom = float(aug_cfg.get("zoom", 0.0))
    brightness = float(aug_cfg.get("brightness", 0.0))
    contrast = float(aug_cfg.get("contrast", 0.0))
    blur_probability = float(aug_cfg.get("blur_probability", 0.0))
    use_flip_h = bool(aug_cfg.get("flip_horizontal", aug_cfg.get("flip", True)))
    use_flip_v = bool(aug_cfg.get("flip_vertical", False))

    rot_layer = tf.keras.layers.RandomRotation(rotation) if rotation > 0 else None
    zoom_layer = (
        tf.keras.layers.RandomZoom(height_factor=zoom, width_factor=zoom)
        if zoom > 0
        else None
    )

    def _decode(path: tf.Tensor, label: tf.Tensor) -> Tuple[tf.Tensor, tf.Tensor]:
        image = tf.io.read_file(path)
        image = tf.image.decode_image(image, channels=3, expand_animations=False)
        image = tf.image.resize(image, [input_size, input_size])
        image = tf.cast(image, tf.float32)
        image.set_shape([input_size, input_size, 3])
        return image, label

    def _augment(image: tf.Tensor, label: tf.Tensor) -> Tuple[tf.Tensor, tf.Tensor]:
        x = image

        if use_flip_h:
            x = tf.image.random_flip_left_right(x)
        if use_flip_v:
            x = tf.image.random_flip_up_down(x)

        if rot_layer is not None:
            x = rot_layer(tf.expand_dims(x, axis=0), training=True)[0]

        if zoom_layer is not None:
            x = zoom_layer(tf.expand_dims(x, axis=0), training=True)[0]

        if brightness > 0:
            x = tf.image.random_brightness(x, max_delta=brightness * 255.0)

        if contrast > 0:
            x = tf.image.random_contrast(x, lower=1.0 - contrast, upper=1.0 + contrast)

        if blur_probability > 0:
            x = tf.cond(
                tf.random.uniform([]) < blur_probability,
                lambda: gaussian_blur_3x3(x),
                lambda: x,
            )

        x = tf.clip_by_value(x, 0.0, 255.0)
        return x, label

    def _one_hot(image: tf.Tensor, label: tf.Tensor) -> Tuple[tf.Tensor, tf.Tensor]:
        return image, tf.one_hot(label, depth=num_classes, dtype=tf.float32)

    ds = ds.map(_decode, num_parallel_calls=tf.data.AUTOTUNE)
    if training:
        ds = ds.map(_augment, num_parallel_calls=tf.data.AUTOTUNE)

    ds = ds.map(_one_hot, num_parallel_calls=tf.data.AUTOTUNE)
    ds = ds.batch(batch_size)
    ds = ds.prefetch(tf.data.AUTOTUNE)
    return ds


def build_model(
    num_classes: int,
    input_size: int,
    dropout: float,
    normalization: str,
) -> Tuple[tf.keras.Model, tf.keras.Model]:
    inputs = tf.keras.layers.Input(shape=(input_size, input_size, 3), name="input_image")
    x = inputs
    backbone = tf.keras.applications.EfficientNetB0(
        include_top=False,
        weights="imagenet",
        input_shape=(input_size, input_size, 3),
    )
    backbone.trainable = False

    x = backbone(x, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(dropout)(x)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax", name="predictions")(x)

    model = tf.keras.Model(inputs=inputs, outputs=outputs)
    return model, backbone


def compile_model(model: tf.keras.Model, learning_rate: float, label_smoothing: float) -> None:
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=learning_rate),
        loss=tf.keras.losses.CategoricalCrossentropy(label_smoothing=label_smoothing),
        metrics=[
            tf.keras.metrics.CategoricalAccuracy(name="accuracy"),
            tf.keras.metrics.TopKCategoricalAccuracy(k=2, name="top2_accuracy"),
        ],
    )


def freeze_backbone_except_top_layers(backbone: tf.keras.Model, unfreeze_layers: int) -> None:
    backbone.trainable = True

    if unfreeze_layers > 0 and unfreeze_layers < len(backbone.layers):
        for layer in backbone.layers[:-unfreeze_layers]:
            layer.trainable = False

    for layer in backbone.layers:
        if isinstance(layer, tf.keras.layers.BatchNormalization):
            layer.trainable = False


def evaluate_predictions(
    y_true: np.ndarray,
    y_prob: np.ndarray,
    label_names: List[str],
    binary_map: Dict[str, str],
) -> Dict:
    y_pred = y_prob.argmax(axis=1)
    class_indices = np.arange(len(label_names))

    macro_f1 = float(f1_score(y_true, y_pred, average="macro", zero_division=0))
    report = classification_report(
        y_true,
        y_pred,
        labels=class_indices,
        target_names=label_names,
        output_dict=True,
        zero_division=0,
    )

    cm = confusion_matrix(y_true, y_pred, labels=class_indices)

    def to_binary(idx: int) -> str:
        class_name = label_names[idx]
        return binary_map.get(class_name, "Unhealthy")

    y_true_binary = np.array([to_binary(i) for i in y_true])
    y_pred_binary = np.array([to_binary(i) for i in y_pred])
    binary_f1 = float(f1_score(y_true_binary, y_pred_binary, average="macro", zero_division=0))

    return {
        "macro_f1": macro_f1,
        "binary_f1": binary_f1,
        "classification_report": report,
        "confusion_matrix": cm.tolist(),
    }


def main() -> None:
    args = parse_args()
    config_path = Path(args.config).resolve()
    cfg = load_config(config_path)

    seed = int(cfg.get("seed", 42))
    set_seed(seed)

    data_cfg = cfg["data"]
    train_cfg = cfg["training"]
    out_cfg = cfg["output"]

    metadata_csv = Path(data_cfg["metadata_csv"]).resolve()
    image_root = Path(data_cfg["image_root"]).resolve()

    image_col = data_cfg.get("image_column", "image_path")
    label_col = data_cfg.get("label_column", "label")
    group_col = data_cfg.get("group_column", "captureSessionId")
    validate_images = bool(data_cfg.get("validate_images", True))
    split_strategy = data_cfg.get("split_strategy", "per_label_grouped")

    allowed_labels = [normalize_label(v) for v in data_cfg.get("allowed_labels", [])]
    if not allowed_labels:
        raise ValueError("data.allowed_labels cannot be empty")

    input_size = int(train_cfg.get("input_size", 224))
    batch_size = int(train_cfg.get("batch_size", 32))

    stage_a_epochs = int(train_cfg.get("stage_a_epochs", 15))
    stage_b_epochs = int(train_cfg.get("stage_b_epochs", 20))
    unfreeze_layers = int(train_cfg.get("stage_b_unfreeze_layers", 40))
    stage_a_lr = float(train_cfg.get("stage_a_lr", 1e-3))
    stage_b_lr = float(train_cfg.get("stage_b_lr", 1e-4))
    dropout = float(train_cfg.get("dropout", 0.30))
    label_smoothing = float(train_cfg.get("label_smoothing", 0.05))
    early_stopping_patience = int(train_cfg.get("early_stopping_patience", 6))
    reduce_lr_patience = int(train_cfg.get("reduce_lr_patience", 3))
    reduce_lr_factor = float(train_cfg.get("reduce_lr_factor", 0.5))
    reduce_lr_min_lr = float(train_cfg.get("reduce_lr_min_lr", 1e-6))
    oversample_train = bool(train_cfg.get("oversample_train", True))
    oversample_target = str(train_cfg.get("oversample_target", "p75"))
    oversample_max_multiplier = float(train_cfg.get("oversample_max_multiplier", 3.0))
    normalization_requested = cfg.get("model", {}).get("normalization", "[0,255]")
    normalization_mode = str(normalization_requested).replace(" ", "").lower()
    if normalization_mode not in {"[0,255]", "[0,255.0]", "raw", "none"}:
        print(
            "[model] warning: EfficientNetB0 in this TensorFlow build already contains "
            "its own preprocessing. For correctness, forcing model input normalization "
            "to [0,255]."
        )
    normalization = "[0,255]"

    run_prefix = out_cfg.get("run_name_prefix", "lettuce_v2")
    run_name = f"{run_prefix}_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
    run_dir = Path(out_cfg.get("root_dir", "ml/artifacts")).resolve() / run_name
    run_dir.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(metadata_csv)
    required_cols = {image_col, label_col, group_col}
    missing = required_cols - set(df.columns)
    if missing:
        raise ValueError(f"metadata.csv missing columns: {sorted(missing)}")

    df[label_col] = df[label_col].astype(str).map(normalize_label)
    df = df[df[label_col].isin(allowed_labels)].copy()
    if df.empty:
        raise RuntimeError("No rows left after filtering to allowed_labels")

    df = add_image_paths(df, image_col=image_col, image_root=image_root)
    if validate_images:
        df = filter_decodable_images(df)
    splits = split_by_group(
        df,
        group_col=group_col,
        label_col=label_col,
        split_cfg=data_cfg["split"],
        seed=seed,
        strategy=split_strategy,
    )
    summarize_split_coverage(splits, label_col=label_col, allowed_labels=allowed_labels)

    label_to_idx = make_label_index(allowed_labels)
    for split_df in (splits.train, splits.val, splits.test):
        split_df["label_idx"] = split_df[label_col].map(label_to_idx)

    for name, split_df in {
        "train": splits.train,
        "val": splits.val,
        "test": splits.test,
    }.items():
        split_df.to_csv(run_dir / f"{name}_split.csv", index=False)

    train_frame = splits.train.copy()
    if oversample_train:
        train_frame = oversample_train_split(
            train_frame,
            label_col=label_col,
            seed=seed,
            target_strategy=oversample_target,
            max_multiplier=oversample_max_multiplier,
        )

    num_classes = len(allowed_labels)
    train_ds = make_dataset(
        train_frame,
        num_classes=num_classes,
        input_size=input_size,
        batch_size=batch_size,
        aug_cfg=train_cfg.get("augmentation", {}),
        seed=seed,
        training=True,
    )
    val_ds = make_dataset(
        splits.val,
        num_classes=num_classes,
        input_size=input_size,
        batch_size=batch_size,
        aug_cfg=train_cfg.get("augmentation", {}),
        seed=seed,
        training=False,
    )
    test_ds = make_dataset(
        splits.test,
        num_classes=num_classes,
        input_size=input_size,
        batch_size=batch_size,
        aug_cfg=train_cfg.get("augmentation", {}),
        seed=seed,
        training=False,
    )

    y_train = train_frame["label_idx"].to_numpy(dtype=np.int32)
    try:
        weights = compute_class_weight(
            class_weight="balanced",
            classes=np.arange(num_classes),
            y=y_train,
        )
        class_weight = {i: float(w) for i, w in enumerate(weights)}
    except Exception:
        class_weight = None

    model, backbone = build_model(
        num_classes=num_classes,
        input_size=input_size,
        dropout=dropout,
        normalization=normalization,
    )

    checkpoint_stage_a = str(run_dir / "best_stage_a.keras")
    checkpoint_stage_b = str(run_dir / "best_stage_b.keras")

    stage_a_callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=early_stopping_patience,
            restore_best_weights=True,
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=reduce_lr_factor,
            patience=reduce_lr_patience,
            min_lr=reduce_lr_min_lr,
            verbose=1,
        ),
        tf.keras.callbacks.ModelCheckpoint(
            filepath=checkpoint_stage_a,
            monitor="val_loss",
            save_best_only=True,
        ),
    ]

    compile_model(model, learning_rate=stage_a_lr, label_smoothing=label_smoothing)
    history_a = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=stage_a_epochs,
        class_weight=class_weight,
        callbacks=stage_a_callbacks,
        verbose=1,
    )

    if Path(checkpoint_stage_a).exists():
        model.load_weights(checkpoint_stage_a)

    freeze_backbone_except_top_layers(backbone, unfreeze_layers=unfreeze_layers)
    compile_model(model, learning_rate=stage_b_lr, label_smoothing=label_smoothing)

    stage_b_callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=early_stopping_patience,
            restore_best_weights=True,
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=reduce_lr_factor,
            patience=reduce_lr_patience,
            min_lr=reduce_lr_min_lr,
            verbose=1,
        ),
        tf.keras.callbacks.ModelCheckpoint(
            filepath=checkpoint_stage_b,
            monitor="val_loss",
            save_best_only=True,
        ),
    ]

    history_b = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=stage_b_epochs,
        class_weight=class_weight,
        callbacks=stage_b_callbacks,
        verbose=1,
    )

    if Path(checkpoint_stage_b).exists():
        model.load_weights(checkpoint_stage_b)

    model_path = run_dir / "model_final.keras"
    model.save(model_path)

    y_val = splits.val["label_idx"].to_numpy(dtype=np.int32)
    y_test = splits.test["label_idx"].to_numpy(dtype=np.int32)

    val_prob = model.predict(val_ds, verbose=0)
    test_prob = model.predict(test_ds, verbose=0)

    binary_map = {
        normalize_label(k): v for k, v in cfg.get("binary_mapping", {}).items()
    }

    val_metrics = evaluate_predictions(y_val, val_prob, allowed_labels, binary_map)
    test_metrics = evaluate_predictions(y_test, test_prob, allowed_labels, binary_map)

    np.savez(
        run_dir / "val_predictions.npz",
        y_true=y_val,
        y_pred=val_prob,
        labels=np.array(allowed_labels),
    )
    np.savez(
        run_dir / "test_predictions.npz",
        y_true=y_test,
        y_pred=test_prob,
        labels=np.array(allowed_labels),
    )

    metrics = {
        "run_name": run_name,
        "model_path": str(model_path),
        "class_names": allowed_labels,
        "val": val_metrics,
        "test": test_metrics,
    }
    (run_dir / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    history = {
        "stage_a": history_a.history,
        "stage_b": history_b.history,
    }
    (run_dir / "history.json").write_text(json.dumps(history, indent=2), encoding="utf-8")

    (run_dir / "labels.txt").write_text("\n".join(allowed_labels) + "\n", encoding="utf-8")

    model_config_template = {
        "modelVersion": run_name,
        "inputSize": input_size,
        "normalization": normalization,
        "classThresholds": {label: 0.60 for label in allowed_labels},
        "binaryMap": {
            label: binary_map.get(label, "Unhealthy")
            for label in allowed_labels
        },
    }
    (run_dir / "model_config.template.json").write_text(
        json.dumps(model_config_template, indent=2),
        encoding="utf-8",
    )

    summary = {
        "run_dir": str(run_dir),
        "train_samples": int(len(splits.train)),
        "train_samples_effective": int(len(train_frame)),
        "val_samples": int(len(splits.val)),
        "test_samples": int(len(splits.test)),
        "macro_f1_test": test_metrics["macro_f1"],
        "binary_f1_test": test_metrics["binary_f1"],
    }
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
