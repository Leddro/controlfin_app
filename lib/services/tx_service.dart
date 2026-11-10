import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/tx.dart';

class TxService {
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
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

  /// Grava vários lançamentos de uma vez (série mensal ou parcelas).
  Future<void> addAll(List<Tx> list) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final t in list) {
      batch.set(_col.doc(), t.toMap());
    }
    await batch.commit();
  }

  Future<void> deleteOne(String id) => _col.doc(id).delete();

  /// Apaga o lançamento da data [from] e todos os seguintes da mesma série.
  Future<void> deleteGroupFrom(String groupId, DateTime from) async {
    final snap = await _col.where('groupId', isEqualTo: groupId).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      final date = (doc.data()['date'] as Timestamp).toDate();
      if (!date.isBefore(from)) batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Média mensal dos ganhos dos últimos [months] meses completos.
  Future<double?> averageIncome({int months = 3}) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - months);
    final end = DateTime(now.year, now.month);
    final snap = await _col
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .get();

    final perMonth = <String, double>{};
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['type'] != 'income') continue;
      final date = (d['date'] as Timestamp).toDate();
      final key = '${date.year}-${date.month}';
      perMonth[key] = (perMonth[key] ?? 0) + (d['amount'] as num).toDouble();
    }

    if (perMonth.isEmpty) return null;
    return perMonth.values.reduce((a, b) => a + b) / perMonth.length;
  }
}
