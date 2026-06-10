import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/services/auth_service.dart';

class AdminCreateEmployeePage extends StatefulWidget {
  const AdminCreateEmployeePage({super.key});

  @override
  State<AdminCreateEmployeePage> createState() => _AdminCreateEmployeePageState();
}

class _AdminCreateEmployeePageState extends State<AdminCreateEmployeePage> {
  final _authService = AuthService();
  final _db = FirebaseFirestore.instance;

  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();

  bool _loading = false;
  String? _msg;

  Future<void> _createEmployee() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      // Create user in Firebase Auth
      final cred = await _authService.registerEmail(_email.text, _pass.text);

      // Set role employee in Firestore
      await _db.collection("users").doc(cred.user!.uid).set({
        "email": _email.text.trim(),
        "name": _name.text.trim(),
        "role": "employee",
        "createdAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() => _msg = "✅ Employee created successfully!");
    } catch (e) {
      setState(() => _msg = "❌ Error: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Employee")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: "Employee Name"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: "Employee Email"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Temporary Password"),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _createEmployee,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text("Create Employee"),
            ),
            const SizedBox(height: 12),
            if (_msg != null) Text(_msg!),
          ],
        ),
      ),
    );
  }
}
