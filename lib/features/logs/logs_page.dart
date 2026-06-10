import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key, required this.selectedDeviceId});

  final String? selectedDeviceId;

  @override
  Widget build(BuildContext context) {
    if (selectedDeviceId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Logs / History")),
        body: const Center(
          child: Text(
            "No devices found. Flash an ESP32 with a unique DEVICE_ID and connect it.",
          ),
        ),
      );
    }

    final q = FirebaseFirestore.instance
        .collection('devices')
        .doc(selectedDeviceId)
        .collection('logs')
        .orderBy('ts', descending: true)
        .limit(200);

    return Scaffold(
      appBar: AppBar(title: const Text("Logs / History")),
      body: StreamBuilder<QuerySnapshot>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("No logs yet."));

          final fmt = DateFormat('dd MMM yyyy, HH:mm:ss');

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final ts = d['ts'];
              final dt = ts is Timestamp ? ts.toDate() : null;

              final level = (d['level'] ?? 'info').toString();
              final event = (d['event'] ?? '').toString();
              final detail = (d['detail'] ?? '').toString();

              IconData icon = Icons.info_outline;
              if (level == 'warn') icon = Icons.warning_amber_outlined;
              if (level == 'error') icon = Icons.error_outline;

              return Card(
                child: ListTile(
                  leading: Icon(icon),
                  title: Text(event),
                  subtitle: Text(
                    "${dt == null ? '—' : fmt.format(dt)}\n$detail",
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
