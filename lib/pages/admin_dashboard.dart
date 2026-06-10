import 'package:flutter/material.dart';
import 'admin_create_employee_page.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Dashboard")),
      body: Center(
        child: ElevatedButton(
          child: const Text("Create Employee Account"),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminCreateEmployeePage()),
            );
          },
        ),
      ),
    );
  }
}

