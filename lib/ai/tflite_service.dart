import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

const String _defaultBinaryHealthy = 'Healthy';
const String _defaultBinaryUnhealthy = 'Unhealthy';

class TfliteService {
  Interpreter? _interpreter;
  List<String> _labels = [];

  List<int>? _inputShape;
  List<int>? _outputShape;
  TensorType? _inputType;
  TensorType? _outputType;

  double _inputScale = 0.0;
  int _inputZeroPoint = 0;
  double _outputScale = 0.0;
  int _outputZeroPoint = 0;

  ModelConfig _modelConfig = ModelConfig.defaults();

  ModelConfig get modelConfig => _modelConfig;

  Future<void> load() async {
    final options = InterpreterOptions()
      ..threads = 2
      ..useNnApiForAndroid = false;

    _interpreter = await Interpreter.fromAsset(
      'assets/models/lettuce_model.tflite',
      options: options,
    );

    final inputTensor = _interpreter!.getInputTensor(0);
    final outputTensor = _interpreter!.getOutputTensor(0);

    _inputShape = inputTensor.shape;
    _outputShape = outputTensor.shape;
    _inputType = inputTensor.type;
    _outputType = outputTensor.type;

    _inputScale = inputTensor.params.scale;
    _inputZeroPoint = inputTensor.params.zeroPoint;
    _outputScale = outputTensor.params.scale;
    _outputZeroPoint = outputTensor.params.zeroPoint;

    final labelsRaw = await rootBundle.loadString('assets/models/labels.txt');
    _labels = labelsRaw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    try {
      final modelConfigRaw = await rootBundle.loadString(
        'assets/models/model_config.json',
      );
      _modelConfig = ModelConfig.fromJsonString(modelConfigRaw);
    } catch (_) {
      _modelConfig = ModelConfig.defaults();
    }
  }

  Future<PredictionResult> predict(img.Image image) async {
    if (_interpreter == null) {
      return PredictionResult.error(
        'Model not loaded',
        modelVersion: _modelConfig.modelVersion,
      );
    }

    final inputShape = _inputShape;
    final inputType = _inputType ?? TensorType.float32;
    final outputType = _outputType ?? TensorType.float32;

    final fallbackSize = _modelConfig.inputSize;
    final inH = (inputShape != null && inputShape.length >= 3)
        ? inputShape[1]
        : fallbackSize;
    final inW = (inputShape != null && inputShape.length >= 3)
        ? inputShape[2]
        : fallbackSize;

    final resized = img.copyResize(image, width: inW, height: inH);

    final inputObject = _buildInput(resized, inW, inH, inputType);
    final classCount = _getClassCount(_outputShape, _labels.length);
    final outputObject = _buildOutput(classCount, outputType);

    _interpreter!.run(inputObject, outputObject);

    final rawScores = (outputObject[0] as List)
        .map((v) => _asScore(v, outputType))
        .toList();

    if (rawScores.isEmpty) {
      return PredictionResult.error(
        'No output scores',
        modelVersion: _modelConfig.modelVersion,
      );
    }

    if (rawScores.length == 1) {
      final pUnhealthy = _toUnitProbability(rawScores.first);
      final healthyLabel = _labels.isNotEmpty ? _labels.first : 'healthy';
      final unhealthyLabel = _labels.length > 1 ? _labels[1] : 'unhealthy';
      final scores = [1.0 - pUnhealthy, pUnhealthy];
      final labels = [healthyLabel, unhealthyLabel];
      return _buildPrediction(scores, labels);
    }

    final scores = _normalizeScoresIfNeeded(rawScores);
    final labels = _resolveLabels(scores.length);
    return _buildPrediction(scores, labels);
  }

  PredictionResult _buildPrediction(List<double> scores, List<String> labels) {
    var bestIdx = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[bestIdx]) bestIdx = i;
    }

    final predictedClass = labels[bestIdx];
    final confidence = scores[bestIdx].clamp(0.0, 1.0).toDouble();
    final decisionThreshold = _modelConfig.thresholdForClass(predictedClass);

    return PredictionResult(
      predictedClass: predictedClass,
      predictedBinary: _modelConfig.binaryLabelForClass(predictedClass),
      confidence: confidence,
      decisionThreshold: decisionThreshold,
      isUncertain: confidence < decisionThreshold,
      topK: _topK(labels: labels, scores: scores, k: 3),
      modelVersion: _modelConfig.modelVersion,
    );
  }

  List<String> _resolveLabels(int scoreCount) {
    if (_labels.length >= scoreCount) {
      return _labels.take(scoreCount).toList();
    }

    final labels = <String>[..._labels];
    for (var i = labels.length; i < scoreCount; i++) {
      labels.add('class_$i');
    }
    return labels;
  }

  Object _buildInput(
    img.Image resized,
    int inW,
    int inH,
    TensorType inputType,
  ) {
    final elementCount = inW * inH * 3;

    switch (inputType) {
      case TensorType.float32:
        final input = Float32List(elementCount);
        var idx = 0;
        for (var y = 0; y < inH; y++) {
          for (var x = 0; x < inW; x++) {
            final p = resized.getPixel(x, y);
            input[idx++] = _normalizeChannel(p.r.toInt());
            input[idx++] = _normalizeChannel(p.g.toInt());
            input[idx++] = _normalizeChannel(p.b.toInt());
          }
        }
        return input.reshape([1, inH, inW, 3]);

      case TensorType.uint8:
        final input = Uint8List(elementCount);
        var idx = 0;
        for (var y = 0; y < inH; y++) {
          for (var x = 0; x < inW; x++) {
            final p = resized.getPixel(x, y);
            input[idx++] = _toQuantizedByte(_normalizeChannel(p.r.toInt()));
            input[idx++] = _toQuantizedByte(_normalizeChannel(p.g.toInt()));
            input[idx++] = _toQuantizedByte(_normalizeChannel(p.b.toInt()));
          }
        }
        return input.reshape([1, inH, inW, 3]);

      case TensorType.int8:
        final input = Int8List(elementCount);
        var idx = 0;
        for (var y = 0; y < inH; y++) {
          for (var x = 0; x < inW; x++) {
            final p = resized.getPixel(x, y);
            input[idx++] = _toQuantizedInt8(_normalizeChannel(p.r.toInt()));
            input[idx++] = _toQuantizedInt8(_normalizeChannel(p.g.toInt()));
            input[idx++] = _toQuantizedInt8(_normalizeChannel(p.b.toInt()));
          }
        }
        return input.reshape([1, inH, inW, 3]);

      default:
        throw UnsupportedError('Unsupported input tensor type: $inputType');
    }
  }

  List<List<Object>> _buildOutput(int classCount, TensorType outputType) {
    switch (outputType) {
      case TensorType.float32:
        return [List<double>.filled(classCount, 0.0)];
      case TensorType.uint8:
      case TensorType.int8:
      case TensorType.int32:
      case TensorType.int64:
        return [List<int>.filled(classCount, 0)];
      default:
        throw UnsupportedError('Unsupported output tensor type: $outputType');
    }
  }

  int _getClassCount(List<int>? outputShape, int labelsCount) {
    if (outputShape == null || outputShape.isEmpty) {
      return labelsCount > 0 ? labelsCount : 1;
    }
    if (outputShape.length == 1) {
      return outputShape[0] > 0
          ? outputShape[0]
          : (labelsCount > 0 ? labelsCount : 1);
    }
    final last = outputShape.last;
    return last > 0 ? last : (labelsCount > 0 ? labelsCount : 1);
  }

  double _asScore(Object v, TensorType outputType) {
    if (v is double) return v;
    if (v is int) {
      if ((outputType == TensorType.uint8 || outputType == TensorType.int8) &&
          _outputScale > 0) {
        return (v - _outputZeroPoint) * _outputScale;
      }
      return v.toDouble();
    }
    return 0.0;
  }

  double _toUnitProbability(double score) {
    if (score >= 0.0 && score <= 1.0) return score;
    return 1.0 / (1.0 + math.exp(-score));
  }

  List<double> _normalizeScoresIfNeeded(List<double> scores) {
    final allInUnitRange = scores.every((s) => s >= 0.0 && s <= 1.0);
    final sum = scores.fold<double>(0.0, (a, b) => a + b);
    final likelyProbabilities = allInUnitRange && sum > 0.98 && sum < 1.02;
    if (likelyProbabilities) return scores;

    final maxValue = scores.reduce(math.max);
    final expValues = scores.map((s) => math.exp(s - maxValue)).toList();
    final expSum = expValues.fold<double>(0.0, (a, b) => a + b);
    if (expSum == 0) return List<double>.filled(scores.length, 0.0);
    return expValues.map((e) => e / expSum).toList();
  }

  List<ClassScore> _topK({
    required List<String> labels,
    required List<double> scores,
    required int k,
  }) {
    final indexed = <MapEntry<String, double>>[];
    for (var i = 0; i < scores.length; i++) {
      indexed.add(MapEntry(labels[i], scores[i].clamp(0.0, 1.0).toDouble()));
    }
    indexed.sort((a, b) => b.value.compareTo(a.value));

    return indexed
        .take(k)
        .map((e) => ClassScore(label: e.key, score: e.value))
        .toList();
  }

  double _normalizeChannel(int channelValue) {
    final mode = _modelConfig.normalization.replaceAll(' ', '').trim();
    switch (mode) {
      case '[-1,1]':
        return (channelValue / 127.5) - 1.0;
      case '[0,1]':
        return channelValue / 255.0;
      case '[0,255]':
      case '[0,255.0]':
      case 'raw':
      case 'none':
        return channelValue.toDouble();
      default:
        return (channelValue / 127.5) - 1.0;
    }
  }

  int _toQuantizedByte(double normalizedValue) {
    final mode = _modelConfig.normalization.replaceAll(' ', '').trim();
    if (_inputScale > 0) {
      final q = (normalizedValue / _inputScale + _inputZeroPoint).round();
      return q.clamp(0, 255).toInt();
    }

    if (mode == '[0,1]') {
      return (normalizedValue * 255.0).round().clamp(0, 255).toInt();
    }

    if (mode == '[0,255]' ||
        mode == '[0,255.0]' ||
        mode == 'raw' ||
        mode == 'none') {
      return normalizedValue.round().clamp(0, 255).toInt();
    }

    return ((normalizedValue + 1.0) * 127.5).round().clamp(0, 255).toInt();
  }

  int _toQuantizedInt8(double normalizedValue) {
    final mode = _modelConfig.normalization.replaceAll(' ', '').trim();
    if (_inputScale > 0) {
      final q = (normalizedValue / _inputScale + _inputZeroPoint).round();
      return q.clamp(-128, 127).toInt();
    }

    if (mode == '[0,255]' ||
        mode == '[0,255.0]' ||
        mode == 'raw' ||
        mode == 'none') {
      return (normalizedValue - 128.0).round().clamp(-128, 127).toInt();
    }

    if (mode == '[0,1]') {
      return (normalizedValue * 255.0 - 128.0).round().clamp(-128, 127).toInt();
    }

    return (normalizedValue * 127.0).round().clamp(-128, 127).toInt();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

class ClassScore {
  final String label;
  final double score;

  const ClassScore({required this.label, required this.score});

  Map<String, dynamic> toJson() => {'label': label, 'score': score};
}

class ModelConfig {
  final String modelVersion;
  final int inputSize;
  final String normalization;
  final Map<String, double> classThresholds;
  final Map<String, String> binaryMap;

  const ModelConfig({
    required this.modelVersion,
    required this.inputSize,
    required this.normalization,
    required this.classThresholds,
    required this.binaryMap,
  });

  factory ModelConfig.defaults() {
    return const ModelConfig(
      modelVersion: 'lettuce_v2_npk',
      inputSize: 224,
      normalization: '[-1,1]',
      classThresholds: {
        'healthy': 0.62,
        'nitrogen_deficiency': 0.58,
        'phosphorus_deficiency': 0.58,
        'potassium_deficiency': 0.58,
        'fungal_mildew': 0.61,
      },
      binaryMap: {
        'healthy': _defaultBinaryHealthy,
        'nitrogen_deficiency': _defaultBinaryUnhealthy,
        'phosphorus_deficiency': _defaultBinaryUnhealthy,
        'potassium_deficiency': _defaultBinaryUnhealthy,
        'fungal_mildew': _defaultBinaryUnhealthy,
      },
    );
  }

  factory ModelConfig.fromJsonString(String jsonString) {
    final decoded = json.decode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      return ModelConfig.defaults();
    }
    return ModelConfig.fromMap(decoded);
  }

  factory ModelConfig.fromMap(Map<String, dynamic> map) {
    final defaults = ModelConfig.defaults();

    final thresholdsRaw = map['classThresholds'];
    final binaryMapRaw = map['binaryMap'];

    final classThresholds = <String, double>{};
    if (thresholdsRaw is Map) {
      for (final entry in thresholdsRaw.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        final value = entry.value;
        if (value is num) {
          classThresholds[key] = value.toDouble().clamp(0.0, 1.0).toDouble();
        }
      }
    }

    final binaryMap = <String, String>{};
    if (binaryMapRaw is Map) {
      for (final entry in binaryMapRaw.entries) {
        binaryMap[entry.key.toString().trim().toLowerCase()] = entry.value
            .toString()
            .trim();
      }
    }

    return ModelConfig(
      modelVersion: (map['modelVersion'] ?? defaults.modelVersion).toString(),
      inputSize: (map['inputSize'] is num)
          ? (map['inputSize'] as num).toInt()
          : defaults.inputSize,
      normalization: (map['normalization'] ?? defaults.normalization)
          .toString(),
      classThresholds: classThresholds.isEmpty
          ? defaults.classThresholds
          : classThresholds,
      binaryMap: binaryMap.isEmpty ? defaults.binaryMap : binaryMap,
    );
  }

  double thresholdForClass(String classLabel) {
    final key = classLabel.trim().toLowerCase();
    return classThresholds[key] ?? 0.60;
  }

  String binaryLabelForClass(String classLabel) {
    final key = classLabel.trim().toLowerCase();
    final mapped = binaryMap[key];
    if (mapped != null && mapped.isNotEmpty) return mapped;
    if (key == 'healthy') return _defaultBinaryHealthy;
    return _defaultBinaryUnhealthy;
  }
}

class PredictionResult {
  final String predictedClass;
  final String predictedBinary;
  final double confidence;
  final bool isUncertain;
  final double decisionThreshold;
  final List<ClassScore> topK;
  final String modelVersion;

  const PredictionResult({
    required this.predictedClass,
    required this.predictedBinary,
    required this.confidence,
    required this.isUncertain,
    required this.decisionThreshold,
    required this.topK,
    required this.modelVersion,
  });

  factory PredictionResult.error(
    String message, {
    required String modelVersion,
  }) {
    return PredictionResult(
      predictedClass: message,
      predictedBinary: message,
      confidence: 0,
      isUncertain: true,
      decisionThreshold: 1,
      topK: const [],
      modelVersion: modelVersion,
    );
  }

  String get label => predictedBinary;
}
