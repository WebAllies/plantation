import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:iot_aqua_app/core/device/device_selector_header.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({super.key, required this.selectedDeviceId});

  final String? selectedDeviceId;

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  // Local UI state for schedule editing
  int _feedCount = 1; // 1/2/3 times per day
  List<TimeOfDay> _feedTimes = [const TimeOfDay(hour: 8, minute: 0)];
  int _feedDurationSec = 8;

  bool _feedingEnabled = true;

  bool _autoFillEnabled = true;
  int _waterLevelLowPct = 40;
  int _maxFillSec = 120;

  bool _hydratedFromFirestore = false;
  static const int _feederRotations = 2;

  Future<void> _sendCommand({
    required String deviceId,
    required String type,
    bool? targetState,
    int? durationSec,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "";
    final email = user?.email ?? "";

    final cmdRef = FirebaseFirestore.instance
        .collection('devices')
        .doc(deviceId)
        .collection('commands')
        .doc();

    final payload = <String, dynamic>{
      'type': type,
      'status': 'pending',
      'requestedBy': uid,
      'requestedByEmail': email,
      'requestedAt': FieldValue.serverTimestamp(),
      'executedAt': null,
      'message': '',
    };

    if (targetState != null) payload['targetState'] = targetState;
    if (durationSec != null) {
      payload['durationSec'] = durationSec;
      payload['durationMs'] = durationSec * 1000;
    }

    await cmdRef.set(payload);

    // Wait for executed / failed feedback
    late StreamSubscription<DocumentSnapshot> sub;
    sub = cmdRef.snapshots().listen((doc) {
      final data = doc.data();
      if (data is! Map<String, dynamic>) return;

      final status = (data['status'] ?? '').toString();
      if (!mounted) return;

      if (status == 'executed') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${type.toUpperCase()} executed ✅")),
        );
        sub.cancel();
      } else if (status == 'failed') {
        final msg = (data['message'] ?? 'Failed').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${type.toUpperCase()} failed ❌: $msg")),
        );
        sub.cancel();
      }
    });
  }

  Future<void> _setControlMode({
    required String deviceId,
    required String mode, // "manual" or "auto"
  }) async {
    await FirebaseFirestore.instance.collection('devices').doc(deviceId).set({
      'controlMode': mode,
      'controlModeUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Automation mode: ${mode.toUpperCase()}")),
    );
  }

  String _fmt(TimeOfDay t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

  Future<void> _pickTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _feedTimes[index],
    );
    if (picked == null) return;
    setState(() => _feedTimes[index] = picked);
  }

  void _applyFeedCount(int count) {
    setState(() {
      _feedCount = count;
      if (_feedTimes.length < count) {
        while (_feedTimes.length < count) {
          _feedTimes.add(const TimeOfDay(hour: 12, minute: 0));
        }
      } else if (_feedTimes.length > count) {
        _feedTimes = _feedTimes.take(count).toList();
      }
    });
  }

  Future<void> _saveAutomationSettings({required String deviceId}) async {
    final times = _feedTimes.take(_feedCount).map(_fmt).toList();

    await FirebaseFirestore.instance.collection('devices').doc(deviceId).set({
      'automation': {
        'feedingEnabled': _feedingEnabled,
        'feedingTimes': times,
        'feedingDurationSec': _feedDurationSec,
        'autoFillEnabled': _autoFillEnabled,
        'waterLevelLowPct': _waterLevelLowPct,
        'maxFillSec': _maxFillSec,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Automation settings saved ✅")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceId = widget.selectedDeviceId;

    if (deviceId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Control"),
          bottom: const DeviceSelectorHeaderBottom(),
        ),
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
      appBar: AppBar(
        title: const Text("Control"),
        bottom: const DeviceSelectorHeaderBottom(),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        key: ValueKey<String>('control-device-$deviceId'),
        stream: devRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return const Center(child: Text("Device not found"));
          }

          final d = snap.data!.data() as Map<String, dynamic>;

          final relayStates = (d['relayStates'] is Map<String, dynamic>)
              ? (d['relayStates'] as Map<String, dynamic>)
              : <String, dynamic>{};
          final phUpState = relayStates['phUp'] == true;
          final phDownState = relayStates['phDown'] == true;
          final nutrientState = relayStates['nutrient'] == true;
          final fishToFilterState = relayStates['fishToFilter'] == true;
          final feederState = relayStates['fishFeeder'] == true;

          // New fields
          final controlMode = (d['controlMode'] ?? 'manual')
              .toString(); // manual/auto
          final isAuto = controlMode == 'auto';

          // Telemetry (your simulator has it)
          final waterLevelPct = (d['waterLevelPct'] is num)
              ? (d['waterLevelPct'] as num).toDouble()
              : null;

          final automation = (d['automation'] is Map<String, dynamic>)
              ? (d['automation'] as Map<String, dynamic>)
              : <String, dynamic>{};

          // One-time hydrate UI from Firestore (so timepickers show current values)
          if (!_hydratedFromFirestore) {
            final fbFeedEnabled = automation['feedingEnabled'];
            final fbTimes = automation['feedingTimes'];
            final fbDur = automation['feedingDurationSec'];
            final fbAutoFill = automation['autoFillEnabled'];
            final fbLowPct = automation['waterLevelLowPct'];
            final fbMaxFill = automation['maxFillSec'];

            if (fbFeedEnabled is bool) _feedingEnabled = fbFeedEnabled;

            if (fbTimes is List) {
              final parsed = <TimeOfDay>[];
              for (final t in fbTimes) {
                final s = (t ?? '').toString();
                final parts = s.split(':');
                if (parts.length == 2) {
                  final hh = int.tryParse(parts[0]) ?? 8;
                  final mm = int.tryParse(parts[1]) ?? 0;
                  parsed.add(
                    TimeOfDay(hour: hh.clamp(0, 23), minute: mm.clamp(0, 59)),
                  );
                }
              }
              if (parsed.isNotEmpty) {
                _feedTimes = parsed;
                _feedCount = parsed.length.clamp(1, 3);
              }
            }

            if (fbDur is int) _feedDurationSec = fbDur.clamp(1, 120);
            if (fbAutoFill is bool) _autoFillEnabled = fbAutoFill;
            if (fbLowPct is int) _waterLevelLowPct = fbLowPct.clamp(1, 100);
            if (fbMaxFill is int) _maxFillSec = fbMaxFill.clamp(10, 600);

            _hydratedFromFirestore = true;
          }

          final lowThreshold = _waterLevelLowPct.toDouble();
          final isWaterLow = waterLevelPct != null
              ? (waterLevelPct <= lowThreshold)
              : false;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ===== Automation Mode =====
              Card(
                child: SwitchListTile(
                  title: const Text("Full Control Automation"),
                  subtitle: Text(
                    isAuto
                        ? "AUTO mode (Firebase drives relay commands)"
                        : "MANUAL mode (you control relays)",
                  ),
                  value: isAuto,
                  onChanged: (v) => _setControlMode(
                    deviceId: deviceId,
                    mode: v ? 'auto' : 'manual',
                  ),
                ),
              ),

              // ===== Water LOW banner =====
              if (waterLevelPct != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isWaterLow
                          ? Colors.red.withValues(alpha: 0.12)
                          : Colors.green.withValues(alpha: 0.10),
                      border: Border.all(
                        color: isWaterLow ? Colors.red : Colors.green,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isWaterLow ? Icons.warning_amber : Icons.water_drop,
                          color: isWaterLow ? Colors.red : Colors.green,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isWaterLow
                                ? "Water level LOW (${waterLevelPct.toStringAsFixed(1)}%). Auto-fill will trigger in AUTO mode."
                                : "Water level OK (${waterLevelPct.toStringAsFixed(1)}%).",
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: feederState
                                  ? Colors.orange.withValues(alpha: 0.16)
                                  : Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.restaurant,
                              color: feederState
                                  ? Colors.orange.shade800
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Fish Feeder",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  feederState
                                      ? "Dispensing food"
                                      : "$_feederRotations full rotations ready",
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            avatar: Icon(
                              feederState
                                  ? Icons.autorenew
                                  : Icons.check_circle_outline,
                              size: 18,
                            ),
                            label: Text(feederState ? "Running" : "Ready"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: feederState
                              ? null
                              : () => _sendCommand(
                                  deviceId: deviceId,
                                  type: 'fish_feeder',
                                ),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            feederState
                                ? "Feeder running"
                                : "Feed now ($_feederRotations full rotations)",
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ===== Manual Controls =====
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text("Manual Controls"),
                      subtitle: Text(
                        isAuto ? "Disabled (Automation is active)" : "Enabled",
                      ),
                      trailing: Icon(isAuto ? Icons.lock : Icons.tune),
                    ),
                    const Divider(height: 1),

                    SwitchListTile(
                      title: const Text("Fish Tank To Filter Bed"),
                      subtitle: Text(fishToFilterState ? "ON" : "OFF"),
                      value: fishToFilterState,
                      onChanged: isAuto
                          ? null
                          : (v) => _sendCommand(
                              deviceId: deviceId,
                              type: 'fish_to_filter',
                              targetState: v,
                            ),
                    ),

                    SwitchListTile(
                      title: const Text("pH Up Relay"),
                      subtitle: Text(phUpState ? "ON" : "OFF"),
                      value: phUpState,
                      onChanged: isAuto
                          ? null
                          : (v) => _sendCommand(
                              deviceId: deviceId,
                              type: 'ph_up',
                              targetState: v,
                            ),
                    ),
                    SwitchListTile(
                      title: const Text("pH Down Relay"),
                      subtitle: Text(phDownState ? "ON" : "OFF"),
                      value: phDownState,
                      onChanged: isAuto
                          ? null
                          : (v) => _sendCommand(
                              deviceId: deviceId,
                              type: 'ph_down',
                              targetState: v,
                            ),
                    ),
                    SwitchListTile(
                      title: const Text("Nutrient Relay"),
                      subtitle: Text(nutrientState ? "ON" : "OFF"),
                      value: nutrientState,
                      onChanged: isAuto
                          ? null
                          : (v) => _sendCommand(
                              deviceId: deviceId,
                              type: 'nutrient',
                              targetState: v,
                            ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ===== Feeding Schedule =====
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Feeding Schedule",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),

                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Enable scheduled feeding"),
                        value: _feedingEnabled,
                        onChanged: (v) => setState(() => _feedingEnabled = v),
                      ),

                      const SizedBox(height: 8),

                      Row(
                        children: [
                          const Expanded(child: Text("Times per day")),
                          DropdownButton<int>(
                            value: _feedCount,
                            items: const [
                              DropdownMenuItem(value: 1, child: Text("1")),
                              DropdownMenuItem(value: 2, child: Text("2")),
                              DropdownMenuItem(value: 3, child: Text("3")),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              _applyFeedCount(v);
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      ...List.generate(_feedCount, (i) {
                        final t = _feedTimes[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.schedule),
                          title: Text("Time ${i + 1}"),
                          subtitle: Text(_fmt(t)),
                          trailing: TextButton(
                            onPressed: () => _pickTime(i),
                            child: const Text("Change"),
                          ),
                        );
                      }),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _saveAutomationSettings(deviceId: deviceId),
                          icon: const Icon(Icons.save),
                          label: const Text("Save schedule"),
                        ),
                      ),

                      const SizedBox(height: 6),
                      Text(
                        isAuto
                            ? "AUTO mode: ESP32 should execute feeding at these times."
                            : "MANUAL mode: schedule is stored, but ESP32 automation runs only in AUTO mode.",
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ===== Auto Fill Settings =====
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Auto Fill (Tank Refill)",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),

                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Enable auto fill when water is low"),
                        value: _autoFillEnabled,
                        onChanged: (v) => setState(() => _autoFillEnabled = v),
                      ),

                      const SizedBox(height: 8),

                      Row(
                        children: [
                          const Expanded(
                            child: Text("Low water threshold (%)"),
                          ),
                          IconButton(
                            onPressed: () => setState(() {
                              _waterLevelLowPct = (_waterLevelLowPct - 1).clamp(
                                1,
                                100,
                              );
                            }),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            "$_waterLevelLowPct",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() {
                              _waterLevelLowPct = (_waterLevelLowPct + 1).clamp(
                                1,
                                100,
                              );
                            }),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Row(
                        children: [
                          const Expanded(child: Text("Max fill time (sec)")),
                          IconButton(
                            onPressed: () => setState(() {
                              _maxFillSec = (_maxFillSec - 10).clamp(10, 600);
                            }),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            "$_maxFillSec",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() {
                              _maxFillSec = (_maxFillSec + 10).clamp(10, 600);
                            }),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _saveAutomationSettings(deviceId: deviceId),
                          icon: const Icon(Icons.save),
                          label: const Text("Save auto-fill settings"),
                        ),
                      ),

                      const SizedBox(height: 6),
                      Text(
                        "In AUTO mode, ESP32 should open the refill valve when waterLevelPct ≤ threshold.",
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ===== Notes =====
              const Text(
                "How it works",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                "• Manual toggles create a command in devices/{deviceId}/commands\n"
                "• ESP32 executes it and updates status to executed/failed\n"
                "• Feeding schedule + auto-fill are stored in devices/{deviceId}.automation\n"
                "• AUTO mode means ESP32 should run scheduled feeding + auto-fill logic",
              ),
            ],
          );
        },
      ),
    );
  }
}
