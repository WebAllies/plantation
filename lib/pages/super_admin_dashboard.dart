import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';

class SuperAdminSettingsPage extends StatefulWidget {
  const SuperAdminSettingsPage({super.key});

  @override
  State<SuperAdminSettingsPage> createState() => _SuperAdminSettingsPageState();
}

class _SuperAdminSettingsPageState extends State<SuperAdminSettingsPage> {
  final _auth = AuthService();

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();

  String _role = "employee"; // default
  bool _loading = false;
  String? _msg;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      await _auth.createUserWithRoleSecondaryApp(
        email: _email.text,
        password: _pass.text,
        name: _name.text,
        role: _role,
      );

      setState(() {
        _msg = "✅ Created ${_role.toUpperCase()} successfully!";
        _name.clear();
        _email.clear();
        _pass.clear();
        _role = "employee";
      });
    } catch (e) {
      setState(() => _msg = "❌ Error: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Super Admin Settings 👑")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Create Admin / Employee Account",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: "Full Name",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? "Name is required" : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: "Email",
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = (v ?? "").trim();
                  if (value.isEmpty) return "Email is required";
                  if (!value.contains("@") || !value.contains(".")) {
                    return "Enter a valid email";
                  }
                  if (value.toLowerCase() == AuthService.superAdminEmail) {
                    return "This is reserved for Super Admin";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Temporary Password",
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = (v ?? "").trim();
                  if (value.isEmpty) return "Password is required";
                  if (value.length < 6) return "At least 6 characters";
                  return null;
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: "Role",
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: "employee", child: Text("Employee")),
                  DropdownMenuItem(value: "admin", child: Text("Admin")),
                ],
                onChanged: (v) => setState(() => _role = v ?? "employee"),
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _loading ? null : _createUser,
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Create Account"),
              ),

              if (_msg != null) ...[
                const SizedBox(height: 14),
                Text(_msg!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
