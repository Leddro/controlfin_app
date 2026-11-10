import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum TxType { income, expense }

class Category {
  final String name;
  final IconData icon;
  final Color color;
  final List<String> keywords; // usadas para sugerir a categoria automaticamente
  const Category(this.name, this.icon, this.color, [this.keywords = const []]);
}

const expenseCategories = <Category>[
  Category('Moradia', Icons.home_rounded, Color(0xFF1D4E89),
      ['aluguel', 'condominio', 'condomínio', 'iptu', 'reforma']),
  Category('Alimentação', Icons.restaurant_rounded, Color(0xFFE07A1F),
      ['mercado', 'supermercado', 'padaria', 'ifood', 'restaurante', 'lanche', 'feira']),
  Category('Transporte', Icons.directions_car_rounded, Color(0xFF7B5EA7),
      ['uber', '99', 'gasolina', 'combustível', 'combustivel', 'ônibus', 'onibus', 'estacionamento']),
  Category('Contas', Icons.receipt_long_rounded, Color(0xFFC2410C),
      ['luz', 'energia', 'água', 'agua', 'internet', 'celular', 'telefone', 'gás', 'gas']),
  Category('Saúde', Icons.favorite_rounded, Color(0xFFBE185D),
      ['farmácia', 'farmacia', 'médico', 'medico', 'plano de saúde', 'dentista', 'consulta']),
  Category('Educação', Icons.school_rounded, Color(0xFF0E7490),
      ['curso', 'faculdade', 'escola', 'livro', 'mensalidade']),
  Category('Lazer', Icons.celebration_rounded, Color(0xFF65A30D),
      ['cinema', 'netflix', 'spotify', 'viagem', 'bar', 'show', 'jogo']),
  Category('Compras', Icons.shopping_bag_rounded, Color(0xFFB45309),
      ['roupa', 'sapato', 'shopee', 'amazon', 'presente']),
  Category('Outros', Icons.more_horiz_rounded, Color(0xFF64748B)),
];

const incomeCategories = <Category>[
  Category('Salário', Icons.work_rounded, Color(0xFF0F766E), ['salário', 'salario', 'pagamento']),
  Category('Extra', Icons.bolt_rounded, Color(0xFF15803D), ['freela', 'bônus', 'bonus', 'venda']),
  Category('Investimentos', Icons.trending_up_rounded, Color(0xFF0369A1), ['dividendo', 'rendimento', 'juros']),
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

class Tx {
  final String? id;
  final TxType type;
  final double amount;
  final String category;
  final String description;
  final DateTime date;

  Tx({
    this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'amount': amount,
        'category': category,
        'description': description,
        'date': Timestamp.fromDate(date),
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
    );
  }
}
