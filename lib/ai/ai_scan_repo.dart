import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AiScanRepo {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Future<void> saveAiScan({
    required String label,
    required double confidence,
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
      'label': label,
      'confidence': confidence,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
