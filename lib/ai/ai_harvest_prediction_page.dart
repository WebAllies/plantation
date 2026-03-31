// lib/pages/ai/ai_harvest_prediction_page.dart
//
// ✅ FULL COPY-PASTE PAGE (matches your Firestore fields):
// devices/{deviceId} has: ph, tdsPpm, temperatureC, waterLevelPct, online, rssi...
//
// ✅ Creates history at:
// devices/{deviceId}/harvest_predictions/{autoId}
//
// Add to pubspec.yaml if not already:
// dependencies:
//   cloud_firestore: ^5.0.0
//   intl: ^0.19.0

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AiHarvestPredictionPage extends StatefulWidget {
  const AiHarvestPredictionPage({super.key, required this.deviceId});
  final String deviceId;

  @override
  State<AiHarvestPredictionPage> createState() => _AiHarvestPredictionPageState();
}

class _AiHarvestPredictionPageState extends State<AiHarvestPredictionPage> {
  bool _saving = false;

  // ✅ Lettuce ideal ranges (for aquaponics)
  // pH: 5.8–6.5
  // TDS (ppm): 560–840
  // Water temp: 20–26 °C
  // Water level: >= 60%
  static const double phMin = 5.8, phMax = 6.5;
  static const double tdsMin = 560, tdsMax = 840;
  static const double tempMin = 20, tempMax = 26;
  static const double waterMinPct = 60;

  Map<String, dynamic> _predict(Map<String, dynamic> data) {
    final double ph = (data["ph"] ?? 0).toDouble();
    final double tds = (data["tdsPpm"] ?? 0).toDouble();
    final double temp = (data["temperatureC"] ?? 0).toDouble();
    final double water = (data["waterLevelPct"] ?? 0).toDouble();

    int score = 100;
    final List<String> reasons = [];

    // --- pH scoring ---
    if (ph <= 0) {
      score -= 15;
      reasons.add("pH missing/invalid → prediction reliability reduced");
    } else if (ph < phMin) {
      score -= 15;
      reasons.add("pH is low ($ph) → nutrient uptake may decrease");
    } else if (ph > phMax) {
      score -= 15;
      reasons.add("pH is high ($ph) → growth may slow");
    } else {
      reasons.add("pH is optimal ($ph) → good nutrient absorption");
    }

    // --- TDS scoring ---
    if (tds <= 0) {
      score -= 20;
      reasons.add("TDS missing/invalid → nutrient status unknown");
    } else if (tds < tdsMin) {
      score -= 20;
      reasons.add("Nutrient level low ($tds ppm) → slower growth expected");
    } else if (tds > tdsMax) {
      score -= 10;
      reasons.add("Nutrient level high ($tds ppm) → risk of stress");
    } else {
      reasons.add("Nutrient concentration ideal ($tds ppm)");
    }

    // --- Temperature scoring ---
    if (temp <= 0) {
      score -= 10;
      reasons.add("Temperature missing/invalid");
    } else if (temp < tempMin) {
      score -= 10;
      reasons.add("Water temperature low ($temp°C) → growth slows down");
    } else if (temp > tempMax) {
      score -= 10;
      reasons.add("Water temperature high ($temp°C) → oxygen may drop");
    } else {
      reasons.add("Temperature stable ($temp°C) → healthy root zone");
    }

    // --- Water level scoring ---
    if (water <= 0) {
      score -= 8;
      reasons.add("Water level missing/invalid");
    } else if (water < waterMinPct) {
      score -= 10;
      reasons.add("Water level low ($water%) → system stability risk");
    } else {
      reasons.add("Water level good ($water%)");
    }

    if (score < 0) score = 0;
    if (score > 100) score = 100;

    // --- Map score → days + risk ---
    int predictedDays;
    String riskLevel;
    if (score >= 85) {
      predictedDays = 10 + ((100 - score) ~/ 8); // 10–12-ish
      riskLevel = "OnTrack";
    } else if (score >= 70) {
      predictedDays = 13 + ((84 - score) ~/ 3); // 13–17-ish
      riskLevel = "Risk";
    } else if (score >= 50) {
      predictedDays = 17 + ((69 - score) ~/ 2); // 17–26-ish
      riskLevel = "DelayRisk";
    } else {
      predictedDays = 23 + ((49 - score) ~/ 2); // 23–30-ish
      riskLevel = "HighRisk";
    }

    // --- Yield estimate (grams per plant) ---
    // simple mapping: 120g..240g (approx)
    final int predictedYieldGrams = (120 + score * 1.2).round();

    final DateTime predDate = DateTime.now().add(Duration(days: predictedDays));
    final String predDateStr = DateFormat("yyyy-MM-dd").format(predDate);

    return {
      "score": score,
      "predictedDays": predictedDays,
      "predictedDate": predDateStr,
      "predictedYieldGrams": predictedYieldGrams,
      "riskLevel": riskLevel,
      "reasons": reasons,
    };
  }

  Future<void> _savePrediction({
    required Map<String, dynamic> reading,
    required Map<String, dynamic> prediction,
  }) async {
    setState(() => _saving = true);

    try {
      final docRef = FirebaseFirestore.instance
          .collection("devices")
          .doc(widget.deviceId)
          .collection("harvest_predictions")
          .doc(); // auto id

      await docRef.set({
        "timestamp": FieldValue.serverTimestamp(),

        // snapshot of sensor data (matching your fields)
        "ph": reading["ph"],
        "tdsPpm": reading["tdsPpm"],
        "temperatureC": reading["temperatureC"],
        "waterLevelPct": reading["waterLevelPct"],
        "online": reading["online"],
        "rssi": reading["rssi"],

        // prediction output
        "score": prediction["score"],
        "predictedDays": prediction["predictedDays"],
        "predictedDate": prediction["predictedDate"],
        "predictedYieldGrams": prediction["predictedYieldGrams"],
        "riskLevel": prediction["riskLevel"],
        "reasons": prediction["reasons"],
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Prediction saved to history ✅")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  IconData _riskIcon(String riskLevel) {
    switch (riskLevel) {
      case "OnTrack":
        return Icons.check_circle;
      case "Risk":
        return Icons.warning_amber_rounded;
      case "DelayRisk":
        return Icons.report_problem_rounded;
      case "HighRisk":
        return Icons.error_rounded;
      default:
        return Icons.help_outline;
    }
  }

  String _riskText(String riskLevel) {
    switch (riskLevel) {
      case "OnTrack":
        return "On Track ✅";
      case "Risk":
        return "Slight Delay Risk ⚠️";
      case "DelayRisk":
        return "Delay Risk ⚠️";
      case "HighRisk":
        return "High Risk ❌";
      default:
        return "Unknown";
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceDoc = FirebaseFirestore.instance
        .collection("devices")
        .doc(widget.deviceId);

    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Harvest Prediction"),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: deviceDoc.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text("Device data not found."));
          }

          final reading = snap.data!.data() ?? {};
          final prediction = _predict(reading);

          final String riskLevel = prediction["riskLevel"] as String;
          final IconData icon = _riskIcon(riskLevel);
          final String riskLabel = _riskText(riskLevel);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- Status card ---
              Card(
                child: ListTile(
                  leading: Icon(icon, size: 40),
                  title: Text("Status: $riskLabel"),
                  subtitle: Text("Growth Score: ${prediction["score"]}/100"),
                ),
              ),
              const SizedBox(height: 12),

              // --- Prediction card ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Prediction",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Text("⏳ Days to harvest: ${prediction["predictedDays"]} days"),
                      Text("📅 Predicted harvest date: ${prediction["predictedDate"]}"),
                      Text("⚖️ Estimated yield: ${prediction["predictedYieldGrams"]} g / plant"),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // --- Reasons card ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Why this prediction?",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      ...List<Widget>.from(
                        (prediction["reasons"] as List).map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text("• $e"),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // --- Live sensor snapshot card ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Live Sensor Snapshot (Device: ${widget.deviceId})",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      _kv("pH", reading["ph"]),
                      _kv("TDS (ppm)", reading["tdsPpm"]),
                      _kv("Temperature (°C)", reading["temperatureC"]),
                      _kv("Water Level (%)", reading["waterLevelPct"]),
                      _kv("Online", reading["online"]),
                      _kv("RSSI", reading["rssi"]),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // --- Save button ---
              ElevatedButton.icon(
                onPressed: _saving
                    ? null
                    : () => _savePrediction(
                          reading: reading,
                          prediction: prediction,
                        ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_saving ? "Saving..." : "Save Prediction to History"),
              ),

              const SizedBox(height: 8),
              Text(
                "Tip: Save daily predictions so you can show history + validation in your dissertation.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(String k, dynamic v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text("$k:")),
          Text(v == null ? "-" : v.toString()),
        ],
      ),
    );
  }
}