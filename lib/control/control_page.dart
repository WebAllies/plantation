import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({super.key, required this.selectedDeviceId});

  final String? selectedDeviceId;

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  Future<void> _sendCommand({
    required String deviceId,
    required String type,
    required bool targetState,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "";
    final email = user?.email ?? "";

    final cmdRef = FirebaseFirestore.instance
        .collection('devices')
        .doc(deviceId)
        .collection('commands')
        .doc(); // auto id

    await cmdRef.set({
      'type': type,
      'targetState': targetState,
      'status': 'pending',
      'requestedBy': uid,
      'requestedByEmail': email,
      'requestedAt': FieldValue.serverTimestamp(),
      'executedAt': null,
      'message': '',
    });

    // Wait for executed feedback (simple: listen once)
    // Wait for executed feedback
    late StreamSubscription<DocumentSnapshot> sub;

    sub = cmdRef.snapshots().listen((doc) {
      final data = doc.data();
      if (data is! Map<String, dynamic>) return;

      final status = (data['status'] ?? '').toString();

      if (status == 'executed') {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${type.toUpperCase()} executed ✅")),
        );

        sub.cancel();
      }

      if (status == 'failed') {
        if (!mounted) return;

        final msg = (data['message'] ?? 'Failed').toString();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${type.toUpperCase()} failed ❌: $msg")),
        );

        sub.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final deviceId = widget.selectedDeviceId;
    if (deviceId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Control")),
        body: const Center(
          child: Text(
            "No devices found. Flash an ESP32 with a unique DEVICE_ID and connect it.",
          ),
        ),
      );
    }

    final devRef = FirebaseFirestore.instance
        .collection('devices')
        .doc(deviceId);

    return Scaffold(
      appBar: AppBar(title: const Text("Control")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: devRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return const Center(child: Text("Device not found"));
          }

          final d = snap.data!.data() as Map<String, dynamic>;
          final pumpState = (d['pumpState'] ?? false) as bool;
          final valveState = (d['valveState'] ?? false) as bool;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: SwitchListTile(
                  title: const Text("Pump"),
                  subtitle: Text(pumpState ? "ON" : "OFF"),
                  value: pumpState,
                  onChanged: (v) => _sendCommand(
                    deviceId: deviceId,
                    type: 'pump',
                    targetState: v,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  title: const Text("Valve"),
                  subtitle: Text(valveState ? "OPEN" : "CLOSED"),
                  value: valveState,
                  onChanged: (v) => _sendCommand(
                    deviceId: deviceId,
                    type: 'valve',
                    targetState: v,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Feedback",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                "When you toggle, the command is saved as pending. ESP32 executes it and updates the command to executed.",
              ),
            ],
          );
        },
      ),
    );
  }
}
