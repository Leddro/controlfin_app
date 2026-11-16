// Robô diário: coleta os dados de mercado e grava na coleção "market" do
// Firestore. Roda no GitHub Actions (.github/workflows/market.yml), onde as
// chaves ficam nos Secrets. O app só lê o resultado e não tem chave nenhuma.
//
// Variáveis de ambiente:
//   ALPHA_VANTAGE_KEY, BRAPI_TOKEN   chaves das APIs
//   FIREBASE_SERVICE_ACCOUNT         JSON da conta de serviço do Firebase
//   DRY_RUN=1                        só coleta e mostra, sem gravar
//
// Rodar no PC (PowerShell), com as chaves em tool/env.json:
//   $env:FIREBASE_SERVICE_ACCOUNT = Get-Content conta.json -Raw
//   dart run tool/update_market.dart --env tool/env.json
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:financas_app/services/market/market_collector.dart';
import 'package:financas_app/services/market/market_sources.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final env = {...Platform.environment};
  final envFile = args.indexOf('--env');
  if (envFile >= 0 && envFile + 1 < args.length) {
    final json = jsonDecode(File(args[envFile + 1]).readAsStringSync()) as Map;
    for (final e in json.entries) {
      env.putIfAbsent(e.key as String, () => '${e.value}');
    }
  }
  final dryRun = env['DRY_RUN'] == '1';

  marketKeys = MarketKeys(
    alphaVantage: env['ALPHA_VANTAGE_KEY'] ?? '',
    brapi: env['BRAPI_TOKEN'] ?? '',
  );
  if (marketKeys.alphaVantage.isEmpty) {
    stderr.writeln('Falta ALPHA_VANTAGE_KEY.');
    exit(2);
  }

  AutoRefreshingAuthClient? client;
  String? project;
  final account = env['FIREBASE_SERVICE_ACCOUNT'];
  if (!dryRun) {
    if (account == null || account.trim().isEmpty) {
      stderr.writeln('Falta FIREBASE_SERVICE_ACCOUNT (ou use DRY_RUN=1).');
      exit(2);
    }
    final json = jsonDecode(account) as Map<String, dynamic>;
    project = json['project_id'] as String;
    client = await clientViaServiceAccount(
      ServiceAccountCredentials.fromJson(json),
      const ['https://www.googleapis.com/auth/datastore'],
    );
  }

  try {
    final firestore = client == null ? null : _Firestore(client, project!);
    final tickers = await firestore?.holdingTickers() ?? const <String>{};
    print('Tickers nas carteiras: ${tickers.length}');

    final result = await collectMarket(holdingTickers: tickers, log: print);

    if (firestore == null) {
      print('\nDRY_RUN: nada gravado.');
      for (final e in result.docs.entries) {
        print('  ${e.key}: ${jsonEncode(e.value).length} bytes');
      }
    } else {
      for (final e in result.docs.entries) {
        await firestore.writeMarketDoc(e.key, e.value);
        print('gravado: market/${e.key}');
      }
    }

    if (result.errors.isNotEmpty) {
      print('\nFalhas (o app segue com a versão anterior desses dados):');
      result.errors.forEach(print);
    }
    // Sem Selic ou sem ETFs a carteira não sai: aí o robô falha (e o GitHub
    // avisa por e-mail). Falhas em ações ou Bitcoin só geram aviso.
    final essential =
        result.docs.containsKey('macro') && result.docs.containsKey('etfs');
    exitCode = essential ? 0 : 1;
  } finally {
    client?.close();
  }
}

/// O mínimo da API REST do Firestore que o robô usa.
class _Firestore {
  final http.Client _http;
  final String _base;

  _Firestore(this._http, String project)
      : _base = 'https://firestore.googleapis.com/v1/projects/$project'
            '/databases/(default)/documents';

  /// Tickers das carteiras de todos os usuários
  /// (users/{uid}/settings/holdings).
  Future<Set<String>> holdingTickers() async {
    final res = await _http.post(
      Uri.parse('$_base:runQuery'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'structuredQuery': {
          'from': [
            {'collectionId': 'settings', 'allDescendants': true},
          ],
        },
      }),
    );
    if (res.statusCode != 200) {
      throw HttpException('runQuery ${res.statusCode}: ${res.body}');
    }
    final tickers = <String>{};
    for (final row in jsonDecode(res.body) as List) {
      final doc = (row as Map)['document'] as Map?;
      if (doc == null || !(doc['name'] as String).endsWith('/holdings')) {
        continue;
      }
      final items = ((((doc['fields'] as Map?)?['items'] as Map?)?['arrayValue']
              as Map?)?['values'] as List?) ??
          const [];
      for (final item in items) {
        final fields = ((item as Map)['mapValue'] as Map?)?['fields'] as Map?;
        final ticker = (fields?['ticker'] as Map?)?['stringValue'] as String?;
        if (ticker != null && ticker.trim().isNotEmpty) {
          tickers.add(ticker.trim().toUpperCase());
        }
      }
    }
    return tickers;
  }

  /// Mesmo formato que o app lê: payload (JSON em texto) e fetchedAt.
  Future<void> writeMarketDoc(String key, Object payload) async {
    final res = await _http.patch(
      Uri.parse('$_base/market/$key'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fields': {
          'payload': {'stringValue': jsonEncode(payload)},
          'fetchedAt': {
            'timestampValue': DateTime.now().toUtc().toIso8601String(),
          },
        },
      }),
    );
    if (res.statusCode != 200) {
      throw HttpException('gravar market/$key ${res.statusCode}: ${res.body}');
    }
  }
}
