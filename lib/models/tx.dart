import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'user_settings.dart';

enum TxType { income, expense }

class Category {
  final String name;
  final IconData icon;
  final Color color;
  final List<String>
      keywords; // usadas para sugerir a categoria automaticamente
  const Category(this.name, this.icon, this.color, [this.keywords = const []]);
}

const expenseCategories = <Category>[
  Category('Moradia', Icons.home_rounded, Color(0xFF1D4E89),
      ['aluguel', 'condominio', 'condomínio', 'iptu', 'reforma']),
  Category('Alimentação', Icons.restaurant_rounded, Color(0xFFE07A1F), [
    'mercado',
    'supermercado',
    'padaria',
    'ifood',
    'restaurante',
    'lanche',
    'feira'
  ]),
  Category('Transporte', Icons.directions_car_rounded, Color(0xFF7B5EA7), [
    'uber',
    '99',
    'gasolina',
    'combustível',
    'combustivel',
    'ônibus',
    'onibus',
    'estacionamento',
    'motos',
  ]),
  Category('Contas', Icons.receipt_long_rounded, Color(0xFFC2410C), [
    'luz',
    'energia',
    'água',
    'agua',
    'internet',
    'celular',
    'telefone',
    'gás',
    'gas'
  ]),
  Category('Saúde', Icons.favorite_rounded, Color(0xFFBE185D), [
    'farmácia',
    'farmacia',
    'médico',
    'medico',
    'plano de saúde',
    'dentista',
    'consulta'
  ]),
  Category('Educação', Icons.school_rounded, Color(0xFF0E7490),
      ['curso', 'faculdade', 'escola', 'livro', 'mensalidade', 'educacao']),
  Category('Lazer', Icons.celebration_rounded, Color(0xFF65A30D),
      [
        'cinema',
        'netflix',
        'spotify',
        'viagem',
        'bar',
        'show',
        'jogo',
        'steam',
      ]),
  Category('Compras', Icons.shopping_bag_rounded, Color(0xFFB45309),
      ['roupa', 'sapato', 'shopee', 'amazon', 'presente']),
  Category('Outros', Icons.more_horiz_rounded, Color(0xFF64748B)),
];

const incomeCategories = <Category>[
  Category('Salário', Icons.work_rounded, Color(0xFF0F766E),
      ['salário', 'salario', 'pagamento']),
  Category('Extra', Icons.bolt_rounded, Color(0xFF15803D),
      ['freela', 'bônus', 'bonus', 'venda']),
  Category('Investimentos', Icons.trending_up_rounded, Color(0xFF0369A1),
      ['dividendo', 'rendimento', 'juros']),
  Category('Outros', Icons.more_horiz_rounded, Color(0xFF64748B)),
];

Category categoryOf(
  TxType type,
  String name, {
  List<ExpenseType> extra = const [],
}) {
  final list = type == TxType.expense ? expenseCategories : incomeCategories;
  for (final c in list) {
    if (c.name == name) return c;
  }
  if (type == TxType.expense) {
    for (final e in extra) {
      if (e.name == name) {
        return Category(e.name, Icons.label_rounded, Color(e.color));
      }
    }
  }
  return Category(name, Icons.more_horiz_rounded, const Color(0xFF64748B));
}

/// Tipos fixos mais os criados pelo usuário. "Outros" permanece no fim.
List<Category> categoriesFor(
  TxType type, {
  List<ExpenseType> extra = const [],
}) {
  final base = type == TxType.expense ? expenseCategories : incomeCategories;
  if (type != TxType.expense || extra.isEmpty) return base;
  final known = base.map((c) => c.name.toLowerCase()).toSet();
  final custom = [
    for (final e in extra)
      if (!known.contains(e.name.toLowerCase()))
        Category(e.name, Icons.label_rounded, Color(e.color)),
  ];
  return [...base.sublist(0, base.length - 1), ...custom, base.last];
}

/// Sugere a categoria a partir da descrição digitada.
Category? suggestCategory(
  TxType type,
  String description, {
  List<ExpenseType> extra = const [],
}) {
  final text = description.toLowerCase();
  if (text.trim().isEmpty) return null;
  final list = categoriesFor(type, extra: extra);
  for (final c in list) {
    if (c.keywords.any(text.contains)) return c;
  }
  return null;
}

enum TxKind { single, recurring, installment }

/// Categorias tratadas como "essenciais" na regra 50/30/20.
const needsCategoryNames = {
  'Moradia',
  'Alimentação',
  'Transporte',
  'Contas',
  'Saúde',
  'Educação',
};

/// Converte "1.500,50" ou "1500.50" em double.
double? parseMoney(String text) {
  var t = text.trim().replaceAll(r'R$', '').replaceAll(' ', '');
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(t);
}

/// Soma meses sem estourar o dia (31/01 + 1 mês = 28/02).
DateTime addMonths(DateTime d, int n) {
  final y = d.year + (d.month - 1 + n) ~/ 12;
  final m = (d.month - 1 + n) % 12 + 1;
  final last = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > last ? last : d.day);
}

class Tx {
  final String? id;
  final TxType type;
  final double amount;
  final String category;
  final String description;
  final DateTime date;
  final String? groupId; // liga os lançamentos de uma mesma série
  final TxKind kind;
  final int index; // posição na série (1..count)
  final int count;

  Tx({
    this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
    this.groupId,
    this.kind = TxKind.single,
    this.index = 1,
    this.count = 1,
  });

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'amount': amount,
        'category': category,
        'description': description,
        'date': Timestamp.fromDate(date),
        'kind': kind.name,
        'index': index,
        'count': count,
        if (groupId != null) 'groupId': groupId,
      };

  factory Tx.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Tx(
      id: doc.id,
      type: d['type'] == 'income' ? TxType.income : TxType.expense,
      amount: (d['amount'] as num).toDouble(),
      category: d['category'] as String,
      description: (d['description'] ?? '') as String,
      date: (d['date'] as Timestamp).toDate(),
      groupId: d['groupId'] as String?,
      kind: TxKind.values
          .firstWhere((k) => k.name == d['kind'], orElse: () => TxKind.single),
      index: (d['index'] as num?)?.toInt() ?? 1,
      count: (d['count'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Gera um lançamento único, uma série mensal ou as parcelas de uma compra.
///
/// - [perInstallment] = false (padrão): [amount] é o valor TOTAL da compra.
/// - [perInstallment] = true: [amount] é o valor de CADA parcela.
/// - [startIndex] indica a partir de qual parcela gerar (ex.: já pagou as 2
///   primeiras, começar pela 3).
List<Tx> buildSeries({
  required TxType type,
  required double amount,
  required String category,
  required String description,
  required DateTime start,
  required TxKind kind,
  int count = 1,
  int startIndex = 1,
  bool perInstallment = false,
}) {
  if (kind == TxKind.single || count <= 1) {
    return [
      Tx(
          type: type,
          amount: amount,
          category: category,
          description: description,
          date: start)
    ];
  }

  final groupId = '${DateTime.now().microsecondsSinceEpoch}';

  if (kind == TxKind.recurring) {
    return List.generate(count, (i) {
      return Tx(
        type: type,
        amount: amount,
        category: category,
        description: description,
        date: addMonths(start, i),
        groupId: groupId,
        kind: kind,
        index: i + 1,
        count: count,
      );
    });
  }

  // Parcelada
  final remaining = count - startIndex + 1;

  if (perInstallment) {
    // amount já é o valor de cada parcela — não precisa dividir
    return List.generate(remaining, (i) {
      return Tx(
        type: type,
        amount: amount,
        category: category,
        description: description,
        date: addMonths(start, i),
        groupId: groupId,
        kind: kind,
        index: startIndex + i,
        count: count,
      );
    });
  }

  // amount é o total — divide entre as parcelas com ajuste de centavos
  final totalCents = (amount * 100).round();
  final baseCents = totalCents ~/ count;
  final extra = totalCents - baseCents * count;

  return List.generate(remaining, (i) {
    final idx = startIndex + i;
    final value = (baseCents + ((idx - 1) < extra ? 1 : 0)) / 100;
    return Tx(
      type: type,
      amount: value,
      category: category,
      description: description,
      date: addMonths(start, i),
      groupId: groupId,
      kind: kind,
      index: idx,
      count: count,
    );
  });
}
