import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/tx.dart';

class TxService {
  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore.instance
      .collection('users')
      .doc(FirebaseAuth.instance.currentUser!.uid)
      .collection('transactions');

  Stream<List<Tx>> watchMonth(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return _col
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Tx.fromDoc).toList());
  }

  Future<void> add(Tx tx) => _col.add(tx.toMap());

  Future<void> delete(String id) => _col.doc(id).delete();
}
