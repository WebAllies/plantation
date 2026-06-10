import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iot_aqua_app/core/device/device_selection_controller.dart';
import 'package:iot_aqua_app/core/local/local_backend_config.dart';
import 'package:iot_aqua_app/core/local/nano_usb_bridge_service.dart';
import 'package:provider/provider.dart';

class NanoUsbBridgePage extends StatefulWidget {
  const NanoUsbBridgePage({super.key, required this.service});

  final NanoUsbBridgeService service;

  @override
  State<NanoUsbBridgePage> createState() => _NanoUsbBridgePageState();
}

class _NanoUsbBridgePageState extends State<NanoUsbBridgePage> {
  late final TextEditingController _backendController;
  late final TextEditingController _deviceController;

  static const List<int> _baudRates = <int>[9600, 57600, 115200];

  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    if (LocalBackendConfig.httpBaseUrl.trim().isNotEmpty &&
        service.backendUrl == 'http://116.203.96.119:8080') {
      service.setBackendUrl(LocalBackendConfig.httpBaseUrl.trim());
    }
    _backendController = TextEditingController(text: service.backendUrl);
    _deviceController = TextEditingController(text: service.deviceId);
    if (_isWindowsDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.service.refreshPorts();
        final selected = context
            .read<DeviceSelectionController>()
            .selectedDeviceId;
        if (selected != null && selected.isNotEmpty) {
          widget.service.setDeviceId(selected);
          _deviceController.text = selected;
        }
      });
    }
  }

  @override
  void dispose() {
    _backendController.dispose();
    _deviceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isWindowsDesktop) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nano USB Bridge')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'The Nano USB bridge runs in the Windows desktop app.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final service = widget.service;
        final devices = context.watch<DeviceSelectionController>().devices;
        final selectedDevice = devices.any((d) => d.id == service.deviceId)
            ? service.deviceId
            : null;

        return Scaffold(
          appBar: AppBar(title: const Text('Nano USB Bridge')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            children: [
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bridge Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue:
                                service.ports.contains(service.selectedPort)
                                ? service.selectedPort
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'COM Port',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final port in service.ports)
                                DropdownMenuItem(
                                  value: port,
                                  child: Text(port),
                                ),
                            ],
                            onChanged: service.isRunning
                                ? null
                                : service.setPort,
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          tooltip: 'Refresh ports',
                          onPressed: service.isRunning
                              ? null
                              : service.refreshPorts,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _baudRates.contains(service.baudRate)
                          ? service.baudRate
                          : 115200,
                      decoration: const InputDecoration(
                        labelText: 'Serial Baud',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final rate in _baudRates)
                          DropdownMenuItem(value: rate, child: Text('$rate')),
                      ],
                      onChanged:
                          service.isRunning || service.selectedPort == null
                          ? null
                          : (value) {
                              if (value != null) service.setBaudRate(value);
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedDevice,
                      decoration: const InputDecoration(
                        labelText: 'Device',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final device in devices)
                          DropdownMenuItem(
                            value: device.id,
                            child: Text('${device.name} (${device.id})'),
                          ),
                      ],
                      onChanged: service.isRunning
                          ? null
                          : (value) {
                              if (value == null) return;
                              context
                                  .read<DeviceSelectionController>()
                                  .selectDevice(value);
                              service.setDeviceId(value);
                              _deviceController.text = value;
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _deviceController,
                      enabled: !service.isRunning,
                      decoration: const InputDecoration(
                        labelText: 'Device ID',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: service.setDeviceId,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _backendController,
                      enabled: !service.isRunning,
                      decoration: const InputDecoration(
                        labelText: 'Realtime Server HTTP URL',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: service.setBackendUrl,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: service.isRunning
                                ? null
                                : () {
                                    service.setBackendUrl(
                                      _backendController.text,
                                    );
                                    service.setDeviceId(_deviceController.text);
                                    service.start();
                                  },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start Bridge'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: service.isRunning ? service.stop : null,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          service.isRunning ? Icons.usb : Icons.usb_off,
                          color: service.isRunning
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFD84315),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            service.status,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    if (service.error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        service.error!,
                        style: const TextStyle(color: Color(0xFFD84315)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _readingChip('pH', service.readings['ph']),
                        _readingChip('TDS', service.readings['tdsPpm']),
                        _readingChip(
                          'pH Up',
                          service.readings['phUpTankLevelPct'],
                        ),
                        _readingChip(
                          'pH Down',
                          service.readings['phDownTankLevelPct'],
                        ),
                        _readingChip(
                          'Nutrient',
                          service.readings['nutrientTankLevelPct'],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Last serial: ${service.lastLineAt?.toLocal().toString().split('.').first ?? '--'}',
                    ),
                    Text(
                      'Last publish: ${service.lastPublishAt?.toLocal().toString().split('.').first ?? '--'}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Serial Log',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 220),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF101418),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        service.logs.isEmpty
                            ? 'No serial data yet'
                            : service.logs.take(80).join('\n'),
                        style: const TextStyle(
                          color: Color(0xFFEAF2F8),
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: child,
    );
  }

  Widget _readingChip(String label, double? value) {
    return Chip(
      avatar: Icon(
        value == null ? Icons.remove_circle_outline : Icons.check_circle,
        size: 18,
      ),
      label: Text('$label: ${value?.toStringAsFixed(2) ?? '--'}'),
    );
  }
}
