/// Ações a partir da carteira do usuário: o que fazer com as que ele já tem
/// e quais empresas completam essa carteira.
///
/// * Ações que ele tem: preço justo por Graham e Gordon, mais a
///   concentração. O app não sugere vendas (o rebalanceamento é só com
///   compras): o pior caso é "não aumentar".
/// * Sugestões: as mais bem avaliadas do ranking, com bônus para as que
///   oscilam diferente das ações dele (correlação baixa diversifica mais).
library;

import 'market_data.dart';
import 'portfolio_engine.dart';
import 'portfolio_math.dart';

enum HeldVerdict { reinforce, keep, hold, noData }

class HeldStockReview {
  final String ticker;

  /// Valor da posição em reais.
  final double value;

  /// Fração das ações de empresas do usuário (0 a 1).
  final double share;

  final StockIdea? idea;
  final HeldVerdict verdict;
  final String reason;

  const HeldStockReview({
    required this.ticker,
    required this.value,
    required this.share,
    required this.idea,
    required this.verdict,
    required this.reason,
  });
}

class StockSuggestion {
  final StockIdea idea;

  /// Correlação média com as ações do usuário (nulo: ele não tem ações
  /// com histórico para comparar).
  final double? correlation;

  final List<String> reasons;

  const StockSuggestion({
    required this.idea,
    required this.correlation,
    required this.reasons,
  });
}

class StockAdvice {
  final List<HeldStockReview> held;
  final List<StockSuggestion> suggestions;
  final String summary;

  const StockAdvice({
    required this.held,
    required this.suggestions,
    required this.summary,
  });
}

/// Uma ação acima disso do total em ações de empresas está concentrada.
const concentrationLimit = 0.30;

/// Preço justo médio abaixo do preço atual com essa folga: cara.
const expensiveBelow = -0.10;

/// Peso da correlação na ordem das sugestões (o score do ranking vai de
/// cerca de −2 a 2; a correlação, de −1 a 1).
const _correlationWeight = 0.75;

String _pct(double v) => '${v >= 0 ? '+' : ''}${(v * 100).round()}%';

String _plainPct(double v) => '${(v * 100).round()}%';

/// Correlação dos retornos mensais (nulo com menos de 12 meses em comum).
double? stockCorrelation(PriceSeries a, PriceSeries b) {
  final r = alignedMonthlyReturns([a, b]);
  if (r.isEmpty || r[0].length < 12) return null;
  return correlation(r[0], r[1]);
}

/// [ideas]: ranking com as ações do universo e as do usuário.
/// [heldValues]: ticker → valor em reais das ações de empresas que ele tem.
/// [targetHasStocks]: a carteira-alvo do perfil inclui ações.
StockAdvice adviseStocks({
  required List<StockIdea> ideas,
  required Map<String, double> heldValues,
  bool targetHasStocks = true,
  int maxSuggestions = 3,
}) {
  final byTicker = {for (final i in ideas) i.quote.symbol: i};
  final total = heldValues.values.fold(0.0, (a, b) => a + b);
  final entries = heldValues.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final held = <HeldStockReview>[];
  for (final e in entries) {
    final share = total > 0 ? e.value / total : 0.0;
    final idea = byTicker[e.key];
    final (verdict, reason) = _review(idea, share, heldValues.length);
    held.add(HeldStockReview(
      ticker: e.key,
      value: e.value,
      share: share,
      idea: idea,
      verdict: verdict,
      reason: reason,
    ));
  }

  final heldHistories = [
    for (final t in heldValues.keys)
      if (byTicker[t] != null) byTicker[t]!.quote.history,
  ];
  final scored = <(StockIdea, double?, double)>[];
  for (final idea in ideas) {
    final up = idea.upside;
    if (heldValues.containsKey(idea.quote.symbol) ||
        idea.hasLoss ||
        up == null ||
        up < expensiveBelow) {
      continue;
    }
    final corrs = [
      for (final h in heldHistories) stockCorrelation(idea.quote.history, h),
    ].whereType<double>().toList();
    final corr = corrs.isEmpty ? null : mean(corrs);
    scored.add((idea, corr, idea.score - _correlationWeight * (corr ?? 0)));
  }
  scored.sort((a, b) => b.$3.compareTo(a.$3));

  final suggestions = [
    for (final (idea, corr, _) in scored.take(maxSuggestions))
      StockSuggestion(
        idea: idea,
        correlation: corr,
        reasons: [
          if (idea.upside! >= Assumptions.marginOfSafety)
            'Abaixo do preço justo, com margem de segurança',
          if (corr != null && corr < 0.5)
            'Oscila diferente das suas ações (correlação '
                '${corr.toStringAsFixed(2).replaceAll('.', ',')})',
          if (idea.quote.dividendYield >= 0.06)
            'Paga ${_plainPct(idea.quote.dividendYield)} ao ano em proventos',
        ],
      ),
  ];

  final n = heldValues.length;
  final summary = !targetHasStocks
      ? 'Seu perfil não tem ações na carteira-alvo agora: a análise fica '
          'como estudo.'
      : n == 0
          ? 'Você ainda não tem ações de empresas. Para começar, um ETF como '
              'o BOVA11 já compra o Ibovespa inteiro; se preferir escolher '
              'empresas, estas são as mais bem avaliadas.'
          : n < 5
              ? 'Com $n ${n == 1 ? 'ação' : 'ações'}, uma empresa que vá mal '
                  'pesa muito. As sugestões priorizam empresas baratas que '
                  'oscilam diferente das suas.'
              : 'As sugestões priorizam empresas baratas que oscilam '
                  'diferente das suas.';

  return StockAdvice(held: held, suggestions: suggestions, summary: summary);
}

(HeldVerdict, String) _review(StockIdea? idea, double share, int count) {
  if (idea == null) {
    return (
      HeldVerdict.noData,
      'Ainda sem dados desta ação. Eles chegam na próxima atualização '
          'diária do mercado.'
    );
  }
  if (idea.hasLoss) {
    return (
      HeldVerdict.hold,
      'Teve prejuízo nos últimos 12 meses: pelo critério de Graham, não é '
          'hora de aumentar.'
    );
  }
  final up = idea.upside;
  if (up == null) {
    return (
      HeldVerdict.noData,
      'Sem lucro nem proventos informados para estimar o preço justo.'
    );
  }
  if (up < expensiveBelow) {
    return (
      HeldVerdict.hold,
      'Acima do preço justo (${_pct(up)}): não vale aumentar agora.'
    );
  }
  if (share > concentrationLimit) {
    return (
      HeldVerdict.keep,
      count == 1
          ? 'É a sua única ação: antes de reforçar, vale diversificar.'
          : 'Já é ${_plainPct(share)} das suas ações: reforçar aumenta a '
              'concentração. Prefira diversificar.'
    );
  }
  if (up >= Assumptions.marginOfSafety) {
    return (
      HeldVerdict.reinforce,
      'Abaixo do preço justo (${_pct(up)}), com a margem de segurança de '
          'Graham.'
    );
  }
  return (HeldVerdict.keep, 'Perto do preço justo (${_pct(up)}).');
}
