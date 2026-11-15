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

  const ExpenseType({required this.name, required this.color});

  factory ExpenseType.fromMap(Map<String, dynamic> m) => ExpenseType(
        name: (m['name'] as String?)?.trim() ?? '',
        color: _color(m['color']),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'color': color.toRadixString(16).padLeft(8, '0'),
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
