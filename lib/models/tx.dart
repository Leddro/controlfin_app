import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
    'estacionamento'
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
      ['curso', 'faculdade', 'escola', 'livro', 'mensalidade']),
  Category('Lazer', Icons.celebration_rounded, Color(0xFF65A30D),
      ['cinema', 'netflix', 'spotify', 'viagem', 'bar', 'show', 'jogo']),
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

Category categoryOf(TxType type, String name) {
  final list = type == TxType.expense ? expenseCategories : incomeCategories;
  return list.firstWhere((c) => c.name == name, orElse: () => list.last);
}

/// Sugere a categoria a partir da descrição digitada.
Category? suggestCategory(TxType type, String description) {
  final text = description.toLowerCase();
  if (text.trim().isEmpty) return null;
  final list = type == TxType.expense ? expenseCategories : incomeCategories;
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
/// Em parcelas, [amount] é o valor TOTAL; os centavos de arredondamento
/// ficam nas primeiras parcelas para a soma fechar exatamente.
List<Tx> buildSeries({
  required TxType type,
  required double amount,
  required String category,
  required String description,
  required DateTime start,
  required TxKind kind,
  int count = 1,
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

  final totalCents = (amount * 100).round();
  final baseCents = totalCents ~/ count;
  final extra = totalCents - baseCents * count;

  return List.generate(count, (i) {
    final value = kind == TxKind.recurring
        ? amount
        : (baseCents + (i < extra ? 1 : 0)) / 100;
    return Tx(
      type: type,
      amount: value,
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
