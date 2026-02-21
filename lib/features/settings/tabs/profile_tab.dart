import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileTab extends StatefulWidget {
  final String name;
  final String email;
  final String role;
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
  final _nameCtrl = TextEditingController();

  // simple personalization without storage
  int _avatarColor = Colors.green.value;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.name;
    _loadProfilePrefs();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfilePrefs() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final doc = await FirebaseFirestore.instance.collection("users").doc(u.uid).get();
    final data = doc.data() ?? {};
    if (!mounted) return;

    setState(() {
      _avatarColor = (data["avatarColor"] is int) ? data["avatarColor"] as int : Colors.green.value;
    });
  }

  String _initials(String nameOrEmail) {
    final t = nameOrEmail.trim();
    if (t.isEmpty) return "?";
    final parts = t.split(RegExp(r"\s+"));
    if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveProfile() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) {
      _toast("Name cannot be empty.");
      return;
    }

    try {
      setState(() => _busy = true);

      await FirebaseFirestore.instance.collection("users").doc(u.uid).update({
        "name": newName,
        "avatarColor": _avatarColor,
      });

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
              decoration: const InputDecoration(labelText: "New password (min 6)"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
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
      Colors.green, Colors.blue, Colors.orange, Colors.purple, Colors.teal, Colors.red
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

  @override
  Widget build(BuildContext context) {
    final displayName = widget.name.trim().isEmpty ? (widget.email) : widget.name;
    final initials = _initials(displayName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: Color(_avatarColor),
                      child: Text(initials,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
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
                          child: const Icon(Icons.palette, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(widget.email, style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 8),
                      Chip(label: Text(widget.role), visualDensity: VisualDensity.compact),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Account", style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),

                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: "Display name",
                    prefixIcon: Icon(Icons.badge),
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _saveProfile,
                        icon: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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

                const SizedBox(height: 10),

                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: _busy ? null : widget.onLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text("Logout"),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
