import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_settings.dart';

class SettingsService {
  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore.instance
      .collection('users')
      .doc(FirebaseAuth.instance.currentUser!.uid)
      .collection('settings')
      .doc('profile');

  Stream<UserSettings> watch() => _doc.snapshots().map((s) => UserSettings.fromMap(s.data()));

  Future<void> save(UserSettings s) => _doc.set(s.toMap());
}
