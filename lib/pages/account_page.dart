import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../services/auth_service.dart';
import '../services/avatar_service.dart';
import '../widgets/user_avatar.dart';
import '../widgets/app_header.dart';
import '../services/notification_samples_service.dart';
import 'bank_notifications_page.dart';
import 'dev_review_page.dart';
import 'cards_page.dart';

const _cardColor = Color(0xFF1A1A1A);

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _auth = AuthService();
  late final _stream = _auth.userChanges();
  final _avatar = AvatarService();
  late final _avatarStream = _avatar.watch();
  bool _savingPhoto = false;

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editName(User user) async {
    final controller = TextEditingController(text: user.displayName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seu nome'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Nome',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Salvar')),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (name == null) return;
    try {
      await _auth.updateName(name);
      if (mounted) _toast('Nome atualizado.');
    } catch (e) {
      if (mounted) _toast(AuthService.friendlyError(e));
    }
  }

  Future<void> _photoOptions({required bool hasCustom}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Escolher foto'),
            onTap: () => Navigator.pop(context, 'pick'),
          ),
          if (hasCustom)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('Remover foto'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
        ]),
      ),
    );
    if (choice == 'pick') await _pickPhoto();
    if (choice == 'remove') await _removePhoto();
  }

  Future<void> _pickPhoto() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null || !mounted) return;
    setState(() => _savingPhoto = true);
    try {
      await _avatar.save(await file.readAsBytes());
      if (mounted) _toast('Foto atualizada.');
    } catch (_) {
      if (mounted) {
        _toast('Não foi possível usar essa imagem. Tente uma foto JPG ou PNG.');
      }
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _savingPhoto = true);
    try {
      await _avatar.remove();
      if (mounted) _toast('Foto removida.');
    } catch (_) {
      if (mounted) _toast('Não foi possível remover a foto.');
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  Future<void> _resetPassword(String email) async {
    try {
      await _auth.resetPassword(email);
      if (mounted) _toast('Enviamos um link para redefinir a senha a $email.');
    } catch (e) {
      if (mounted) _toast(AuthService.friendlyError(e));
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text(
            'Seus dados continuam salvos. É só entrar de novo para vê-los.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sair')),
        ],
      ),
    );
    if (ok == true) await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Conta'),
      body: StreamBuilder<User?>(
        stream: _stream,
        initialData: FirebaseAuth.instance.currentUser,
        builder: (context, snap) {
          final user = snap.data;
          if (user == null) return const SizedBox.shrink();
          final providers = user.providerData.map((p) => p.providerId).toSet();
          final hasPassword = providers.contains('password');
          final email = user.email ?? '';
          final name = user.displayName?.trim() ?? '';
          final theme = Theme.of(context);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Column(children: [
                    StreamBuilder<Uint8List?>(
                      stream: _avatarStream,
                      builder: (context, avatarSnap) => _PhotoEditor(
                        busy: _savingPhoto,
                        onTap: () =>
                            _photoOptions(hasCustom: avatarSnap.data != null),
                        child: AvatarCircle(
                          bytes: avatarSnap.data,
                          photoUrl: user.photoURL,
                          label: name.isNotEmpty ? name : email,
                          radius: 48,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(name.isNotEmpty ? name : 'Sem nome',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(email, style: theme.textTheme.bodyMedium),
                  ]),
                  const SizedBox(height: 24),
                  _Section(title: 'Dados da conta', children: [
                    ListTile(
                      leading: const Icon(Icons.person_rounded),
                      title: const Text('Nome'),
                      subtitle: Text(name.isNotEmpty ? name : 'Não informado'),
                      trailing: const Icon(Icons.edit_rounded),
                      onTap: () => _editName(user),
                    ),
                    ListTile(
                      leading: const Icon(Icons.mail_rounded),
                      title: const Text('E-mail'),
                      subtitle: Text(email),
                    ),
                    ListTile(
                      leading: const Icon(Icons.login_rounded),
                      title: const Text('Forma de entrada'),
                      subtitle: Text([
                        if (providers.contains('google.com')) 'Google',
                        if (hasPassword) 'E-mail e senha',
                      ].join(' e ')),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _Section(title: 'Finanças', children: [
                    ListTile(
                      leading: const Icon(Icons.credit_card_rounded),
                      title: const Text('Meus cartões'),
                      subtitle: const Text(
                          'Bancos, fechamento e vencimento das faturas'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CardsPage())),
                    ),
                    ListTile(
                      leading: const Icon(Icons.notifications_active_rounded),
                      title: const Text('Notificações dos bancos'),
                      subtitle: const Text(
                          'Compras e Pix lidos das notificações: confirmar e '
                          'validar as leituras'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const BankNotificationsPage())),
                    ),
                  ]),
                  if (isDeveloper(user)) ...[
                    const SizedBox(height: 16),
                    _Section(title: 'Desenvolvedor', children: [
                      ListTile(
                        leading: const Icon(Icons.fact_check_rounded),
                        title: const Text('Revisão das notificações'),
                        subtitle: const Text(
                            'Textos dos bancos enviados pelos usuários e a '
                            'leitura de cada um'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const DevReviewPage())),
                      ),
                    ]),
                  ],
                  if (hasPassword && email.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Section(title: 'Segurança', children: [
                      ListTile(
                        leading: const Icon(Icons.lock_reset_rounded),
                        title: const Text('Redefinir senha'),
                        subtitle:
                            const Text('Enviamos um link para o seu e-mail'),
                        onTap: () => _resetPassword(email),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sair da conta'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Foto com o botão de câmera e o indicador enquanto salva.
class _PhotoEditor extends StatelessWidget {
  final Widget child;
  final bool busy;
  final VoidCallback onTap;

  const _PhotoEditor(
      {required this.child, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Alterar foto',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: Stack(alignment: Alignment.center, children: [
          child,
          if (busy)
            const SizedBox(
              width: 96,
              height: 96,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor, width: 3),
              ),
              child: Icon(Icons.photo_camera_rounded,
                  size: 18, color: scheme.onPrimary),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        Material(
          color: _cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}
