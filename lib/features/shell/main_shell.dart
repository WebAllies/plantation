import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

// صفحاتك (بدّلهم بصفحاتك الحقيقية)

import 'package:iot_aqua_app/ai/ai_insight_page.dart';
import 'package:iot_aqua_app/analytics/analytics_page.dart';
import 'package:iot_aqua_app/control/control_page.dart';
import 'package:iot_aqua_app/dashboard/dashboard_page.dart';
import 'package:iot_aqua_app/core/device/device_selection_controller.dart';
import 'package:iot_aqua_app/features/settings/settings_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  String _role = "employee"; // default

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();
    final role = (doc.data()?["role"] ?? "employee").toString();

    if (!mounted) return;
    setState(() => _role = role);
  }

  bool get _hasControlTab => (_role == "admin" || _role == "super_admin");

  List<Widget> _pages(String? selectedDeviceId) {
    final list = <Widget>[
      DashboardPage(selectedDeviceId: selectedDeviceId),
      if (_hasControlTab) ControlPage(selectedDeviceId: selectedDeviceId),
      const AiInsightPage(),
      const AnalyticsPage(),
      const SettingsPage(),
    ];
    return list;
  }

  List<BottomNavigationBarItem> get _items {
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.dashboard),
        label: "Dashboard",
      ),
      if (_hasControlTab)
        const BottomNavigationBarItem(icon: Icon(Icons.tune), label: "Control"),
      const BottomNavigationBarItem(
        icon: Icon(Icons.psychology),
        label: "AI Insight",
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.bar_chart),
        label: "Analytics",
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.settings),
        label: "Settings",
      ),
    ];
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final deviceController = context.watch<DeviceSelectionController>();
    final selectedDeviceId = deviceController.selectedDeviceId;
    final pages = _pages(selectedDeviceId);

    // Ensure index stays valid when role loads (e.g. employee has fewer tabs)
    if (_index >= pages.length) _index = 0;

    return Scaffold(
      body: Column(
        children: [
          _DevicePickerBar(
            loading: deviceController.isLoading,
            error: deviceController.error,
            devices: deviceController.devices,
            selectedDeviceId: selectedDeviceId,
            onChanged: deviceController.selectDevice,
          ),
          Expanded(child: pages[_index]),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: _items,
      ),
    );
  }
}

class _DevicePickerBar extends StatelessWidget {
  const _DevicePickerBar({
    required this.loading,
    required this.error,
    required this.devices,
    required this.selectedDeviceId,
    required this.onChanged,
  });

  final bool loading;
  final String? error;
  final List<DeviceSummary> devices;
  final String? selectedDeviceId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    if (error != null) {
      return Material(
        color: Colors.red.shade50,
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: const Text("Device list unavailable"),
          subtitle: Text(error!),
        ),
      );
    }

    if (devices.isEmpty) {
      return Material(
        color: Colors.amber.shade50,
        child: const ListTile(
          leading: Icon(Icons.sensors_off),
          title: Text("No devices found"),
          subtitle: Text(
            "Flash an ESP32 with a unique DEVICE_ID and connect it to Firebase.",
          ),
        ),
      );
    }

    final selected = selectedDeviceId ?? devices.first.id;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.memory),
            const SizedBox(width: 10),
            const Text("Device: "),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: devices
                    .map(
                      (d) => DropdownMenuItem<String>(
                        value: d.id,
                        child: Text(
                          "${d.name} (${d.id})${d.online ? " • online" : ""}",
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onChanged(value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
