import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/credit_card.dart';

/// Cartões de crédito do usuário em users/{uid}/cards.
class CardService {
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('cards');

  Stream<List<CreditCard>> watch() => _col.snapshots().map((s) {
        final docs = [...s.docs]..sort((a, b) {
            final ta = a.data()['createdAt'] as Timestamp?;
            final tb = b.data()['createdAt'] as Timestamp?;
            if (ta == null || tb == null) return 0;
            return ta.compareTo(tb);
          });
        return [for (final d in docs) CreditCard.fromMap(d.id, d.data())];
      });

  /// Cria o cartão e devolve com o id preenchido.
  Future<CreditCard> add(CreditCard card) async {
    final ref = _col.doc();
    await ref.set({...card.toMap(), 'createdAt': FieldValue.serverTimestamp()});
    return card.copyWith(id: ref.id);
  }

  /// Apaga apelido e final quando o usuário os deixou em branco.
  Future<void> update(CreditCard card) => _col.doc(card.id!).update({
        'nickname': FieldValue.delete(),
        'last4': FieldValue.delete(),
        ...card.toMap(),
      });

  /// Os lançamentos do cartão ficam, mostrados como "cartão excluído".
  Future<void> delete(String id) => _col.doc(id).delete();
}
