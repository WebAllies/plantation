// lib/ai/ai_scan_page.dart
//
// ✅ Full working AI Scan Page (Camera + Capture + TFLite + Save to Firestore)
// Works with your INT8/UINT8 TFLite model (lettuce_model.tflite) + labels.txt
//
// Required pubspec dependencies:
//   camera: ^0.11.0+2
//   image: ^4.2.0
//   tflite_flutter: ^0.10.4
//   firebase_auth: ^5.3.0
//   cloud_firestore: ^5.4.0
//
// Also ensure assets in pubspec.yaml:
// flutter:
//   assets:
//     - assets/models/

import 'dart:io';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;


import 'tflite_service.dart'; // make sure this path is correct in your project

class AiScanPage extends StatefulWidget {
  const AiScanPage({super.key});

  @override
  State<AiScanPage> createState() => _AiScanPageState();
}

class _AiScanPageState extends State<AiScanPage> {
  CameraController? _cam;
  bool _initializing = true;
  bool _predicting = false;

  String _status = "Model not loaded";
  double _confidence = 0.0;

  final _tflite = TfliteService();
  XFile? _lastCapture;

static const double kMinConfidence = 0.60;

String _explanation = "";
String _recommendation = "";

String _explainLabel(String label) {
  final l = label.toLowerCase();
  if (l.contains("healthy")) return "Leaf appears healthy based on the trained model.";
  if (l.contains("unhealthy")) return "Leaf shows patterns that may indicate stress, damage, or disease risk.";
  return "Prediction received from AI model.";
}

String _recommendForLabel(String label, {required double confidence}) {
  if (confidence < kMinConfidence) {
    return "Uncertain result. Retake the photo: good light, close-up, leaf centered, avoid blur.";
  }

  final l = label.toLowerCase();
  if (l.contains("healthy")) {
    return "Maintain stable pH and temperature. Keep monitoring EC and water level for consistency.";
  }
  if (l.contains("unhealthy")) {
    return "Check EC/pH trends, inspect leaf underside, and improve airflow. If symptoms persist, isolate affected plants and review nutrients.";
  }
  return "Verify with sensor readings for confirmation.";
}

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
      _status = "Initializing camera & model...";
      _confidence = 0.0;
    });

    try {
      // 1) Init camera
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

      // 2) Load model
      await _tflite.load();

      setState(() {
        _cam = controller;
        _initializing = false;
        _status = "Ready. Capture a lettuce leaf.";
        _confidence = 0.0;
      });
    } catch (e) {
      setState(() {
        _initializing = false;
        _status = "Camera/model init error: $e";
        _confidence = 0.0;
      });
    }
  }

  Future<void> _captureAndAnalyze() async {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized || _predicting) return;

    setState(() {
      _predicting = true;
      _status = "Capturing...";
      _confidence = 0.0;
    });

    try {
      // Capture photo
      final shot = await cam.takePicture();
      _lastCapture = shot;

      setState(() {
        _status = "Analyzing...";
      });

      // Decode image
      final bytes = await File(shot.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw Exception("Could not decode captured image.");
      }

      // Run inference
      final result = await _tflite.predict(decoded);

      final conf = result.confidence.clamp(0.0, 1.0);

      setState(() {
        _status = (conf < kMinConfidence)
            ? "Uncertain (${result.label})"
            : result.label;

        _confidence = conf;

        _explanation = _explainLabel(result.label);
        _recommendation = _recommendForLabel(result.label, confidence: conf);
      });


      // Save to Firestore for everyone
      await _saveAiScan(label: result.label, confidence: result.confidence);
    } catch (e) {
      setState(() {
        _status = "Scan error: $e";
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

  Future<void> _saveAiScan({
    required String label,
    required double confidence,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Read role from users/{uid}
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final role = (userDoc.data()?['role'] ?? 'Employee').toString();
    final email = (userDoc.data()?['email'] ?? user.email ?? '').toString();

    await FirebaseFirestore.instance.collection('ai_scans').add({
      'userId': user.uid,
      'email': email,
      'role': role,
      'label': label,
      'confidence': confidence,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Lettuce AI Scan"),
        actions: [
          IconButton(
            tooltip: "Reload",
            onPressed: _predicting ? null : _init,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const SizedBox(height: 12),

                // Camera Preview
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

                // Result Card
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
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Confidence: ${(100 * _confidence).toStringAsFixed(1)}%",
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("AI Explanation", style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(_explanation.isEmpty ? "—" : _explanation),
                          const SizedBox(height: 12),
                          const Text("Recommended Action", style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(_recommendation.isEmpty ? "—" : _recommendation),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                const SizedBox(height: 8),

                // Capture Button
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt),
                      label: Text(_predicting ? "Analyzing..." : "Capture & Analyze"),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Tip
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceVariant,
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
                              "Tip: Use good lighting, keep the leaf centered, avoid blur, and try both sides of the leaf.",
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
    );
  }
}
