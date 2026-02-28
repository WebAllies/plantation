import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DevicePage extends StatelessWidget {
  const DevicePage({super.key, required this.selectedDeviceId});

  final String? selectedDeviceId;

  @override
  Widget build(BuildContext context) {
    if (selectedDeviceId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Device Status")),
        body: const Center(
          child: Text(
            "No devices found. Flash an ESP32 with a unique DEVICE_ID and connect it.",
          ),
        ),
      );
    }

    final ref = FirebaseFirestore.instance
        .collection('devices')
        .doc(selectedDeviceId);

    return Scaffold(
      appBar: AppBar(title: const Text("Device Status")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return Center(
              child: Text(
                "Device not found. Create devices/$selectedDeviceId in Firestore.",
              ),
            );
          }

          final d = snap.data!.data() as Map<String, dynamic>;
          final online = (d['online'] ?? false) as bool;
          final rssi = (d['rssi'] ?? 0) as num;
          final ts = d['lastSeen'];
          final dt = ts is Timestamp ? ts.toDate() : null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(
                    online ? Icons.wifi : Icons.wifi_off,
                    color: online ? Colors.green : Colors.red,
                  ),
                  title: Text(online ? "Online" : "Offline"),
                  subtitle: Text("RSSI: ${rssi.toInt()} dBm"),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.access_time),
                  title: const Text("Last Seen"),
                  subtitle: Text(
                    dt == null
                        ? "—"
                        : DateFormat('dd MMM yyyy, HH:mm:ss').format(dt),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.memory),
                  title: Text(d['name']?.toString() ?? "ESP32 Device"),
                  subtitle: Text("Device ID: $selectedDeviceId"),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
