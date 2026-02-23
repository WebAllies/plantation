import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:iot_aqua_app/ai/ai_insight_page.dart';
import 'package:iot_aqua_app/analytics/analytics_page.dart';
import 'package:iot_aqua_app/control/control_page.dart';
import 'package:iot_aqua_app/core/device/device_selection_controller.dart';
import 'package:iot_aqua_app/core/device/device_selector_header.dart';
import 'package:iot_aqua_app/dashboard/dashboard_page.dart';
import 'package:iot_aqua_app/features/settings/settings_page.dart';
import 'package:iot_aqua_app/features/shell/main_shell.dart';
import 'package:iot_aqua_app/firebase_options.dart';

Widget _wrapWithApp(Widget child, DeviceSelectionController controller) {
  return ChangeNotifierProvider<DeviceSelectionController>.value(
    value: controller,
    child: MaterialApp(home: child),
  );
}

DeviceSelectionController _buildTestController({
  bool loading = false,
  String? error,
  String? selectedDeviceId,
  List<DeviceSummary>? devices,
}) {
  final controller = DeviceSelectionController(autoListen: false);
  controller.debugSetState(
    loading: loading,
    error: error,
    devices:
        devices ??
        const [
          DeviceSummary(
            id: 'gh-1',
            name: 'Greenhouse A',
            online: true,
            lastSeen: null,
          ),
          DeviceSummary(
            id: 'gh-2',
            name: 'Greenhouse B',
            online: false,
            lastSeen: null,
          ),
        ],
    selectedDeviceId: selectedDeviceId,
  );
  return controller;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
  });

  group('DeviceSelectorHeaderRow', () {
    testWidgets('renders loading state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceSelectorHeaderRow(
              loading: true,
              error: null,
              devices: const [],
              selectedDeviceId: null,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byKey(kDeviceSelectorHeaderLoadingKey), findsOneWidget);
      expect(find.byKey(kDeviceSelectorHeaderErrorKey), findsNothing);
      expect(find.byKey(kDeviceSelectorHeaderEmptyKey), findsNothing);
      expect(find.byKey(kDeviceSelectorHeaderReadyKey), findsNothing);
    });

    testWidgets('renders error state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceSelectorHeaderRow(
              loading: false,
              error: 'permission denied',
              devices: const [],
              selectedDeviceId: null,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byKey(kDeviceSelectorHeaderErrorKey), findsOneWidget);
    });

    testWidgets('renders empty state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceSelectorHeaderRow(
              loading: false,
              error: null,
              devices: const [],
              selectedDeviceId: null,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byKey(kDeviceSelectorHeaderEmptyKey), findsOneWidget);
      expect(find.text('No devices found'), findsOneWidget);
    });

    testWidgets('renders ready state and calls onChanged', (
      WidgetTester tester,
    ) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceSelectorHeaderRow(
              loading: false,
              error: null,
              devices: const [
                DeviceSummary(
                  id: 'gh-1',
                  name: 'Greenhouse A',
                  online: true,
                  lastSeen: null,
                ),
                DeviceSummary(
                  id: 'gh-2',
                  name: 'Greenhouse B',
                  online: false,
                  lastSeen: null,
                ),
              ],
              selectedDeviceId: 'gh-1',
              onChanged: (value) => picked = value,
            ),
          ),
        ),
      );

      expect(find.byKey(kDeviceSelectorHeaderReadyKey), findsOneWidget);
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byKey(kDeviceSelectorHeaderDropdownKey),
      );
      expect(dropdown.value, 'gh-1');

      await tester.tap(find.byKey(kDeviceSelectorHeaderDropdownKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Greenhouse B (gh-2)').last);
      await tester.pumpAndSettle();

      expect(picked, 'gh-2');
    });
  });

  group('Main shell and page headers', () {
    testWidgets('shell shows selector in page header (not global top bar)', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = _buildTestController(selectedDeviceId: null);
      await tester.pumpWidget(_wrapWithApp(const MainShell(), controller));
      await tester.pumpAndSettle();

      expect(find.text('Live Dashboard'), findsOneWidget);
      expect(find.byType(DeviceSelectorHeaderRow), findsOneWidget);

      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();
      expect(find.text('Analytics'), findsNWidgets(2));
      expect(find.byType(DeviceSelectorHeaderRow), findsOneWidget);

      await tester.tap(find.byKey(kDeviceSelectorHeaderDropdownKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Greenhouse B (gh-2)').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.selectedDeviceId, 'gh-2');

      final analyticsDropdown = tester.widget<DropdownButton<String>>(
        find.byKey(kDeviceSelectorHeaderDropdownKey),
      );
      expect(analyticsDropdown.value, 'gh-2');

      await tester.tap(find.text('AI Insight'));
      await tester.pumpAndSettle();
      expect(find.text('AI Insight 🧠'), findsOneWidget);
      final aiDropdown = tester.widget<DropdownButton<String>>(
        find.byKey(kDeviceSelectorHeaderDropdownKey),
      );
      expect(aiDropdown.value, 'gh-2');

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(DeviceSelectorHeaderRow), findsOneWidget);

      final headerTop = tester
          .getTopLeft(find.byType(DeviceSelectorHeaderRow))
          .dy;
      final tabsTop = tester.getTopLeft(find.byType(TabBar)).dy;
      expect(headerTop, lessThan(tabsTop));
    });

    testWidgets('each updated main page includes selector in app bar', (
      WidgetTester tester,
    ) async {
      final dashboardController = _buildTestController(selectedDeviceId: null);
      await tester.pumpWidget(
        _wrapWithApp(
          const DashboardPage(selectedDeviceId: null),
          dashboardController,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Live Dashboard'), findsOneWidget);
      expect(find.byType(DeviceSelectorHeaderRow), findsOneWidget);

      final controlController = _buildTestController(selectedDeviceId: null);
      await tester.pumpWidget(
        _wrapWithApp(
          const ControlPage(selectedDeviceId: null),
          controlController,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Control'), findsOneWidget);
      expect(find.byType(DeviceSelectorHeaderRow), findsOneWidget);

      final aiController = _buildTestController(selectedDeviceId: null);
      await tester.pumpWidget(
        _wrapWithApp(const AiInsightPage(), aiController),
      );
      await tester.pumpAndSettle();
      expect(find.text('AI Insight 🧠'), findsOneWidget);
      expect(find.byType(DeviceSelectorHeaderRow), findsOneWidget);

      final analyticsController = _buildTestController(selectedDeviceId: null);
      await tester.pumpWidget(
        _wrapWithApp(const AnalyticsPage(), analyticsController),
      );
      await tester.pumpAndSettle();
      expect(find.text('Data Analytics'), findsOneWidget);
      expect(find.byType(DeviceSelectorHeaderRow), findsOneWidget);

      final settingsController = _buildTestController(selectedDeviceId: null);
      await tester.pumpWidget(
        _wrapWithApp(const SettingsPage(), settingsController),
      );
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byType(DeviceSelectorHeaderRow), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
    });
  });
}
