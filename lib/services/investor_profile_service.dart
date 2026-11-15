import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/investor_profile.dart';

/// Perfil de investidor em users/{uid}/settings/investor, separado das metas
/// (que regravam o documento "profile" inteiro a cada alteração).
class InvestorProfileService {
  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore.instance
      .collection('users')
      .doc(FirebaseAuth.instance.currentUser!.uid)
      .collection('settings')
      .doc('investor');

  /// Emite nulo enquanto o perfil não foi montado.
  Stream<InvestorProfile?> watch() => _doc.snapshots().map((s) {
        final data = s.data();
        if (data == null) return null;
        final profile = InvestorProfile.fromMap(data);
        return profile.isComplete ? profile : null;
      });

  Future<void> save(InvestorProfile profile) => _doc.set(profile.toMap());
}
