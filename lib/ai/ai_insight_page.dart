import 'package:flutter/material.dart';
import 'package:iot_aqua_app/core/device/device_selector_header.dart';
import 'package:iot_aqua_app/ai/my_scan_history_page.dart';

import 'ai_scan_page.dart';
import 'ai_weather_page.dart';

class AiInsightPage extends StatelessWidget {
  const AiInsightPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Insight "),
        bottom: const DeviceSelectorHeaderBottom(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text("Scan Lettuce Leaf"),
                subtitle: const Text("Camera → AI prediction (TFLite)"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AiScanPage()),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud),
                title: const Text("Weather AI (Forecast Automation)"),
                subtitle: const Text("Rain → reduce irrigation • Heat → increase circulation"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AiWeatherPage()),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: const Text("My Scan History"),
                subtitle: const Text("View all my previous AI scans"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyScanHistoryPage(),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),
            const Text(
              "Later we will connect this with real sensor data + disease detection model.",
            ),
          ],
        ),
      ),
    );
  }
}

class AIEngine {
  static AIResult analyze({
    required double ph,
    required double temperature,
    required double waterLevel,
    required double ec,
  }) {
    int score = 100;
    List<String> risks = [];
    List<String> recommendations = [];

    if (ph < 6.0 || ph > 7.2) {
      score -= 20;
      risks.add("pH level out of optimal range.");
      recommendations.add("Adjust nutrient solution to stabilize pH.");
    }

    if (temperature < 22 || temperature > 28) {
      score -= 15;
      risks.add("Water temperature is not optimal.");
      recommendations.add("Adjust shading or aeration.");
    }

    if (waterLevel < 30) {
      score -= 10;
      risks.add("Low water level detected.");
      recommendations.add("Refill water tank.");
    }

    if (ec < 1.4 || ec > 2.2) {
      score -= 10;
      risks.add("Nutrient concentration imbalance.");
      recommendations.add("Adjust nutrient dosage.");
    }

    if (risks.isEmpty) {
      recommendations.add("System operating optimally.");
    }

    int harvestDays = 30 - ((score - 60) ~/ 5);

    return AIResult(
      score: score,
      risks: risks,
      recommendations: recommendations,
      harvestDays: harvestDays.clamp(5, 40),
    );
  }
}

class AIResult {
  final int score;
  final List<String> risks;
  final List<String> recommendations;
  final int harvestDays;

  AIResult({
    required this.score,
    required this.risks,
    required this.recommendations,
    required this.harvestDays,
  });
}

class HealthCard extends StatelessWidget {
  final int score;
  const HealthCard({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    Color color;

    if (score >= 85) {
      color = Colors.green;
    } else if (score >= 60) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              "System Health Score",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "$score%",
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }
}

class Bullet extends StatelessWidget {
  final String text;
  const Bullet({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 8, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
