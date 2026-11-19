/// Estatística e otimização de carteira (Markowitz, 1952).
library;

import 'dart:math' as math;

import 'market_data.dart';

/// Retornos mensais simples alinhados por mês, só nos meses em que todas as
/// séries têm preço. Devolve uma lista de retornos por série, na ordem dada.
List<List<double>> alignedMonthlyReturns(List<PriceSeries> series,
    {int maxMonths = 60}) {
  if (series.isEmpty) return const [];
  var common = series.first.monthly.keys.toSet();
  for (final s in series.skip(1)) {
    common = common.intersection(s.monthly.keys.toSet());
  }
  final months = common.toList()..sort();
  final window = months.length > maxMonths + 1
      ? months.sublist(months.length - maxMonths - 1)
      : months;
  return [
    for (final s in series)
      [
        for (var i = 1; i < window.length; i++)
          s.monthly[window[i]]! / s.monthly[window[i - 1]]! - 1,
      ],
  ];
}

double mean(List<double> xs) =>
    xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

double covariance(List<double> a, List<double> b) {
  final n = math.min(a.length, b.length);
  if (n < 2) return 0;
  final ma = mean(a.sublist(0, n));
  final mb = mean(b.sublist(0, n));
  var s = 0.0;
  for (var i = 0; i < n; i++) {
    s += (a[i] - ma) * (b[i] - mb);
  }
  return s / (n - 1);
}

/// Beta de [asset] contra [market] (inclinação da regressão).
double beta(List<double> asset, List<double> market) {
  final v = covariance(market, market);
  return v == 0 ? 1 : covariance(asset, market) / v;
}

/// Correlação de Pearson (−1 a 1); 0 se uma das séries não varia.
double correlation(List<double> a, List<double> b) {
  final d = math.sqrt(covariance(a, a) * covariance(b, b));
  return d == 0 ? 0 : (covariance(a, b) / d).clamp(-1.0, 1.0);
}

/// Matriz de covariância anualizada (×12) com encolhimento para a diagonal
/// ([shrink] entre 0 e 1), que deixa a otimização menos sensível a ruído.
List<List<double>> annualCovariance(List<List<double>> returns,
    {double shrink = 0.2}) {
  final n = returns.length;
  return [
    for (var i = 0; i < n; i++)
      [
        for (var j = 0; j < n; j++)
          covariance(returns[i], returns[j]) * 12 * (i == j ? 1 : 1 - shrink),
      ],
  ];
}

/// Projeta [v] no conjunto {soma = 1, lo ≤ w ≤ hi} (busca do deslocamento τ).
List<double> projectToBoxSimplex(
    List<double> v, List<double> lo, List<double> hi) {
  double sumAt(double tau) {
    var s = 0.0;
    for (var i = 0; i < v.length; i++) {
      s += (v[i] - tau).clamp(lo[i], hi[i]);
    }
    return s;
  }

  var a = v.reduce(math.min) - hi.reduce(math.max) - 1;
  var b = v.reduce(math.max) - lo.reduce(math.min) + 1;
  for (var k = 0; k < 100; k++) {
    final mid = (a + b) / 2;
    if (sumAt(mid) > 1) {
      a = mid;
    } else {
      b = mid;
    }
  }
  final tau = (a + b) / 2;
  return [
    for (var i = 0; i < v.length; i++) (v[i] - tau).clamp(lo[i], hi[i]),
  ];
}

/// Maximiza μ·w − (γ/2)·wᵀΣw com soma 1 e limites por ativo
/// (utilidade média-variância de Markowitz, com a aversão ao risco γ de
/// Arrow-Pratt). Gradiente projetado; converge bem para poucos ativos.
List<double> optimizeMeanVariance({
  required List<double> mu,
  required List<List<double>> cov,
  required double gamma,
  required List<double> lower,
  required List<double> upper,
  int iterations = 3000,
}) {
  final n = mu.length;
  assert(lower.fold(0.0, (s, x) => s + x) <= 1 + 1e-9,
      'A soma dos mínimos passa de 100%.');
  assert(upper.fold(0.0, (s, x) => s + x) >= 1 - 1e-9,
      'A soma dos máximos não chega a 100%.');

  // Passo: 1 / constante de Lipschitz (γ vezes o maior autovalor ≤ traço).
  var trace = 0.0;
  for (var i = 0; i < n; i++) {
    trace += cov[i][i];
  }
  final step = 1 / (gamma * trace + 1e-9);

  var w = projectToBoxSimplex(List.filled(n, 1 / n), lower, upper);
  for (var it = 0; it < iterations; it++) {
    final grad = [
      for (var i = 0; i < n; i++)
        mu[i] -
            gamma *
                [for (var j = 0; j < n; j++) cov[i][j] * w[j]]
                    .reduce((a, b) => a + b),
    ];
    w = projectToBoxSimplex(
        [for (var i = 0; i < n; i++) w[i] + step * grad[i]], lower, upper);
  }
  return w;
}

double portfolioReturn(List<double> w, List<double> mu) {
  var s = 0.0;
  for (var i = 0; i < w.length; i++) {
    s += w[i] * mu[i];
  }
  return s;
}

double portfolioVolatility(List<double> w, List<List<double>> cov) {
  var s = 0.0;
  for (var i = 0; i < w.length; i++) {
    for (var j = 0; j < w.length; j++) {
      s += w[i] * w[j] * cov[i][j];
    }
  }
  return math.sqrt(math.max(s, 0));
}
