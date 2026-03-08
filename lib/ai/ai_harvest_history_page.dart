// lib/pages/ai/ai_harvest_history_page.dart
//
// ✅ Harvest prediction history for your device:
// devices/{deviceId}/harvest_predictions
//
// Requires:
// cloud_firestore
// intl

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AiHarvestHistoryPage extends StatelessWidget {
  const AiHarvestHistoryPage({super.key, required this.deviceId});
  final String deviceId;

  Future<void> _deleteOne(BuildContext context, String docId) async {
    await FirebaseFirestore.instance
        .collection("devices")
        .doc(deviceId)
        .collection("harvest_predictions")
        .doc(docId)
        .delete();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Prediction deleted ✅")),
    );
  }

  Future<void> _deleteAll(BuildContext context) async {
    final col = FirebaseFirestore.instance
        .collection("devices")
        .doc(deviceId)
        .collection("harvest_predictions");

    final snap = await col.get();
    final batch = FirebaseFirestore.instance.batch();

    for (final d in snap.docs) {
      batch.delete(d.reference);
    }

    await batch.commit();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("All predictions deleted ✅")),
    );
  }

  String _formatTs(dynamic ts) {
    try {
      if (ts == null) return "-";
      if (ts is Timestamp) {
        return DateFormat("yyyy-MM-dd  HH:mm").format(ts.toDate());
      }
      return ts.toString();
    } catch (_) {
      return "-";
    }
  }

  IconData _riskIcon(String risk) {
    switch (risk) {
      case "OnTrack":
        return Icons.check_circle;
      case "Risk":
        return Icons.warning_amber_rounded;
      case "DelayRisk":
        return Icons.report_problem_rounded;
      case "HighRisk":
        return Icons.error_rounded;
      default:
        return Icons.help_outline;
    }
  }

  String _riskLabel(String risk) {
    switch (risk) {
      case "OnTrack":
        return "On Track ✅";
      case "Risk":
        return "Slight Risk ⚠️";
      case "DelayRisk":
        return "Delay Risk ⚠️";
      case "HighRisk":
        return "High Risk ❌";
      default:
        return "Unknown";
    }
  }

  void _showDetails(BuildContext context, Map<String, dynamic> d) {
    final reasons = (d["reasons"] is List) ? List.from(d["reasons"]) : <dynamic>[];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Prediction Details"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row("Time", _formatTs(d["timestamp"])),
              const SizedBox(height: 8),

              Text("Output", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              _row("Score", "${d["score"] ?? "-"} / 100"),
              _row("Days", "${d["predictedDays"] ?? "-"}"),
              _row("Date", "${d["predictedDate"] ?? "-"}"),
              _row("Yield", "${d["predictedYieldGrams"] ?? "-"} g/plant"),
              _row("Risk", _riskLabel("${d["riskLevel"] ?? ""}")),
              const SizedBox(height: 12),

              Text("Reasons", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              if (reasons.isEmpty) const Text("No reasons saved."),
              ...reasons.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text("• $e"),
                  )),

              const SizedBox(height: 12),
              Text("Sensor Snapshot", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              _row("pH", "${d["ph"] ?? "-"}"),
              _row("TDS (ppm)", "${d["tdsPpm"] ?? "-"}"),
              _row("Temp (°C)", "${d["temperatureC"] ?? "-"}"),
              _row("Water Level (%)", "${d["waterLevelPct"] ?? "-"}"),
              _row("Online", "${d["online"] ?? "-"}"),
              _row("RSSI", "${d["rssi"] ?? "-"}"),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text("$k:")),
          Text(v),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection("devices")
        .doc(deviceId)
        .collection("harvest_predictions")
        .orderBy("timestamp", descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Harvest Prediction History"),
        actions: [
          IconButton(
            tooltip: "Delete all",
            icon: const Icon(Icons.delete_forever),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("Delete all predictions?"),
                  content: const Text("This will remove all saved harvest predictions."),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Cancel"),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("Delete All"),
                    ),
                  ],
                ),
              );

              if (ok == true) {
                await _deleteAll(context);
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text("No harvest predictions saved yet."));
          }

          final docs = snap.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final d = doc.data();

              final risk = "${d["riskLevel"] ?? ""}";
              final icon = _riskIcon(risk);

              return Card(
                child: ListTile(
                  leading: Icon(icon, size: 34),
                  title: Text(
                    "Harvest in ${d["predictedDays"] ?? "-"} days • ${d["predictedYieldGrams"] ?? "-"} g",
                  ),
                  subtitle: Text(
                    "Date: ${d["predictedDate"] ?? "-"}  |  Score: ${d["score"] ?? "-"}  |  ${_formatTs(d["timestamp"])}",
                  ),
                  onTap: () => _showDetails(context, d),
                  trailing: IconButton(
                    tooltip: "Delete",
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await _deleteOne(context, doc.id);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}