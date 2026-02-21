import 'package:flutter/material.dart';
import 'package:iot_aqua_app/main.dart';
import 'package:iot_aqua_app/pages/super_admin_dashboard.dart';


class SystemTab extends StatelessWidget {
  final String role;
  final bool isSuperAdmin;

  const SystemTab({
    super.key,
    required this.role,
    required this.isSuperAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge),
            title: const Text("System Role"),
            subtitle: Text(role),
          ),
        ),
        const SizedBox(height: 12),

        // ✅ Super Admin only: Create Admin/Employee
        if (isSuperAdmin)
          Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text("User Management"),
              subtitle: const Text("Create Admin / Employee accounts"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SuperAdminSettingsPage()),
                );
              },
            ),
          ),

        const SizedBox(height: 12),

        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.notifications_active),
            title: const Text("Enable Notifications"),
            subtitle: const Text("Alerts for pH, temperature, water level, etc."),
            value: true,
            onChanged: (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Later: connect to notification logic.")),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

      Card(
        child: SwitchListTile(
          secondary: const Icon(Icons.dark_mode),
          title: const Text("Dark Mode"),
          subtitle: const Text("Switch app theme"),
          value: themeController.isDark,
          onChanged: (v) async {
            await themeController.setDark(v);
          },
        ),
      ),
      ],
    );
  }
}
