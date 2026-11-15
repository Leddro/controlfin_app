import 'package:flutter/material.dart';

import 'account_page.dart';
import 'home_page.dart';
import 'invest_page.dart';

/// Estrutura principal: Início, Investimentos e Conta no menu do rodapé.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack mantém o estado de cada aba ao trocar de aba.
      body: IndexedStack(index: _index, children: [
        HomePage(onOpenAccount: () => setState(() => _index = 2)),
        const InvestPage(),
        const AccountPage(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
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
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Conta',
          ),
        ],
      ),
    );
  }
}
