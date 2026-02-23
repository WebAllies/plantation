import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import 'package:iot_aqua_app/core/device/device_selection_controller.dart';

import 'tflite_service.dart';

class AiScanPage extends StatefulWidget {
  const AiScanPage({super.key});

  @override
  State<AiScanPage> createState() => _AiScanPageState();
}

class _AiScanPageState extends State<AiScanPage> {
  CameraController? _cam;
  bool _initializing = true;
  bool _predicting = false;

  String _status = 'Model not loaded';
  String _predictedClass = '';
  String _predictedBinary = '';
  String _modelVersion = '';

  double _confidence = 0.0;
  double _decisionThreshold = 0.60;

  String _explanation = '';
  String _recommendation = '';

  List<ClassScore> _topK = const [];

  final _tflite = TfliteService();
  final String _captureSessionId = DateTime.now()
      .toUtc()
      .millisecondsSinceEpoch
      .toString();

  XFile? _lastCapture;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _cam?.dispose();
    _tflite.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _initializing = true;
      _status = 'Initializing camera & model...';
      _confidence = 0.0;
      _decisionThreshold = 0.60;
      _predictedClass = '';
      _predictedBinary = '';
      _modelVersion = '';
      _topK = const [];
    });

    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      if (!mounted) return;

      await _tflite.load();

      setState(() {
        _cam = controller;
        _initializing = false;
        _status = 'Ready. Capture a lettuce leaf.';
      });
    } catch (e) {
      setState(() {
        _initializing = false;
        _status = 'Camera/model init error: $e';
      });
    }
  }

  Future<void> _captureAndAnalyze() async {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized || _predicting) return;
    final selectedDeviceId = _selectedDeviceIdFromContext();

    setState(() {
      _predicting = true;
      _status = 'Capturing...';
      _confidence = 0.0;
    });

    try {
      final shot = await cam.takePicture();
      _lastCapture = shot;

      setState(() {
        _status = 'Analyzing...';
      });

      final bytes = await File(shot.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw Exception('Could not decode captured image.');
      }

      final result = await _tflite.predict(decoded);
      final conf = result.confidence.clamp(0.0, 1.0).toDouble();

      setState(() {
        _predictedClass = result.predictedClass;
        _predictedBinary = result.predictedBinary;
        _modelVersion = result.modelVersion;
        _confidence = conf;
        _decisionThreshold = result.decisionThreshold;
        _topK = result.topK;

        _status = result.isUncertain
            ? 'Uncertain (${result.predictedClass})'
            : result.predictedClass;

        _explanation = _explainClass(result.predictedClass);
        _recommendation = _recommendForClass(
          result.predictedClass,
          isUncertain: result.isUncertain,
        );
      });

      if (result.topK.isNotEmpty) {
        await _saveAiScan(
          result: result,
          capture: shot,
          selectedDeviceId: selectedDeviceId,
        );
      }
    } catch (e) {
      setState(() {
        _status = 'Scan error: $e';
        _confidence = 0.0;
      });
    } finally {
      if (mounted) {
        setState(() {
          _predicting = false;
        });
      }
    }
  }

  String _explainClass(String predictedClass) {
    switch (predictedClass.toLowerCase()) {
      case 'healthy':
        return 'Leaf texture and color look healthy for the trained class set.';
      case 'tipburn':
        return 'Detected leaf-edge burn pattern consistent with tipburn stress.';
      case 'nutrient_deficiency':
        return 'Detected discoloration pattern that may indicate nutrient imbalance.';
      case 'fungal_mildew':
        return 'Detected surface pattern similar to fungal or mildew infection.';
      case 'pest_damage':
        return 'Detected marks and tissue loss pattern associated with pest damage.';
      case 'physical_damage':
        return 'Detected tears/bruising pattern likely from handling or mechanical damage.';
      default:
        return 'Prediction received from AI model.';
    }
  }

  String _recommendForClass(
    String predictedClass, {
    required bool isUncertain,
  }) {
    if (isUncertain) {
      return 'Uncertain result. Retake with stable light, close-up focus, full leaf in frame, and no blur.';
    }

    switch (predictedClass.toLowerCase()) {
      case 'healthy':
        return 'Maintain stable pH/EC/temperature and continue routine monitoring.';
      case 'tipburn':
        return 'Check calcium availability, reduce heat stress, and improve airflow around canopy.';
      case 'nutrient_deficiency':
        return 'Review EC and nutrient mix, then inspect new leaves over 24-48 hours for recovery.';
      case 'fungal_mildew':
        return 'Inspect leaf underside, isolate affected plants, and improve humidity/airflow control.';
      case 'pest_damage':
        return 'Inspect both leaf surfaces and nearby plants, then apply integrated pest control actions.';
      case 'physical_damage':
        return 'Review handling workflow and tooling; monitor if new growth remains unaffected.';
      default:
        return 'Cross-check this prediction with sensor trends before acting.';
    }
  }

  Future<void> _saveAiScan({
    required PredictionResult result,
    required XFile capture,
    required String? selectedDeviceId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final role = (userDoc.data()?['role'] ?? 'Employee').toString();
    final email = (userDoc.data()?['email'] ?? user.email ?? '').toString();

    final scans = FirebaseFirestore.instance.collection('ai_scans');
    final scanDoc = scans.doc();

    final imagePath = await _uploadCapture(
      capture: capture,
      uid: user.uid,
      scanId: scanDoc.id,
    );

    final now = DateTime.now();

    await scanDoc.set({
      'userId': user.uid,
      'email': email,
      'role': role,

      // Backward-compat fields
      'label': result.predictedBinary,

      // New inference fields
      'predictedClass': result.predictedClass,
      'predictedBinary': result.predictedBinary,
      'confidence': result.confidence,
      'topK': result.topK.map((s) => s.toJson()).toList(),
      'modelVersion': result.modelVersion,
      'imagePath': imagePath,

      // Verification lifecycle
      'verificationStatus': 'pending',
      'verifiedLabel': null,
      'verifiedBy': null,
      'verifiedAt': null,

      // Capture metadata for retraining
      'captureMetadata': {
        'farmId': selectedDeviceId,
        'deviceId': selectedDeviceId,
        'captureSessionId': _captureSessionId,
        'timeOfDay': _timeOfDay(now),
      },

      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String?> _uploadCapture({
    required XFile capture,
    required String uid,
    required String scanId,
  }) async {
    try {
      final ref = FirebaseStorage.instance.ref('ai_scans/$uid/$scanId.jpg');
      await ref.putFile(
        File(capture.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return ref.fullPath;
    } catch (_) {
      return null;
    }
  }

  String _timeOfDay(DateTime dt) {
    final hour = dt.hour;
    if (hour < 6) return 'night';
    if (hour < 12) return 'morning';
    if (hour < 18) return 'afternoon';
    return 'evening';
  }

  String? _selectedDeviceIdFromContext() {
    try {
      return context.read<DeviceSelectionController>().selectedDeviceId;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lettuce AI Scan'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _predicting ? null : _init,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: cam?.value.aspectRatio ?? (3 / 4),
                        child: cam == null || !cam.value.isInitialized
                            ? Container(
                                color: Colors.black12,
                                alignment: Alignment.center,
                                child: Text(
                                  _status,
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : CameraPreview(cam),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.psychology),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _status,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Class: ${_predictedClass.isEmpty ? '—' : _predictedClass}',
                                  ),
                                  Text(
                                    'Binary: ${_predictedBinary.isEmpty ? '—' : _predictedBinary}',
                                  ),
                                  Text(
                                    'Confidence: ${(100 * _confidence).toStringAsFixed(1)}% '
                                    '(threshold ${(100 * _decisionThreshold).toStringAsFixed(1)}%)',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.black54),
                                  ),
                                  if (_modelVersion.isNotEmpty)
                                    Text(
                                      'Model: $_modelVersion',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.black54),
                                    ),
                                ],
                              ),
                            ),
                            if (_lastCapture != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(_lastCapture!.path),
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AI Explanation',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text(_explanation.isEmpty ? '—' : _explanation),
                            const SizedBox(height: 12),
                            const Text(
                              'Recommended Action',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _recommendation.isEmpty ? '—' : _recommendation,
                            ),
                            if (_topK.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const Text(
                                'Top Predictions',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              ..._topK.map(
                                (s) => Text(
                                  '${s.label}: ${(100 * s.score).toStringAsFixed(1)}%',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _predicting ? null : _captureAndAnalyze,
                        icon: _predicting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.camera_alt),
                        label: Text(
                          _predicting ? 'Analyzing...' : 'Capture & Analyze',
                        ),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      elevation: 0,
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.lightbulb_outline),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Tip: use stable light, keep full leaf in frame, avoid blur, and capture both sides if possible.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
    );
  }
}
