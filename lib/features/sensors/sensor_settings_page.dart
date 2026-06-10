import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:iot_aqua_app/core/alerts/sensor_thresholds.dart';
import 'package:iot_aqua_app/core/device/device_selection_controller.dart';

class SensorSettingsPage extends StatefulWidget {
  const SensorSettingsPage({super.key});

  @override
  State<SensorSettingsPage> createState() => _SensorSettingsPageState();
}

class _SensorSettingsPageState extends State<SensorSettingsPage> {
  final _globalFormKey = GlobalKey<FormState>();
  final _overrideFormKey = GlobalKey<FormState>();

  final _gTempMinCtrl = TextEditingController();
  final _gTempMaxCtrl = TextEditingController();
  final _gPhMinCtrl = TextEditingController();
  final _gPhMaxCtrl = TextEditingController();
  final _gWaterLowCtrl = TextEditingController();
  final _gTdsMinCtrl = TextEditingController();
  final _gTdsMaxCtrl = TextEditingController();

  final _dTempMinCtrl = TextEditingController();
  final _dTempMaxCtrl = TextEditingController();
  final _dPhMinCtrl = TextEditingController();
  final _dPhMaxCtrl = TextEditingController();
  final _dWaterLowCtrl = TextEditingController();
  final _dTdsMinCtrl = TextEditingController();
  final _dTdsMaxCtrl = TextEditingController();

  bool _globalAutoDoseEnabled = kDefaultLowTdsAutoDoseEnabled;
  bool _overrideEnabled = false;
  bool _overrideAutoDoseEnabled = kDefaultLowTdsAutoDoseEnabled;

  bool _globalLoaded = false;
  bool _overrideLoaded = false;
  bool _savingGlobal = false;
  bool _savingOverride = false;
  String? _overrideDeviceId;

  List<TextEditingController> get _allControllers => [
    _gTempMinCtrl,
    _gTempMaxCtrl,
    _gPhMinCtrl,
    _gPhMaxCtrl,
    _gWaterLowCtrl,
    _gTdsMinCtrl,
    _gTdsMaxCtrl,
    _dTempMinCtrl,
    _dTempMaxCtrl,
    _dPhMinCtrl,
    _dPhMaxCtrl,
    _dWaterLowCtrl,
    _dTdsMinCtrl,
    _dTdsMaxCtrl,
  ];

  @override
  void initState() {
    super.initState();
    // Preload forms with defaults, then hydrate with Firestore snapshots.
    _applyGlobal(SensorGlobalSettings.defaults);
    _applyOverride(SensorDeviceOverrideSettings.defaults);
  }

  @override
  void dispose() {
    for (final ctrl in _allControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _saveGlobal() async {
    final form = _globalFormKey.currentState;
    if (form == null || !form.validate()) return;

    final values = _readValues(isGlobal: true);
    if (values == null) return;
    final errors = validateThresholdValues(values);
    if (errors.isNotEmpty) {
      _showError(errors.values.first);
      return;
    }

    setState(() => _savingGlobal = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('sensors')
          .set({
            'thresholds': values.toMap(),
            'automation': {
              'lowTdsAutoDoseEnabled': _globalAutoDoseEnabled,
              'pumpMaxRunSec': kDefaultPumpMaxRunSec,
              'stopTarget': kDefaultStopTarget,
            },
            'reminders': {'inAppIntervalSec': kDefaultInAppReminderIntervalSec},
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedByUid': user?.uid ?? '',
            'updatedByEmail': user?.email ?? '',
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Global thresholds saved.')));
    } catch (error) {
      final message = error.toString();
      if (message.contains('permission-denied')) {
        _showError(
          'Permission denied. Ensure users/{uid}.role is admin/super_admin and deploy latest firestore.rules.',
        );
      } else {
        _showError('Failed to save global thresholds: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _savingGlobal = false);
      }
    }
  }

  Future<void> _saveOverride(String deviceId) async {
    final form = _overrideFormKey.currentState;
    if (form == null || !form.validate()) return;

    final values = _readValues(isGlobal: false);
    if (values == null) return;
    final errors = validateThresholdValues(values);
    if (errors.isNotEmpty) {
      _showError(errors.values.first);
      return;
    }

    setState(() => _savingOverride = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('devices')
          .doc(deviceId)
          .collection('configs')
          .doc('sensors')
          .set({
            'overrideEnabled': _overrideEnabled,
            'thresholds': values.toMap(),
            'automation': {'lowTdsAutoDoseEnabled': _overrideAutoDoseEnabled},
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedByUid': user?.uid ?? '',
            'updatedByEmail': user?.email ?? '',
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Device override saved.')));
    } catch (error) {
      final message = error.toString();
      if (message.contains('permission-denied')) {
        _showError(
          'Permission denied. Ensure users/{uid}.role is admin/super_admin and deploy latest firestore.rules.',
        );
      } else {
        _showError('Failed to save device override: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _savingOverride = false);
      }
    }
  }

  void _applyGlobal(SensorGlobalSettings settings) {
    final t = settings.thresholds;
    _gTempMinCtrl.text = t.temperatureMinC.toStringAsFixed(2);
    _gTempMaxCtrl.text = t.temperatureMaxC.toStringAsFixed(2);
    _gPhMinCtrl.text = t.phMin.toStringAsFixed(2);
    _gPhMaxCtrl.text = t.phMax.toStringAsFixed(2);
    _gWaterLowCtrl.text = t.waterLevelLowPct.toStringAsFixed(2);
    _gTdsMinCtrl.text = t.tdsMinPpm.toStringAsFixed(2);
    _gTdsMaxCtrl.text = t.tdsMaxPpm.toStringAsFixed(2);
    _globalAutoDoseEnabled = settings.automation.lowTdsAutoDoseEnabled;
  }

  void _applyOverride(SensorDeviceOverrideSettings settings) {
    final t = settings.thresholds;
    _dTempMinCtrl.text = t.temperatureMinC.toStringAsFixed(2);
    _dTempMaxCtrl.text = t.temperatureMaxC.toStringAsFixed(2);
    _dPhMinCtrl.text = t.phMin.toStringAsFixed(2);
    _dPhMaxCtrl.text = t.phMax.toStringAsFixed(2);
    _dWaterLowCtrl.text = t.waterLevelLowPct.toStringAsFixed(2);
    _dTdsMinCtrl.text = t.tdsMinPpm.toStringAsFixed(2);
    _dTdsMaxCtrl.text = t.tdsMaxPpm.toStringAsFixed(2);
    _overrideEnabled = settings.overrideEnabled;
    _overrideAutoDoseEnabled = settings.lowTdsAutoDoseEnabled;
  }

  SensorThresholdValues? _readValues({required bool isGlobal}) {
    double? parse(TextEditingController controller) {
      return double.tryParse(controller.text.trim());
    }

    final tMin = parse(isGlobal ? _gTempMinCtrl : _dTempMinCtrl);
    final tMax = parse(isGlobal ? _gTempMaxCtrl : _dTempMaxCtrl);
    final phMin = parse(isGlobal ? _gPhMinCtrl : _dPhMinCtrl);
    final phMax = parse(isGlobal ? _gPhMaxCtrl : _dPhMaxCtrl);
    final waterLow = parse(isGlobal ? _gWaterLowCtrl : _dWaterLowCtrl);
    final tdsMin = parse(isGlobal ? _gTdsMinCtrl : _dTdsMinCtrl);
    final tdsMax = parse(isGlobal ? _gTdsMaxCtrl : _dTdsMaxCtrl);

    if ([tMin, tMax, phMin, phMax, waterLow, tdsMin, tdsMax].contains(null)) {
      _showError('All threshold fields must be valid numbers.');
      return null;
    }

    return SensorThresholdValues(
      temperatureMinC: tMin!,
      temperatureMaxC: tMax!,
      phMin: phMin!,
      phMax: phMax!,
      waterLevelLowPct: waterLow!,
      tdsMinPpm: tdsMin!,
      tdsMaxPpm: tdsMax!,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String? _requiredNumberValidator(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    if (double.tryParse(value.trim()) == null) return 'Enter a valid number';
    return null;
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: _requiredNumberValidator,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _thresholdInputs({required bool isGlobal, required bool enabled}) {
    return Wrap(
      runSpacing: 12,
      spacing: 12,
      children: [
        SizedBox(
          width: 220,
          child: _numberField(
            controller: isGlobal ? _gTempMinCtrl : _dTempMinCtrl,
            label: 'Temperature Min (°C)',
            hint: '22',
            enabled: enabled,
          ),
        ),
        SizedBox(
          width: 220,
          child: _numberField(
            controller: isGlobal ? _gTempMaxCtrl : _dTempMaxCtrl,
            label: 'Temperature Max (°C)',
            hint: '28',
            enabled: enabled,
          ),
        ),
        SizedBox(
          width: 220,
          child: _numberField(
            controller: isGlobal ? _gPhMinCtrl : _dPhMinCtrl,
            label: 'pH Min',
            hint: '6.0',
            enabled: enabled,
          ),
        ),
        SizedBox(
          width: 220,
          child: _numberField(
            controller: isGlobal ? _gPhMaxCtrl : _dPhMaxCtrl,
            label: 'pH Max',
            hint: '7.2',
            enabled: enabled,
          ),
        ),
        SizedBox(
          width: 220,
          child: _numberField(
            controller: isGlobal ? _gWaterLowCtrl : _dWaterLowCtrl,
            label: 'Water Level Low (%)',
            hint: '30',
            enabled: enabled,
          ),
        ),
        SizedBox(
          width: 220,
          child: _numberField(
            controller: isGlobal ? _gTdsMinCtrl : _dTdsMinCtrl,
            label: 'TDS Min (ppm)',
            hint: '800',
            enabled: enabled,
          ),
        ),
        SizedBox(
          width: 220,
          child: _numberField(
            controller: isGlobal ? _gTdsMaxCtrl : _dTdsMaxCtrl,
            label: 'TDS Max (ppm)',
            hint: '1200',
            enabled: enabled,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDeviceId = context
        .watch<DeviceSelectionController>()
        .selectedDeviceId;

    if (_overrideDeviceId != selectedDeviceId) {
      _overrideDeviceId = selectedDeviceId;
      _overrideLoaded = false;
      _applyOverride(SensorDeviceOverrideSettings.defaults);
    }

    final globalStream = FirebaseFirestore.instance
        .collection('settings')
        .doc('sensors')
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: globalStream,
      builder: (context, globalSnap) {
        final globalData = globalSnap.data?.data();
        final globalSettings = SensorGlobalSettings.fromMap(globalData);
        if (!_globalLoaded && globalSnap.hasData && globalSnap.data!.exists) {
          _applyGlobal(globalSettings);
          _globalLoaded = true;
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _globalFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.public),
                          SizedBox(width: 8),
                          Text(
                            'Global Defaults',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Applied when device override is disabled.',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      _thresholdInputs(isGlobal: true, enabled: !_savingGlobal),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _globalAutoDoseEnabled,
                        onChanged: _savingGlobal
                            ? null
                            : (v) => setState(() => _globalAutoDoseEnabled = v),
                        title: const Text('Auto-dose for low TDS'),
                        subtitle: const Text(
                          'Uses pump automation when TDS is below min.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _savingGlobal ? null : _saveGlobal,
                          icon: _savingGlobal
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: const Text('Save Global'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (selectedDeviceId == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Select a greenhouse to manage device-specific sensor overrides.',
                  ),
                ),
              )
            else
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('devices')
                    .doc(selectedDeviceId)
                    .collection('configs')
                    .doc('sensors')
                    .snapshots(),
                builder: (context, overrideSnap) {
                  final overrideData = overrideSnap.data?.data();
                  final overrideSettings = SensorDeviceOverrideSettings.fromMap(
                    overrideData,
                  );
                  if (!_overrideLoaded &&
                      overrideSnap.hasData &&
                      overrideSnap.data!.exists) {
                    _applyOverride(overrideSettings);
                    _overrideLoaded = true;
                  }

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _overrideFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.home_work_outlined),
                                const SizedBox(width: 8),
                                Text(
                                  'Device Override ($selectedDeviceId)',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _overrideEnabled,
                              onChanged: _savingOverride
                                  ? null
                                  : (v) => setState(() => _overrideEnabled = v),
                              title: const Text('Enable device override'),
                              subtitle: const Text(
                                'When off, this device uses global defaults.',
                              ),
                            ),
                            const SizedBox(height: 12),
                            _thresholdInputs(
                              isGlobal: false,
                              enabled: !_savingOverride && _overrideEnabled,
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _overrideAutoDoseEnabled,
                              onChanged: (!_savingOverride && _overrideEnabled)
                                  ? (v) => setState(
                                      () => _overrideAutoDoseEnabled = v,
                                    )
                                  : null,
                              title: const Text('Auto-dose for low TDS'),
                              subtitle: const Text(
                                'Override-level automation toggle.',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _savingOverride
                                    ? null
                                    : () => _saveOverride(selectedDeviceId),
                                icon: _savingOverride
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save),
                                label: const Text('Save Device Override'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Reminder cadence'),
                subtitle: Text(
                  'In-app reminders are configured for every 15 seconds.',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
