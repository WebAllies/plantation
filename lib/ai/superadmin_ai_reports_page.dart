import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:csv/csv.dart';

class SuperAdminAiReportsPage extends StatefulWidget {
  const SuperAdminAiReportsPage({super.key});

  @override
  State<SuperAdminAiReportsPage> createState() =>
      _SuperAdminAiReportsPageState();
}

class _SuperAdminAiReportsPageState
    extends State<SuperAdminAiReportsPage> {
  String? selectedRole;
  String? selectedLabel;
  DateTimeRange? selectedRange;

  List<QueryDocumentSnapshot> _lastFiltered = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Scan Reports"),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt),
            onPressed: _openFilterDialog,
          ),
           IconButton(
            icon: const Icon(Icons.filter_alt),
            onPressed: _openFilterDialog,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == "pdf") _exportPdf();
              if (v == "csv") _exportCsv();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: "pdf", child: Text("Export PDF")),
              PopupMenuItem(value: "csv", child: Text("Export CSV")),
            ],
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("ai_scans")
            .orderBy("createdAt", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          final filtered = _applyFilters(docs);
          _lastFiltered = filtered;

          final total = filtered.length;
          final healthy = filtered
              .where((e) =>
                  (e["label"] ?? "").toString().toLowerCase() ==
                  "healthy")
              .length;
          final unhealthy = filtered
              .where((e) =>
                  (e["label"] ?? "").toString().toLowerCase() ==
                  "unhealthy")
              .length;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildKpis(total, healthy, unhealthy),
                const SizedBox(height: 16),
                _buildScanList(filtered),
              ],
            ),
          );
        },
      ),
    );
  }

  // ===========================
  // FILTER LOGIC
  // ===========================

  List<QueryDocumentSnapshot> _applyFilters(
      List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final role = (doc["role"] ?? "").toString();
      final label = (doc["label"] ?? "").toString();
      final createdAt =
          (doc["createdAt"] as Timestamp?)?.toDate();

      if (selectedRole != null && role != selectedRole) return false;
      if (selectedLabel != null && label != selectedLabel)
        return false;

      if (selectedRange != null && createdAt != null) {
        if (createdAt.isBefore(selectedRange!.start) ||
            createdAt.isAfter(selectedRange!.end)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

Future<void> _exportPdf() async {
  if (_lastFiltered.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No data to export.")),
    );
    return;
  }

  final pdf = pw.Document();
  final now = DateTime.now();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text("AI Scan Report", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text("Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(now)}"),
        pw.SizedBox(height: 12),

        pw.Table.fromTextArray(
          headers: ["Email", "Role", "Label", "Conf(%)", "Date"],
          data: _lastFiltered.map((d) {
            final label = (d["label"] ?? "").toString();
            final role = (d["role"] ?? "").toString();
            final email = (d["email"] ?? "").toString();
            final conf = ((d["confidence"] ?? 0.0) as num).toDouble();
            final dt = (d["createdAt"] as Timestamp?)?.toDate();
            final dateStr = dt == null ? "" : DateFormat('dd MMM yyyy HH:mm').format(dt);

            return [
              email,
              role,
              label,
              (conf * 100).toStringAsFixed(1),
              dateStr,
            ];
          }).toList(),
        ),
      ],
    ),
  );

  await Printing.layoutPdf(onLayout: (format) => pdf.save());
}

Future<void> _exportCsv() async {
  if (_lastFiltered.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No data to export.")),
    );
    return;
  }

  final rows = <List<String>>[
    ["email", "role", "label", "confidence", "createdAt"],
    ..._lastFiltered.map((d) {
      final dt = (d["createdAt"] as Timestamp?)?.toDate();
      return [
        (d["email"] ?? "").toString(),
        (d["role"] ?? "").toString(),
        (d["label"] ?? "").toString(),
        ((d["confidence"] ?? 0.0) as num).toDouble().toString(),
        dt == null ? "" : dt.toIso8601String(),
      ];
    }),
  ];

  final csvStr = const ListToCsvConverter().convert(rows);
  final dir = await getApplicationDocumentsDirectory();
  final file = File("${dir.path}/ai_scan_report_${DateTime.now().millisecondsSinceEpoch}.csv");
  await file.writeAsString(csvStr);

  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text("CSV saved: ${file.path}")),
  );
}

  // ===========================
  // FILTER POPUP
  // ===========================

  void _openFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Filter Reports"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration:
                    const InputDecoration(labelText: "Role"),
                items: const [
                  DropdownMenuItem(
                      value: "admin", child: Text("Admin")),
                  DropdownMenuItem(
                      value: "employee",
                      child: Text("Employee")),
                ],
                onChanged: (v) {
                  setState(() => selectedRole = v);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedLabel,
                decoration:
                    const InputDecoration(labelText: "Label"),
                items: const [
                  DropdownMenuItem(
                      value: "Healthy",
                      child: Text("Healthy")),
                  DropdownMenuItem(
                      value: "Unhealthy",
                      child: Text("Unhealthy")),
                ],
                onChanged: (v) {
                  setState(() => selectedLabel = v);
                },
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2023),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => selectedRange = picked);
                  }
                },
                child: const Text("Select Date Range"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  selectedRole = null;
                  selectedLabel = null;
                  selectedRange = null;
                });
                Navigator.pop(context);
              },
              child: const Text("Clear"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Apply"),
            ),
          ],
        );
      },
    );
  }

  // ===========================
  // KPI CARDS
  // ===========================

  Widget _buildKpis(int total, int healthy, int unhealthy) {
    return Row(
      children: [
        _kpiCard("Total", total.toString(), Icons.fact_check),
        const SizedBox(width: 10),
        _kpiCard("Healthy", healthy.toString(),
            Icons.check_circle),
        const SizedBox(width: 10),
        _kpiCard("Unhealthy", unhealthy.toString(),
            Icons.warning),
      ],
    );
  }

  Widget _kpiCard(String title, String value, IconData icon) {
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon),
              const SizedBox(height: 6),
              Text(title),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================
  // SCAN LIST
  // ===========================

  Widget _buildScanList(
      List<QueryDocumentSnapshot> filtered) {
    return ListView.builder(
      shrinkWrap: true,
      physics:
          const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final doc = filtered[index];
        final dt =
            (doc["createdAt"] as Timestamp?)?.toDate();

        return Card(
          child: ListTile(
            leading: const Icon(Icons.psychology),
            title: Text(
                "${doc["label"]} • ${(doc["confidence"] * 100).toStringAsFixed(1)}%"),
            subtitle: Text(
                "${doc["email"]}\n${doc["role"]} • ${dt != null ? DateFormat('dd MMM yyyy, HH:mm').format(dt) : ""}"),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
