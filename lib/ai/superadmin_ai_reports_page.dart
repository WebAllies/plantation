import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class SuperAdminAiReportsPage extends StatefulWidget {
  const SuperAdminAiReportsPage({super.key});

  @override
  State<SuperAdminAiReportsPage> createState() =>
      _SuperAdminAiReportsPageState();
}

class _SuperAdminAiReportsPageState extends State<SuperAdminAiReportsPage> {
  static const List<String> _classOptions = [
    'healthy',
    'tipburn',
    'nutrient_deficiency',
    'fungal_mildew',
    'pest_damage',
    'physical_damage',
  ];

  String? selectedRole;
  String? selectedBinary;
  String? selectedVerificationStatus;
  DateTimeRange? selectedRange;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastFiltered = [];

  String _predictedClass(Map<String, dynamic> data) {
    return (data['predictedClass'] ?? data['label'] ?? '').toString();
  }

  String _binaryLabel(Map<String, dynamic> data) {
    final binary = (data['predictedBinary'] ?? data['label'] ?? '').toString();
    if (binary.isNotEmpty) return binary;

    final predictedClass = _predictedClass(data).toLowerCase();
    if (predictedClass == 'healthy') return 'Healthy';
    if (predictedClass.isNotEmpty) return 'Unhealthy';
    return '';
  }

  String _verificationStatus(Map<String, dynamic> data) {
    return (data['verificationStatus'] ?? 'pending').toString();
  }

  double _confidence(Map<String, dynamic> data) {
    final value = data['confidence'];
    if (value is num) return value.toDouble();
    return 0.0;
  }

  DateTime? _createdAt(Map<String, dynamic> data) {
    final ts = data['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final data = doc.data();
      final role = (data['role'] ?? '').toString();
      final binary = _binaryLabel(data);
      final verificationStatus = _verificationStatus(data);
      final createdAt = _createdAt(data);

      if (selectedRole != null &&
          role.toLowerCase() != selectedRole!.toLowerCase()) {
        return false;
      }

      if (selectedBinary != null &&
          binary.toLowerCase() != selectedBinary!.toLowerCase()) {
        return false;
      }

      if (selectedVerificationStatus != null &&
          verificationStatus.toLowerCase() !=
              selectedVerificationStatus!.toLowerCase()) {
        return false;
      }

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export.')));
      return;
    }

    final pdf = pw.Document();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.Text(
            'AI Scan Report',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(now)}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Email',
              'Role',
              'Class',
              'Binary',
              'Conf(%)',
              'Verify',
              'Date',
            ],
            data: _lastFiltered.map((doc) {
              final data = doc.data();
              final dt = _createdAt(data);

              return [
                (data['email'] ?? '').toString(),
                (data['role'] ?? '').toString(),
                _predictedClass(data),
                _binaryLabel(data),
                (_confidence(data) * 100).toStringAsFixed(1),
                _verificationStatus(data),
                dt == null ? '' : DateFormat('dd MMM yyyy HH:mm').format(dt),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export.')));
      return;
    }

    final rows = <List<String>>[
      [
        'email',
        'role',
        'predictedClass',
        'predictedBinary',
        'confidence',
        'verificationStatus',
        'verifiedLabel',
        'modelVersion',
        'createdAt',
      ],
      ..._lastFiltered.map((doc) {
        final data = doc.data();
        final dt = _createdAt(data);
        return [
          (data['email'] ?? '').toString(),
          (data['role'] ?? '').toString(),
          _predictedClass(data),
          _binaryLabel(data),
          _confidence(data).toString(),
          _verificationStatus(data),
          (data['verifiedLabel'] ?? '').toString(),
          (data['modelVersion'] ?? '').toString(),
          dt == null ? '' : dt.toIso8601String(),
        ];
      }),
    ];

    final csvStr = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/ai_scan_report_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(csvStr);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('CSV saved: ${file.path}')));
  }

  void _openFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Filter Reports'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'Employee', child: Text('Employee')),
                  DropdownMenuItem(
                    value: 'SuperAdmin',
                    child: Text('SuperAdmin'),
                  ),
                ],
                onChanged: (v) => setState(() => selectedRole = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedBinary,
                decoration: const InputDecoration(labelText: 'Binary Label'),
                items: const [
                  DropdownMenuItem(value: 'Healthy', child: Text('Healthy')),
                  DropdownMenuItem(
                    value: 'Unhealthy',
                    child: Text('Unhealthy'),
                  ),
                ],
                onChanged: (v) => setState(() => selectedBinary = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedVerificationStatus,
                decoration: const InputDecoration(labelText: 'Verification'),
                items: const [
                  DropdownMenuItem(value: 'pending', child: Text('pending')),
                  DropdownMenuItem(value: 'verified', child: Text('verified')),
                  DropdownMenuItem(value: 'rejected', child: Text('rejected')),
                ],
                onChanged: (v) =>
                    setState(() => selectedVerificationStatus = v),
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
                child: const Text('Select Date Range'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  selectedRole = null;
                  selectedBinary = null;
                  selectedVerificationStatus = null;
                  selectedRange = null;
                });
                Navigator.pop(context);
              },
              child: const Text('Clear'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpis(int total, int healthy, int unhealthy) {
    return Row(
      children: [
        _kpiCard('Total', total.toString(), Icons.fact_check),
        const SizedBox(width: 10),
        _kpiCard('Healthy', healthy.toString(), Icons.check_circle),
        const SizedBox(width: 10),
        _kpiCard('Unhealthy', unhealthy.toString(), Icons.warning),
      ],
    );
  }

  Widget _kpiCard(String title, String value, IconData icon) {
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon),
              const SizedBox(height: 6),
              Text(title),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setVerification({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String status,
    String? verifiedLabel,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await doc.reference.update({
        'verificationStatus': status,
        'verifiedLabel': verifiedLabel,
        'verifiedBy': user?.email ?? user?.uid ?? 'unknown_admin',
        'verifiedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Verification updated: $status')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _openCorrectLabelDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    var selected = _classOptions.first;

    final picked = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Correct Label'),
              content: DropdownButtonFormField<String>(
                initialValue: selected,
                items: _classOptions
                    .map(
                      (c) => DropdownMenuItem<String>(value: c, child: Text(c)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setModalState(() => selected = v);
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null) return;

    await _setVerification(doc: doc, status: 'verified', verifiedLabel: picked);
  }

  Widget _buildScanList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered,
  ) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final doc = filtered[index];
        final data = doc.data();

        final predictedClass = _predictedClass(data);
        final binary = _binaryLabel(data);
        final conf = _confidence(data);
        final verify = _verificationStatus(data);
        final dt = _createdAt(data);

        return Card(
          child: ListTile(
            leading: const Icon(Icons.psychology),
            title: Text(
              '$predictedClass • ${(conf * 100).toStringAsFixed(1)}%',
            ),
            subtitle: Text(
              'Binary: $binary\n'
              'Verify: $verify\n'
              '${(data['email'] ?? '').toString()} • ${(data['role'] ?? '').toString()} • '
              '${dt != null ? DateFormat('dd MMM yyyy, HH:mm').format(dt) : ''}',
            ),
            isThreeLine: true,
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'verify_predicted') {
                  _setVerification(
                    doc: doc,
                    status: 'verified',
                    verifiedLabel: predictedClass,
                  );
                } else if (value == 'correct_label') {
                  _openCorrectLabelDialog(doc);
                } else if (value == 'reject') {
                  _setVerification(
                    doc: doc,
                    status: 'rejected',
                    verifiedLabel: null,
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'verify_predicted',
                  child: Text('Mark verified (predicted)'),
                ),
                PopupMenuItem(
                  value: 'correct_label',
                  child: Text('Correct label...'),
                ),
                PopupMenuItem(value: 'reject', child: Text('Mark rejected')),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Scan Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt),
            onPressed: _openFilterDialog,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'csv') _exportCsv();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
              PopupMenuItem(value: 'csv', child: Text('Export CSV')),
            ],
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('ai_scans')
            .orderBy('createdAt', descending: true)
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
              .where((d) => _binaryLabel(d.data()).toLowerCase() == 'healthy')
              .length;
          final unhealthy = filtered
              .where((d) => _binaryLabel(d.data()).toLowerCase() == 'unhealthy')
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
}
