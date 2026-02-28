import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';
import 'app_auth_root.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _auth = AuthService();

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();

  bool _loading = false;
  bool _hidePass = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AppAuthRoot()),
      (route) => false,
    );
  }

  Future<void> _loginEmail() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      if (!_formKey.currentState!.validate()) {
        setState(() => _loading = false);
        return;
      }

      await _auth.signInEmail(_email.text, _pass.text);
      if (!mounted) return;
      _goHome();
    } catch (e) {
      setState(() => _error = _prettyError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginGoogle() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      await _auth.signInGoogle();
      if (!mounted) return;
      _goHome();
    } catch (e) {
      setState(() => _error = _prettyError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _prettyError(String raw) {
    final s = raw.toLowerCase();
    if (s.contains("wrong-password") || s.contains("invalid-credential")) {
      return "Wrong password. Try again.";
    }
    if (s.contains("user-not-found")) {
      return "No account found for this email.";
    }
    if (s.contains("invalid-email")) {
      return "Invalid email format.";
    }
    if (s.contains("network-request-failed")) {
      return "Network error. Check your internet connection.";
    }
    if (s.contains("canceled") || s.contains("cancelled")) {
      return "Google sign-in canceled.";
    }
    return "Login failed. ${raw.replaceAll('Exception:', '').trim()}";
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w < 600 ? 420 : 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),

                // Header Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Color(0xFF2E7D32)),
                  ),
                  child: Column(
                    children: const [
                      Icon(Icons.eco, size: 56, color: Color(0xFF2E7D32)),
                      SizedBox(height: 10),
                      Text(
                        "Smart IoT Aquaponics",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        "Sign in to monitor and manage your system",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF2E7D32)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Form Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF2E7D32)),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: "Email",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.email),
                          ),
                          validator: (v) {
                            final value = (v ?? "").trim();
                            if (value.isEmpty) return "Email is required";
                            if (!value.contains("@") || !value.contains(".")) {
                              return "Enter a valid email";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: _pass,
                          obscureText: _hidePass,
                          decoration: InputDecoration(
                            labelText: "Password",
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _hidePass = !_hidePass),
                              icon: Icon(
                                _hidePass
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                          validator: (v) {
                            final value = (v ?? "").trim();
                            if (value.isEmpty) return "Password is required";
                            if (value.length < 6) {
                              return "Password must be at least 6 characters";
                            }
                            return null;
                          },
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _loginEmail,
                            child: _loading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text("Login"),
                          ),
                        ),

                        const SizedBox(height: 12),

                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : _loginGoogle,
                            icon: const Icon(Icons.g_mobiledata, size: 28),
                            label: const Text("Continue with Google"),
                          ),
                        ),

                        const SizedBox(height: 10),

                        const Text(
                          "Note: Employees are created by Admin.\nIf you don’t have credentials, contact your admin.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF2E7D32),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Footer hint
                Text(
                  "Super Admin: ${AuthService.superAdminEmail}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF2E7D32),
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
