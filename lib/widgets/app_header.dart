import 'package:material_ui/material_ui.dart';

import 'app_logo.dart';
import 'user_avatar.dart';

/// Troca de aba para qualquer tela dentro do MainShell.
class ShellNavigation extends InheritedWidget {
  static const home = 0, investments = 1, profile = 2, account = 3;

  final ValueChanged<int> go;

  const ShellNavigation({super.key, required this.go, required super.child});

  /// Nulo em telas abertas por cima das abas (ex.: Meus cartões).
  static ShellNavigation? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellNavigation>();

  @override
  bool updateShouldNotify(ShellNavigation oldWidget) => false;
}

/// Barra do topo de todas as telas: logo, título e foto do usuário.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  /// Título em amarelo, como o nome do app na Início.
  final bool highlight;

  /// Botões antes da foto.
  final List<Widget> actions;

  /// Troca a foto nos testes (a foto padrão usa o Firebase).
  final Widget? avatar;

  const AppHeader({
    super.key,
    required this.title,
    this.highlight = false,
    this.actions = const [],
    this.avatar,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final nav = ShellNavigation.maybeOf(context);
    final canPop = Navigator.of(context).canPop();
    final photo = avatar ?? const UserAvatar(radius: 17);
    return AppBar(
      // Nas telas abertas por cima, a seta de voltar vem antes da logo.
      titleSpacing: canPop ? 0 : 16,
      // Logo e título encolhem juntos em telas estreitas para caber os
      // botões.
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const AppLogo(size: 30),
          const SizedBox(width: 10),
          Text(
            title,
            style: highlight
                ? const TextStyle(
                    fontWeight: FontWeight.w800, color: Color(0xFFFBBF24))
                : const TextStyle(fontWeight: FontWeight.w700),
          ),
        ]),
      ),
      actions: [
        ...actions,
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 12),
          child: Tooltip(
            message: 'Conta',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: nav == null ? null : () => nav.go(ShellNavigation.account),
              child: photo,
            ),
          ),
        ),
      ],
    );
  }
}
