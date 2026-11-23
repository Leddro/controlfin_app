import 'package:material_ui/material_ui.dart';

import '../widgets/app_header.dart';
import 'account_page.dart';
import 'goals_page.dart';
import 'home_page.dart';
import 'investments_page.dart';

/// Estrutura principal: Início, Investimentos (com o perfil de investidor),
/// Metas e Conta.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = ShellNavigation.home;

  /// Abas já abertas. Cada aba é montada na primeira visita e depois fica
  /// viva, guardando o estado (rolagem, filtros, dados carregados).
  final _visited = <int>{ShellNavigation.home};

  /// Criadas uma vez só: trocar de aba não reconstrói as telas.
  late final List<Widget> _pages = [
    const HomePage(),
    const InvestmentsPage(),
    const GoalsPage(),
    const AccountPage(),
  ];

  void _go(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShellNavigation(
      go: _go,
      child: Scaffold(
        body: Stack(fit: StackFit.expand, children: [
          for (var i = 0; i < _pages.length; i++)
            if (_visited.contains(i))
              _TabView(
                key: ValueKey(i),
                active: i == _index,
                child: _pages[i],
              ),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _go,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Início',
            ),
            NavigationDestination(
              icon: Icon(Icons.trending_up_outlined),
              selectedIcon: Icon(Icons.trending_up_rounded),
              label: 'Investimentos',
            ),
            NavigationDestination(
              icon: Icon(Icons.flag_outlined),
              selectedIcon: Icon(Icons.flag_rounded),
              label: 'Metas',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Conta',
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma aba: aparece com esmaecimento e um leve zoom; escondida, não recebe
/// toques, não anima e não conta para o leitor de tela.
class _TabView extends StatelessWidget {
  final bool active;
  final Widget child;

  const _TabView({super.key, required this.active, required this.child});

  static const _duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    // A animação fica por fora do TickerMode: a aba que sai ainda precisa
    // animar o esmaecimento.
    return AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: _duration,
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: active ? 1 : 0.985,
        duration: _duration,
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          ignoring: !active,
          child: ExcludeSemantics(
            excluding: !active,
            child: TickerMode(
              enabled: active,
              // Só a aba visível participa das animações de abrir telas.
              child: HeroMode(
                enabled: active,
                child: RepaintBoundary(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
