import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:iot_aqua_app/ai/superadmin_ai_reports_page.dart';
import 'package:iot_aqua_app/core/device/device_selector_header.dart';

import '../auth/login_page.dart';
import '../sensors/sensor_settings_page.dart';

import 'tabs/profile_tab.dart';
import 'tabs/system_tab.dart';
import 'tabs/about_tab.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  String _role = "employee";
  String _name = "";
  String _email = "";

  // ✅ Normalize role for safety (handles Admin/SuperAdmin vs admin/super_admin)
  String get roleNormalized {
    final r = _role.trim().toLowerCase();
    if (r == "superadmin") return "super_admin";
    if (r == "admin") return "admin";
    if (r == "employee") return "employee";
    return r; // keep custom
  }

  bool get isAdmin =>
      roleNormalized == "admin" || roleNormalized == "super_admin";
  bool get isSuperAdmin => roleNormalized == "super_admin";

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      final data = doc.data() ?? {};

      if (!mounted) return;
      setState(() {
        _role = (data["role"] ?? "employee").toString();
        _name = (data["name"] ?? user.displayName ?? "").toString();
        _email = (data["email"] ?? user.email ?? "").toString();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // ✅ Dynamic tabs
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.person), text: "Profile"),
      const Tab(icon: Icon(Icons.settings), text: "System"),
      if (isAdmin) const Tab(icon: Icon(Icons.sensors), text: "Sensors"),
      if (isSuperAdmin)
        const Tab(icon: Icon(Icons.assessment), text: "Reports"),
      const Tab(icon: Icon(Icons.info_outline), text: "About"),
    ];

    final views = <Widget>[
      ProfileTab(
        name: _name,
        email: _email,
        role: roleNormalized, // pass normalized role
        onLogout: _logout,
      ),
      SystemTab(role: roleNormalized, isSuperAdmin: isSuperAdmin),
      if (isAdmin) const SensorSettingsPage(),

      // ✅ SuperAdmin only: AI Reports page (filters + PDF/CSV export)
      if (isSuperAdmin) const SuperAdminAiReportsPage(),

      const AboutTab(),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Settings"),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(
              kDeviceSelectorHeaderHeight + kTextTabBarHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DeviceSelectorHeaderFromProvider(),
                TabBar(tabs: tabs, isScrollable: true),
              ],
            ),
          ),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}
