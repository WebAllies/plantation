import 'package:flutter/material.dart';

class SensorSettingsPage extends StatelessWidget {
  const SensorSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.thermostat),
              title: const Text("Temperature Threshold"),
              subtitle: const Text("Set min/max water temperature alerts"),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.science),
              title: const Text("pH Threshold"),
              subtitle: const Text("Set safe pH range"),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.water_drop),
              title: const Text("Water Level Threshold"),
              subtitle: const Text("Set low water alert level"),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            "Next step: store these thresholds in Firestore (settings/sensors) and use them for alerting.",
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
