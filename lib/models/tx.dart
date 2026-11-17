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
  Category('Lazer', Icons.celebration_rounded, Color(0xFF65A30D), [
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

/// Como um gasto foi pago. Débito, Pix e dinheiro saem na hora; crédito sai
/// no vencimento da fatura.
enum PaymentMethod { debit, credit }

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
/// Aceita [n] negativo (voltar meses), inclusive atravessando o ano.
DateTime addMonths(DateTime d, int n) {
  // DateTime normaliza o mês (13 vira janeiro do ano seguinte, 0 vira
  // dezembro do anterior). A divisão inteira antiga arredondava -2 ~/ 12
  // para 0 e errava o ano ao voltar meses.
  final first = DateTime(d.year, d.month + n);
  final last = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, d.day > last ? last : d.day);
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

  /// Forma de pagamento do gasto. Nulo em lançamentos antigos e em ganhos.
  final PaymentMethod? payment;

  /// Cartão usado, quando [payment] é crédito.
  final String? cardId;

  /// Vencimento da fatura em que o gasto no crédito é cobrado.
  final DateTime? billDate;

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
    this.payment,
    this.cardId,
    this.billDate,
  });

  bool get isCredit => payment == PaymentMethod.credit;

  /// Data em que o dinheiro sai: o vencimento da fatura no crédito, a
  /// própria data nos demais. Define em qual mês o lançamento conta.
  DateTime get cashDate => isCredit && billDate != null ? billDate! : date;

  Tx copyWith({
    String? id,
    double? amount,
    DateTime? date,
    String? groupId,
    TxKind? kind,
    int? index,
    int? count,
    PaymentMethod? Function()? payment,
    String? Function()? cardId,
    DateTime? Function()? billDate,
  }) =>
      Tx(
        id: id ?? this.id,
        type: type,
        amount: amount ?? this.amount,
        category: category,
        description: description,
        date: date ?? this.date,
        groupId: groupId ?? this.groupId,
        kind: kind ?? this.kind,
        index: index ?? this.index,
        count: count ?? this.count,
        payment: payment != null ? payment() : this.payment,
        cardId: cardId != null ? cardId() : this.cardId,
        billDate: billDate != null ? billDate() : this.billDate,
      );

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
        // Sempre gravados (mesmo nulos) para a edição conseguir limpar.
        'payment': payment?.name,
        'cardId': isCredit ? cardId : null,
        'billDate':
            isCredit && billDate != null ? Timestamp.fromDate(billDate!) : null,
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
      payment:
          PaymentMethod.values.where((p) => p.name == d['payment']).firstOrNull,
      cardId: d['cardId'] as String?,
      billDate: (d['billDate'] as Timestamp?)?.toDate(),
    );
  }
}

/// Gera um lançamento único, uma série mensal ou as parcelas de uma compra.
///
/// - [perInstallment] = false (padrão): [amount] é o valor TOTAL da compra.
/// - [perInstallment] = true: [amount] é o valor de CADA parcela.
/// - [startIndex] indica a partir de qual parcela gerar (ex.: já pagou as 2
///   primeiras, começar pela 3).
/// - No crédito, [firstBill] é o vencimento da fatura do primeiro
///   lançamento; os seguintes vão para as faturas dos meses seguintes. As
///   parcelas de uma compra no crédito guardam a data da compra.
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
  PaymentMethod? payment,
  String? cardId,
  DateTime? firstBill,
}) {
  final credit = payment == PaymentMethod.credit;
  Tx make(double value, int offset, {String? groupId, int index = 1}) => Tx(
        type: type,
        amount: value,
        category: category,
        description: description,
        date: credit && kind == TxKind.installment
            ? start
            : addMonths(start, offset),
        groupId: groupId,
        kind: groupId == null ? TxKind.single : kind,
        index: index,
        count: groupId == null ? 1 : count,
        payment: payment,
        cardId: credit ? cardId : null,
        billDate:
            credit && firstBill != null ? addMonths(firstBill, offset) : null,
      );

  if (kind == TxKind.single || count <= 1) return [make(amount, 0)];

  final groupId = '${DateTime.now().microsecondsSinceEpoch}';

  if (kind == TxKind.recurring) {
    return List.generate(
        count, (i) => make(amount, i, groupId: groupId, index: i + 1));
  }

  // Parcelada
  final remaining = count - startIndex + 1;

  if (perInstallment) {
    // amount já é o valor de cada parcela — não precisa dividir
    return List.generate(remaining,
        (i) => make(amount, i, groupId: groupId, index: startIndex + i));
  }

  // amount é o total — divide entre as parcelas com ajuste de centavos
  final totalCents = (amount * 100).round();
  final baseCents = totalCents ~/ count;
  final extra = totalCents - baseCents * count;

  return List.generate(remaining, (i) {
    final idx = startIndex + i;
    final value = (baseCents + ((idx - 1) < extra ? 1 : 0)) / 100;
    return make(value, i, groupId: groupId, index: idx);
  });
}

/// Edição de uma compra parcelada: [edited] é a parcela aberta no
/// formulário, já com a data da compra (crédito) ou a data dela (débito) e,
/// no crédito, a fatura em que ela cai. As outras parcelas acompanham:
///
/// - crédito: todas guardam a data da compra e a parcela N vai para a
///   fatura N-k meses depois da fatura da parcela editada (k);
/// - débito: cada parcela fica um mês depois da anterior.
///
/// Cartão, categoria e descrição valem para todas. O valor novo vale para
/// as parcelas que tinham o mesmo valor da editada ([oldAmount]); as que
/// diferem (ajuste de centavos) ficam como estão.
List<Tx> rebuildInstallments(Tx edited, List<Tx> series, {double? oldAmount}) {
  final all =
      series.any((o) => o.id == edited.id) ? series : [...series, edited];
  return [
    for (final o in all)
      if (o.id == edited.id)
        edited
      else
        Tx(
          id: o.id,
          type: edited.type,
          amount: oldAmount != null && (o.amount - oldAmount).abs() < 0.005
              ? edited.amount
              : o.amount,
          category: edited.category,
          description: edited.description,
          date: edited.isCredit
              ? edited.date
              : addMonths(edited.date, o.index - edited.index),
          groupId: o.groupId,
          kind: o.kind,
          index: o.index,
          count: o.count,
          payment: edited.payment,
          cardId: edited.isCredit ? edited.cardId : null,
          billDate: edited.isCredit && edited.billDate != null
              ? addMonths(edited.billDate!, o.index - edited.index)
              : null,
        ),
  ];
}

/// Leva a forma de pagamento, o cartão, a categoria e a descrição de
/// [edited] para os outros meses de um lançamento mensal. Cada mês mantém
/// a data e o valor; no crédito, vai para a fatura do seu mês.
List<Tx> applyToSeries(Tx edited, List<Tx> series) => [
      for (final o in series)
        if (o.id == edited.id)
          edited
        else
          Tx(
            id: o.id,
            type: edited.type,
            amount: o.amount,
            category: edited.category,
            description: edited.description,
            date: o.date,
            groupId: o.groupId,
            kind: o.kind,
            index: o.index,
            count: o.count,
            payment: edited.payment,
            cardId: edited.isCredit ? edited.cardId : null,
            billDate: edited.isCredit && edited.billDate != null
                ? addMonths(edited.billDate!, o.index - edited.index)
                : null,
          ),
    ];

/// A edição mudou algo que faz sentido levar para o resto da série.
bool changesSeries(Tx before, Tx after) =>
    before.payment != after.payment ||
    before.cardId != after.cardId ||
    before.category != after.category ||
    before.description != after.description ||
    (after.isCredit &&
        after.billDate != null &&
        (before.billDate == null ||
            !_sameDay(before.billDate!, after.billDate!)));

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
