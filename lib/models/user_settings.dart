import 'tx.dart';

enum BudgetKind { needs, wants, save, custom }

class BudgetCategory {
  final String name;
  final double percent;
  final BudgetKind kind;

  const BudgetCategory({
    required this.name,
    required this.percent,
    required this.kind,
  });

  static const defaults = <BudgetCategory>[
    BudgetCategory(name: 'Essenciais', percent: 50, kind: BudgetKind.needs),
    BudgetCategory(name: 'Desejos', percent: 30, kind: BudgetKind.wants),
    BudgetCategory(name: 'Guardar', percent: 20, kind: BudgetKind.save),
  ];

  BudgetCategory copyWith({String? name, double? percent}) => BudgetCategory(
        name: name ?? this.name,
        percent: percent ?? this.percent,
        kind: kind,
      );

  factory BudgetCategory.fromMap(Map<String, dynamic> m) {
    final kindName = m['kind'] as String?;
    final kind = BudgetKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => BudgetKind.custom,
    );
    return BudgetCategory(
      name: (m['name'] as String?)?.trim().isNotEmpty == true
          ? (m['name'] as String).trim()
          : 'Categoria',
      percent: (m['percent'] as num?)?.toDouble() ?? 0,
      kind: kind,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'percent': percent,
        'kind': kind.name,
      };
}

class ExpenseType {
  final String name;
  final int color;

  /// Nome da meta em que esse gasto conta (ex.: "Essenciais", "Desejos" ou
  /// uma categoria criada). Nulo ou meta inexistente: conta em Desejos.
  final String? goal;

  const ExpenseType({required this.name, required this.color, this.goal});

  ExpenseType copyWith({String? Function()? goal}) => ExpenseType(
        name: name,
        color: color,
        goal: goal != null ? goal() : this.goal,
      );

  factory ExpenseType.fromMap(Map<String, dynamic> m) => ExpenseType(
        name: (m['name'] as String?)?.trim() ?? '',
        color: _color(m['color']),
        goal: (m['goal'] as String?)?.trim().isNotEmpty == true
            ? (m['goal'] as String).trim()
            : null,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'color': color.toRadixString(16).padLeft(8, '0'),
        if (goal != null) 'goal': goal,
      };
}

class UserSettings {
  final double? monthlyIncome;
  final int emergencyMonths;
  final double reserveSaved;
  final List<BudgetCategory> budgets;
  final List<ExpenseType> expenseTypes;

  const UserSettings({
    this.monthlyIncome,
    this.emergencyMonths = 6,
    this.reserveSaved = 0,
    this.budgets = const [],
    this.expenseTypes = const [],
  });

  /// Metas salvas, com Essenciais, Desejos e Guardar garantidos.
  List<BudgetCategory> get effectiveBudgets {
    final source = budgets.isEmpty ? BudgetCategory.defaults : budgets;
    final result = [...source];
    for (final fallback in BudgetCategory.defaults) {
      if (!result.any((b) => b.kind == fallback.kind)) result.add(fallback);
    }
    final customs = result.where((b) => b.kind == BudgetKind.custom).toList();
    final ordered = <BudgetCategory>[
      result.firstWhere((b) => b.kind == BudgetKind.needs),
      ...customs,
      result.firstWhere((b) => b.kind == BudgetKind.wants),
      result.firstWhere((b) => b.kind == BudgetKind.save),
    ];
    return ordered;
  }

  /// Meta em que um gasto da categoria [category] é contado.
  ///
  /// Ordem: meta escolhida no tipo de gasto; meta criada com o mesmo nome;
  /// Essenciais para as categorias fixas essenciais; Desejos para o resto.
  BudgetCategory budgetOf(String category) =>
      goalFor(effectiveBudgets, expenseTypes, category);

  UserSettings copyWith({
    double? Function()? monthlyIncome,
    int? emergencyMonths,
    double? reserveSaved,
    List<BudgetCategory>? budgets,
    List<ExpenseType>? expenseTypes,
  }) {
    return UserSettings(
      monthlyIncome:
          monthlyIncome != null ? monthlyIncome() : this.monthlyIncome,
      emergencyMonths: emergencyMonths ?? this.emergencyMonths,
      reserveSaved: reserveSaved ?? this.reserveSaved,
      budgets: budgets ?? this.budgets,
      expenseTypes: expenseTypes ?? this.expenseTypes,
    );
  }

  factory UserSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const UserSettings();
    return UserSettings(
      monthlyIncome: (m['monthlyIncome'] as num?)?.toDouble(),
      emergencyMonths: (m['emergencyMonths'] as num?)?.toInt() ?? 6,
      reserveSaved: (m['reserveSaved'] as num?)?.toDouble() ?? 0,
      budgets: _list(m['budgets'], BudgetCategory.fromMap),
      expenseTypes: _list(m['expenseTypes'], ExpenseType.fromMap)
          .where((e) => e.name.isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'monthlyIncome': monthlyIncome,
        'emergencyMonths': emergencyMonths,
        'reserveSaved': reserveSaved,
        'budgets': budgets.map((b) => b.toMap()).toList(),
        'expenseTypes': expenseTypes.map((e) => e.toMap()).toList(),
      };
}

/// Metas em que um gasto pode contar (todas menos "Guardar", que é a sobra).
List<BudgetCategory> spendingGoals(List<BudgetCategory> budgets) =>
    budgets.where((b) => b.kind != BudgetKind.save).toList();

/// Mesma regra de [UserSettings.budgetOf], para listas ainda em edição.
BudgetCategory goalFor(
  List<BudgetCategory> budgets,
  List<ExpenseType> types,
  String category,
) {
  final goals = spendingGoals(budgets);
  BudgetCategory? named(String? name) {
    if (name == null) return null;
    final key = name.toLowerCase();
    for (final b in goals) {
      if (b.name.toLowerCase() == key) return b;
    }
    return null;
  }

  final key = category.toLowerCase();
  for (final type in types) {
    if (type.name.toLowerCase() != key) continue;
    final chosen = named(type.goal);
    if (chosen != null) return chosen;
    break;
  }
  final custom = named(category);
  if (custom != null && custom.kind == BudgetKind.custom) return custom;
  final kind = needsCategoryNames.contains(category)
      ? BudgetKind.needs
      : BudgetKind.wants;
  return goals.firstWhere((b) => b.kind == kind);
}

int _color(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) {
    final parsed = int.tryParse(raw, radix: 16);
    if (parsed != null) return parsed;
  }
  return 0xFF64748B;
}

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) parse(Map<String, dynamic>.from(item)),
  ];
}
