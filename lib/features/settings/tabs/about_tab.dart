import 'package:flutter/material.dart';

class AboutTab extends StatelessWidget {
  const AboutTab({super.key});

  // ✅ Dissertation Details
  static const String appName = "Smart Aquaponics System for Lettuce Cultivation";
  static const String version = "v1.0.0";
  static const String university = "University of Mauritius";
  static const String programme = "BSc (Hons) Software Engineering";
  static const String level = "Level 3";
  static const String academicYear = "2025–2026";

  // ✅ Student Details
  static const String studentName = "Muhammad Shu'aib Teeluck";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _HeaderCard(theme: theme),
        const SizedBox(height: 14),

        _SectionCard(
          title: "About this Dissertation",
          icon: Icons.info_outline,
          children: const [
            Text(
              "This mobile application is developed as part of a final-year dissertation project titled "
              "“Develop a Smart Aquaponics System for Lettuce Cultivation”. "
              "The system integrates a Flutter-based mobile platform with Firebase cloud services and IoT devices (ESP32) "
              "to monitor aquaponics conditions and support automation for more efficient lettuce growth. "
              "The application provides real-time monitoring, alerts, and control functionalities to improve productivity and reduce manual intervention.",
            ),
          ],
        ),

        const SizedBox(height: 12),
        _SectionCard(
          title: "Key Features",
          icon: Icons.auto_awesome,
          children: [
            _bullet("Role-based Authentication (Admin / Employee)"),
            _bullet("Real-time monitoring of aquaponics parameters via Firebase"),
            _bullet("IoT integration using ESP32 for sensor readings and actuator control"),
            _bullet("Automated control logic for valves/pumps based on defined thresholds"),
            _bullet("QR-based module/device identification and activity logs"),
            _bullet("Notifications and alerts for abnormal readings and system events"),
          ],
        ),

        const SizedBox(height: 12),
        _SectionCard(
          title: "System Architecture Summary",
          icon: Icons.account_tree_outlined,
          children: const [
            Text(
              "The ESP32 microcontroller collects sensor readings and publishes data to Firebase Cloud Firestore in real-time. "
              "The Flutter mobile application retrieves this data for dashboard visualization and monitoring. "
              "When users trigger actions (e.g., valve ON/OFF), commands are written to Firebase and read by the ESP32 for execution. "
              "Logs are stored in Firestore to ensure traceability and accountability of system operations.",
            ),
          ],
        ),

        const SizedBox(height: 12),
        _SectionCard(
          title: "Technologies Used",
          icon: Icons.memory_outlined,
          children: [
            _chipWrap([
              "Flutter",
              "Firebase Authentication",
              "Cloud Firestore",
              "ESP32 (IoT)",
              "Wi-Fi Networking",
              "Draw.io (System Design)",
              "GitHub (Version Control)",
            ]),
          ],
        ),

        const SizedBox(height: 12),
        _SectionCard(
          title: "Developer Information",
          icon: Icons.badge_outlined,
          children: const [
            _InfoRow(label: "Student", value: studentName),
            _InfoRow(label: "Programme", value: programme),
            _InfoRow(label: "Level", value: level),
            _InfoRow(label: "Institution", value: university),
            _InfoRow(label: "Academic Year", value: academicYear),
          ],
        ),

        const SizedBox(height: 12),
        _SectionCard(
          title: "Disclaimer",
          icon: Icons.gpp_maybe_outlined,
          children: const [
            Text(
              "This application is a prototype developed strictly for academic purposes as part of a dissertation project. "
              "While the system demonstrates real-time monitoring and automation, it requires further testing, calibration, "
              "and security hardening before any commercial or large-scale deployment.",
            ),
          ],
        ),

        const SizedBox(height: 12),
        _SectionCard(
          title: "Future Enhancements",
          icon: Icons.trending_up_outlined,
          children: [

            _bullet("Predictive analytics for water quality and nutrient balance"),
            _bullet("Offline mode + background sync for unstable networks"),
            _bullet("Device health monitoring (uptime, connectivity, battery)"),
            _bullet("Advanced reporting and export (PDF/CSV) for supervisors"),
          ],
        ),

        const SizedBox(height: 18),
        Center(
          child: Text(
            "© $university • $studentName",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.65),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withOpacity(0.18),
            theme.colorScheme.secondary.withOpacity(0.12),
          ],
        ),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.18),
            child: Icon(
              Icons.eco_outlined,
              color: theme.colorScheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AboutTab.appName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(theme, AboutTab.version, Icons.verified_outlined),
                    _pill(theme, AboutTab.level, Icons.workspace_premium_outlined),
                    _pill(theme, AboutTab.university, Icons.apartment_outlined),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _pill(ThemeData theme, String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.75)),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children.map(
              (w) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: w,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _bullet(String text) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Icon(Icons.check_circle_outline, size: 18),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text)),
    ],
  );
}

Widget _chipWrap(List<String> items) {
  return Wrap(
    spacing: 10,
    runSpacing: 10,
    children: items
        .map(
          (t) => Chip(
            label: Text(t),
            visualDensity: VisualDensity.compact,
          ),
        )
        .toList(),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Text(value, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}