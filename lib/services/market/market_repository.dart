import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/market/market_data.dart';

/// Lê os dados de mercado da coleção "market" do Firestore.
///
/// O app não busca nada nas APIs pagas nem tem as chaves: um robô diário
/// (tool/update_market.dart, no GitHub Actions) coleta e grava os dados. A
/// coleção é só leitura para os usuários.
class MarketRepository {
  final FirebaseFirestore _db;

  MarketRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Leitura bloqueada pelas regras do Firestore.
  static const permissionDeniedWarning =
      'Sem permissão para ler os dados de mercado. As regras do Firestore '
      'precisam liberar a leitura da coleção "market" para usuários logados.';

  /// Dados com mais de 3 dias: avisa que o robô pode ter parado.
  static const staleAfter = Duration(days: 3);

  /// Lê do servidor; sem conexão, usa a cópia guardada no aparelho e avisa.
  /// (O get() padrão do Firestore volta para a cópia local sem avisar quando
  /// acha que está offline, e o "Atualizar dados" mostrava o dado velho.)
  Future<QuerySnapshot<Map<String, dynamic>>> _read(
      List<String> warnings) async {
    final col = _db.collection('market');
    try {
      return await col
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') rethrow;
    } on TimeoutException {
      // Segue para a cópia local.
    }
    final cached = await col.get(const GetOptions(source: Source.cache));
    if (cached.docs.isNotEmpty) {
      warnings.add('Sem conexão com o servidor: mostrando os últimos dados '
          'guardados no aparelho.');
    }
    return cached;
  }

  Future<MarketData> load() async {
    final warnings = <String>[];
    final docs = <String, (Object?, DateTime)>{};
    try {
      final snap = await _read(warnings);
      for (final d in snap.docs) {
        final data = d.data();
        final payload = data['payload'];
        final at = data['fetchedAt'];
        if (payload is String && at is Timestamp) {
          docs[d.id] = (jsonDecode(payload), at.toDate());
        }
      }
    } on FirebaseException catch (e) {
      debugPrint('Mercado: $e');
      // Regras do Firestore sem a leitura de "market": não é falta de dado.
      return MarketData(warnings: [
        e.code == 'permission-denied'
            ? permissionDeniedWarning
            : 'Não foi possível ler os dados de mercado (${e.code}). '
                'Confira a internet e tente de novo.',
      ]);
    } catch (e) {
      debugPrint('Mercado: $e');
      return const MarketData(
        warnings: ['Não foi possível ler os dados de mercado.'],
      );
    }
    return fromDocs(docs, warnings: warnings);
  }

  /// Monta os dados a partir dos documentos de "market": id → (conteúdo
  /// JSON, horário da gravação). Separado do Firestore para ser testado.
  static MarketData fromDocs(Map<String, (Object?, DateTime)> docs,
      {List<String> warnings = const [], DateTime? now}) {
    warnings = [...warnings];
    if (docs.isEmpty) {
      return const MarketData(warnings: [
        'Os dados de mercado ainda não foram gerados. Eles são atualizados '
            'uma vez por dia.',
      ]);
    }

    /// [stamped]: documento com horário próprio (macro e bitcoin). O que
    /// vale é o da gravação no Firestore (instante exato); o do conteúdo
    /// vinha sem fuso e aparecia 3 horas adiantado. Nos outros documentos
    /// (ETFs, cotações) cada chave é um ativo: não pode ganhar campo extra.
    T? read<T>(String key, T Function(Object?) parse, {bool stamped = false}) {
      final entry = docs[key];
      if (entry == null) return null;
      try {
        final json = entry.$1;
        return parse(stamped && json is Map
            ? {...json, 'fetchedAt': entry.$2.toUtc().toIso8601String()}
            : json);
      } catch (e) {
        debugPrint('Mercado ($key): $e');
        return null;
      }
    }

    final oldest =
        docs.values.map((e) => e.$2).reduce((a, b) => a.isBefore(b) ? a : b);
    final age = (now ?? DateTime.now()).difference(oldest);
    if (age > staleAfter) {
      warnings.add('Parte dos dados de mercado é de ${age.inDays} dias '
          'atrás; a atualização automática pode ter falhado.');
    }

    final stocks = read(
        'stocks',
        (j) => [
              for (final s in j as List)
                StockQuote.fromJson(Map<String, dynamic>.from(s as Map)),
            ]);

    return MarketData(
      macro: read('macro',
          (j) => MacroSnapshot.fromJson(Map<String, dynamic>.from(j as Map)),
          stamped: true),
      etfs: read(
              'etfs',
              (j) => {
                    for (final e in (j as Map).entries)
                      e.key as String: PriceSeries.fromJson(
                          Map<String, dynamic>.from(e.value as Map)),
                  }) ??
          const {},
      bitcoin: read('bitcoin',
          (j) => BitcoinSnapshot.fromJson(Map<String, dynamic>.from(j as Map)),
          stamped: true),
      // O ranking usa histórico de preços: só existe se o robô conseguiu.
      stocks: stocks ?? const [],
      quotes: read(
              'quotes',
              (j) => {
                    for (final e in (j as Map).entries)
                      e.key as String: (e.value as num).toDouble(),
                  }) ??
          const {},
      warnings: warnings,
    );
  }
}
