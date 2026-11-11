import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/app_logo.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _auth = AuthService();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    if (_email.text.trim().isEmpty) {
      setState(() =>
          _error = 'Digite seu e-mail para receber o link de redefinição.');
      return;
    }
    await _run(() => _auth.resetPassword(_email.text));
    if (mounted && _error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link de redefinição enviado.')));
    }
  }

  void _submit() => _run(() => _creating
      ? _auth.signUp(_email.text, _password.text)
      : _auth.signIn(_email.text, _password.text));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo + nome
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppLogo(size: 56),
                    const SizedBox(width: 16),
                    RichText(
                      text: TextSpan(
                        style: theme.textTheme.displaySmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                        children: const [
                          TextSpan(
                              text: 'Control',
                              style: TextStyle(color: Colors.white)),
                          TextSpan(
                              text: 'Fin',
                              style: TextStyle(color: Color(0xFFFBBF24))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Controle total das suas finanças.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(_auth.signInWithGoogle),
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 32),
                  label: const Text('Continuar com Google'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Row(children: [
                    Expanded(child: Divider()),
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('ou')),
                    Expanded(child: Divider()),
                  ]),
                ),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'E-mail', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                      labelText: 'Senha', border: OutlineInputBorder()),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_creating ? 'Criar conta' : 'Entrar'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _creating = !_creating),
                  child: Text(_creating ? 'Já tenho conta' : 'Criar uma conta'),
                ),
                if (!_creating)
                  TextButton(
                      onPressed: _busy ? null : _forgot,
                      child: const Text('Esqueci minha senha')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
