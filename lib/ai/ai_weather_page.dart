import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:iot_aqua_app/core/device/device_selector_header.dart';
import 'package:iot_aqua_app/core/device/device_selection_controller.dart';
import 'package:provider/provider.dart';

class AiWeatherPage extends StatefulWidget {
  const AiWeatherPage({super.key, this.selectedDeviceId});

  final String? selectedDeviceId;

  @override
  State<AiWeatherPage> createState() => _AiWeatherPageState();
}

class _AiWeatherPageState extends State<AiWeatherPage> {
  final TextEditingController _locationCtrl = TextEditingController(
    text: "Mauritius",
  );

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
  String? _boundDeviceId;
  bool _autoModePermissionDenied = false;
  String? _syncNote;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _autoModeSub?.cancel();
    _locationCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final selected =
        widget.selectedDeviceId ??
        context.watch<DeviceSelectionController>().selectedDeviceId;
    if (selected != null && selected.isNotEmpty && selected != _boundDeviceId) {
      _bindDevice(selected);
    }
  }

  void _bindDevice(String deviceId) {
    _boundDeviceId = deviceId;
    _autoModeSub?.cancel();
    _lastAutoRunAt = null;
    _latest = null;
    _error = null;
    _autoModeEnabled = false;
    _autoModePermissionDenied = false;
    _syncNote = null;
    _bindAutoMode(deviceId);
    unawaited(_loadCachedThenFetch(deviceId));
  }

  bool _isPermissionDenied(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
  }

  // ---------- Firestore refs ----------
  DocumentReference<Map<String, dynamic>> _cacheDoc(String deviceId) {
    return FirebaseFirestore.instance
        .collection("devices")
        .doc(deviceId)
        .collection("weather")
        .doc("latest");
  }

  DocumentReference<Map<String, dynamic>> _autoModeDoc(String deviceId) {
    return FirebaseFirestore.instance
        .collection("devices")
        .doc(deviceId)
        .collection("settings")
        .doc("automation");
  }

  CollectionReference<Map<String, dynamic>> _schedulerLogsRef(String deviceId) {
    return FirebaseFirestore.instance
        .collection("devices")
        .doc(deviceId)
        .collection("scheduler_logs");
  }

  CollectionReference<Map<String, dynamic>> _commandsRef(String deviceId) {
    return FirebaseFirestore.instance
        .collection("devices")
        .doc(deviceId)
        .collection("commands");
  }

  // ---------- Auto mode binding ----------
  void _bindAutoMode(String deviceId) {
    _autoModeSub?.cancel();
    _autoModeSub = _autoModeDoc(deviceId).snapshots().listen(
      (snap) {
        final enabled = (snap.data()?["enabled"] == true);
        if (!mounted) return;
        setState(() => _autoModeEnabled = enabled);
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _autoModeEnabled = false;
          _autoModePermissionDenied = _isPermissionDenied(e);
          _syncNote = _autoModePermissionDenied
              ? "Weather forecast works, but Auto Weather Mode settings cannot sync for this account."
              : "Auto Weather Mode settings are unavailable right now.";
        });
      },
    );
  }

  Future<void> _setAutoMode(bool enabled) async {
    final deviceId = _boundDeviceId;
    if (deviceId == null) return;
    final email = FirebaseAuth.instance.currentUser?.email ?? "unknown";
    try {
      await _autoModeDoc(deviceId).set({
        "enabled": enabled,
        "updatedAt": FieldValue.serverTimestamp(),
        "updatedBy": email,
      }, SetOptions(merge: true));
      _autoModePermissionDenied = false;
      _syncNote = null;
    } catch (e) {
      if (!_isPermissionDenied(e)) rethrow;
      _autoModePermissionDenied = true;
      _syncNote =
          "Auto Weather Mode is local only for this session because Firestore permission was denied.";
    }

    if (!mounted) return;
    setState(() => _autoModeEnabled = enabled);

    // Optional: run immediately if turned on and we already have forecast
    if (enabled && _latest != null) {
      await _runAutoIfEnabled(deviceId, _latest!);
    }
  }

  // ---------- Load cache then fetch ----------
  Future<void> _loadCachedThenFetch(String deviceId) async {
    try {
      final snap = await _cacheDoc(deviceId).get();
      if (snap.exists && snap.data() != null) {
        if (!mounted || _boundDeviceId != deviceId) return;
        setState(() => _latest = WeatherSnapshot.fromFirestore(snap.data()!));
      }
    } catch (e) {
      if (!_isPermissionDenied(e)) rethrow;
      if (mounted && _boundDeviceId == deviceId) {
        setState(() {
          _syncNote =
              "Weather cache is not readable for this account. Live forecast will still load.";
        });
      }
    }
    await _fetchWeather();
  }

  // ---------- Fetch weather ----------
  Future<void> _fetchWeather() async {
    final deviceId = _boundDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      setState(() => _error = "No device selected. Pick a device first.");
      return;
    }
    final loc = _locationCtrl.text.trim();
    if (loc.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snapshot = await _fetchOpenMeteo(loc);
      if (!mounted || _boundDeviceId != deviceId) return;
      setState(() => _latest = snapshot);

      // ✅ cache latest
      try {
        await _cacheDoc(
          deviceId,
        ).set(snapshot.toFirestore(), SetOptions(merge: true));
      } catch (e) {
        if (!_isPermissionDenied(e)) rethrow;
        if (mounted) {
          setState(() {
            _syncNote =
                "Forecast loaded, but it could not be saved to Firestore for this account.";
          });
        }
      }

      // ✅ save history for analytics
      try {
        await FirebaseFirestore.instance
            .collection("devices")
            .doc(deviceId)
            .collection("weather_history")
            .add({
              "ts": FieldValue.serverTimestamp(),
              "locationName": snapshot.locationName,
              "maxTempC": snapshot.maxTempC,
              "chanceOfRain": snapshot.chanceOfRain,
              "precipMm": snapshot.totalPrecipMm,
              "source": "Open-Meteo",
            });
      } catch (e) {
        if (!_isPermissionDenied(e)) rethrow;
      }

      // ✅ run auto if enabled (anti-spam inside)
      await _runAutoIfEnabled(deviceId, snapshot);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Failed to fetch weather. Showing cached data (if any).\n$e";
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<WeatherSnapshot> _fetchOpenMeteo(String location) async {
    final geoUri = Uri.https("geocoding-api.open-meteo.com", "/v1/search", {
      "name": location,
      "count": "1",
      "language": "en",
      "format": "json",
    });
    final geoRes = await http.get(geoUri).timeout(const Duration(seconds: 12));
    if (geoRes.statusCode != 200) {
      throw Exception("Geocoding failed: HTTP ${geoRes.statusCode}");
    }

    final geoRoot = jsonDecode(geoRes.body) as Map<String, dynamic>;
    final results = geoRoot["results"] as List?;
    if (results == null || results.isEmpty || results.first is! Map) {
      throw Exception("Location not found: $location");
    }

    final geo = (results.first as Map).cast<String, dynamic>();
    final lat = (geo["latitude"] as num?)?.toDouble();
    final lon = (geo["longitude"] as num?)?.toDouble();
    if (lat == null || lon == null) {
      throw Exception("Location coordinates missing for $location");
    }

    final forecastUri = Uri.https("api.open-meteo.com", "/v1/forecast", {
      "latitude": lat.toString(),
      "longitude": lon.toString(),
      "daily":
          "temperature_2m_max,precipitation_sum,precipitation_probability_max",
      "forecast_days": "1",
      "timezone": "auto",
    });
    final forecastRes = await http
        .get(forecastUri)
        .timeout(const Duration(seconds: 12));
    if (forecastRes.statusCode != 200) {
      throw Exception("Forecast failed: HTTP ${forecastRes.statusCode}");
    }

    final forecast = jsonDecode(forecastRes.body) as Map<String, dynamic>;
    return WeatherSnapshot.fromOpenMeteo(geo: geo, forecast: forecast);
  }

  // ---------- Decision rules ----------
  WeatherDecision _decide(WeatherSnapshot w) {
    final actions = <WeatherAction>[];

    final rainExpected =
        (w.chanceOfRain >= rainChanceThreshold) ||
        (w.totalPrecipMm >= rainMmThreshold);

    final heatExpected = w.maxTempC >= highTempThreshold;

    if (rainExpected) {
      actions.add(
        WeatherAction(
          title: "Reduce irrigation",
          detail:
              "Rain likely (${w.chanceOfRain.toStringAsFixed(0)}% / ${w.totalPrecipMm.toStringAsFixed(1)}mm). Reduce/stop irrigation.",
          commandType: null,
          targetState: null,
        ),
      );
    }

    if (heatExpected) {
      actions.add(
        WeatherAction(
          title: "Increase water circulation",
          detail:
              "High temperature forecast (${w.maxTempC.toStringAsFixed(1)}°C). Increase pump circulation.",
          commandType: null,
          targetState: null,
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
  Future<void> _runAutoIfEnabled(
    String deviceId,
    WeatherSnapshot snapshot,
  ) async {
    if (!_autoModeEnabled) return;

    // Anti-spam: only every 10 minutes
    final now = DateTime.now();
    if (_lastAutoRunAt != null &&
        now.difference(_lastAutoRunAt!).inMinutes < 10) {
      return;
    }

    final decision = _decide(snapshot);
    final actionable = decision.actions
        .where((a) => a.commandType != null)
        .toList();

    if (actionable.isEmpty) {
      try {
        await _schedulerLogsRef(deviceId).add({
          "ts": FieldValue.serverTimestamp(),
          "mode": "weather_only",
          "locationName": snapshot.locationName,
          "maxTempC": snapshot.maxTempC,
          "chanceOfRain": snapshot.chanceOfRain,
          "precipMm": snapshot.totalPrecipMm,
          "actions": ["No changes required"],
          "executed": false,
        });
      } catch (e) {
        if (!_isPermissionDenied(e)) rethrow;
      }
      _lastAutoRunAt = now;
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "unknown";
    final email = FirebaseAuth.instance.currentUser?.email ?? "unknown";

    for (final a in actionable) {
      try {
        await _commandsRef(deviceId).add({
          "type": a.commandType, // "pump" | "valve"
          "targetState": a.targetState,
          "status": "pending",
          "requestedBy": uid,
          "requestedByEmail": email,
          "requestedAt": FieldValue.serverTimestamp(),
          "executedAt": null,
          "message": "Auto Weather Mode: ${a.title}",
        });
      } catch (e) {
        if (!_isPermissionDenied(e)) rethrow;
      }
    }

    try {
      await _schedulerLogsRef(deviceId).add({
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
    } catch (e) {
      if (!_isPermissionDenied(e)) rethrow;
    }

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
    final deviceId = _boundDeviceId;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Weather AI"),
        bottom: const DeviceSelectorHeaderBottom(),
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
            if (deviceId == null) ...[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text("No device selected. Pick a device first."),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _buildLocationCard(),
            const SizedBox(height: 12),
            _buildAutoModeCard(),
            if (_syncNote != null) ...[
              const SizedBox(height: 12),
              _buildInfoCard(_syncNote!),
            ],

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
        subtitle: Text(
          _autoModePermissionDenied
              ? "Local only: this account cannot sync weather automation settings."
              : "When ON: writes commands based on forecast rules",
        ),
        trailing: Switch(
          value: _autoModeEnabled,
          onChanged: (v) => _setAutoMode(v),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String msg) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade700),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
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
            const Text(
              "Forecast Source",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              "Open-Meteo forecast, cached to the selected device",
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
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
    final deviceId = _boundDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No device selected.")));
      return;
    }
    final actionable = decision.actions
        .where((a) => a.commandType != null)
        .toList();
    if (actionable.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Nothing to apply.")));
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "unknown";
    final email = FirebaseAuth.instance.currentUser?.email ?? "unknown";

    for (final a in actionable) {
      await _commandsRef(deviceId).add({
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

    await _schedulerLogsRef(deviceId).add({
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
                Text(
                  a.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
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
    final locationName = region.trim().isEmpty ? name : "$name, $region";

    return WeatherSnapshot(
      locationName: locationName.trim().isEmpty ? "Unknown" : locationName,
      maxTempC: toDouble(day0["maxtemp_c"]),
      chanceOfRain: toDouble(day0["daily_chance_of_rain"]),
      totalPrecipMm: toDouble(day0["totalprecip_mm"]),
      updatedAt: DateTime.tryParse((loc["localtime"] ?? "").toString()),
    );
  }

  factory WeatherSnapshot.fromOpenMeteo({
    required Map<String, dynamic> geo,
    required Map<String, dynamic> forecast,
  }) {
    double firstDouble(dynamic value) {
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is num) return first.toDouble();
        return double.tryParse(first.toString()) ?? 0;
      }
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    final daily = (forecast["daily"] as Map?)?.cast<String, dynamic>() ?? {};
    final name = (geo["name"] ?? "").toString();
    final admin1 = (geo["admin1"] ?? "").toString();
    final country = (geo["country"] ?? "").toString();
    final parts = <String>[
      name,
      if (admin1.trim().isNotEmpty) admin1,
      if (country.trim().isNotEmpty) country,
    ].where((e) => e.trim().isNotEmpty).toList(growable: false);

    return WeatherSnapshot(
      locationName: parts.isEmpty ? "Unknown" : parts.join(", "),
      maxTempC: firstDouble(daily["temperature_2m_max"]),
      chanceOfRain: firstDouble(daily["precipitation_probability_max"]),
      totalPrecipMm: firstDouble(daily["precipitation_sum"]),
      updatedAt: DateTime.now(),
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
