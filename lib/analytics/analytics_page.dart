import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:iot_aqua_app/core/device/device_selection_controller.dart';
import 'package:iot_aqua_app/core/device/device_selector_header.dart';

const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

enum AnalyticsRange { day24, day7, day30, custom }

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key, this.selectedDeviceId});

  final String? selectedDeviceId;

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final DateFormat _timeFormatter = DateFormat('dd MMM yyyy, HH:mm:ss');
  final DateFormat _shortTimeFormatter = DateFormat('HH:mm');
  final DateFormat _shortDateFormatter = DateFormat('dd MMM');

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _alertStateSub;
  Timer? _alertReminderTimer;

  String? _boundDeviceId;
  List<String> _activeAlertMetrics = const [];
  Map<String, dynamic>? _alertStateData;

  AnalyticsRange _selectedRange = AnalyticsRange.day24;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    if (!_isFlutterTest && widget.selectedDeviceId != null) {
      _bindAlertState(widget.selectedDeviceId);
    }
  }

  @override
  void didUpdateWidget(covariant AnalyticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isFlutterTest &&
        oldWidget.selectedDeviceId != widget.selectedDeviceId &&
        widget.selectedDeviceId != null) {
      _bindAlertState(widget.selectedDeviceId);
    }
  }

  @override
  void dispose() {
    _alertStateSub?.cancel();
    _alertReminderTimer?.cancel();
    super.dispose();
  }

  void _bindAlertState(String? deviceId) {
    if (_isFlutterTest) return;
    if (_boundDeviceId == deviceId) return;

    _alertStateSub?.cancel();
    _alertStateSub = null;
    _boundDeviceId = deviceId;
    _activeAlertMetrics = const [];
    _alertStateData = null;
    _syncAlertReminderTimer();

    if (deviceId == null) return;

    _alertStateSub = FirebaseFirestore.instance
        .collection('devices')
        .doc(deviceId)
        .collection('alert_state')
        .doc('current')
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      final rawMetrics = data?['activeMetrics'];
      final metrics = rawMetrics is Iterable
          ? rawMetrics
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList(growable: false)
          : const <String>[];

      if (!mounted) return;
      setState(() {
        _alertStateData = data;
        _activeAlertMetrics = metrics;
      });
      _syncAlertReminderTimer();
    });
  }

  void _syncAlertReminderTimer() {
    if (_activeAlertMetrics.isEmpty) {
      _alertReminderTimer?.cancel();
      _alertReminderTimer = null;
      return;
    }

    if (_alertReminderTimer != null) return;
    _alertReminderTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _activeAlertMetrics.isEmpty) return;
      final labels = _activeAlertMetrics.map(_prettyMetric).join(', ');
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Active sensor alerts: $labels'),
            duration: const Duration(seconds: 3),
          ),
        );
    });
  }

  String _prettyMetric(String metric) {
    switch (metric) {
      case 'temperature':
        return 'Temperature';
      case 'ph':
        return 'pH';
      case 'waterLevel':
        return 'Water Level';
      case 'tds':
        return 'TDS';
      case 'humidity':
        return 'Humidity';
      default:
        return metric;
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return const <String, dynamic>{};
  }

  String _fmtDouble(dynamic value, String unit, {int decimals = 1}) {
    if (value is! num) return '--';
    final text = value.toDouble().toStringAsFixed(decimals);
    return unit.isEmpty ? text : '$text $unit';
  }

  String _latestValueForMetric(String metric) {
    final latestValues = _asMap(_alertStateData?['latestValues']);
    switch (metric) {
      case 'temperature':
        return _fmtDouble(latestValues['temperatureC'], '°C');
      case 'ph':
        return _fmtDouble(latestValues['ph'], 'pH');
      case 'waterLevel':
        return _fmtDouble(latestValues['waterLevelPct'], '%');
      case 'tds':
        return _fmtDouble(latestValues['tdsPpm'], 'ppm');
      case 'humidity':
        return _fmtDouble(latestValues['humidity'], '%');
      default:
        return '--';
    }
  }

  IconData _eventIcon(String eventType) {
    switch (eventType) {
      case 'recovered':
        return Icons.check_circle_outline;
      case 'auto_dose_started':
        return Icons.play_circle_outline;
      case 'auto_dose_completed':
        return Icons.task_alt;
      case 'auto_dose_timeout':
        return Icons.timer_off_outlined;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  Color _eventColor(String eventType) {
    switch (eventType) {
      case 'recovered':
      case 'auto_dose_completed':
        return Colors.green;
      case 'auto_dose_started':
        return Colors.blue;
      case 'auto_dose_timeout':
        return Colors.deepOrange;
      default:
        return Colors.red;
    }
  }

  DateTime get _rangeStart {
    final now = DateTime.now();
    switch (_selectedRange) {
      case AnalyticsRange.day24:
        return now.subtract(const Duration(hours: 24));
      case AnalyticsRange.day7:
        return now.subtract(const Duration(days: 7));
      case AnalyticsRange.day30:
        return now.subtract(const Duration(days: 30));
      case AnalyticsRange.custom:
        return _customRange?.start ?? now.subtract(const Duration(days: 7));
    }
  }

  DateTime get _rangeEnd {
    return _selectedRange == AnalyticsRange.custom
        ? (_customRange?.end ?? DateTime.now())
        : DateTime.now();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
    );

    if (picked != null) {
      setState(() {
        _customRange = picked;
        _selectedRange = AnalyticsRange.custom;
      });
    }
  }

  Future<void> _exportPdf({
    required String deviceId,
    required List<_TelemetryPoint> points,
    required _MetricSummary ph,
    required _MetricSummary tds,
    required _MetricSummary temp,
    required _MetricSummary waterLevel,
  }) async {
    final pdf = pw.Document();
    final rangeText =
        '${DateFormat('dd MMM yyyy').format(_rangeStart)} - ${DateFormat('dd MMM yyyy').format(_rangeEnd)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            'Smart Aquaponics Analytics Report',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Device ID: $deviceId'),
          pw.Text('Period: $rangeText'),
          pw.Text('Generated: ${_timeFormatter.format(DateTime.now())}'),
          pw.SizedBox(height: 18),
          pw.Text(
            'Metric Summary',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['Metric', 'Latest', 'Min', 'Avg', 'Max'],
            data: [
              ['pH', ph.latestText, ph.minText, ph.avgText, ph.maxText],
              ['TDS', tds.latestText, tds.minText, tds.avgText, tds.maxText],
              [
                'Temperature',
                temp.latestText,
                temp.minText,
                temp.avgText,
                temp.maxText
              ],
              [
                'Water Level',
                waterLevel.latestText,
                waterLevel.minText,
                waterLevel.avgText,
                waterLevel.maxText
              ],
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'System Insights',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Bullet(text: 'Total telemetry records analysed: ${points.length}'),
          pw.Bullet(
            text:
                'Active alerts: ${_activeAlertMetrics.isEmpty ? 'None' : _activeAlertMetrics.map(_prettyMetric).join(', ')}',
          ),
          pw.Bullet(text: 'Growth stage: Vegetative (Day 14)'),
          pw.Bullet(text: 'Harvest prediction: 31 days remaining'),
          pw.Bullet(text: 'Overall smart system performance: 85.4%'),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  Future<void> _sharePdf({
    required String deviceId,
    required List<_TelemetryPoint> points,
    required _MetricSummary ph,
    required _MetricSummary tds,
    required _MetricSummary temp,
    required _MetricSummary waterLevel,
  }) async {
    final pdf = pw.Document();
    final rangeText =
        '${DateFormat('dd MMM yyyy').format(_rangeStart)} - ${DateFormat('dd MMM yyyy').format(_rangeEnd)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            'Smart Aquaponics Analytics Report',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Device ID: $deviceId'),
          pw.Text('Period: $rangeText'),
          pw.Text('Generated: ${_timeFormatter.format(DateTime.now())}'),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: ['Metric', 'Latest', 'Min', 'Avg', 'Max'],
            data: [
              ['pH', ph.latestText, ph.minText, ph.avgText, ph.maxText],
              ['TDS', tds.latestText, tds.minText, tds.avgText, tds.maxText],
              [
                'Temperature',
                temp.latestText,
                temp.minText,
                temp.avgText,
                temp.maxText
              ],
              [
                'Water Level',
                waterLevel.latestText,
                waterLevel.minText,
                waterLevel.avgText,
                waterLevel.maxText
              ],
            ],
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          mimeType: 'application/pdf',
          name: 'analytics_report.pdf',
        ),
      ],
      text: 'Smart Aquaponics Analytics Report',
    );
  }

  Widget _activeAlertsCard() {
    final source = (_alertStateData?['effectiveSource'] ?? 'global').toString();

    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active Alerts (${_activeAlertMetrics.length})',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Threshold source: $source',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _activeAlertMetrics
                  .map(
                    (metric) => Chip(
                      backgroundColor: Colors.white,
                      avatar: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red,
                        size: 18,
                      ),
                      label: Text(
                        '${_prettyMetric(metric)}: ${_latestValueForMetric(metric)}',
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rangeSelector() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          _rangeButton('24h', AnalyticsRange.day24),
          _rangeButton('7d', AnalyticsRange.day7),
          _rangeButton('30d', AnalyticsRange.day30),
          _rangeButton('Custom', AnalyticsRange.custom),
        ],
      ),
    );
  }

  Widget _rangeButton(String label, AnalyticsRange range) {
    final selected = _selectedRange == range;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          if (range == AnalyticsRange.custom) {
            await _pickCustomRange();
          } else {
            setState(() => _selectedRange = range);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2E7D32) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 13.5,
            ),
          ),
        ]
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final providerDeviceId =
        context.watch<DeviceSelectionController>().selectedDeviceId;
    final deviceId = widget.selectedDeviceId ?? providerDeviceId;

    if (!_isFlutterTest && deviceId != _boundDeviceId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _bindAlertState(deviceId);
      });
    }

    final alertCutoff =
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 3)));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text(
          'Data Analytics',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        bottom: const DeviceSelectorHeaderBottom(),
        actions: [
          if (deviceId != null)
            IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'PDF export uses the current analytics data below.',
                    ),
                  ),
                );
              },
            ),
          if (deviceId != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Share will work from the current analytics data below.',
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: deviceId == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No device selected. Pick a greenhouse to view analytics.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _isFlutterTest
                  ? null
                  : FirebaseFirestore.instance
                      .collection('devices')
                      .doc(deviceId)
                      .collection('telemetry')
                      .where(
                        'ts',
                        isGreaterThanOrEqualTo:
                            Timestamp.fromDate(_rangeStart),
                      )
                      .orderBy('ts')
                      .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? const [];
                final telemetry = docs
                    .map((d) => _TelemetryPoint.fromMap(d.data()))
                    .where((e) => e.timestamp != null)
                    .toList();

                final phSummary = _MetricSummary.fromTelemetry(
                  telemetry,
                  selector: (e) => e.ph,
                  unit: 'pH',
                  decimals: 1,
                );

                final tdsSummary = _MetricSummary.fromTelemetry(
                  telemetry,
                  selector: (e) => e.tds,
                  unit: 'ppm',
                  decimals: 0,
                );

                final tempSummary = _MetricSummary.fromTelemetry(
                  telemetry,
                  selector: (e) => e.temperature,
                  unit: '°C',
                  decimals: 1,
                );

                final waterLevelSummary = _MetricSummary.fromTelemetry(
                  telemetry,
                  selector: (e) => e.waterLevel,
                  unit: '%',
                  decimals: 0,
                );

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _sectionTitle(
                      'Overview',
                      subtitle:
                          'Monitor pH, TDS, temperature and water level in one place.',
                    ),
                    const SizedBox(height: 14),
                    _rangeSelector(),
                    const SizedBox(height: 16),

                    if (_activeAlertMetrics.isNotEmpty) ...[
                      _activeAlertsCard(),
                      const SizedBox(height: 16),
                    ] else ...[
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: const ListTile(
                          leading: Icon(
                            Icons.check_circle_outline,
                            color: Colors.green,
                          ),
                          title: Text('No active alerts'),
                          subtitle: Text(
                            'All monitored sensor values are within range.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      _AnalyticsMetricCard(
                        title: 'pH Levels',
                        currentValue: phSummary.latestText,
                        trendText: phSummary.trendPercentText,
                        trendUp: phSummary.trendUp,
                        lineColor: const Color(0xFF66BB6A),
                        fillColor: const Color(0xFFDFF3E3),
                        points: phSummary.chartPoints,
                        labels: phSummary.labels,
                        minText: phSummary.minText,
                        avgText: phSummary.avgText,
                        maxText: phSummary.maxText,
                      ),
                      const SizedBox(height: 16),
                      _AnalyticsMetricCard(
                        title: 'TDS',
                        currentValue: tdsSummary.latestText,
                        trendText: tdsSummary.trendPercentText,
                        trendUp: tdsSummary.trendUp,
                        lineColor: const Color(0xFF42A5F5),
                        fillColor: const Color(0xFFD8ECFF),
                        points: tdsSummary.chartPoints,
                        labels: tdsSummary.labels,
                        minText: tdsSummary.minText,
                        avgText: tdsSummary.avgText,
                        maxText: tdsSummary.maxText,
                      ),
                      const SizedBox(height: 16),
                      _AnalyticsMetricCard(
                        title: 'Water Temperature',
                        currentValue: tempSummary.latestText,
                        trendText: tempSummary.trendPercentText,
                        trendUp: tempSummary.trendUp,
                        lineColor: const Color(0xFFFFA726),
                        fillColor: const Color(0xFFFFEBCB),
                        points: tempSummary.chartPoints,
                        labels: tempSummary.labels,
                        minText: tempSummary.minText,
                        avgText: tempSummary.avgText,
                        maxText: tempSummary.maxText,
                      ),
                      const SizedBox(height: 16),
                      _AnalyticsMetricCard(
                        title: 'Water Level',
                        currentValue: waterLevelSummary.latestText,
                        trendText: waterLevelSummary.trendPercentText,
                        trendUp: waterLevelSummary.trendUp,
                        lineColor: const Color(0xFF29B6F6),
                        fillColor: const Color(0xFFD8F2FF),
                        points: waterLevelSummary.chartPoints,
                        labels: waterLevelSummary.labels,
                        minText: waterLevelSummary.minText,
                        avgText: waterLevelSummary.avgText,
                        maxText: waterLevelSummary.maxText,
                      ),
                      const SizedBox(height: 20),

                      _ComparisonCard(
                        onExport: () => _exportPdf(
                          deviceId: deviceId,
                          points: telemetry,
                          ph: phSummary,
                          tds: tdsSummary,
                          temp: tempSummary,
                          waterLevel: waterLevelSummary,
                        ),
                        onShare: () => _sharePdf(
                          deviceId: deviceId,
                          points: telemetry,
                          ph: phSummary,
                          tds: tdsSummary,
                          temp: tempSummary,
                          waterLevel: waterLevelSummary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _GrowthTrackingCard(),
                      const SizedBox(height: 16),
                      const _HarvestPredictionCard(),
                      const SizedBox(height: 16),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Recent Alerts (Last 3 Days)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_isFlutterTest)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('No alert events in the last 3 days.'),
                                )
                              else
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: FirebaseFirestore.instance
                                      .collection('devices')
                                      .doc(deviceId)
                                      .collection('alerts')
                                      .where('createdAt', isGreaterThan: alertCutoff)
                                      .orderBy('createdAt', descending: true)
                                      .limit(30)
                                      .snapshots(),
                                  builder: (context, alertSnap) {
                                    if (alertSnap.connectionState ==
                                            ConnectionState.waiting &&
                                        !alertSnap.hasData) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 20),
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    }

                                    final alertDocs =
                                        alertSnap.data?.docs ?? const [];
                                    if (alertDocs.isEmpty) {
                                      return const Text(
                                        'No alert events in the last 3 days.',
                                      );
                                    }

                                    return ListView.separated(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: alertDocs.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, i) {
                                        final data = alertDocs[i].data();
                                        final ts = data['createdAt'];
                                        final dateTime =
                                            ts is Timestamp ? ts.toDate() : null;
                                        final eventType =
                                            (data['eventType'] ?? '').toString();
                                        final metric =
                                            (data['metric'] ?? '').toString();
                                        final message =
                                            (data['message'] ?? '').toString();

                                        return ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          dense: true,
                                          leading: Icon(
                                            _eventIcon(eventType),
                                            color: _eventColor(eventType),
                                          ),
                                          title: Text(
                                            '${eventType.isEmpty ? 'event' : eventType} · ${metric.isEmpty ? 'metric' : metric}',
                                          ),
                                          subtitle: Text(
                                            '${dateTime == null ? '—' : _timeFormatter.format(dateTime)}\n$message',
                                          ),
                                          isThreeLine: true,
                                        );
                                      },
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

class _TelemetryPoint {
  final DateTime? timestamp;
  final double? ph;
  final double? tds;
  final double? temperature;
  final double? waterLevel;
  final double? phUpTankLevelPct;
  final double? phDownTankLevelPct;
  final double? nutrientTankLevelPct;
  final String? sensorStatus;
  final bool? lastReadOk;
  final int? sampleCount;

  _TelemetryPoint({
    required this.timestamp,
    required this.ph,
    required this.tds,
    required this.temperature,
    required this.waterLevel,
    required this.phUpTankLevelPct,
    required this.phDownTankLevelPct,
    required this.nutrientTankLevelPct,
    required this.sensorStatus,
    required this.lastReadOk,
    required this.sampleCount,
  });

  factory _TelemetryPoint.fromMap(Map<String, dynamic> map) {
    DateTime? ts;
    final rawTs = map['ts'];
    if (rawTs is Timestamp) ts = rawTs.toDate();

    return _TelemetryPoint(
      timestamp: ts,
      ph: (map['ph'] as num?)?.toDouble(),
      tds: (map['tdsPpm'] as num?)?.toDouble(),
      temperature: (map['temperatureC'] as num?)?.toDouble(),
      waterLevel: (map['waterLevelPct'] as num?)?.toDouble(),
      phUpTankLevelPct: (map['phUpTankLevelPct'] as num?)?.toDouble(),
      phDownTankLevelPct: (map['phDownTankLevelPct'] as num?)?.toDouble(),
      nutrientTankLevelPct: (map['nutrientTankLevelPct'] as num?)?.toDouble(),
      sensorStatus: map['sensorStatus']?.toString(),
      lastReadOk: map['lastReadOk'] as bool?,
      sampleCount: (map['sampleCount'] as num?)?.toInt(),
    );
  }
}

class _MetricSummary {
  final double? latest;
  final double? min;
  final double? avg;
  final double? max;
  final String unit;
  final int decimals;
  final List<double> chartPoints;
  final List<String> labels;
  final bool trendUp;
  final String trendPercentText;

  _MetricSummary({
    required this.latest,
    required this.min,
    required this.avg,
    required this.max,
    required this.unit,
    required this.decimals,
    required this.chartPoints,
    required this.labels,
    required this.trendUp,
    required this.trendPercentText,
  });

  static _MetricSummary fromTelemetry(
    List<_TelemetryPoint> items, {
    required double? Function(_TelemetryPoint e) selector,
    required String unit,
    required int decimals,
  }) {
    final filtered = items
        .where((e) => selector(e) != null && e.timestamp != null)
        .toList();

    if (filtered.isEmpty) {
      return _MetricSummary(
        latest: null,
        min: null,
        avg: null,
        max: null,
        unit: unit,
        decimals: decimals,
        chartPoints: const [],
        labels: const [],
        trendUp: true,
        trendPercentText: '0.0%',
      );
    }

    final values = filtered.map((e) => selector(e)!).toList();
    final latest = values.last;
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final avg = values.reduce((a, b) => a + b) / values.length;

    final first = values.first;
    final diff = latest - first;
    final pct = first == 0 ? 0 : (diff / first) * 100;

    final sample = filtered.length <= 8
        ? filtered
        : List.generate(
            8,
            (i) => filtered[((filtered.length - 1) * i / 7).round()],
          );

    return _MetricSummary(
      latest: latest,
      min: min,
      avg: avg,
      max: max,
      unit: unit,
      decimals: decimals,
      chartPoints: sample.map((e) => selector(e) ?? 0).toList(),
      labels: sample
          .map((e) => DateFormat('HH:mm').format(e.timestamp!))
          .toList(),
      trendUp: pct >= 0,
      trendPercentText: '${pct.abs().toStringAsFixed(1)}%',
    );
  }

  String _format(double? value) {
    if (value == null) return '--';
    final text = value.toStringAsFixed(decimals);
    return unit.isEmpty ? text : '$text $unit';
  }

  String get latestText => _format(latest);
  String get minText => _format(min);
  String get avgText => _format(avg);
  String get maxText => _format(max);
}

class _AnalyticsMetricCard extends StatelessWidget {
  const _AnalyticsMetricCard({
    required this.title,
    required this.currentValue,
    required this.trendText,
    required this.trendUp,
    required this.lineColor,
    required this.fillColor,
    required this.points,
    required this.labels,
    required this.minText,
    required this.avgText,
    required this.maxText,
  });

  final String title;
  final String currentValue;
  final String trendText;
  final bool trendUp;
  final Color lineColor;
  final Color fillColor;
  final List<double> points;
  final List<String> labels;
  final String minText;
  final String avgText;
  final String maxText;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: trendUp
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${trendUp ? '↗' : '↘'} $trendText',
                    style: TextStyle(
                      color: trendUp ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(height: 6),
            Text(
              currentValue,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: _MiniLineChart(
                points: points,
                labels: labels,
                lineColor: lineColor,
                fillColor: fillColor,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _MetricInfo(label: 'Min', value: minText, color: Colors.lightBlue)),
                Expanded(child: _MetricInfo(label: 'Avg', value: avgText, color: Colors.grey)),
                Expanded(child: _MetricInfo(label: 'Max', value: maxText, color: Colors.orange)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricInfo extends StatelessWidget {
  const _MetricInfo({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _MiniLineChart extends StatelessWidget {
  const _MiniLineChart({
    required this.points,
    required this.labels,
    required this.lineColor,
    required this.fillColor,
  });

  final List<double> points;
  final List<String> labels;
  final Color lineColor;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(
        child: Text('No telemetry data available for this period.'),
      );
    }

    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _LineChartPainter(
              points: points,
              lineColor: lineColor,
              fillColor: fillColor,
            ),
            child: Container(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels
              .map(
                (e) => Expanded(
                  child: Text(
                    e,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.lineColor,
    required this.fillColor,
  });

  final List<double> points;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPadding = 6.0;
    const rightPadding = 6.0;
    const topPadding = 10.0;
    const bottomPadding = 18.0;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;

    final minVal = points.reduce(math.min);
    final maxVal = points.reduce(math.max);
    final range = (maxVal - minVal).abs() < 0.0001 ? 1.0 : (maxVal - minVal);

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeWidth = 1;

    for (int i = 0; i < 4; i++) {
      final y = topPadding + (chartHeight / 3) * i;
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
    }

    final path = Path();
    final fillPath = Path();
    final dotPaint = Paint()..color = lineColor;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    Offset pointOffset(int index) {
      final x = leftPadding +
          (points.length == 1 ? chartWidth / 2 : (chartWidth * index / (points.length - 1)));
      final normalized = (points[index] - minVal) / range;
      final y = topPadding + chartHeight - (normalized * chartHeight);
      return Offset(x, y);
    }

    final first = pointOffset(0);
    path.moveTo(first.dx, first.dy);
    fillPath.moveTo(first.dx, first.dy);

    for (int i = 1; i < points.length; i++) {
      final p = pointOffset(i);
      path.lineTo(p.dx, p.dy);
      fillPath.lineTo(p.dx, p.dy);
    }

    final last = pointOffset(points.length - 1);
    fillPath
      ..lineTo(last.dx, topPadding + chartHeight)
      ..lineTo(first.dx, topPadding + chartHeight)
      ..close();

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    for (int i = 0; i < points.length; i++) {
      final p = pointOffset(i);
      canvas.drawCircle(p, 5.5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 4.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor;
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.onExport,
    required this.onShare,
  });

  final VoidCallback onExport;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'System Performance',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onExport,
                  icon: const Icon(Icons.download_rounded),
                ),
                IconButton(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _comparisonRow(
              title: 'Yield Quality',
              smart: '9.2/10',
              traditional: '7.8/10',
              percent: '+17.9%',
            ),
            const SizedBox(height: 10),
            _comparisonRow(
              title: 'Energy Efficiency',
              smart: '78.9%',
              traditional: '45.2%',
              percent: '+74.6%',
            ),
            const SizedBox(height: 24),
            const Text(
              'Overall Performance',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            _progressItem('Smart System', 0.854, Colors.green),
            const SizedBox(height: 12),
            _progressItem('Traditional', 0.651, Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _comparisonRow({
    required String title,
    required String smart,
    required String traditional,
    required String percent,
  }) {
    return Row(
      children: [
        const Icon(Icons.eco, color: Colors.green),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  )),
              const SizedBox(height: 4),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 15),
                  children: [
                    TextSpan(
                      text: 'Smart: $smart   ',
                      style: const TextStyle(color: Colors.green),
                    ),
                    TextSpan(
                      text: 'Traditional: $traditional',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            percent,
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w700,
            ),
          ),
        )
      ],
    );
  }

  Widget _progressItem(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${(value * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 12,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _GrowthTrackingCard extends StatelessWidget {
  const _GrowthTrackingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.eco, color: Colors.green),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Growth Tracking',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Lettuce Cultivation Progress',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Day 14',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(height: 22),
            const Row(
              children: [
                Expanded(
                  child: _StageItem(
                    title: 'Seedling',
                    day: 'Day 1',
                    size: '0.5 cm',
                    done: true,
                  ),
                ),
                Expanded(
                  child: _StageItem(
                    title: 'First Leaves',
                    day: 'Day 7',
                    size: '2.1 cm',
                    done: true,
                  ),
                ),
                Expanded(
                  child: _StageItem(
                    title: 'Vegetative',
                    day: 'Day 14',
                    size: '5.8 cm',
                    done: true,
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _StageItem extends StatelessWidget {
  const _StageItem({
    required this.title,
    required this.day,
    required this.size,
    required this.done,
  });

  final String title;
  final String day;
  final String size;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: done ? Colors.green.shade400 : Colors.grey.shade300,
          child: Icon(
            done ? Icons.check : Icons.circle_outlined,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          day,
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            size,
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w700,
            ),
          ),
        )
      ],
    );
  }
}

class _HarvestPredictionCard extends StatelessWidget {
  const _HarvestPredictionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5EA),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.event_available, color: Colors.green),
                SizedBox(width: 10),
                Text(
                  'Harvest Prediction',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Row(
              children: [
                Expanded(
                  child: _PredictionItem(
                    label: 'Expected Date',
                    value: '6/4/2026',
                  ),
                ),
                Expanded(
                  child: _PredictionItem(
                    label: 'Days Remaining',
                    value: '31 days',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: 0.31,
                minHeight: 12,
                backgroundColor: Colors.white,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                '31% Complete',
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _PredictionItem extends StatelessWidget {
  const _PredictionItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.green,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
