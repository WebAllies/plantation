import 'package:flutter/material.dart';
import 'package:iot_aqua_app/core/device/device_selector_header.dart';
import 'package:iot_aqua_app/ai/my_scan_history_page.dart';

// ✅ NEW: Harvest prediction pages (adjust paths if needed)
import 'ai_harvest_prediction_page.dart';
import 'ai_harvest_history_page.dart';

import 'ai_scan_page.dart';
import 'ai_weather_page.dart';

class AiInsightPage extends StatelessWidget {
  const AiInsightPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Insight"),
        bottom: const DeviceSelectorHeaderBottom(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // ✅ 1) Disease scan
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

            // ✅ 2) Weather AI
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud),
                title: const Text("Weather AI (Forecast Automation)"),
                subtitle: const Text(
                    "Rain → reduce irrigation • Heat → increase circulation"),
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

            // ✅ 3) NEW: Harvest prediction (live)
            Card(
              child: ListTile(
                leading: const Icon(Icons.agriculture),
                title: const Text("AI Harvest Prediction"),
                subtitle: const Text("Uses pH + TDS + Temperature + Water Level"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AiHarvestPredictionPage(
                        deviceId: "esp32_sim_01",
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // ✅ 4) NEW: Harvest prediction history
            Card(
              child: ListTile(
                leading: const Icon(Icons.history_edu),
                title: const Text("Harvest Prediction History"),
                subtitle: const Text("View saved harvest predictions"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AiHarvestHistoryPage(
                        deviceId: "esp32_sim_01",
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // ✅ 5) Disease scan history
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
              "AI modules: Disease Detection • Weather Automation • Harvest Prediction.",
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ Updated AI Engine (matches YOUR sensor fields)
/// devices/{deviceId} fields: ph, tdsPpm, temperatureC, waterLevelPct
class AIEngine {
  static AIResult analyze({
    required double ph,
    required double temperatureC,
    required double waterLevelPct,
    required double tdsPpm,
  }) {
    int score = 100;
    List<String> risks = [];
    List<String> recommendations = [];

    // ✅ Lettuce: pH ~ 5.8–6.5
    if (ph < 5.8 || ph > 6.5) {
      score -= 20;
      risks.add("pH out of ideal range (5.8–6.5).");
      recommendations.add("Use pH up/down valves to stabilize pH.");
    } else {
      recommendations.add("pH is optimal for nutrient absorption.");
    }

    // ✅ Lettuce: temp ~ 20–26°C
    if (temperatureC < 20 || temperatureC > 26) {
      score -= 15;
      risks.add("Water temperature not ideal (20–26°C).");
      recommendations.add("Improve circulation / shading / aeration.");
    } else {
      recommendations.add("Temperature supports healthy growth.");
    }

    // ✅ Water level should be stable (>= 60%)
    if (waterLevelPct < 60) {
      score -= 10;
      risks.add("Water level low (< 60%).");
      recommendations.add("Auto-fill tank (water level valve).");
    } else {
      recommendations.add("Water level is stable.");
    }

    // ✅ Lettuce nutrient (TDS) ~ 560–840 ppm
    if (tdsPpm < 560) {
      score -= 15;
      risks.add("Nutrients low (TDS < 560 ppm).");
      recommendations.add("Increase feeding/nutrient dosing.");
    } else if (tdsPpm > 840) {
      score -= 10;
      risks.add("Nutrients high (TDS > 840 ppm).");
      recommendations.add("Dilute solution / reduce dosing.");
    } else {
      recommendations.add("Nutrient concentration is in good range.");
    }

    if (score < 0) score = 0;
    if (score > 100) score = 100;

    // ✅ Predict harvest days (simple mapping)
    // better score -> fewer days
    int harvestDays;
    if (score >= 85) {
      harvestDays = 10;
    } else if (score >= 70) {
      harvestDays = 14;
    } else if (score >= 50) {
      harvestDays = 20;
    } else {
      harvestDays = 28;
    }

    return AIResult(
      score: score,
      risks: risks,
      recommendations: recommendations,
      harvestDays: harvestDays,
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