import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:iot_aqua_app/core/device/device_selection_controller.dart';

const double kDeviceSelectorHeaderHeight = 52;

const Key kDeviceSelectorHeaderLoadingKey = Key(
  'device-selector-header-loading',
);
const Key kDeviceSelectorHeaderErrorKey = Key('device-selector-header-error');
const Key kDeviceSelectorHeaderEmptyKey = Key('device-selector-header-empty');
const Key kDeviceSelectorHeaderReadyKey = Key('device-selector-header-ready');
const Key kDeviceSelectorHeaderDropdownKey = Key(
  'device-selector-header-dropdown',
);

class DeviceSelectorHeaderBottom extends StatelessWidget
    implements PreferredSizeWidget {
  const DeviceSelectorHeaderBottom({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kDeviceSelectorHeaderHeight);

  @override
  Widget build(BuildContext context) {
    return const DeviceSelectorHeaderFromProvider();
  }
}

class DeviceSelectorHeaderFromProvider extends StatelessWidget {
  const DeviceSelectorHeaderFromProvider({super.key});

  @override
  Widget build(BuildContext context) {
    final deviceController = context.watch<DeviceSelectionController>();
    return DeviceSelectorHeaderRow(
      loading: deviceController.isLoading,
      error: deviceController.error,
      devices: deviceController.devices,
      selectedDeviceId: deviceController.selectedDeviceId,
      onChanged: deviceController.selectDevice,
    );
  }
}

class DeviceSelectorHeaderRow extends StatelessWidget {
  const DeviceSelectorHeaderRow({
    super.key,
    required this.loading,
    required this.error,
    required this.devices,
    required this.selectedDeviceId,
    required this.onChanged,
  });

  final bool loading;
  final String? error;
  final List<DeviceSummary> devices;
  final String? selectedDeviceId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        height: kDeviceSelectorHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (loading) {
      return const Row(
        key: kDeviceSelectorHeaderLoadingKey,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Loading greenhouses...',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    if (error != null) {
      return Row(
        key: kDeviceSelectorHeaderErrorKey,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Device list unavailable: $error',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    if (devices.isEmpty) {
      return const Row(
        key: kDeviceSelectorHeaderEmptyKey,
        children: [
          Icon(Icons.sensors_off),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No devices found',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    final fallback = devices.first.id;
    final selected = devices.any((d) => d.id == selectedDeviceId)
        ? selectedDeviceId!
        : fallback;
    final borderColor = Theme.of(context).colorScheme.outlineVariant;

    return Row(
      key: kDeviceSelectorHeaderReadyKey,
      children: [
        const Icon(Icons.home_work_outlined),
        const SizedBox(width: 8),
        const Text('Greenhouse:'),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: kDeviceSelectorHeaderDropdownKey,
                value: selected,
                isExpanded: true,
                items: devices
                    .map(
                      (d) => DropdownMenuItem<String>(
                        value: d.id,
                        child: Text(
                          '${d.name} (${d.id})${d.online ? ' online' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onChanged(value);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
