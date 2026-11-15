import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Cliente OAuth "web" do projeto Firebase (tipo 3 no google-services.json).
/// O login nativo do Android precisa dele para gerar o idToken do Firebase.
/// Não é segredo: o mesmo valor já está no google-services.json.
const _googleServerClientId =
    '310581093313-eeei75uepp2epotl4ieevsncgnmh2mmb.apps.googleusercontent.com';

class AuthService {
  final _auth = FirebaseAuth.instance;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signUp(String email, String password) => _auth
      .createUserWithEmailAndPassword(email: email.trim(), password: password);

  static Future<void>? _googleInit;

  /// Web: popup do Firebase. Android: seletor de contas nativo do Google,
  /// sem abrir o navegador (o redirecionamento pelo navegador perdia a
  /// sessão e mostrava "missing initial state").
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await _auth.signInWithPopup(GoogleAuthProvider());
      return;
    }
    final google = GoogleSignIn.instance;
    await (_googleInit ??=
        google.initialize(serverClientId: _googleServerClientId));
    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(code: 'missing-id-token');
    }
    await _auth
        .signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
  }

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() async {
    final usedGoogle = _auth.currentUser?.providerData
            .any((p) => p.providerId == 'google.com') ??
        false;
    if (!kIsWeb && usedGoogle) {
      // Para o seletor de contas aparecer de novo no próximo login.
      try {
        final google = GoogleSignIn.instance;
        await (_googleInit ??=
            google.initialize(serverClientId: _googleServerClientId));
        await google.signOut();
      } catch (_) {
        // Sair do Firebase é o que importa; o Google é só conveniência.
      }
    }
    await _auth.signOut();
  }

  /// Emite o usuário de novo quando nome ou foto mudam.
  Stream<User?> userChanges() => _auth.userChanges();

  Future<void> updateName(String name) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updateDisplayName(name.trim().isEmpty ? null : name.trim());
    await user.reload();
  }

  static String friendlyError(Object e) {
    if (e is GoogleSignInException) {
      return e.code == GoogleSignInExceptionCode.canceled
          ? 'Login com Google cancelado.'
          : 'Não foi possível entrar com o Google. Tente novamente.';
    }
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'O e-mail informado não é válido.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'E-mail ou senha incorretos.';
        case 'email-already-in-use':
          return 'Já existe uma conta com esse e-mail. Tente entrar.';
        case 'weak-password':
          return 'Use uma senha com pelo menos 6 caracteres.';
        case 'popup-closed-by-user':
        case 'canceled':
          return 'Login com Google cancelado.';
        case 'network-request-failed':
          return 'Sem conexão. Verifique sua internet.';
      }
    }
    return 'Algo deu errado. Tente novamente.';
  }
}
