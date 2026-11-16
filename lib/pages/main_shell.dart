import 'package:flutter/material.dart';

import 'account_page.dart';
import 'home_page.dart';
import 'investments_page.dart';
import 'investor_profile_page.dart';

/// Estrutura principal: Início, Investimentos, Perfil de investidor e Conta.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _home = 0, _profile = 2, _account = 3;
  int _index = _home;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack mantém o estado de cada aba ao trocar de aba.
      body: IndexedStack(index: _index, children: [
        HomePage(onOpenAccount: () => _go(_account)),
        InvestmentsPage(onOpenProfile: () => _go(_profile)),
        const InvestorProfilePage(),
        const AccountPage(),
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
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Perfil',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Conta',
          ),
        ],
      ),
    );
  }
}
