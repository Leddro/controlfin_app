import 'package:flutter/material.dart';

import '../models/credit_card.dart';
import '../services/card_service.dart';
import '../widgets/card_editor_sheet.dart';
import '../widgets/card_widgets.dart';

/// Lista, cria, edita e exclui os cartões de crédito.
class CardsPage extends StatefulWidget {
  const CardsPage({super.key});

  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  final _service = CardService();
  late final _stream = _service.watch();
  List<CreditCard> _cards = const [];

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add() async {
    final card = await showCardEditor(context, existing: _cards);
    if (card == null) return;
    await _service.add(card);
    if (mounted) _toast('${card.label} adicionado.');
  }

  Future<void> _edit(CreditCard card) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('Editar cartão'),
            onTap: () => Navigator.pop(context, 'edit'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.error),
            title: const Text('Excluir cartão'),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      final updated =
          await showCardEditor(context, initial: card, existing: _cards);
      if (updated == null) return;
      await _service.update(updated);
      if (mounted) _toast('Cartão atualizado.');
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Excluir ${card.label}?'),
          content: const Text(
              'Os lançamentos feitos com esse cartão continuam salvos e '
              'contando nos meses deles.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Excluir')),
          ],
        ),
      );
      if (ok == true) {
        await _service.delete(card.id!);
        if (mounted) _toast('Cartão excluído.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Meus cartões')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_card_rounded),
        label: const Text('Novo cartão'),
      ),
      body: StreamBuilder<List<CreditCard>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
                child: Text('Não foi possível carregar seus cartões.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          _cards = snap.data!;
          if (_cards.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.credit_card_rounded,
                      size: 56, color: Color(0xFFFBBF24)),
                  const SizedBox(height: 16),
                  Text('Nenhum cartão ainda',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text(
                    'Cadastre seus cartões para ver quanto vem em cada fatura '
                    'e em que mês cada compra vai ser paga. Ao importar uma '
                    'fatura, o cartão é reconhecido e cadastrado sozinho.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add_card_rounded),
                    label: const Text('Adicionar cartão'),
                  ),
                ]),
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                itemCount: _cards.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, i) {
                  if (i == _cards.length) {
                    return Text(
                      'Toque num cartão para editar ou excluir.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    );
                  }
                  final card = _cards[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _edit(card),
                    child: CardFace(card: card),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
