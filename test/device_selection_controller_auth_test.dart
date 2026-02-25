import 'package:flutter_test/flutter_test.dart';

import 'package:iot_aqua_app/core/device/device_selection_controller.dart';

DeviceSummary _device(String id, {required bool online}) {
  return DeviceSummary(id: id, name: id, online: online, lastSeen: null);
}

void main() {
  group('DeviceSelectionController auth lifecycle', () {
    test('signed_out_clears_devices_and_error', () {
      final controller = DeviceSelectionController(autoListen: false);
      controller.debugSetState(
        loading: false,
        error: '[cloud_firestore/permission-denied]',
        devices: [_device('gh-1', online: true)],
        selectedDeviceId: 'gh-1',
      );

      controller.debugHandleAuthChange(signedIn: false);

      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.devices, isEmpty);
      expect(controller.selectedDeviceId, isNull);
    });

    test('signed_in_starts_loading_then_snapshot_clears_error', () {
      final controller = DeviceSelectionController(autoListen: false);
      controller.debugSetState(
        loading: false,
        error: 'stale error',
        devices: const [],
        selectedDeviceId: null,
      );

      controller.debugHandleAuthChange(signedIn: true);
      final generation = controller.debugStreamGeneration;

      expect(controller.isLoading, isTrue);
      expect(controller.error, isNull);

      controller.debugApplySnapshotForGeneration(
        generation: generation,
        devices: [
          _device('gh-1', online: false),
          _device('gh-2', online: true),
        ],
      );

      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.devices.map((d) => d.id).toList(), ['gh-2', 'gh-1']);
      expect(controller.selectedDeviceId, 'gh-2');
    });

    test(
      'logout_then_relogin_recreates_stream_and_removes_permission_denied',
      () {
        final controller = DeviceSelectionController(autoListen: false);

        controller.debugHandleAuthChange(signedIn: true);
        final firstGeneration = controller.debugStreamGeneration;
        controller.debugApplyErrorForGeneration(
          generation: firstGeneration,
          error:
              '[cloud_firestore/permission-denied] The caller does not have permission.',
        );
        expect(controller.error, contains('permission-denied'));

        controller.debugHandleAuthChange(signedIn: false);
        expect(controller.error, isNull);
        expect(controller.devices, isEmpty);
        expect(controller.selectedDeviceId, isNull);

        controller.debugHandleAuthChange(signedIn: true);
        final secondGeneration = controller.debugStreamGeneration;
        controller.debugApplySnapshotForGeneration(
          generation: secondGeneration,
          devices: [_device('gh-9', online: true)],
        );

        expect(controller.error, isNull);
        expect(controller.isLoading, isFalse);
        expect(controller.devices.length, 1);
        expect(controller.selectedDeviceId, 'gh-9');
      },
    );

    test('stale_error_from_old_generation_is_ignored', () {
      final controller = DeviceSelectionController(autoListen: false);

      controller.debugHandleAuthChange(signedIn: true);
      final oldGeneration = controller.debugStreamGeneration;

      controller.debugHandleAuthChange(signedIn: false);
      final newGeneration = controller.debugStreamGeneration;
      expect(newGeneration, isNot(equals(oldGeneration)));

      controller.debugApplyErrorForGeneration(
        generation: oldGeneration,
        error: '[cloud_firestore/permission-denied] stale',
      );

      expect(controller.error, isNull);
      expect(controller.devices, isEmpty);
      expect(controller.selectedDeviceId, isNull);
      expect(controller.isLoading, isFalse);
    });
  });
}
