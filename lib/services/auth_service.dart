import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signUp(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);

  /// Funciona na web (popup) e em Android/iOS sem pacote extra.
  Future<void> signInWithGoogle() => _auth.signInWithProvider(GoogleAuthProvider());

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() => _auth.signOut();

  static String friendlyError(Object e) {
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
