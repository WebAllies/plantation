import 'package:flutter/material.dart';

class AboutTab extends StatelessWidget {
  const AboutTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Card(
          child: ListTile(
            leading: Icon(Icons.eco),
            title: Text("Smart IoT Aquaponics"),
            subtitle: Text("Dissertation Project — Lettuce Cultivation Monitoring"),
          ),
        ),
        SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text("Version"),
            subtitle: Text("v1.0.0"),
          ),
        ),
        SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.school),
            title: Text("University of Mauritius"),
            subtitle: Text("BSc (Hons) Software Engineering"),
          ),
        ),
      ],
    );
  }
}
