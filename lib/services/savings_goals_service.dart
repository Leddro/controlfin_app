import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/savings_goal.dart';

/// Metas de conquista em users/{uid}/settings/goals (documento próprio:
/// settings/profile é regravado inteiro a cada salvamento).
class SavingsGoalsService {
  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore.instance
      .collection('users')
      .doc(FirebaseAuth.instance.currentUser!.uid)
      .collection('settings')
      .doc('goals');

  Stream<List<SavingsGoal>> watch() => _doc.snapshots().map((s) {
        final items = s.data()?['items'];
        if (items is! List) return const <SavingsGoal>[];
        return [
          for (final i in items)
            if (i is Map) SavingsGoal.fromMap(Map<String, dynamic>.from(i)),
        ].whereType<SavingsGoal>().toList();
      });

  Future<void> save(List<SavingsGoal> items) => _doc.set({
        'items': [for (final g in items) g.toMap()],
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
