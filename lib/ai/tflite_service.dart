import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class TfliteService {
  Interpreter? _interpreter;
  List<String> _labels = [];

  List<int>? _inputShape;
  List<int>? _outputShape;
  TensorType? _inputType;
  TensorType? _outputType;
  double _outputScale = 0.0;
  int _outputZeroPoint = 0;

  Future<void> load() async {
    try {
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
      _outputScale = outputTensor.params.scale;
      _outputZeroPoint = outputTensor.params.zeroPoint;

      final labelsRaw = await rootBundle.loadString('assets/models/labels.txt');
      _labels = labelsRaw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<PredictionResult> predict(img.Image image) async {
    if (_interpreter == null) {
      return const PredictionResult(label: 'Model not loaded', confidence: 0);
    }

    final inputShape = _inputShape;
    final inputType = _inputType ?? TensorType.float32;
    final outputType = _outputType ?? TensorType.float32;

    final inH = (inputShape != null && inputShape.length >= 3) ? inputShape[1] : 224;
    final inW = (inputShape != null && inputShape.length >= 3) ? inputShape[2] : 224;

    final resized = img.copyResize(image, width: inW, height: inH);

    final inputObject = _buildInput(resized, inW, inH, inputType);
    final classCount = _getClassCount(_outputShape);
    final outputObject = _buildOutput(classCount, outputType);

    _interpreter!.run(inputObject, outputObject);

    final rawScores = (outputObject[0] as List)
        .map((v) => _asScore(v, outputType))
        .toList();

    if (rawScores.isEmpty) {
      return const PredictionResult(label: 'No output scores', confidence: 0);
    }

    if (rawScores.length == 1) {
      final pUnhealthy = rawScores.first.clamp(0.0, 1.0);
      final label = (pUnhealthy >= 0.5)
          ? (_labels.length > 1 ? _labels[1] : 'Unhealthy')
          : (_labels.isNotEmpty ? _labels[0] : 'Healthy');
      final confidence = pUnhealthy >= 0.5 ? pUnhealthy : (1.0 - pUnhealthy);
      return PredictionResult(label: label, confidence: confidence);
    }

    final scores = _normalizeScoresIfNeeded(rawScores);

    var bestIdx = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[bestIdx]) bestIdx = i;
    }

    final label = bestIdx < _labels.length ? _labels[bestIdx] : 'Class $bestIdx';
    final confidence = scores[bestIdx].clamp(0.0, 1.0);
    return PredictionResult(label: label, confidence: confidence);
  }

  Object _buildInput(img.Image resized, int inW, int inH, TensorType inputType) {
    final elementCount = inW * inH * 3;

    switch (inputType) {
      case TensorType.float32:
        final input = Float32List(elementCount);
        var idx = 0;
        for (var y = 0; y < inH; y++) {
          for (var x = 0; x < inW; x++) {
            final p = resized.getPixel(x, y);
            input[idx++] = (p.r.toDouble() / 127.5) - 1.0;
            input[idx++] = (p.g.toDouble() / 127.5) - 1.0;
            input[idx++] = (p.b.toDouble() / 127.5) - 1.0;
          }
        }
        return input.reshape([1, inH, inW, 3]);

      case TensorType.uint8:
        final input = Uint8List(elementCount);
        var idx = 0;
        for (var y = 0; y < inH; y++) {
          for (var x = 0; x < inW; x++) {
            final p = resized.getPixel(x, y);
            input[idx++] = p.r.toInt().clamp(0, 255);
            input[idx++] = p.g.toInt().clamp(0, 255);
            input[idx++] = p.b.toInt().clamp(0, 255);
          }
        }
        return input.reshape([1, inH, inW, 3]);

      case TensorType.int8:
        final input = Int8List(elementCount);
        var idx = 0;
        for (var y = 0; y < inH; y++) {
          for (var x = 0; x < inW; x++) {
            final p = resized.getPixel(x, y);
            input[idx++] = (p.r.toInt() - 128).clamp(-128, 127);
            input[idx++] = (p.g.toInt() - 128).clamp(-128, 127);
            input[idx++] = (p.b.toInt() - 128).clamp(-128, 127);
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

  int _getClassCount(List<int>? outputShape) {
    if (outputShape == null || outputShape.isEmpty) return 1;
    if (outputShape.length == 1) return outputShape[0];
    return outputShape.last;
  }

  double _asScore(Object v, TensorType outputType) {
    if (v is double) return v;
    if (v is int) {
      if ((outputType == TensorType.uint8 || outputType == TensorType.int8) && _outputScale > 0) {
        return (v - _outputZeroPoint) * _outputScale;
      }
      return v.toDouble();
    }
    return 0.0;
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

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

class PredictionResult {
  final String label;
  final double confidence;

  const PredictionResult({required this.label, required this.confidence});
}
