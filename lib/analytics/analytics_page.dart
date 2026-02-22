import 'package:flutter/material.dart';
import 'package:iot_aqua_app/core/device/device_selector_header.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Analytics"),
        bottom: const DeviceSelectorHeaderBottom(),
      ),
      body: const Center(child: Text("Data Analytics")),
    );
  }
}
