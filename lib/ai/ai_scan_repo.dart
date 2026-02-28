import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'tflite_service.dart';

class AiScanRepo {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Future<void> saveAiScan({
    required PredictionResult prediction,
    String? imagePath,
    String? deviceId,
    String? captureSessionId,
    String? timeOfDay,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final u = await _db.collection('users').doc(user.uid).get();
    final role = (u.data()?['role'] ?? 'Employee').toString();
    final email = (u.data()?['email'] ?? user.email ?? '').toString();

    await _db.collection('ai_scans').add({
      'userId': user.uid,
      'email': email,
      'role': role,

      // Backward compatibility for existing dashboards.
      'label': prediction.predictedBinary,

      'predictedClass': prediction.predictedClass,
      'predictedBinary': prediction.predictedBinary,
      'confidence': prediction.confidence,
      'topK': prediction.topK.map((s) => s.toJson()).toList(),
      'modelVersion': prediction.modelVersion,
      'imagePath': imagePath,

      'verificationStatus': 'pending',
      'verifiedLabel': null,
      'verifiedBy': null,
      'verifiedAt': null,

      'captureMetadata': {
        'farmId': deviceId,
        'deviceId': deviceId,
        'captureSessionId': captureSessionId,
        'timeOfDay': timeOfDay,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
