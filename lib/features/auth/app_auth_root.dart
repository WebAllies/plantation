import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_session_gate.dart';
import '../onboarding/onboarding_page.dart';

class AppAuthRoot extends StatelessWidget {
  const AppAuthRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const OnboardingPage();
        }

        return AppSessionGate(user: user);
      },
    );
  }
}
