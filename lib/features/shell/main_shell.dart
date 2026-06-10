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
import 'package:iot_aqua_app/core/local/nano_usb_bridge_service.dart';
import 'package:iot_aqua_app/features/bridge/nano_usb_bridge_page.dart';
import 'package:iot_aqua_app/features/settings/settings_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  String _role = "employee"; // default
  late final NanoUsbBridgeService _nanoBridgeService;

  @override
  void initState() {
    super.initState();
    _nanoBridgeService = NanoUsbBridgeService();
    _loadRole();
  }

  @override
  void dispose() {
    _nanoBridgeService.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();
      final role = (doc.data()?["role"] ?? "employee").toString();

      if (!mounted) return;
      setState(() => _role = role);
    } catch (_) {
      // Keep default role if Firebase context is not available yet.
    }
  }

  bool get _hasControlTab => (_role == "admin" || _role == "super_admin");

  List<Widget> _pages(String? selectedDeviceId) {
    final list = <Widget>[
      DashboardPage(selectedDeviceId: selectedDeviceId),
      if (_hasControlTab) ControlPage(selectedDeviceId: selectedDeviceId),
      const AiInsightPage(),
      const AnalyticsPage(),
      NanoUsbBridgePage(service: _nanoBridgeService),
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
      const BottomNavigationBarItem(icon: Icon(Icons.usb), label: "Bridge"),
      const BottomNavigationBarItem(
        icon: Icon(Icons.settings),
        label: "Settings",
      ),
    ];
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final selectedDeviceId = context
        .watch<DeviceSelectionController>()
        .selectedDeviceId;
    final pages = _pages(selectedDeviceId);

    // Ensure index stays valid when role loads (e.g. employee has fewer tabs)
    if (_index >= pages.length) _index = 0;

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Esp32StatusStrip(),
          BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            type: BottomNavigationBarType.fixed,
            items: _items,
          ),
        ],
      ),
    );
  }
}

class _Esp32StatusStrip extends StatelessWidget {
  const _Esp32StatusStrip();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DeviceSelectionController>();
    final selectedDeviceId = controller.selectedDeviceId;
    DeviceSummary? selectedDevice;
    for (final device in controller.devices) {
      if (device.id == selectedDeviceId) {
        selectedDevice = device;
        break;
      }
    }

    final theme = Theme.of(context);
    final online = selectedDevice?.online == true;
    final color = online ? const Color(0xFF2E7D32) : const Color(0xFFD84315);
    final lastSeen = _formatLastSeen(selectedDevice?.lastSeen);
    final label = selectedDevice == null
        ? 'ESP32: No device selected'
        : 'ESP32 ${online ? 'Online' : 'Offline'}';

    return Material(
      color: theme.colorScheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Icon(
                online ? Icons.wifi : Icons.wifi_off,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$label  •  Last seen: $lastSeen',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatLastSeen(DateTime? value) {
    if (value == null) return '--';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
