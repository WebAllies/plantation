import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MyScanHistoryPage extends StatelessWidget {
  const MyScanHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    final q = FirebaseFirestore.instance
        .collection('ai_scans')
        .where('userId', isEqualTo: user.uid); // ✅ no orderBy (avoids index)

    return Scaffold(
      appBar: AppBar(title: const Text("My Scan History")),
      body: StreamBuilder<QuerySnapshot>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text("Error loading history:\n${snap.error}"),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("No scans yet."));
          }

          // ✅ sort locally by createdAt desc (null-safe)
          docs.sort((a, b) {
            final ad = (a.data() as Map<String, dynamic>)['createdAt'];
            final bd = (b.data() as Map<String, dynamic>)['createdAt'];
            final at = ad is Timestamp ? ad.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            final bt = bd is Timestamp ? bd.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            return bt.compareTo(at);
          });

          final dtf = DateFormat('dd MMM yyyy, HH:mm');

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final label = (d['label'] ?? '').toString();
              final conf = (d['confidence'] ?? 0.0) as num;

              final ts = d['createdAt'];
              final dt = ts is Timestamp ? ts.toDate() : null;

              return Card(
                child: ListTile(
                  leading: const Icon(Icons.psychology),
                  title: Text(label),
                  subtitle: Text(
                    "Confidence: ${(conf * 100).toStringAsFixed(1)}%  •  ${dt == null ? '—' : dtf.format(dt)}",
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
