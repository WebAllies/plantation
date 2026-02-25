import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_core/firebase_core.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static Future<void>? _googleSignInInitFuture;

  static const String superAdminEmail = "superadmin@iot.com";

  Future<void> _ensureGoogleSignInInitialized() {
    return _googleSignInInitFuture ??= _googleSignIn.initialize();
  }

  Future<UserCredential> signInEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
    await ensureUserDoc(cred.user);
    return cred;
  }

  Future<UserCredential> registerEmail(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
    await ensureUserDoc(cred.user);
    return cred;
  }

  Future<void> createUserWithRole({
    required String email,
    required String password,
    required String name,
    required String role, // "admin" or "employee"
  }) async {
    // Create user in Firebase Auth
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );

    // Create/merge user document with role
    await _db.collection("users").doc(cred.user!.uid).set({
      "uid": cred.user!.uid,
      "email": email.trim(),
      "name": name.trim(),
      "role": role,
      "createdAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> createUserWithRoleSecondaryApp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    // Create a secondary Firebase app so current super admin stays logged in
    final secondaryApp = await Firebase.initializeApp(
      name: "SecondaryApp",
      options: Firebase.app().options,
    );

    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

    final cred = await secondaryAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );

    await _db.collection("users").doc(cred.user!.uid).set({
      "uid": cred.user!.uid,
      "email": email.trim(),
      "name": name.trim(),
      "role": role,
      "createdAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Sign out secondary and delete app instance
    await secondaryAuth.signOut();
    await secondaryApp.delete();
  }

  Future<UserCredential> signInGoogle() async {
    await _ensureGoogleSignInInitialized();

    final googleUser = await _googleSignIn.authenticate();

    final googleAuth = googleUser.authentication;
    if (googleAuth.idToken == null || googleAuth.idToken!.isEmpty) {
      throw Exception("Google sign-in failed: missing ID token");
    }

    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    final cred = await _auth.signInWithCredential(credential);
    await ensureUserDoc(cred.user);
    return cred;
  }

  Future<void> signOut() async {
    try {
      await _ensureGoogleSignInInitialized();
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  Future<void> ensureUserDoc(User? user) async {
    if (user == null) return;

    final ref = _db.collection("users").doc(user.uid);
    final doc = await ref.get();

    if (!doc.exists) {
      final role = (user.email?.toLowerCase() == superAdminEmail)
          ? "super_admin"
          : "employee";

      await ref.set({
        "uid": user.uid,
        "email": user.email ?? "",
        "name": user.displayName ?? "",
        "role": role,
        "createdAt": FieldValue.serverTimestamp(),
      });
    } else {
      // Optional: keep superadmin enforced even if doc exists
      final data = doc.data() ?? {};
      final currentRole = (data["role"] ?? "employee").toString();
      if (user.email?.toLowerCase() == superAdminEmail &&
          currentRole != "super_admin") {
        await ref.update({"role": "super_admin"});
      }
    }
  }
}
