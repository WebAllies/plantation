import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:iot_aqua_app/main.dart'; // for themeController
import 'package:iot_aqua_app/pages/manage_roles_page.dart';
import 'package:iot_aqua_app/pages/super_admin_dashboard.dart';

class SystemTab extends StatefulWidget {
  final String role; // "Super Admin" | "Admin" | "Employee"
  final bool isSuperAdmin;

  const SystemTab({super.key, required this.role, required this.isSuperAdmin});

  @override
  State<SystemTab> createState() => _SystemTabState();
}

class _SystemTabState extends State<SystemTab> {
  bool _busy = false;

  // Settings stored in Firestore: system/settings
  bool _enableNotifications = true;
  bool _autoMode = true;
  bool _maintenanceMode = false;
  bool _emergencyAlertsEnabled = true; // ON by default

  // Match your Firestore screenshot
  final String _defaultDeviceId = "esp32_sim_01";

  @override
  void initState() {
    super.initState();
    _loadSystemSettings();
  }

  bool get _isSuperAdmin => widget.role.toLowerCase().contains("super");
  bool get _isAdmin =>
      widget.role.toLowerCase().contains("admin") || _isSuperAdmin;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return "—";
    final y = dt.year.toString().padLeft(4, "0");
    final m = dt.month.toString().padLeft(2, "0");
    final d = dt.day.toString().padLeft(2, "0");
    final hh = dt.hour.toString().padLeft(2, "0");
    final mm = dt.minute.toString().padLeft(2, "0");
    return "$y-$m-$d  $hh:$mm";
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  Future<void> _loadSystemSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection("system")
          .doc("settings")
          .get();

      final data = doc.data() ?? {};
      if (!mounted) return;

      setState(() {
        _enableNotifications = (data["enableNotifications"] is bool)
            ? data["enableNotifications"] as bool
            : true;
        _autoMode =
            (data["autoMode"] is bool) ? data["autoMode"] as bool : true;
        _maintenanceMode = (data["maintenanceMode"] is bool)
            ? data["maintenanceMode"] as bool
            : false;
        _emergencyAlertsEnabled = (data["emergencyAlertsEnabled"] is bool)
            ? data["emergencyAlertsEnabled"] as bool
            : true;
      });
    } catch (_) {
      // keep defaults
    }
  }

  Future<void> _saveSystemSettings({
    bool? enableNotifications,
    bool? autoMode,
    bool? maintenanceMode,
    bool? emergencyAlertsEnabled,
  }) async {
    try {
      setState(() => _busy = true);

      await FirebaseFirestore.instance
          .collection("system")
          .doc("settings")
          .set({
            if (enableNotifications != null)
              "enableNotifications": enableNotifications,
            if (autoMode != null) "autoMode": autoMode,
            if (maintenanceMode != null) "maintenanceMode": maintenanceMode,
            if (emergencyAlertsEnabled != null)
              "emergencyAlertsEnabled": emergencyAlertsEnabled,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": FirebaseAuth.instance.currentUser?.uid ?? "unknown",
          }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast("Failed: $e");
    }
  }

  Future<void> _sendDeviceCommand({
    required String type, // "pump" | "valve"
    required bool targetState,
  }) async {
    if (!_isAdmin) {
      _toast("Not allowed for this role.");
      return;
    }

    try {
      setState(() => _busy = true);

      final uid = FirebaseAuth.instance.currentUser?.uid ?? "unknown";
      final email = FirebaseAuth.instance.currentUser?.email ?? "unknown";

      await FirebaseFirestore.instance
          .collection("devices")
          .doc(_defaultDeviceId)
          .collection("commands")
          .add({
            "type": type,
            "targetState": targetState,
            "status": "pending",
            "requestedBy": uid,
            "requestedByEmail": email,
            "requestedAt": FieldValue.serverTimestamp(),
          });

      if (!mounted) return;
      setState(() => _busy = false);
      _toast("Command sent ✅ ($type = ${targetState ? "ON" : "OFF"})");
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast("Failed: $e");
    }
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w900)),
      );

  Widget _miniCard({required Widget child}) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _miniCard(
          child: Row(
            children: [
              const Icon(Icons.badge),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "System Role",
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(widget.role),
                  ],
                ),
              ),
              if (_isSuperAdmin) const Chip(label: Text("Super Admin")),
              if (!_isSuperAdmin && _isAdmin) const Chip(label: Text("Admin")),
              if (!_isAdmin) const Chip(label: Text("Employee")),
            ],
          ),
        ),

        const SizedBox(height: 12),

        _sectionTitle("System Status"),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("system")
              .doc("status")
              .snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? {};
            final online = (data["cloudOnline"] is bool)
                ? data["cloudOnline"] as bool
                : true;
            final lastSync = (data["lastSyncAt"] is Timestamp)
                ? (data["lastSyncAt"] as Timestamp).toDate()
                : null;
            final env = (data["environment"] is String)
                ? data["environment"] as String
                : "prod";

            return _miniCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(online ? Icons.cloud_done : Icons.cloud_off),
                    title: Text("Cloud: ${online ? "Connected" : "Offline"}"),
                    subtitle: Text("Last Sync: ${_fmt(lastSync)}"),
                  ),
                  const Divider(),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.settings_applications),
                    title: const Text("Environment"),
                    subtitle: Text(env),
                  ),
                  if (_maintenanceMode)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        "⚠ Maintenance Mode is ON (some functions may be disabled).",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        _sectionTitle("Devices (IoT Monitoring)"),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("devices")
              .limit(10)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return _miniCard(
                child: Row(
                  children: const [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text("Loading devices..."),
                  ],
                ),
              );
            }

            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return _miniCard(
                child: const Text(
                  "No devices found. Add documents in devices/{deviceId}.",
                ),
              );
            }

            return _miniCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < docs.length; i++) ...[
                    _DeviceTile(deviceId: docs[i].id, data: docs[i].data(), fmt: _fmt),
                    if (i != docs.length - 1) const Divider(),
                  ],
                  const SizedBox(height: 6),
                  const Text(
                    "Tip: recommended fields: online, lastSeenAt, firmware, ip, wifiRssi",
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        _sectionTitle("Live Emergency Alert State"),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("devices")
              .doc(_defaultDeviceId)
              .collection("alert_state")
              .doc("current")
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return _miniCard(
                child: Row(
                  children: const [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text("Loading live alert state..."),
                  ],
                ),
              );
            }

            final data = snap.data?.data() ?? {};
            final activeMetricsRaw = data["activeMetrics"];
            final activeMetrics = activeMetricsRaw is List
                ? activeMetricsRaw.map((e) => e.toString()).toList()
                : <String>[];

            final latestValues = (data["latestValues"] is Map<String, dynamic>)
                ? data["latestValues"] as Map<String, dynamic>
                : <String, dynamic>{};

            final metrics = (data["metrics"] is Map<String, dynamic>)
                ? data["metrics"] as Map<String, dynamic>
                : <String, dynamic>{};

            final effectiveSource = (data["effectiveSource"] is String)
                ? data["effectiveSource"] as String
                : "—";

            return _miniCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      activeMetrics.isNotEmpty
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                    ),
                    title: Text(
                      activeMetrics.isNotEmpty
                          ? "Emergency detected"
                          : "No active emergency",
                    ),
                    subtitle: Text("Device: $_defaultDeviceId"),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.source_outlined),
                    title: const Text("Effective Source"),
                    subtitle: Text(effectiveSource),
                  ),
                  if (activeMetrics.isNotEmpty) const Divider(),
                  if (activeMetrics.isNotEmpty)
                    ...activeMetrics.map((metric) {
                      final metricData = metrics[metric];
                      String state = "abnormal";
                      if (metricData is Map && metricData["state"] != null) {
                        state = metricData["state"].toString();
                      }

                      dynamic currentValue;
                      switch (metric) {
                        case "temperature":
                          currentValue = latestValues["temperatureC"];
                          break;
                        case "tds":
                          currentValue = latestValues["tdsPpm"];
                          break;
                        case "waterLevel":
                          currentValue = latestValues["waterLevelPct"];
                          break;
                        default:
                          currentValue = latestValues[metric];
                      }

                      return Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.error_outline),
                            title: Text(_prettyMetric(metric)),
                            subtitle: Text(
                              "State: ${state.toUpperCase()}\nCurrent value: ${currentValue ?? "—"}",
                            ),
                            isThreeLine: true,
                          ),
                          const Divider(),
                        ],
                      );
                    }),
                  Text(
                    activeMetrics.isNotEmpty
                        ? "Emergency popup and vibration work globally only if you connect the watcher outside this page."
                        : "System is currently within normal range.",
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        _sectionTitle("Automation & Schedules"),
        _miniCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.autorenew),
                title: const Text("Auto Mode"),
                subtitle: const Text(
                  "Automatic valve/pump actions using schedules",
                ),
                value: _autoMode,
                onChanged: (_isAdmin && !_busy)
                    ? (v) async {
                        setState(() => _autoMode = v);
                        await _saveSystemSettings(autoMode: v);
                      }
                    : null,
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text("Schedules"),
                subtitle: const Text(
                  "Next run time + recent executions (connect to your schedule collection)",
                ),
                onTap: () {
                  _toast(
                    "If you share your schedule Firestore structure, I'll connect this fully.",
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        if (_isAdmin) ...[
          _sectionTitle("Quick Controls (Admin)"),
          _miniCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Send a manual command to device (writes to Firestore commands).",
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _sendDeviceCommand(
                                  type: "pump",
                                  targetState: true,
                                ),
                        icon: const Icon(Icons.water),
                        label: const Text("Pump ON"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _sendDeviceCommand(
                                  type: "pump",
                                  targetState: false,
                                ),
                        icon: const Icon(Icons.water_drop_outlined),
                        label: const Text("Pump OFF"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _sendDeviceCommand(
                                  type: "valve",
                                  targetState: true,
                                ),
                        icon: const Icon(Icons.tune),
                        label: const Text("Valve OPEN"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _sendDeviceCommand(
                                  type: "valve",
                                  targetState: false,
                                ),
                        icon: const Icon(Icons.close),
                        label: const Text("Valve CLOSE"),
                      ),
                    ),
                  ],
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        _sectionTitle("Logs & Diagnostics"),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("devices")
              .doc(_defaultDeviceId)
              .collection("logs")
              .orderBy("ts", descending: true)
              .limit(8)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return _miniCard(
                child: Row(
                  children: const [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text("Loading logs..."),
                  ],
                ),
              );
            }

            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return _miniCard(
                child: const Text(
                  "No logs yet. ESP32 should write to devices/{deviceId}/logs.",
                ),
              );
            }

            return _miniCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < docs.length; i++) ...[
                    _LogTile(data: docs[i].data(), fmt: _fmt),
                    if (i != docs.length - 1) const Divider(),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    "Showing latest logs for $_defaultDeviceId",
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  if (_isAdmin)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _toast(
                                "Next: export logs CSV/PDF (I can add this).",
                              ),
                      icon: const Icon(Icons.download),
                      label: const Text("Export Logs"),
                    ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        _sectionTitle("Alert History"),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("devices")
              .doc(_defaultDeviceId)
              .collection("alerts")
              .orderBy("createdAt", descending: true)
              .limit(8)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return _miniCard(
                child: Row(
                  children: const [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text("Loading alert history..."),
                  ],
                ),
              );
            }

            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return _miniCard(
                child: const Text("No alert history found."),
              );
            }

            return _miniCard(
              child: Column(
                children: [
                  for (int i = 0; i < docs.length; i++) ...[
                    _AlertHistoryTile(data: docs[i].data(), fmt: _fmt),
                    if (i != docs.length - 1) const Divider(),
                  ],
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        _sectionTitle("AI Module"),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("system")
              .doc("ai")
              .snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? {};
            final model = (data["modelName"] is String)
                ? data["modelName"] as String
                : "Leaf Health Classifier";
            final version = (data["modelVersion"] is String)
                ? data["modelVersion"] as String
                : "v1.0";
            final f1 = data["f1Score"];
            final lastUsed = (data["lastInferenceAt"] is Timestamp)
                ? (data["lastInferenceAt"] as Timestamp).toDate()
                : null;

            return _miniCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.psychology),
                    title: Text(model),
                    subtitle: Text("Version: $version"),
                  ),
                  const Divider(),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.analytics),
                    title: const Text("Quality Metrics"),
                    subtitle: Text(
                      "F1-score: ${f1 == null ? "—" : f1.toString()}",
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timelapse),
                    title: const Text("Last AI Scan"),
                    subtitle: Text(_fmt(lastUsed)),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        if (_isSuperAdmin) ...[
          _sectionTitle("Super Admin Tools"),
          _miniCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text("User Management"),
                  subtitle: const Text("Create Admin / Employee accounts"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SuperAdminSettingsPage(),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.groups_2_outlined),
                  title: const Text("Roles & App PIN Reset"),
                  subtitle: const Text(
                    "Manage roles and force PIN reset for users",
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManageRolesPage(),
                      ),
                    );
                  },
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.build_circle),
                  title: const Text("Maintenance Mode"),
                  subtitle: const Text(
                    "Disable critical actions for all users (demo-worthy)",
                  ),
                  value: _maintenanceMode,
                  onChanged: _busy
                      ? null
                      : (v) async {
                          setState(() => _maintenanceMode = v);
                          await _saveSystemSettings(maintenanceMode: v);
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (_isAdmin && !_isSuperAdmin) ...[
          _sectionTitle("Admin Tools"),
          _miniCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.groups_2_outlined),
              title: const Text("App PIN Reset"),
              subtitle: const Text("Reset user app PIN and security lock"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageRolesPage()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],

        _sectionTitle("App Preferences"),
        _miniCard(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.warning_amber_rounded),
                title: const Text("Emergency Alerts"),
                subtitle: Text(
                  _isAdmin
                      ? "Blocking emergency popup + vibration + 2-minute snooze"
                      : "Enabled by system administrators",
                ),
                value: _emergencyAlertsEnabled,
                onChanged: (_isAdmin && !_busy)
                    ? (v) async {
                        setState(() => _emergencyAlertsEnabled = v);
                        await _saveSystemSettings(emergencyAlertsEnabled: v);
                        _toast(
                          "Emergency alerts ${v ? "enabled" : "disabled"}",
                        );
                      }
                    : null,
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.notifications_active),
                title: const Text("Enable Notifications"),
                subtitle: const Text(
                  "Alerts for pH, temperature, water level, etc.",
                ),
                value: _enableNotifications,
                onChanged: _busy
                    ? null
                    : (v) async {
                        setState(() => _enableNotifications = v);
                        await _saveSystemSettings(enableNotifications: v);
                        _toast("Saved ✅");
                      },
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.dark_mode),
                title: const Text("Dark Mode"),
                subtitle: const Text("Switch app theme"),
                value: themeController.isDark,
                onChanged: (v) async {
                  await themeController.setDark(v);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        _sectionTitle("About"),
        _miniCard(
          child: Column(
            children: const [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text("IoT Aqua App"),
                subtitle: Text(
                  "Smart Aquaponics System • ATOL Case Study • Firebase + ESP32 + AI",
                ),
              ),
              Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.verified_user_outlined),
                title: Text("Security"),
                subtitle: Text("Role-based access control + audit-ready logs"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _prettyMetric(String metric) {
    switch (metric) {
      case 'ph':
        return 'pH';
      case 'tds':
        return 'TDS';
      case 'temperature':
        return 'Temperature';
      case 'waterLevel':
        return 'Water Level';
      default:
        return metric;
    }
  }
}

class _DeviceTile extends StatelessWidget {
  final String deviceId;
  final Map<String, dynamic> data;
  final String Function(DateTime?) fmt;

  const _DeviceTile({
    required this.deviceId,
    required this.data,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final online = (data["online"] is bool) ? data["online"] as bool : false;
    final lastSeen = (data["lastSeenAt"] is Timestamp)
        ? (data["lastSeenAt"] as Timestamp).toDate()
        : null;
    final firmware =
        (data["firmware"] is String) ? data["firmware"] as String : "—";
    final ip = (data["ip"] is String) ? data["ip"] as String : "—";
    final rssi = data["wifiRssi"] ?? data["rssi"];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(online ? Icons.wifi : Icons.wifi_off),
      title: Text(deviceId),
      subtitle: Text(
        "Status: ${online ? "Online" : "Offline"}\n"
        "Last seen: ${fmt(lastSeen)}\n"
        "Firmware: $firmware  •  IP: $ip  •  RSSI: ${rssi == null ? "—" : rssi.toString()}",
      ),
      isThreeLine: true,
    );
  }
}

class _LogTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String Function(DateTime?) fmt;

  const _LogTile({required this.data, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final ts = (data["ts"] is Timestamp)
        ? (data["ts"] as Timestamp).toDate()
        : null;
    final level = (data["level"] is String) ? data["level"] as String : "info";
    final event = (data["event"] is String) ? data["event"] as String : "event";
    final detail =
        (data["detail"] is String) ? data["detail"] as String : "";

    IconData icon;
    if (level == "error") {
      icon = Icons.error_outline;
    } else if (level == "warn") {
      icon = Icons.warning_amber_outlined;
    } else {
      icon = Icons.info_outline;
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text("$event • $level"),
      subtitle: Text("${fmt(ts)}\n$detail"),
      isThreeLine: true,
    );
  }
}

class _AlertHistoryTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String Function(DateTime?) fmt;

  const _AlertHistoryTile({required this.data, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final createdAt = (data["createdAt"] is Timestamp)
        ? (data["createdAt"] as Timestamp).toDate()
        : null;
    final eventType = (data["eventType"] is String)
        ? data["eventType"] as String
        : "event";
    final message =
        (data["message"] is String) ? data["message"] as String : "—";
    final metric = (data["metric"] is String) ? data["metric"] as String : "—";
    final state = (data["state"] is String) ? data["state"] as String : "—";

    IconData icon;
    if (eventType == "breach_started") {
      icon = Icons.warning_amber_rounded;
    } else if (eventType == "recovered") {
      icon = Icons.check_circle_outline;
    } else {
      icon = Icons.info_outline;
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text("$eventType • $metric"),
      subtitle: Text("${fmt(createdAt)}\nState: $state\n$message"),
      isThreeLine: true,
    );
  }
}