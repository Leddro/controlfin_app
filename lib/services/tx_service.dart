import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/tx.dart';

class TxService {
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('transactions');

  Stream<List<Tx>> _watch(String field, DateTime from, DateTime to) => _col
      .where(field, isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .where(field, isLessThan: Timestamp.fromDate(to))
      .snapshots()
      .map((s) => s.docs.map(Tx.fromDoc).toList());

  /// Lançamentos que contam no mês: pela data, ou pelo vencimento da
  /// fatura quando é no crédito (ver [Tx.cashDate]).
  Stream<List<Tx>> watchMonth(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return _combineAll([
      _watch('date', start, end),
      _watch('billDate', start, end),
    ]).map((l) => mergeCashMonth(l[0], l[1]));
  }

  /// O mês como a tela inicial mostra: o que conta nele, as compras no
  /// crédito feitas nele que só serão pagas depois, e o que já está na
  /// fatura do mês seguinte.
  Stream<MonthView> watchMonthView(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final afterNext = DateTime(month.year, month.month + 2);
    return _combineAll([
      _watch('date', start, end),
      _watch('billDate', start, end),
      _watch('billDate', end, afterNext),
    ]).map((l) => buildMonthView(month, l[0], l[1], l[2]));
  }

  /// Lançamentos de [from] até [to] (inclusive) pela data da compra.
  Future<List<Tx>> fetchRange(DateTime from, DateTime to) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day + 1);
    final snap = await _col
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .get();
    return snap.docs.map(Tx.fromDoc).toList();
  }

  /// Lançamentos que contam entre [from] e [to] (inclusive), pela data em
  /// que o dinheiro sai, como na tela inicial.
  Future<List<Tx>> fetchCashRange(DateTime from, DateTime to) async {
    final start = Timestamp.fromDate(DateTime(from.year, from.month, from.day));
    final end = Timestamp.fromDate(DateTime(to.year, to.month, to.day + 1));
    final results = await Future.wait([
      _col
          .where('date', isGreaterThanOrEqualTo: start)
          .where('date', isLessThan: end)
          .get(),
      _col
          .where('billDate', isGreaterThanOrEqualTo: start)
          .where('billDate', isLessThan: end)
          .get(),
    ]);
    return mergeCashMonth(results[0].docs.map(Tx.fromDoc).toList(),
        results[1].docs.map(Tx.fromDoc).toList());
  }

  /// Gastos no crédito da fatura que vence em [due].
  Future<List<Tx>> fetchBill(DateTime due) async {
    final day = DateTime(due.year, due.month, due.day);
    final snap = await _col
        .where('billDate', isGreaterThanOrEqualTo: Timestamp.fromDate(day))
        .where('billDate',
            isLessThan: Timestamp.fromDate(day.add(const Duration(days: 1))))
        .get();
    return snap.docs.map(Tx.fromDoc).toList();
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

  Future<void> update(Tx tx) => _col.doc(tx.id!).update(tx.toMap());

  /// Apaga o lançamento [from] e os seguintes da mesma série. Usa a
  /// posição na série, porque as parcelas no crédito têm a mesma data.
  Future<void> deleteGroupFrom(String groupId, Tx from) async {
    final snap = await _col.where('groupId', isEqualTo: groupId).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      final t = Tx.fromDoc(doc);
      final later = t.index != from.index
          ? t.index > from.index
          : !t.date.isBefore(from.date);
      if (later || doc.id == from.id) batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Junta várias consultas do Firestore, emitindo a cada mudança de
  /// qualquer uma depois que todas responderam.
  static Stream<List<List<Tx>>> _combineAll(List<Stream<List<Tx>>> streams) {
    late StreamController<List<List<Tx>>> controller;
    final subs = <StreamSubscription<List<Tx>>>[];
    final latest = List<List<Tx>?>.filled(streams.length, null);

    controller = StreamController<List<List<Tx>>>(
      onListen: () {
        for (var i = 0; i < streams.length; i++) {
          subs.add(streams[i].listen((v) {
            latest[i] = v;
            if (latest.every((l) => l != null)) {
              controller.add([for (final l in latest) l!]);
            }
          }, onError: controller.addError));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
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

/// Une os lançamentos achados pela data e pelo vencimento da fatura,
/// mantendo só os que contam pelo critério de [Tx.cashDate], ordenados da
/// compra mais recente para a mais antiga.
///
/// [byDate] traz tudo cuja data está no período, inclusive compras no
/// crédito que só contam no mês da fatura; [byBill] traz as compras no
/// crédito cuja fatura vence no período.
List<Tx> mergeCashMonth(List<Tx> byDate, List<Tx> byBill) {
  final result = <String?, Tx>{};
  for (final t in byDate) {
    if (t.isCredit && t.billDate != null) continue;
    result[t.id] = t;
  }
  for (final t in byBill) {
    if (t.isCredit) result[t.id] = t;
  }
  return result.values.toList()..sort((a, b) => b.date.compareTo(a.date));
}

/// Um mês na tela inicial.
class MonthView {
  /// Lançamentos que contam no mês (crédito pelo vencimento da fatura).
  final List<Tx> counted;

  /// Compras no crédito feitas no mês que só serão pagas em faturas
  /// seguintes. Não entram nos totais do mês.
  final List<Tx> deferred;

  /// Gastos no crédito que já estão na fatura do mês seguinte, inclusive
  /// parcelas de compras antigas.
  final List<Tx> nextMonthCredit;

  const MonthView({
    required this.counted,
    this.deferred = const [],
    this.nextMonthCredit = const [],
  });

  double get deferredTotal => deferred.fold(0.0, (s, t) => s + t.amount);
  double get nextMonthTotal =>
      nextMonthCredit.fold(0.0, (s, t) => s + t.amount);
}

/// Monta o [MonthView] a partir das consultas: pela data no mês, pelo
/// vencimento no mês e pelo vencimento no mês seguinte.
MonthView buildMonthView(
  DateTime month,
  List<Tx> byDate,
  List<Tx> byBill,
  List<Tx> byNextBill,
) {
  final end = DateTime(month.year, month.month + 1);
  final deferred = byDate
      .where((t) =>
          t.type == TxType.expense &&
          t.isCredit &&
          t.billDate != null &&
          !t.billDate!.isBefore(end))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return MonthView(
    counted: mergeCashMonth(byDate, byBill),
    deferred: deferred,
    nextMonthCredit: byNextBill
        .where((t) => t.type == TxType.expense && t.isCredit)
        .toList(),
  );
}
