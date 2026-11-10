class UserSettings {
  final double? monthlyIncome; // renda média mensal definida pelo usuário
  final int emergencyMonths; // meses de gastos essenciais para a reserva
  final double reserveSaved; // quanto já está guardado
  const UserSettings({this.monthlyIncome, this.emergencyMonths = 6, this.reserveSaved = 0});

  factory UserSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const UserSettings();
    return UserSettings(
      monthlyIncome: (m['monthlyIncome'] as num?)?.toDouble(),
      emergencyMonths: (m['emergencyMonths'] as num?)?.toInt() ?? 6,
      reserveSaved: (m['reserveSaved'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'monthlyIncome': monthlyIncome,
        'emergencyMonths': emergencyMonths,
        'reserveSaved': reserveSaved,
      };
}
