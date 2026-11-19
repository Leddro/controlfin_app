/// Carteira atual do usuário e o cálculo do aporte do mês.
///
/// O aporte do mês (meta "Guardar") é dividido entre a reserva de
/// emergência (meses de gastos essenciais, pela média dos últimos meses) e os
/// investimentos. Enquanto a reserva se forma, ela recebe a maior parte, mas
/// os investimentos não param. O que vai para investimentos entra nas classes
/// mais abaixo do alvo da carteira (rebalanceamento só com compras).
library;

import 'dart:math' as math;

import '../tx.dart';
import '../user_settings.dart';
import 'portfolio_engine.dart';

export 'tickers.dart';

/// Uma posição: ação/ETF/FII (ticker e quantidade) ou um valor em renda fixa
/// fora da reserva (sem ticker, só [manualValue]).
class Holding {
  final String ticker;
  final AssetClass assetClass;
  final double quantity;

  /// Valor em reais quando não há cotação (renda fixa, ou ticker sem preço).
  final double? manualValue;

  const Holding({
    required this.ticker,
    required this.assetClass,
    this.quantity = 0,
    this.manualValue,
  });

  bool get isTicker => ticker.isNotEmpty;

  /// Valor atual: quantidade × preço; sem preço, o valor informado.
  double value(double? price) => isTicker && price != null && quantity > 0
      ? quantity * price
      : manualValue ?? 0;

  factory Holding.fromMap(Map<String, dynamic> m) => Holding(
        ticker: (m['ticker'] as String? ?? '').trim().toUpperCase(),
        assetClass: AssetClass.values.firstWhere(
          (c) => c.name == m['assetClass'],
          orElse: () => AssetClass.brStocks,
        ),
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
        manualValue: (m['manualValue'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'ticker': ticker,
        'assetClass': assetClass.name,
        'quantity': quantity,
        if (manualValue != null) 'manualValue': manualValue,
      };
}

/// Média mensal dos gastos que contam na meta Essenciais, nos meses que
/// tiveram algum gasto. [txs] deve cobrir meses fechados.
double essentialMonthlyAverage(List<Tx> txs, UserSettings settings) {
  final perMonth = <String, double>{};
  final months = <String>{};
  for (final t in txs.where((t) => t.type == TxType.expense)) {
    // Mês em que o dinheiro sai (crédito pelo vencimento da fatura).
    final key = '${t.cashDate.year}-${t.cashDate.month}';
    months.add(key);
    if (settings.budgetOf(t.category).kind == BudgetKind.needs) {
      perMonth[key] = (perMonth[key] ?? 0) + t.amount;
    }
  }
  if (months.isEmpty) return 0;
  final total = perMonth.values.fold(0.0, (a, b) => a + b);
  return total / months.length;
}

class ReserveStatus {
  /// Gasto essencial mensal usado na conta.
  final double monthlyBase;

  /// De onde veio [monthlyBase], para mostrar na tela.
  final String baseSource;

  final double target;
  final double saved;

  const ReserveStatus({
    required this.monthlyBase,
    required this.baseSource,
    required this.target,
    required this.saved,
  });

  double get missing => math.max(0, target - saved);
  bool get complete => target > 0 && missing <= 0.005;
  double get progress => target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0);
}

/// Meta da reserva = meses escolhidos × gasto essencial mensal.
/// Gasto essencial: média dos últimos meses fechados; sem histórico, o do
/// mês atual; sem nada lançado, 50% da renda.
ReserveStatus reserveStatus(
  UserSettings settings, {
  double essentialAverage = 0,
  double currentMonthNeeds = 0,
}) {
  final income = settings.monthlyIncome ?? 0;
  final (base, source) = essentialAverage > 0
      ? (essentialAverage, 'média dos gastos essenciais dos últimos meses')
      : currentMonthNeeds > 0
          ? (currentMonthNeeds, 'gastos essenciais deste mês')
          : (income * 0.5, '50% da renda, até haver gastos lançados');
  return ReserveStatus(
    monthlyBase: base,
    baseSource: source,
    target: base * settings.emergencyMonths,
    saved: settings.reserveSaved,
  );
}

/// Fração do aporte que vai para a reserva enquanto ela se forma. Começa
/// alta e cai conforme a reserva enche, sem parar de investir na bolsa.
double reserveShareFor(ReserveStatus reserve) {
  if (reserve.complete) return 0;
  final p = reserve.progress;
  if (p < 0.25) return 0.8;
  if (p < 0.50) return 0.7;
  if (p < 0.75) return 0.6;
  return 0.5;
}

enum SalaryFocus { defineIncome, buildReserve, invest }

/// Como dividir o próximo salário: gastos, reserva e cada classe.
class SalaryPlan {
  final double income;

  /// O que a meta "Guardar" separa da renda (o aporte do mês).
  final double amount;

  /// Fração do salário que é aportada (= meta "Guardar").
  final double savePercent;

  /// Quanto sobrou em média nos últimos meses (renda − gastos); nulo sem
  /// histórico.
  final double? recentSurplus;

  final ReserveStatus reserve;
  final double toReserve;
  final double toInvest;

  /// Meses para completar a reserva nesse ritmo.
  final int monthsToReserve;

  /// Quanto do investimento vai para cada classe.
  final Map<AssetClass, double> byClass;

  const SalaryPlan({
    required this.income,
    required this.amount,
    required this.savePercent,
    required this.recentSurplus,
    required this.reserve,
    required this.toReserve,
    required this.toInvest,
    required this.monthsToReserve,
    required this.byClass,
  });

  SalaryFocus get focus => income <= 0
      ? SalaryFocus.defineIncome
      : reserve.complete
          ? SalaryFocus.invest
          : SalaryFocus.buildReserve;

  double share(double value) => income <= 0 ? 0 : value / income;

  /// Nos últimos meses sobrou menos do que a meta pede.
  bool get goalAboveReality =>
      recentSurplus != null && recentSurplus! < amount - 0.005;

  /// Nos últimos meses sobrou bem mais do que a meta (dá para aportar mais).
  bool get roomForMore =>
      recentSurplus != null && recentSurplus! > amount * 1.2;
}

/// Plano do próximo salário: aporta a meta "Guardar"; enquanto a reserva
/// não está completa, a maior parte vai para ela e o resto já vai para os
/// investimentos (nas classes mais abaixo do alvo).
SalaryPlan planNextSalary({
  required UserSettings settings,
  required ReserveStatus reserve,
  required double? recentAverageExpenses,
  required Map<AssetClass, double> current,
  required Map<AssetClass, double>? targetWeights,
}) {
  final income = settings.monthlyIncome ?? 0;
  final savePct = settings.effectiveBudgets
          .firstWhere((b) => b.kind == BudgetKind.save)
          .percent /
      100;
  final amount = income * savePct;
  final toReserve =
      math.min(reserve.missing, amount * reserveShareFor(reserve));
  final toInvest = amount - toReserve;
  final months = reserve.missing <= 0 || toReserve <= 0
      ? 0
      : (reserve.missing / toReserve).ceil();
  return SalaryPlan(
    income: income,
    amount: amount,
    savePercent: savePct,
    recentSurplus: recentAverageExpenses == null
        ? null
        : math.max(0, income - recentAverageExpenses),
    reserve: reserve,
    toReserve: toReserve,
    toInvest: toInvest,
    monthsToReserve: months,
    byClass: targetWeights == null || toInvest <= 0
        ? const {}
        : mergeSmallOrders(splitByDeficit(current, targetWeights, toInvest)),
  );
}

/// Média mensal de todos os gastos nos meses com algum gasto lançado.
double? averageMonthlyExpenses(List<Tx> txs) {
  final perMonth = <String, double>{};
  for (final t in txs.where((t) => t.type == TxType.expense)) {
    // Mês em que o dinheiro sai (crédito pelo vencimento da fatura).
    final key = '${t.cashDate.year}-${t.cashDate.month}';
    perMonth[key] = (perMonth[key] ?? 0) + t.amount;
  }
  if (perMonth.isEmpty) return null;
  return perMonth.values.reduce((a, b) => a + b) / perMonth.length;
}

/// Junta valores abaixo de [minimum] na classe que já recebe mais, para não
/// sugerir compras de poucos reais.
Map<AssetClass, double> mergeSmallOrders(Map<AssetClass, double> split,
    {double minimum = 25}) {
  if (split.length < 2) return split;
  final out = {...split};
  final largest = out.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  for (final k in out.keys.toList()) {
    if (k != largest && out[k]! < minimum) {
      out[largest] = out[largest]! + out.remove(k)!;
    }
  }
  return out;
}

/// Divide [amount] entre as classes para aproximar a carteira dos pesos
/// [weights], sem vender: primeiro cobre o que falta em cada classe até o
/// alvo; se sobrar, distribui pelos pesos.
Map<AssetClass, double> splitByDeficit(
  Map<AssetClass, double> current,
  Map<AssetClass, double> weights,
  double amount,
) {
  final total = current.values.fold(0.0, (a, b) => a + b) + amount;
  final deficits = {
    for (final e in weights.entries)
      e.key: math.max(0.0, e.value * total - (current[e.key] ?? 0)),
  };
  final sumDeficit = deficits.values.fold(0.0, (a, b) => a + b);
  final Map<AssetClass, double> out;
  if (sumDeficit <= 0) {
    out = {for (final e in weights.entries) e.key: amount * e.value};
  } else if (sumDeficit >= amount) {
    out = {
      for (final e in deficits.entries) e.key: amount * e.value / sumDeficit,
    };
  } else {
    final rest = amount - sumDeficit;
    out = {
      for (final e in weights.entries) e.key: deficits[e.key]! + rest * e.value,
    };
  }
  out.removeWhere((_, v) => v < 0.005);
  return out;
}
