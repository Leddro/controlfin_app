import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/market/contribution.dart';

/// Carteira atual do usuário em users/{uid}/settings/holdings.
class HoldingsService {
  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore.instance
      .collection('users')
      .doc(FirebaseAuth.instance.currentUser!.uid)
      .collection('settings')
      .doc('holdings');

  Stream<List<Holding>> watch() => _doc.snapshots().map((s) {
        final items = s.data()?['items'];
        if (items is! List) return const <Holding>[];
        return [
          for (final i in items)
            if (i is Map) Holding.fromMap(Map<String, dynamic>.from(i)),
        ];
      });

  Future<void> save(List<Holding> items) => _doc.set({
        'items': [for (final h in items) h.toMap()],
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
