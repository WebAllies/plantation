import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class AiWeatherPage extends StatefulWidget {
  const AiWeatherPage({super.key});

  @override
  State<AiWeatherPage> createState() => _AiWeatherPageState();
}

class _AiWeatherPageState extends State<AiWeatherPage> {
  // ✅ device id (you can later replace with your device selector value)
  static const String kDeviceId = "esp32_sim_01";

  // ✅ WeatherAPI key (Option B)
  static const String kWeatherApiKey = "94bebc8d802a466a90f160222262702";

  final TextEditingController _locationCtrl =
      TextEditingController(text: "Mauritius");

  bool _loading = false;
  String? _error;

  WeatherSnapshot? _latest;

  // thresholds
  double rainChanceThreshold = 60; // %
  double rainMmThreshold = 5; // mm
  double highTempThreshold = 30; // °C

  // ✅ Auto mode
  bool _autoModeEnabled = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _autoModeSub;
  DateTime? _lastAutoRunAt;

  @override
  void initState() {
    super.initState();
    _bindAutoMode();
    _loadCachedThenFetch();
  }

  @override
  void dispose() {
    _autoModeSub?.cancel();
    _locationCtrl.dispose();
    super.dispose();
  }

  // ---------- Firestore refs ----------
  DocumentReference<Map<String, dynamic>> _cacheDoc() {
    return FirebaseFirestore.instance
        .collection("devices")
        .doc(kDeviceId)
        .collection("weather")
        .doc("latest");
  }

  DocumentReference<Map<String, dynamic>> _autoModeDoc() {
    return FirebaseFirestore.instance
        .collection("devices")
        .doc(kDeviceId)
        .collection("settings")
        .doc("automation");
  }

  CollectionReference<Map<String, dynamic>> _schedulerLogsRef() {
    return FirebaseFirestore.instance
        .collection("devices")
        .doc(kDeviceId)
        .collection("scheduler_logs");
  }

  CollectionReference<Map<String, dynamic>> _commandsRef() {
    return FirebaseFirestore.instance
        .collection("devices")
        .doc(kDeviceId)
        .collection("commands");
  }

  // ---------- Auto mode binding ----------
void _bindAutoMode() {
  _autoModeSub?.cancel();
  _autoModeSub = _autoModeDoc().snapshots().listen(
    (snap) {
      final enabled = (snap.data()?["enabled"] == true);
      if (!mounted) return;
      setState(() => _autoModeEnabled = enabled);
    },
    onError: (e) {
      if (!mounted) return;
      setState(() => _autoModeEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No permission for Auto Mode settings."),
        ),
      );
    },
  );
}

  Future<void> _setAutoMode(bool enabled) async {
    final email = FirebaseAuth.instance.currentUser?.email ?? "unknown";
    await _autoModeDoc().set({
      "enabled": enabled,
      "updatedAt": FieldValue.serverTimestamp(),
      "updatedBy": email,
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() => _autoModeEnabled = enabled);

    // Optional: run immediately if turned on and we already have forecast
    if (enabled && _latest != null) {
      await _runAutoIfEnabled(_latest!);
    }
  }

  // ---------- Load cache then fetch ----------
  Future<void> _loadCachedThenFetch() async {
    final snap = await _cacheDoc().get();
    if (snap.exists && snap.data() != null) {
      setState(() => _latest = WeatherSnapshot.fromFirestore(snap.data()!));
    }
    await _fetchWeather();
  }

  // ---------- Fetch weather ----------
  Future<void> _fetchWeather() async {
    final loc = _locationCtrl.text.trim();
    if (loc.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        "https://api.weatherapi.com/v1/forecast.json"
        "?key=$kWeatherApiKey"
        "&q=${Uri.encodeComponent(loc)}"
        "&days=1"
        "&aqi=no&alerts=no",
      );

      final res = await http.get(uri);
      if (res.statusCode != 200) {
        throw Exception("WeatherAPI error: ${res.statusCode} ${res.body}");
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final snapshot = WeatherSnapshot.fromWeatherApi(data);

      // ✅ cache latest
      await _cacheDoc().set(snapshot.toFirestore(), SetOptions(merge: true));

      // ✅ save history for analytics
      await FirebaseFirestore.instance
          .collection("devices")
          .doc(kDeviceId)
          .collection("weather_history")
          .add({
        "ts": FieldValue.serverTimestamp(),
        "locationName": snapshot.locationName,
        "maxTempC": snapshot.maxTempC,
        "chanceOfRain": snapshot.chanceOfRain,
        "precipMm": snapshot.totalPrecipMm,
        "source": "WeatherAPI",
      });

      if (!mounted) return;
      setState(() => _latest = snapshot);

      // ✅ run auto if enabled (anti-spam inside)
      await _runAutoIfEnabled(snapshot);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            "Failed to fetch weather. Showing cached data (if any).\n$e";
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ---------- Decision rules ----------
  WeatherDecision _decide(WeatherSnapshot w) {
    final actions = <WeatherAction>[];

    final rainExpected = (w.chanceOfRain >= rainChanceThreshold) ||
        (w.totalPrecipMm >= rainMmThreshold);

    final heatExpected = w.maxTempC >= highTempThreshold;

    if (rainExpected) {
      actions.add(
        WeatherAction(
          title: "Reduce irrigation",
          detail:
              "Rain likely (${w.chanceOfRain.toStringAsFixed(0)}% / ${w.totalPrecipMm.toStringAsFixed(1)}mm). Reduce/stop irrigation.",
          commandType: "fish_to_filter",
          targetState: false,
        ),
      );
    }

    if (heatExpected) {
      actions.add(
        WeatherAction(
          title: "Increase water circulation",
          detail:
              "High temperature forecast (${w.maxTempC.toStringAsFixed(1)}°C). Increase pump circulation.",
          commandType: "fish_to_filter",
          targetState: true,
        ),
      );
    }

    if (actions.isEmpty) {
      actions.add(
        WeatherAction(
          title: "No changes required",
          detail: "Forecast stable. Keep normal schedule.",
          commandType: null,
          targetState: null,
        ),
      );
    }

    return WeatherDecision(actions: actions);
  }

  // ---------- Auto execution ----------
  Future<void> _runAutoIfEnabled(WeatherSnapshot snapshot) async {
    if (!_autoModeEnabled) return;

    // Anti-spam: only every 10 minutes
    final now = DateTime.now();
    if (_lastAutoRunAt != null &&
        now.difference(_lastAutoRunAt!).inMinutes < 10) {
      return;
    }

    final decision = _decide(snapshot);
    final actionable =
        decision.actions.where((a) => a.commandType != null).toList();

    if (actionable.isEmpty) {
      await _schedulerLogsRef().add({
        "ts": FieldValue.serverTimestamp(),
        "mode": "weather_only",
        "locationName": snapshot.locationName,
        "maxTempC": snapshot.maxTempC,
        "chanceOfRain": snapshot.chanceOfRain,
        "precipMm": snapshot.totalPrecipMm,
        "actions": ["No changes required"],
        "executed": false,
      });
      _lastAutoRunAt = now;
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "unknown";
    final email = FirebaseAuth.instance.currentUser?.email ?? "unknown";

    for (final a in actionable) {
      await _commandsRef().add({
        "type": a.commandType, // "pump" | "valve"
        "targetState": a.targetState,
        "status": "pending",
        "requestedBy": uid,
        "requestedByEmail": email,
        "requestedAt": FieldValue.serverTimestamp(),
        "executedAt": null,
        "message": "Auto Weather Mode: ${a.title}",
      });
    }

    await _schedulerLogsRef().add({
      "ts": FieldValue.serverTimestamp(),
      "mode": "weather_only",
      "locationName": snapshot.locationName,
      "maxTempC": snapshot.maxTempC,
      "chanceOfRain": snapshot.chanceOfRain,
      "precipMm": snapshot.totalPrecipMm,
      "actions": actionable.map((a) => a.title).toList(),
      "executed": true,
      "commandCount": actionable.length,
    });

    _lastAutoRunAt = now;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Auto mode applied ${actionable.length} action(s)."),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final w = _latest;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Weather AI"),
        actions: [
          IconButton(
            onPressed: _loading ? null : _fetchWeather,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _buildLocationCard(),
            const SizedBox(height: 12),
            _buildAutoModeCard(),

            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              _buildErrorCard(_error!),
            ],

            const SizedBox(height: 12),

            if (w == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text("No weather data yet. Tap refresh."),
                ),
              )
            else ...[
              _buildForecastCard(w),
              const SizedBox(height: 12),
              _buildDecisionCard(w),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAutoModeCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.auto_mode),
        title: const Text("Auto Weather Mode"),
        subtitle: const Text("When ON: writes commands based on forecast rules"),
        trailing: Switch(
          value: _autoModeEnabled,
          onChanged: (v) => _setAutoMode(v),
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Forecast Source (WeatherAPI)",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: "Location",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.place),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _fetchWeather(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _thresholdField(
                    label: "Rain % ≥",
                    value: rainChanceThreshold,
                    onChanged: (v) => setState(() => rainChanceThreshold = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _thresholdField(
                    label: "Rain mm ≥",
                    value: rainMmThreshold,
                    onChanged: (v) => setState(() => rainMmThreshold = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _thresholdField(
              label: "High Temp °C ≥",
              value: highTempThreshold,
              onChanged: (v) => setState(() => highTempThreshold = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thresholdField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return TextFormField(
      initialValue: value.toStringAsFixed(0),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (t) {
        final v = double.tryParse(t.trim());
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _buildErrorCard(String msg) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
      ),
    );
  }

  Widget _buildForecastCard(WeatherSnapshot w) {
    final updated = w.updatedAt == null
        ? "—"
        : DateFormat("dd MMM yyyy, HH:mm").format(w.updatedAt!);

    return Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: Text("${w.locationName} • Updated: $updated"),
        subtitle: Text(
          "Max: ${w.maxTempC.toStringAsFixed(1)}°C  •  "
          "Rain: ${w.chanceOfRain.toStringAsFixed(0)}%  •  "
          "Precip: ${w.totalPrecipMm.toStringAsFixed(1)}mm",
        ),
      ),
    );
  }

  Widget _buildDecisionCard(WeatherSnapshot w) {
    final decision = _decide(w);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "AI Recommendations (Next 24h)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...decision.actions.map((a) => _actionTile(a)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  // Manual apply (same as auto, but immediate)
                  await _applyManual(decision);
                },
                icon: const Icon(Icons.play_circle),
                label: const Text("Apply Actions (Manual)"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyManual(WeatherDecision decision) async {
    final actionable =
        decision.actions.where((a) => a.commandType != null).toList();
    if (actionable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nothing to apply.")),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "unknown";
    final email = FirebaseAuth.instance.currentUser?.email ?? "unknown";

    for (final a in actionable) {
      await _commandsRef().add({
        "type": a.commandType,
        "targetState": a.targetState,
        "status": "pending",
        "requestedBy": uid,
        "requestedByEmail": email,
        "requestedAt": FieldValue.serverTimestamp(),
        "executedAt": null,
        "message": "Manual Weather AI: ${a.title}",
      });
    }

    await _schedulerLogsRef().add({
      "ts": FieldValue.serverTimestamp(),
      "mode": "manual_weather",
      "actions": actionable.map((a) => a.title).toList(),
      "executed": true,
      "commandCount": actionable.length,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Applied ${actionable.length} action(s).")),
    );
  }

  Widget _actionTile(WeatherAction a) {
    IconData icon = Icons.check_circle_outline;
    if (a.commandType != null) icon = Icons.tips_and_updates_outlined;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(a.detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Models ----------------

class WeatherSnapshot {
  final String locationName;
  final double maxTempC;
  final double chanceOfRain;
  final double totalPrecipMm;
  final DateTime? updatedAt;

  WeatherSnapshot({
    required this.locationName,
    required this.maxTempC,
    required this.chanceOfRain,
    required this.totalPrecipMm,
    required this.updatedAt,
  });

  factory WeatherSnapshot.fromWeatherApi(Map<String, dynamic> root) {
    final loc = (root["location"] as Map?)?.cast<String, dynamic>() ?? {};
    final forecast = (root["forecast"] as Map?)?.cast<String, dynamic>() ?? {};
    final days = (forecast["forecastday"] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    final day0 = days.isNotEmpty
        ? (days.first["day"] as Map?)?.cast<String, dynamic>() ?? {}
        : <String, dynamic>{};

    double toDouble(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    final name = (loc["name"] ?? "").toString();
    final region = (loc["region"] ?? "").toString();
    final locationName =
        region.trim().isEmpty ? name : "$name, $region";

    return WeatherSnapshot(
      locationName: locationName.trim().isEmpty ? "Unknown" : locationName,
      maxTempC: toDouble(day0["maxtemp_c"]),
      chanceOfRain: toDouble(day0["daily_chance_of_rain"]),
      totalPrecipMm: toDouble(day0["totalprecip_mm"]),
      updatedAt: DateTime.tryParse((loc["localtime"] ?? "").toString()),
    );
  }

  factory WeatherSnapshot.fromFirestore(Map<String, dynamic> data) {
    DateTime? dt;
    final raw = data["updatedAt"];
    if (raw is Timestamp) dt = raw.toDate();
    if (raw is String) dt = DateTime.tryParse(raw);

    return WeatherSnapshot(
      locationName: (data["locationName"] ?? "Unknown").toString(),
      maxTempC: (data["maxTempC"] as num?)?.toDouble() ?? 0,
      chanceOfRain: (data["chanceOfRain"] as num?)?.toDouble() ?? 0,
      totalPrecipMm: (data["totalPrecipMm"] as num?)?.toDouble() ?? 0,
      updatedAt: dt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      "locationName": locationName,
      "maxTempC": maxTempC,
      "chanceOfRain": chanceOfRain,
      "totalPrecipMm": totalPrecipMm,
      "updatedAt": FieldValue.serverTimestamp(),
    };
  }
}

class WeatherDecision {
  final List<WeatherAction> actions;
  WeatherDecision({required this.actions});
}

class WeatherAction {
  final String title;
  final String detail;
  final String? commandType; // "pump" | "valve" | null
  final bool? targetState;

  WeatherAction({
    required this.title,
    required this.detail,
    required this.commandType,
    required this.targetState,
  });
}
