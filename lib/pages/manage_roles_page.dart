import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ManageRolesPage extends StatefulWidget {
  const ManageRolesPage({super.key});

  @override
  State<ManageRolesPage> createState() => _ManageRolesPageState();
}

class _ManageRolesPageState extends State<ManageRolesPage> {
  String _currentRole = 'employee';
  bool _loadingRole = true;

  String _normalizeRole(dynamic value) {
    final raw = (value ?? '').toString().toLowerCase().trim();
    if (raw == 'superadmin' || raw == 'super_admin' || raw == 'super admin') {
      return 'super_admin';
    }
    if (raw == 'admin') return 'admin';
    if (raw == 'employee') return 'employee';
    return raw.isEmpty ? 'employee' : raw;
  }

  bool get _isSuperAdmin => _currentRole == 'super_admin';
  bool get _isAdmin => _isSuperAdmin || _currentRole == 'admin';

  @override
  void initState() {
    super.initState();
    _loadCurrentRole();
  }

  Future<void> _loadCurrentRole() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _loadingRole = false);
        return;
      }
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final rawRole = _normalizeRole(snap.data()?['role']);
      if (!mounted) return;
      setState(() {
        _currentRole = rawRole;
        _loadingRole = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRole = false);
    }
  }

  Future<void> _resetAppPin({required String targetUid}) async {
    final actor = FirebaseAuth.instance.currentUser;
    if (actor == null) return;

    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(targetUid);
      await ref.set({
        'security': {
          'appLock': {'enforced': true, 'pinPolicy': 'v1_6digit_cooldown'},
        },
      }, SetOptions(merge: true));
      await ref.update({
        'security.appLock.pinVersion': FieldValue.increment(1),
        'security.appLock.resetAt': FieldValue.serverTimestamp(),
        'security.appLock.resetByUid': actor.uid,
        'security.appLock.resetByRole': _currentRole,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('App PIN reset issued ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PIN reset failed: $e')));
    }
  }

  Future<void> _updateRole({
    required String targetUid,
    required String? newRole,
  }) async {
    if (newRole == null || !_isSuperAdmin) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .update({'role': newRole});
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Role updated to $newRole ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Role update failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text("Manage User Roles")),
        body: const Center(child: Text("You are not allowed to manage users.")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Manage User Roles & PIN")),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection("users").snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Failed to load users: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs;
          if (users.isEmpty) {
            return const Center(child: Text('No users found.'));
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final data = user.data();
              final role = _normalizeRole(data["role"]);
              final email = (data["email"] ?? "unknown").toString();
              final targetUid = user.id;
              final isReservedSuper =
                  email.toLowerCase() == "superadmin@iot.com";
              final isSuperRole = role == 'super_admin';
              final canUseDropdownRole = role == 'employee' || role == 'admin';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  email,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "uid: $targetUid",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: "Reset App PIN",
                            icon: const Icon(Icons.lock_reset),
                            onPressed: (isReservedSuper || isSuperRole)
                                ? null
                                : () => _resetAppPin(targetUid: targetUid),
                          ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        children: [
                          const Text("Role: "),
                          const SizedBox(width: 8),
                          Expanded(
                            child: (isReservedSuper || isSuperRole)
                                ? const Text("super_admin (reserved)")
                                : DropdownButton<String>(
                                    value: canUseDropdownRole ? role : null,
                                    hint: Text(
                                      canUseDropdownRole
                                          ? "Select role"
                                          : "Unsupported role: $role",
                                    ),
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                        value: "employee",
                                        child: Text("Employee"),
                                      ),
                                      DropdownMenuItem(
                                        value: "admin",
                                        child: Text("Admin"),
                                      ),
                                    ],
                                    onChanged:
                                        (_isSuperAdmin && canUseDropdownRole)
                                        ? (newRole) => _updateRole(
                                            targetUid: targetUid,
                                            newRole: newRole,
                                          )
                                        : null,
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
