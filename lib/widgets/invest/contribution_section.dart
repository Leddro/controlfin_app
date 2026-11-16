import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/investor_profile.dart';
import '../../models/market/contribution.dart';
import '../../models/market/market_data.dart';
import '../../models/market/portfolio_engine.dart';
import '../../models/tx.dart';
import '../../models/user_settings.dart';
import '../../services/holdings_service.dart';
import '../../services/market/market_sources.dart';
import '../../services/settings_service.dart';
import '../../services/tx_service.dart';
import 'market_section.dart' show classColor;

const _cardColor = Color(0xFF1A1A1A);
final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

String _pct(double v) => '${(v * 100).round()}%';

/// Aporte do mês e carteira atual, ligados ao Firebase.
class ContributionSection extends StatefulWidget {
  final InvestorProfile profile;
  final PortfolioPlan? plan;
  final Map<String, PriceSeries> etfs;

  /// Cotações gravadas pelo robô diário (coleção market/quotes).
  final Map<String, double> quotes;

  const ContributionSection({
    super.key,
    required this.profile,
    required this.plan,
    required this.etfs,
    this.quotes = const {},
  });

  @override
  State<ContributionSection> createState() => _ContributionSectionState();
}

class _ContributionSectionState extends State<ContributionSection> {
  final _settingsService = SettingsService();
  final _txService = TxService();
  final _holdingsService = HoldingsService();
  late final _settingsStream = _settingsService.watch();
  late final _monthStream = _txService.watchMonth(_thisMonth);
  late final _holdingsStream = _holdingsService.watch();
  late final Future<List<Tx>> _history = _txService.fetchRange(
    DateTime(_thisMonth.year, _thisMonth.month - 3),
    _thisMonth.subtract(const Duration(days: 1)),
  );

  static final _thisMonth = DateTime(DateTime.now().year, DateTime.now().month);

  /// Preços buscados no Yahoo para tickers que ainda não estão nas cotações
  /// do robô (ex.: acabou de ser adicionado). Só no celular: o navegador
  /// bloqueia o Yahoo.
  final Map<String, double?> _prices = {};
  final Set<String> _loading = {};

  void _ensurePrices(Iterable<String> tickers) {
    if (kIsWeb) return;
    final missing = tickers
        .where((t) =>
            widget.quotes[t] == null &&
            !_prices.containsKey(t) &&
            !_loading.contains(t))
        .toList();
    if (missing.isEmpty) return;
    _loading.addAll(missing);
    () async {
      for (final t in missing) {
        final p = await yahooPrice(t);
        if (!mounted) return;
        setState(() {
          _prices[t] = p;
          _loading.remove(t);
        });
      }
    }();
  }

  /// Preço de um ticker: cotação do robô, série mensal do ETF ou Yahoo.
  double? _priceOf(String ticker) =>
      widget.quotes[ticker] ??
      widget.etfs['$ticker.SAO']?.last ??
      _prices[ticker];

  Future<void> _updateReserve(UserSettings settings, double suggested) async {
    final controller = TextEditingController(
        text: suggested.toStringAsFixed(2).replaceAll('.', ','));
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Atualizar reserva'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Quanto você tem guardado na reserva de emergência agora?'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixText: r'R$ ',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, parseMoney(controller.text)),
              child: const Text('Salvar')),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (value == null || value < 0) return;
    await _settingsService.save(settings.copyWith(reserveSaved: value));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserSettings>(
      stream: _settingsStream,
      builder: (context, settingsSnap) {
        final settings = settingsSnap.data;
        return StreamBuilder<List<Tx>>(
          stream: _monthStream,
          builder: (context, monthSnap) {
            return StreamBuilder<List<Holding>>(
              stream: _holdingsStream,
              builder: (context, holdingsSnap) {
                return FutureBuilder<List<Tx>>(
                  future: _history,
                  builder: (context, historySnap) {
                    if (settings == null ||
                        !monthSnap.hasData ||
                        !holdingsSnap.hasData) {
                      return const SizedBox.shrink();
                    }
                    return _build(
                      settings,
                      monthSnap.data!,
                      historySnap.data ?? const [],
                      holdingsSnap.data!,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _build(UserSettings settings, List<Tx> month, List<Tx> history,
      List<Holding> holdings) {
    final currentNeeds = month
        .where((t) =>
            t.type == TxType.expense &&
            settings.budgetOf(t.category).kind == BudgetKind.needs)
        .fold(0.0, (s, t) => s + t.amount);
    final reserve = reserveStatus(
      settings,
      essentialAverage: essentialMonthlyAverage(history, settings),
      currentMonthNeeds: currentNeeds,
    );

    _ensurePrices(holdings.where((h) => h.isTicker).map((h) => h.ticker));
    final current = <AssetClass, double>{};
    for (final h in holdings) {
      current[h.assetClass] =
          (current[h.assetClass] ?? 0) + h.value(_priceOf(h.ticker));
    }

    final salary = planNextSalary(
      settings: settings,
      reserve: reserve,
      recentAverageExpenses: averageMonthlyExpenses(history),
      current: current,
      targetWeights: widget.plan?.weights,
    );
    _ensurePrices(salary.byClass.keys
        .map(productFor)
        .whereType<String>()
        .where((t) => widget.etfs['$t.SAO'] == null));

    final owned = <AssetClass, List<String>>{};
    for (final h in holdings.where((h) => h.isTicker)) {
      owned.putIfAbsent(h.assetClass, () => []).add(h.ticker);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FocusCard(
          plan: salary,
          priceOf: _priceOf,
          ownedByClass: owned,
          hasPortfolio: widget.plan != null,
          onUpdateReserve: () =>
              _updateReserve(settings, reserve.saved + salary.toReserve),
        ),
        const SizedBox(height: 16),
        HoldingsCard(
          holdings: holdings,
          priceOf: _priceOf,
          targetWeights: widget.plan?.weights,
          onChanged: _holdingsService.save,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Foco agora

/// "Foco agora": como dividir o próximo salário entre gastos, reserva e
/// cada classe de investimento, em % da renda e em reais.
class FocusCard extends StatelessWidget {
  final SalaryPlan plan;
  final double? Function(String ticker) priceOf;
  final Map<AssetClass, List<String>> ownedByClass;
  final bool hasPortfolio;
  final VoidCallback? onUpdateReserve;

  const FocusCard({
    super.key,
    required this.plan,
    required this.priceOf,
    this.ownedByClass = const {},
    this.hasPortfolio = true,
    this.onUpdateReserve,
  });

  static const _spendColor = Color(0xFF52525B);
  static const _reserveColor = Color(0xFF4ADE80);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final reserve = plan.reserve;

    if (plan.focus == SalaryFocus.defineIncome) {
      return const _Panel(
        title: 'Foco agora: definir sua renda',
        child: Text('Informe sua renda média em Início › Suas metas do mês › '
            'Ajustar. Com ela, o app mostra quanto do salário vai para cada '
            'lugar.'),
      );
    }

    final building = plan.focus == SalaryFocus.buildReserve;
    final classes = plan.byClass.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final spend = plan.income - plan.amount;
    final showClasses = hasPortfolio && classes.isNotEmpty;
    final segments = <(Color, double)>[
      (_spendColor, spend),
      if (plan.toReserve > 0) (_reserveColor, plan.toReserve),
      if (!showClasses && plan.toInvest > 0)
        (theme.colorScheme.primary, plan.toInvest),
      if (showClasses)
        for (final e in classes) (classColor(e.key), e.value),
    ];
    final reservePct = (reserveShareFor(reserve) * 100).round();
    final months = plan.monthsToReserve;

    return _Panel(
      title: building
          ? 'Foco agora: montar sua reserva de emergência'
          : 'Foco agora: fazer seu patrimônio crescer',
      subtitle: building
          ? 'A maior parte do que você guardar vai para a reserva, e uma '
              'parte já vai para a bolsa, para buscar mais que o CDI '
              'enquanto ela se forma.'
          : 'Sua reserva está completa. Tudo o que você guardar vai para os '
              'investimentos, nas classes mais abaixo do alvo.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No próximo salário (${_brl.format(plan.income)})',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          // Barra com a divisão do salário.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(children: [
                for (final (color, value) in segments)
                  if (value > 0)
                    Expanded(
                      flex: (value / plan.income * 1000).round().clamp(1, 1000),
                      child: Container(color: color),
                    ),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          _SalaryLine(
            color: _spendColor,
            label: 'Gastos do mês',
            detail: 'Essenciais, desejos e as outras metas',
            share: plan.share(spend),
            amount: spend,
          ),
          if (plan.toReserve > 0)
            _SalaryLine(
              key: const Key('focus-reserve'),
              color: _reserveColor,
              label: 'Reserva de emergência',
              detail: 'Tesouro Selic ou CDB com liquidez diária',
              share: plan.share(plan.toReserve),
              amount: plan.toReserve,
              strong: building,
            ),
          if (!showClasses && plan.toInvest > 0)
            _SalaryLine(
              color: theme.colorScheme.primary,
              label: 'Investimentos',
              detail: 'A divisão entre as classes aparece quando os dados de '
                  'mercado carregarem.',
              share: plan.share(plan.toInvest),
              amount: plan.toInvest,
            ),
          if (showClasses)
            for (final e in classes)
              _SalaryLine(
                key: Key('focus-${e.key.name}'),
                color: classColor(e.key),
                label: e.key.label,
                detail: _howToBuy(e.key, e.value),
                share: plan.share(e.value),
                amount: e.value,
                strong: !building,
              ),
          const Divider(height: 24),
          if (building) ...[
            Text(
              'Reserva: ${_brl.format(reserve.saved)} de '
              '${_brl.format(reserve.target)}. Agora $reservePct% do que você '
              'guarda vai para ela. Nesse ritmo fica pronta em cerca de '
              '$months ${months == 1 ? 'mês' : 'meses'}; a parte da reserva '
              'diminui conforme ela enche e, depois, tudo vai para os '
              'investimentos.',
            ),
            const SizedBox(height: 4),
            Text(
              'Meta da reserva: ${_brl.format(reserve.monthlyBase)} por mês de '
              'gastos essenciais (${reserve.baseSource}).',
              style: small,
            ),
          ],
          if (plan.goalAboveReality) ...[
            const SizedBox(height: 8),
            Text(
              'Atenção: nos últimos meses sobrou em média '
              '${_brl.format(plan.recentSurplus)}, menos que os '
              '${_brl.format(plan.amount)} da meta "Guardar". Para cumprir o '
              'plano, corte gastos em Desejos.',
              style: TextStyle(color: theme.colorScheme.tertiary),
            ),
          ] else if (plan.roomForMore) ...[
            const SizedBox(height: 8),
            Text(
              'Nos últimos meses sobrou em média '
              '${_brl.format(plan.recentSurplus)}, mais que a meta. Se '
              'continuar assim, aporte também a diferença '
              '(${_brl.format(plan.recentSurplus! - plan.amount)}).',
              style: const TextStyle(color: Color(0xFF4ADE80)),
            ),
          ],
          if (plan.toReserve > 0 && onUpdateReserve != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onUpdateReserve,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Já guardei: atualizar reserva'),
              ),
            ),
        ],
      ),
    );
  }

  String _howToBuy(AssetClass c, double amount) {
    final product = productFor(c);
    final owned = ownedByClass[c] ?? const [];
    final reinforce = owned.isEmpty ? '' : ' Ou reforce: ${owned.join(', ')}.';
    if (product == null) return '${c.examples}.$reinforce';
    final price = priceOf(product);
    if (price == null || price <= 0) return '$product.$reinforce';
    final qty = (amount / price).floor();
    final how = qty >= 1
        ? '$product: $qty ${qty == 1 ? 'cota' : 'cotas'} de ${_brl.format(price)}'
        : '$product: fração (${product}F), a cota custa ${_brl.format(price)}';
    return '$how.$reinforce';
  }
}

class _SalaryLine extends StatelessWidget {
  final Color color;
  final String label;
  final String detail;
  final double share;
  final double amount;
  final bool strong;

  const _SalaryLine({
    super.key,
    required this.color,
    required this.label,
    required this.detail,
    required this.share,
    required this.amount,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final pct = share * 100;
    final pctText = pct < 1
        ? '<1%'
        : pct < 10
            ? '${pct.toStringAsFixed(1).replaceAll('.', ',')}%'
            : '${pct.round()}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
            Text(detail, style: small),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(pctText,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: strong ? 16 : 14)),
          Text(_brl.format(amount), style: small),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Carteira atual

class HoldingsCard extends StatelessWidget {
  final List<Holding> holdings;
  final double? Function(String ticker) priceOf;
  final Map<AssetClass, double>? targetWeights;
  final Future<void> Function(List<Holding>) onChanged;

  const HoldingsCard({
    super.key,
    required this.holdings,
    required this.priceOf,
    required this.targetWeights,
    required this.onChanged,
  });

  Future<void> _edit(BuildContext context, [int? index]) async {
    final result = await showDialog<Holding>(
      context: context,
      builder: (_) =>
          _HoldingDialog(initial: index == null ? null : holdings[index]),
    );
    if (result == null) return;
    final next = [...holdings];
    if (index == null) {
      // Mesmo ticker: soma as quantidades.
      final same = result.isTicker
          ? next.indexWhere((h) => h.ticker == result.ticker)
          : -1;
      if (same >= 0) {
        next[same] = Holding(
          ticker: result.ticker,
          assetClass: result.assetClass,
          quantity: next[same].quantity + result.quantity,
        );
      } else {
        next.add(result);
      }
    } else {
      next[index] = result;
    }
    await onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final values = [for (final h in holdings) h.value(priceOf(h.ticker))];
    final total = values.fold(0.0, (a, b) => a + b);
    final byClass = <AssetClass, double>{};
    for (var i = 0; i < holdings.length; i++) {
      byClass[holdings[i].assetClass] =
          (byClass[holdings[i].assetClass] ?? 0) + values[i];
    }

    return _Panel(
      title: 'Minha carteira',
      subtitle: 'O que você já tem investido, fora a reserva de emergência.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (holdings.isEmpty)
            Text(
              'Adicione suas ações, FIIs, ETFs e renda fixa para o aporte '
              'levar em conta o que você já tem.',
              style: small,
            )
          else ...[
            for (var i = 0; i < holdings.length; i++)
              _HoldingRow(
                holding: holdings[i],
                price: priceOf(holdings[i].ticker),
                value: values[i],
                onTap: () => _edit(context, i),
                onRemove: () => onChanged([...holdings]..removeAt(i)),
              ),
            const Divider(height: 24),
            Row(children: [
              const Expanded(
                child: Text('Total',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(_brl.format(total),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            if (targetWeights != null && total > 0) ...[
              const SizedBox(height: 12),
              Text('Hoje × alvo da carteira sugerida',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final c in AssetClass.values)
                if ((byClass[c] ?? 0) > 0 || (targetWeights![c] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: classColor(c), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(c.label, style: small)),
                      Text(
                        '${_pct((byClass[c] ?? 0) / total)} hoje • alvo '
                        '${_pct(targetWeights![c] ?? 0)}',
                        style: small,
                      ),
                    ]),
                  ),
            ],
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Adicionar investimento'),
          ),
        ],
      ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  final Holding holding;
  final double? price;
  final double value;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _HoldingRow({
    required this.holding,
    required this.price,
    required this.value,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final qty = holding.quantity == holding.quantity.roundToDouble()
        ? holding.quantity.toStringAsFixed(0)
        : holding.quantity.toString().replaceAll('.', ',');
    final detail = !holding.isTicker
        ? holding.assetClass.label
        : price == null
            ? '$qty cotas • buscando preço...'
            : '$qty × ${_brl.format(price)}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: classColor(holding.assetClass), shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(holding.isTicker ? holding.ticker : 'Renda fixa',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(detail, style: small),
            ]),
          ),
          Text(_brl.format(value)),
          IconButton(
            tooltip: 'Remover',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ]),
      ),
    );
  }
}

class _HoldingDialog extends StatefulWidget {
  final Holding? initial;

  const _HoldingDialog({this.initial});

  @override
  State<_HoldingDialog> createState() => _HoldingDialogState();
}

class _HoldingDialogState extends State<_HoldingDialog> {
  late bool _fixed = widget.initial != null && !widget.initial!.isTicker;
  late final _ticker = TextEditingController(text: widget.initial?.ticker);
  late final _quantity = TextEditingController(
      text: widget.initial == null || !widget.initial!.isTicker
          ? ''
          : widget.initial!.quantity
              .toStringAsFixed(widget.initial!.quantity % 1 == 0 ? 0 : 2)
              .replaceAll('.', ','));
  late final _value = TextEditingController(
      text:
          widget.initial?.manualValue?.toStringAsFixed(2).replaceAll('.', ','));
  late AssetClass _class = widget.initial?.assetClass ?? AssetClass.brStocks;
  bool _classTouched = false;
  String? _error;

  @override
  void dispose() {
    _ticker.dispose();
    _quantity.dispose();
    _value.dispose();
    super.dispose();
  }

  void _save() {
    if (_fixed) {
      final v = parseMoney(_value.text);
      if (v == null || v <= 0) {
        setState(() => _error = 'Informe o valor aplicado.');
        return;
      }
      Navigator.pop(
        context,
        Holding(ticker: '', assetClass: AssetClass.fixedIncome, manualValue: v),
      );
      return;
    }
    final ticker = _ticker.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{4}\d{1,2}F?$').hasMatch(ticker)) {
      setState(() => _error = 'Use o código da B3, como PETR4 ou BOVA11.');
      return;
    }
    final q = parseMoney(_quantity.text);
    if (q == null || q <= 0) {
      setState(() => _error = 'Informe a quantidade de cotas.');
      return;
    }
    // Compra fracionária (PETR4F) conta como o mesmo ativo.
    final base =
        ticker.endsWith('F') ? ticker.substring(0, ticker.length - 1) : ticker;
    Navigator.pop(
        context, Holding(ticker: base, assetClass: _class, quantity: q));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null
          ? 'Adicionar investimento'
          : 'Editar investimento'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Ação, FII ou ETF')),
                ButtonSegment(value: true, label: Text('Renda fixa')),
              ],
              selected: {_fixed},
              onSelectionChanged: (s) => setState(() {
                _fixed = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_fixed)
              TextField(
                key: const Key('holding-value'),
                controller: _value,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Valor aplicado hoje',
                  helperText: 'CDB, Tesouro, LCI... fora da reserva',
                  prefixText: r'R$ ',
                  border: OutlineInputBorder(),
                ),
              )
            else ...[
              TextField(
                key: const Key('holding-ticker'),
                controller: _ticker,
                autofocus: widget.initial == null,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Código (ex.: PETR4, BOVA11, HGLG11)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (t) {
                  if (!_classTouched) {
                    setState(() => _class = guessAssetClass(t));
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('holding-quantity'),
                controller: _quantity,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Quantidade de cotas',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AssetClass>(
                key: const Key('holding-class'),
                initialValue: _class,
                decoration: const InputDecoration(
                  labelText: 'Classe',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in AssetClass.values)
                    if (c != AssetClass.fixedIncome)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (c) => setState(() {
                  if (c != null) _class = c;
                  _classTouched = true;
                }),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Panel({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
