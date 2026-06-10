import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:iot_aqua_app/core/security/app_lock_models.dart';
import 'package:iot_aqua_app/core/security/app_lock_service.dart';
import 'package:iot_aqua_app/features/auth/app_auth_root.dart';

// OPTIONAL (only if you want real profile photo upload):
// Add to pubspec.yaml:
//   image_picker: ^1.0.7
//   firebase_storage: ^12.0.1
//
// import 'package:image_picker/image_picker.dart';
// import 'package:firebase_storage/firebase_storage.dart';

class ProfileTab extends StatefulWidget {
  final String name;
  final String email;
  final String role; // "Admin" | "Super Admin" | "Employee"
  final Future<void> Function() onLogout;

  const ProfileTab({
    super.key,
    required this.name,
    required this.email,
    required this.role,
    required this.onLogout,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _busy = false;
  final AppLockService _appLockService = AppLockService();
  bool _lockBusy = false;
  bool _pinConfigured = false;
  bool _biometricEnabled = false;

  // Editable fields (industry-level profile)
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Read-only work fields (from Firestore)

  final String _assignedZone = "—"; // warehouse/zone/site
  final String _accessLevel = "—"; // e.g., Read / Write / Full

  // Security / audit info (from Firestore)
  DateTime? _lastLoginAt;
  DateTime? _lastActivityAt;

  // Analytics (from Firestore)
  int _requestsCount = 0;
  int _approvalsCount = 0;
  int _aiUsageCount = 0;

  // Personalization
  int _avatarColor = Colors.green.value;
  String? _photoUrl; // if you later store profile photo URL

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.name;
    _loadProfile(); // loads everything (prefs + work + security + stats)
    _tryWriteLastLogin(); // updates last login timestamp (audit)
    _loadLockStatus();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  /// Firestore user doc expected:
  /// users/{uid} {
  ///   name, phone, role,
  ///   employeeId, department, assignedZone, accessLevel,
  ///   avatarColor, photoUrl,
  ///   lastLoginAt, lastActivityAt,
  ///   stats: { requestsCount, approvalsCount, aiUsageCount }
  /// }
  Future<void> _loadProfile() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(u.uid)
          .get();
      final data = doc.data() ?? {};
      if (!mounted) return;

      final stats = (data["stats"] is Map) ? (data["stats"] as Map) : const {};

      setState(() {
        _avatarColor = (data["avatarColor"] is int)
            ? data["avatarColor"] as int
            : Colors.green.value;
        _photoUrl = (data["photoUrl"] is String)
            ? data["photoUrl"] as String
            : null;

        _nameCtrl.text =
            (data["name"] is String &&
                (data["name"] as String).trim().isNotEmpty)
            ? (data["name"] as String)
            : widget.name;

        _phoneCtrl.text = (data["phone"] is String)
            ? (data["phone"] as String)
            : "";

        _lastLoginAt = (data["lastLoginAt"] is Timestamp)
            ? (data["lastLoginAt"] as Timestamp).toDate()
            : null;
        _lastActivityAt = (data["lastActivityAt"] is Timestamp)
            ? (data["lastActivityAt"] as Timestamp).toDate()
            : null;

        _requestsCount = _asInt(stats["requestsCount"]);
        _approvalsCount = _asInt(stats["approvalsCount"]);
        _aiUsageCount = _asInt(stats["aiUsageCount"]);
      });
    } catch (_) {
      // ignore UI crash; keep defaults
    }
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  Future<void> _tryWriteLastLogin() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    try {
      await FirebaseFirestore.instance.collection("users").doc(u.uid).set({
        "lastLoginAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _loadLockStatus() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    try {
      final state = await _appLockService.getLockState(u.uid);
      if (!mounted) return;
      setState(() {
        _pinConfigured = !state.needsSetup;
        _biometricEnabled = state.biometricEnabled;
      });
    } catch (_) {}
  }

  Future<void> _changePinDialog() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Change App PIN"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: "Current PIN",
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: "New PIN (6 digits)",
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: "Confirm new PIN",
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final currentPin = currentCtrl.text.trim();
              final newPin = newCtrl.text.trim();
              final confirmPin = confirmCtrl.text.trim();

              if (!AppLockService.isValidPin(newPin)) {
                _toast("New PIN must be exactly 6 digits.");
                return;
              }
              if (newPin != confirmPin) {
                _toast("PIN confirmation does not match.");
                return;
              }

              setState(() => _lockBusy = true);
              final verify = await _appLockService.verifyPin(
                uid: u.uid,
                pin: currentPin,
              );
              if (verify.status != AppLockVerifyStatus.success) {
                setState(() => _lockBusy = false);
                _toast("Current PIN is incorrect.");
                return;
              }

              await _appLockService.setPin(
                uid: u.uid,
                pin: newPin,
                biometricEnabled: _biometricEnabled,
              );

              if (!mounted) return;
              Navigator.pop(context);
              setState(() => _lockBusy = false);
              _toast("App PIN changed ✅");
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );

    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _resetPinOnDevice() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Reset PIN on this device?"),
            content: const Text(
              "This clears your local app PIN and requires immediate setup again.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Reset"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _lockBusy = true);
    await _appLockService.resetPinOnDevice(u.uid);

    if (!mounted) return;
    setState(() => _lockBusy = false);
    _toast("PIN reset. Please set a new PIN.");

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AppAuthRoot()),
      (route) => false,
    );
  }

  Future<void> _toggleBiometric(bool value) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    setState(() => _lockBusy = true);
    await _appLockService.setBiometricPreference(u.uid, value);

    if (!mounted) return;
    setState(() {
      _biometricEnabled = value;
      _lockBusy = false;
    });
    _toast("Biometric preference updated.");
  }

  String _initials(String nameOrEmail) {
    final t = nameOrEmail.trim();
    if (t.isEmpty) return "?";
    final parts = t.split(RegExp(r"\s+"));
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts[0].characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool get _isSuperAdmin => widget.role.toLowerCase().contains("super");
  bool get _isAdmin =>
      widget.role.toLowerCase().contains("admin") || _isSuperAdmin;
  bool get _isEmployee => widget.role.toLowerCase().contains("employee");

  Future<void> _saveProfile() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final newName = _nameCtrl.text.trim();
    final newPhone = _phoneCtrl.text.trim();

    if (newName.isEmpty) {
      _toast("Name cannot be empty.");
      return;
    }

    try {
      setState(() => _busy = true);

      await FirebaseFirestore.instance.collection("users").doc(u.uid).set({
        "name": newName,
        "phone": newPhone,
        "avatarColor": _avatarColor,
        // Keep role in Firestore too (read-only from UI)
        "role": widget.role,
        "updatedAt": FieldValue.serverTimestamp(),
        "lastActivityAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await u.updateDisplayName(newName);

      if (!mounted) return;
      setState(() => _busy = false);
      _toast("Profile updated ✅");
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast("Failed: $e");
    }
  }

  Future<void> _changePasswordDialog() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final providers = u.providerData.map((p) => p.providerId).toList();
    final isPasswordUser = providers.contains("password");
    if (!isPasswordUser) {
      _toast("Password change is only for Email/Password accounts.");
      return;
    }

    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Change Password"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Current password"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "New password (min 6)",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final oldPass = oldCtrl.text.trim();
              final newPass = newCtrl.text.trim();

              if (newPass.length < 6) {
                _toast("New password must be at least 6 characters.");
                return;
              }

              try {
                setState(() => _busy = true);

                final cred = EmailAuthProvider.credential(
                  email: u.email ?? "",
                  password: oldPass,
                );

                await u.reauthenticateWithCredential(cred);
                await u.updatePassword(newPass);

                // audit
                await FirebaseFirestore.instance
                    .collection("users")
                    .doc(u.uid)
                    .set({
                      "lastActivityAt": FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                if (!mounted) return;
                setState(() => _busy = false);
                Navigator.pop(context);
                _toast("Password updated ✅");
              } catch (e) {
                if (!mounted) return;
                setState(() => _busy = false);
                _toast("Failed: $e");
              }
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );

    oldCtrl.dispose();
    newCtrl.dispose();
  }

  Future<void> _pickAvatarColor() async {
    final colors = <Color>[
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.red,
      Colors.brown,
      Colors.indigo,
    ];

    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((c) {
              return InkWell(
                onTap: () {
                  setState(() => _avatarColor = c.value);
                  Navigator.pop(context);
                },
                child: CircleAvatar(backgroundColor: c, radius: 22),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // OPTIONAL (real profile photo upload). Uncomment imports + pubspec deps above to use.
  /*
  Future<void> _pickAndUploadPhoto() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    try {
      setState(() => _busy = true);

      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (x == null) {
        setState(() => _busy = false);
        return;
      }

      final ref = FirebaseStorage.instance.ref("users/${u.uid}/profile.jpg");
      await ref.putFile(File(x.path));
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection("users").doc(u.uid).set({
        "photoUrl": url,
        "lastActivityAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _busy = false;
      });

      _toast("Profile picture updated ✅");
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast("Failed: $e");
    }
  }
  */

  Future<void> _openActivityLog() async {
    // Minimal, dissertation-ready: show last activity + basic info.
    // If you already have /logs page, replace this with Navigator.push to it.
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("My Activity"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Last login: ${_fmt(_lastLoginAt)}"),
            const SizedBox(height: 8),
            Text("Last activity: ${_fmt(_lastActivityAt)}"),
            const SizedBox(height: 12),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return "—";
    final y = dt.year.toString().padLeft(4, "0");
    final m = dt.month.toString().padLeft(2, "0");
    final d = dt.day.toString().padLeft(2, "0");
    final hh = dt.hour.toString().padLeft(2, "0");
    final mm = dt.minute.toString().padLeft(2, "0");
    return "$y-$m-$d  $hh:$mm";
  }

  Widget _kv(String k, String v, {IconData? icon}) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: icon == null ? null : Icon(icon, size: 20),
      title: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(v),
    );
  }

  Widget _statChip(String label, int value, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text("$label: $value"),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _nameCtrl.text.trim().isEmpty
        ? (widget.email)
        : _nameCtrl.text.trim();
    final initials = _initials(displayName);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // ===== Header =====
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: Color(_avatarColor),
                      // If you enable photoUrl, you can replace with NetworkImage
                      // backgroundImage: (_photoUrl != null) ? NetworkImage(_photoUrl!) : null,
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: InkWell(
                        onTap: _busy ? null : _pickAvatarColor,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          child: const Icon(
                            Icons.palette,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // OPTIONAL: photo upload button (uncomment if you enable upload)
                    /*
                    Positioned(
                      top: 0,
                      right: 0,
                      child: InkWell(
                        onTap: _busy ? null : _pickAndUploadPhoto,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    */
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.email,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(widget.role),
                            visualDensity: VisualDensity.compact,
                          ),
                          if (_isSuperAdmin)
                            const Chip(
                              label: Text("Highest Privilege"),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ===== Account (editable) =====
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Account",
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: "Display name",
                    prefixIcon: Icon(Icons.badge),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: "Phone number",
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _saveProfile,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: const Text("Save"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _changePasswordDialog,
                        icon: const Icon(Icons.lock_reset),
                        label: const Text("Password"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ===== App Lock =====
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "App Lock",
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text("PIN Status"),
                  subtitle: Text(
                    _pinConfigured
                        ? "Configured on this device"
                        : "Setup required",
                  ),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.pin),
                  title: const Text("Change PIN"),
                  subtitle: const Text("Update your local 6-digit app PIN"),
                  onTap: (_busy || _lockBusy || !_pinConfigured)
                      ? null
                      : _changePinDialog,
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text("Use biometrics"),
                  subtitle: const Text(
                    "Fingerprint/Face unlock on this device",
                  ),
                  value: _biometricEnabled,
                  onChanged: (_busy || _lockBusy || !_pinConfigured)
                      ? null
                      : _toggleBiometric,
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restart_alt),
                  title: const Text("Reset PIN on this device"),
                  subtitle: const Text("Force setup of a new app PIN locally"),
                  onTap: (_busy || _lockBusy) ? null : _resetPinOnDevice,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ===== Security & Logs =====
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Security & Activity",
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: const Text("View my activity"),
                  subtitle: const Text(
                    "Last login, last activity, and audit-ready info",
                  ),
                  onTap: _busy ? null : _openActivityLog,
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text("Privacy"),
                  subtitle: const Text(
                    "Your data is stored securely in Firebase (Firestore).",
                  ),
                  onTap: () => _toast(
                    "Add a Privacy page if your dissertation requires it.",
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ===== Logout =====
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          onPressed: _busy ? null : widget.onLogout,
          icon: const Icon(Icons.logout),
          label: const Text("Logout"),
        ),
      ],
    );
  }
}
