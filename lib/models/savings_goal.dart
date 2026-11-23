/// Metas de conquista do usuário (Viagem, Reforma...): quanto custa, até
/// quando e quanto já foi separado. Dart puro.
library;

/// Dinheiro separado (positivo) ou retirado (negativo) de uma meta.
class GoalDeposit {
  final double amount;
  final DateTime date;

  const GoalDeposit({required this.amount, required this.date});

  Map<String, dynamic> toMap() => {
        'amount': amount,
        'date': date.toIso8601String(),
      };

  static GoalDeposit? fromMap(Map<String, dynamic> m) {
    final amount = (m['amount'] as num?)?.toDouble();
    final date = DateTime.tryParse('${m['date']}');
    if (amount == null || date == null) return null;
    return GoalDeposit(amount: amount, date: date);
  }
}

class SavingsGoal {
  final String id;
  final String name;

  /// Chave do ícone (`goalIcons` na tela). Chave desconhecida vira estrela.
  final String icon;
  final int color;
  final double target;

  /// Mês em que o usuário quer conquistar (dia 1). Nulo: sem prazo.
  final DateTime? deadline;
  final List<GoalDeposit> deposits;
  final DateTime createdAt;

  const SavingsGoal({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.target,
    this.deadline,
    this.deposits = const [],
    required this.createdAt,
  });

  double get saved => deposits.fold(0.0, (s, d) => s + d.amount);
  double get remaining => (target - saved).clamp(0, double.infinity);
  double get progress =>
      target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0).toDouble();
  bool get done => target > 0 && saved >= target;

  /// Meses até o prazo, contando o mês atual (nulo sem prazo; 0 se passou).
  int? monthsLeft(DateTime now) {
    final d = deadline;
    if (d == null) return null;
    final months = (d.year - now.year) * 12 + d.month - now.month + 1;
    return months < 0 ? 0 : months;
  }

  /// Quanto separar por mês para chegar no prazo (nulo sem prazo, com a
  /// meta batida ou com o prazo vencido).
  double? monthlyNeeded(DateTime now) {
    final months = monthsLeft(now);
    if (months == null || months == 0 || done) return null;
    return remaining / months;
  }

  /// Histórico do mais recente para o mais antigo.
  List<GoalDeposit> get history =>
      [...deposits]..sort((a, b) => b.date.compareTo(a.date));

  SavingsGoal copyWith({
    String? name,
    String? icon,
    int? color,
    double? target,
    DateTime? Function()? deadline,
    List<GoalDeposit>? deposits,
  }) =>
      SavingsGoal(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        target: target ?? this.target,
        deadline: deadline != null ? deadline() : this.deadline,
        deposits: deposits ?? this.deposits,
        createdAt: createdAt,
      );

  SavingsGoal withDeposit(GoalDeposit d) =>
      copyWith(deposits: [...deposits, d]);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'target': target,
        'deadline': deadline?.toIso8601String(),
        'deposits': [for (final d in deposits) d.toMap()],
        'createdAt': createdAt.toIso8601String(),
      };

  static SavingsGoal? fromMap(Map<String, dynamic> m) {
    final id = m['id'], name = m['name'];
    final target = (m['target'] as num?)?.toDouble();
    if (id is! String || name is! String || target == null) return null;
    return SavingsGoal(
      id: id,
      name: name,
      icon: (m['icon'] as String?) ?? 'star',
      color: (m['color'] as num?)?.toInt() ?? goalSuggestions.first.color,
      target: target,
      deadline:
          m['deadline'] == null ? null : DateTime.tryParse('${m['deadline']}'),
      deposits: [
        for (final d in (m['deposits'] as List?) ?? const [])
          if (d is Map) GoalDeposit.fromMap(Map<String, dynamic>.from(d)),
      ].whereType<GoalDeposit>().toList(),
      createdAt: DateTime.tryParse('${m['createdAt']}') ?? DateTime(2026, 1, 1),
    );
  }
}

/// Ponto de partida para uma meta nova: nome, ícone e cor.
class GoalSuggestion {
  final String name;
  final String icon;
  final int color;

  const GoalSuggestion(this.name, this.icon, this.color);
}

const goalSuggestions = [
  GoalSuggestion('Viagem', 'travel', 0xFF38BDF8),
  GoalSuggestion('Reforma', 'renovation', 0xFFFBBF24),
  GoalSuggestion('Carro', 'car', 0xFFF87171),
  GoalSuggestion('Entrada da casa', 'house', 0xFF4ADE80),
  GoalSuggestion('Casamento', 'wedding', 0xFFF472B6),
  GoalSuggestion('Estudos', 'school', 0xFFA78BFA),
  GoalSuggestion('Celular novo', 'phone', 0xFF2DD4BF),
  GoalSuggestion('Móveis', 'furniture', 0xFFFB923C),
  GoalSuggestion('Moto', 'motorcycle', 0xFFA3E635),
  GoalSuggestion('Festa', 'party', 0xFFE879F9),
];

/// Sugestões que ainda não viraram meta: some a sugestão contida no nome de
/// alguma meta ("Reforma da cozinha" usa "Reforma"), sem diferenciar
/// maiúsculas.
List<GoalSuggestion> unusedSuggestions(List<SavingsGoal> goals) {
  final names = [for (final g in goals) g.name.trim().toLowerCase()];
  return [
    for (final s in goalSuggestions)
      if (!names.any((n) => n.contains(s.name.toLowerCase()))) s,
  ];
}

/// Metas em andamento primeiro (prazo mais perto antes; sem prazo no fim),
/// depois as conquistadas.
List<SavingsGoal> sortGoals(Iterable<SavingsGoal> goals) => goals.toList()
  ..sort((a, b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    final x = a.deadline, y = b.deadline;
    if (x != null && y != null) return x.compareTo(y);
    if (x != null || y != null) return x != null ? -1 : 1;
    return a.createdAt.compareTo(b.createdAt);
  });
