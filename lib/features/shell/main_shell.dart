import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// صفحاتك (بدّلهم بصفحاتك الحقيقية)

import 'package:iot_aqua_app/ai/ai_insight_page.dart';
import 'package:iot_aqua_app/analytics/analytics_page.dart';
import 'package:iot_aqua_app/control/control_page.dart';
import 'package:iot_aqua_app/dashboard/dashboard_page.dart';
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

    final doc = await FirebaseFirestore.instance.collection("users").doc(user.uid).get();
    final role = (doc.data()?["role"] ?? "employee").toString();

    if (!mounted) return;
    setState(() => _role = role);
  }

  bool get _hasControlTab => (_role == "admin" || _role == "super_admin");

  List<Widget> get _pages {
    final list = <Widget>[
      const DashboardPage(),
      if (_hasControlTab) const ControlPage(),
      const AiInsightPage(),
      const AnalyticsPage(),
      const SettingsPage(),
    ];
    return list;
  }

  List<BottomNavigationBarItem> get _items {
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Dashboard"),
      if (_hasControlTab)
        const BottomNavigationBarItem(icon: Icon(Icons.tune), label: "Control"),
      const BottomNavigationBarItem(icon: Icon(Icons.psychology), label: "AI Insight"),
      const BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Analytics"),
      const BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
    ];
    return items;
  }

  @override
  Widget build(BuildContext context) {
    // Ensure index stays valid when role loads (e.g. employee has fewer tabs)
    if (_index >= _pages.length) _index = 0;

    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: _items,
      ),
    );
  }
}
