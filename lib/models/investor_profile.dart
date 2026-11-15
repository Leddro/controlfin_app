/// Perfil de investidor.
///
/// O perfil combina duas medidas, como na literatura de finanças pessoais:
///
/// * **Disposição para risco** (preferência): estimada com escolhas entre
///   loterias (utilidade esperada de von Neumann e Morgenstern), com a
///   aposta de renda de Barsky, Juster, Kimball e Shapiro (1997), que
///   classifica o coeficiente de aversão relativa ao risco de Arrow e Pratt.
///   A utilidade logarítmica de Bernoulli (γ = 1) é uma das fronteiras.
///   Também usa a reação a perdas (Kahneman e Tversky) e a escolha entre
///   faixas de risco e retorno (Markowitz).
/// * **Capacidade de correr risco** (situação): horizonte e fase da vida
///   (ciclo de vida de Modigliani e Brumberg; Samuelson e Merton), renda do
///   trabalho como capital humano (Bodie, Merton e Samuelson), reserva de
///   emergência, dependentes e experiência (suitability, Resolução CVM 30).
///
/// O perfil final segue a menor das duas: quem gosta de risco mas não pode
/// perder o dinheiro no curto prazo, ou o contrário, fica no perfil menor.
library;

enum InvestorType { conservative, moderate, aggressive }

extension InvestorTypeText on InvestorType {
  String get label => switch (this) {
        InvestorType.conservative => 'Conservador',
        InvestorType.moderate => 'Moderado',
        InvestorType.aggressive => 'Arrojado',
      };

  String get description => switch (this) {
        InvestorType.conservative =>
          'Prioriza segurança e liquidez. Aceita ganhar menos para não ver o '
              'dinheiro cair, e o foco é preservar o que já tem.',
        InvestorType.moderate =>
          'Busca equilíbrio. Aceita algumas oscilações em parte do dinheiro '
              'para ganhar mais no médio e longo prazo, mantendo uma base segura.',
        InvestorType.aggressive =>
          'Aceita oscilações fortes e perdas temporárias em busca de mais '
              'retorno no longo prazo, com tempo e estrutura para esperar.',
      };
}

/// Uma pergunta do questionário, com as opções em ordem de pontuação.
class InvestorQuestion {
  final String id;
  final String title;
  final String? help;
  final List<String> options;

  const InvestorQuestion({
    required this.id,
    required this.title,
    this.help,
    required this.options,
  });
}

const goalOptions = [
  'Montar ou reforçar a reserva de emergência',
  'Comprar algo (casa, carro, viagem)',
  'Aposentadoria',
  'Fazer o patrimônio crescer no longo prazo',
  'Ter uma renda extra todo mês',
];

const horizonOptions = [
  'Em menos de 1 ano',
  'Entre 1 e 3 anos',
  'Entre 3 e 5 anos',
  'Entre 5 e 10 anos',
  'Daqui a mais de 10 anos',
];

/// Perguntas fixas, na ordem em que aparecem. A aposta de renda
/// ([gambleQuestion] e [gambleFollowUp]) entra depois da experiência.
const investorQuestions = <InvestorQuestion>[
  InvestorQuestion(
    id: 'goal',
    title: 'Qual é o principal objetivo do dinheiro que você vai investir?',
    options: goalOptions,
  ),
  InvestorQuestion(
    id: 'horizon',
    title: 'Quando você deve precisar desse dinheiro?',
    help: 'Quanto mais tempo até precisar, mais dá para esperar uma queda '
        'passar.',
    options: horizonOptions,
  ),
  InvestorQuestion(
    id: 'age',
    title: 'Qual é a sua idade?',
    help: 'Pela teoria do ciclo de vida, quem está no começo da vida '
        'profissional ainda tem muitos anos de renda pela frente.',
    options: [
      'Menos de 25 anos',
      '25 a 34 anos',
      '35 a 44 anos',
      '45 a 54 anos',
      '55 a 64 anos',
      '65 anos ou mais',
    ],
  ),
  InvestorQuestion(
    id: 'income',
    title: 'Como é a sua renda?',
    help: 'Uma renda estável funciona como uma parte segura do seu patrimônio.',
    options: [
      'Estável (CLT, servidor público, aposentadoria)',
      'Varia um pouco de mês a mês',
      'Muito variável (autônomo, comissão)',
      'Não tenho renda no momento',
    ],
  ),
  InvestorQuestion(
    id: 'reserve',
    title: 'Você tem uma reserva de emergência?',
    help: 'Dinheiro guardado para imprevistos, que dá para sacar a qualquer '
        'hora.',
    options: [
      'Não tenho',
      'Tenho menos de 3 meses de gastos',
      'Entre 3 e 6 meses de gastos',
      'Mais de 6 meses de gastos',
    ],
  ),
  InvestorQuestion(
    id: 'dependents',
    title: 'Alguém depende financeiramente de você?',
    options: ['Não', 'Sim'],
  ),
  InvestorQuestion(
    id: 'experience',
    title: 'Em quais investimentos você já aplicou?',
    options: [
      'Só poupança, ou nenhum',
      'Renda fixa (Tesouro Direto, CDB, LCI/LCA)',
      'Fundos, fundos imobiliários ou ações, de vez em quando',
      'Ações, ETFs ou derivativos com frequência',
    ],
  ),
  InvestorQuestion(
    id: 'drop',
    title: 'Você investiu R\$ 10.000 e, em um mês, o valor caiu para '
        'R\$ 8.000. O que você faria?',
    options: [
      'Venderia tudo para não perder mais',
      'Venderia uma parte',
      'Manteria e esperaria recuperar',
      'Aproveitaria para investir mais',
    ],
  ),
  InvestorQuestion(
    id: 'range',
    title: 'Para R\$ 10.000 investidos por um ano, qual faixa de resultado '
        'você aceitaria?',
    help: 'Faixas mais largas costumam render mais na média, mas podem '
        'terminar abaixo do valor investido.',
    options: [
      'Entre R\$ 10.500 e R\$ 10.700 (sem risco de perda)',
      'Entre R\$ 9.800 e R\$ 11.200',
      'Entre R\$ 9.200 e R\$ 12.000',
      'Entre R\$ 8.000 e R\$ 13.500',
    ],
  ),
];

/// Aposta de renda de Barsky et al. (1997): 50% de chance de dobrar a
/// renda e 50% de reduzi-la. Respostas: 0 = não aceita, 1 = aceita.
const gambleQuestion = InvestorQuestion(
  id: 'gamble',
  title: 'Imagine que você pode trocar de trabalho. O novo tem 50% de chance '
      'de dobrar sua renda e 50% de chance de reduzi-la em um terço (-33%). '
      'Você aceitaria?',
  help: 'Não existe resposta certa. A pergunta mede o quanto você troca '
      'segurança por chance de ganho.',
  options: ['Não, prefiro a renda atual', 'Sim, aceitaria'],
);

/// Segunda aposta: mais arriscada (-50%) se aceitou, mais leve (-20%) se não.
InvestorQuestion gambleFollowUp({required bool acceptedFirst}) =>
    InvestorQuestion(
      id: 'gambleFollow',
      title: acceptedFirst
          ? 'E se a redução possível fosse de metade da renda (-50%), com a '
              'mesma chance de dobrar?'
          : 'E se a redução possível fosse de um quinto da renda (-20%), com '
              'a mesma chance de dobrar?',
      options: const ['Não aceitaria', 'Sim, aceitaria'],
    );

/// Faixa do coeficiente de aversão relativa ao risco (Arrow-Pratt) indicada
/// pelas duas apostas de renda, para utilidade CRRA.
enum RiskAversionClass { veryHigh, high, moderate, low }

extension RiskAversionText on RiskAversionClass {
  String get range => switch (this) {
        RiskAversionClass.veryHigh => 'γ ≥ 3,76',
        RiskAversionClass.high => '2 ≤ γ < 3,76',
        RiskAversionClass.moderate => '1 ≤ γ < 2',
        RiskAversionClass.low => 'γ < 1',
      };

  String get label => switch (this) {
        RiskAversionClass.veryHigh => 'muito alta',
        RiskAversionClass.high => 'alta',
        RiskAversionClass.moderate => 'moderada',
        RiskAversionClass.low => 'baixa',
      };
}

class InvestorProfile {
  static const version = 1;

  /// Índice da opção escolhida em cada pergunta, pela chave [InvestorQuestion.id].
  final Map<String, int> answers;
  final DateTime createdAt;

  const InvestorProfile({required this.answers, required this.createdAt});

  static const requiredKeys = [
    'goal',
    'horizon',
    'age',
    'income',
    'reserve',
    'dependents',
    'experience',
    'gamble',
    'gambleFollow',
    'drop',
    'range',
  ];

  bool get isComplete => requiredKeys.every(answers.containsKey);

  int _a(String key) => answers[key] ?? 0;

  int get goal => _a('goal');
  int get horizon => _a('horizon');

  RiskAversionClass get riskAversion {
    final first = _a('gamble') == 1;
    final second = _a('gambleFollow') == 1;
    if (first) {
      return second ? RiskAversionClass.low : RiskAversionClass.moderate;
    }
    return second ? RiskAversionClass.high : RiskAversionClass.veryHigh;
  }

  /// Disposição para risco, de 0 a 100.
  double get willingness {
    final gamble = RiskAversionClass.values.indexOf(riskAversion) / 3 * 100;
    final drop = _a('drop') / 3 * 100;
    final range = _a('range') / 3 * 100;
    return gamble * 0.45 + drop * 0.30 + range * 0.25;
  }

  /// Capacidade de correr risco, de 0 a 100.
  double get capacity {
    const ageScore = [100.0, 90.0, 75.0, 55.0, 35.0, 20.0];
    const incomeScore = [100.0, 60.0, 30.0, 0.0];
    const reserveScore = [0.0, 35.0, 75.0, 100.0];
    const experienceScore = [0.0, 35.0, 70.0, 100.0];
    return horizon / 4 * 100 * 0.35 +
        ageScore[_a('age').clamp(0, 5)] * 0.15 +
        incomeScore[_a('income').clamp(0, 3)] * 0.15 +
        reserveScore[_a('reserve').clamp(0, 3)] * 0.20 +
        (_a('dependents') == 0 ? 100.0 : 50.0) * 0.05 +
        experienceScore[_a('experience').clamp(0, 3)] * 0.10;
  }

  /// Nota final: a menor entre disposição e capacidade.
  double get score => willingness < capacity ? willingness : capacity;

  /// Motivo que limita o perfil a Conservador, mesmo com nota maior.
  String? get conservativeCap {
    if (goal == 0) {
      return 'O objetivo é a reserva de emergência, que precisa estar '
          'disponível a qualquer momento e sem perdas.';
    }
    if (horizon == 0) {
      return 'Você vai precisar do dinheiro em menos de 1 ano, sem tempo '
          'para esperar uma queda passar.';
    }
    if (_a('reserve') == 0) {
      return 'Você ainda não tem reserva de emergência. O primeiro passo é '
          'montá-la antes de correr riscos.';
    }
    return null;
  }

  /// Motivo que limita o perfil a Moderado.
  String? get moderateCap {
    if (goal == 1 && horizon <= 1) {
      return 'A compra que você planeja é em até 3 anos, então o dinheiro '
          'não pode oscilar muito.';
    }
    return null;
  }

  InvestorType get type {
    if (conservativeCap != null) return InvestorType.conservative;
    final s = score;
    final byScore = s >= 70
        ? InvestorType.aggressive
        : s >= 40
            ? InvestorType.moderate
            : InvestorType.conservative;
    if (moderateCap != null && byScore == InvestorType.aggressive) {
      return InvestorType.moderate;
    }
    return byScore;
  }

  /// Qual das duas medidas definiu o perfil (ou a regra que o limitou).
  String get limitingFactor {
    final cap = conservativeCap ??
        (type == InvestorType.moderate && score >= 70 ? moderateCap : null);
    if (cap != null) return cap;
    if ((willingness - capacity).abs() < 5) {
      return 'Sua disposição e sua capacidade de correr risco estão '
          'parecidas.';
    }
    return willingness < capacity
        ? 'Sua situação permitiria mais risco, mas o perfil respeita o quanto '
            'você se sente confortável com oscilações.'
        : 'Você aceitaria mais risco, mas sua situação atual (prazo, reserva, '
            'renda ou fase da vida) pede mais cautela.';
  }

  factory InvestorProfile.fromMap(Map<String, dynamic> m) {
    final raw = m['answers'];
    final answers = <String, int>{
      if (raw is Map)
        for (final e in raw.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toInt(),
    };
    final created = m['createdAt'];
    return InvestorProfile(
      answers: answers,
      createdAt: (created is String ? DateTime.tryParse(created) : null) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'version': version,
        'answers': answers,
        'createdAt': createdAt.toIso8601String(),
        // Guardados só para consulta; o app sempre recalcula pelas respostas.
        'type': type.name,
        'score': double.parse(score.toStringAsFixed(1)),
      };
}

/// Referências teóricas exibidas na tela de investimentos.
const investorReferences = <(String, String)>[
  (
    'Daniel Bernoulli (1738)',
    'Utilidade marginal decrescente: perder R\$ 1.000 pesa mais do que '
        'ganhar R\$ 1.000, e o peso depende do quanto você já tem.'
  ),
  (
    'John von Neumann e Oskar Morgenstern (1944)',
    'Teoria da utilidade esperada: preferências de risco podem ser medidas '
        'por escolhas entre apostas, como as perguntas de renda.'
  ),
  (
    'Kenneth Arrow (1965) e John Pratt (1964)',
    'Coeficiente de aversão ao risco, que mede quanto retorno a pessoa '
        'exige para aceitar incerteza.'
  ),
  (
    'Barsky, Juster, Kimball e Shapiro (1997)',
    'As apostas de dobrar ou reduzir a renda, usadas para estimar o '
        'coeficiente de Arrow-Pratt.'
  ),
  (
    'Franco Modigliani e Richard Brumberg (1954)',
    'Ciclo de vida: as pessoas acumulam na fase ativa para consumir depois, '
        'então idade e horizonte mudam o quanto dá para arriscar.'
  ),
  (
    'Paul Samuelson (1969) e Robert Merton (1969)',
    'Escolha de carteira ao longo da vida: a parte em risco depende da '
        'aversão ao risco de cada pessoa.'
  ),
  (
    'Bodie, Merton e Samuelson (1992)',
    'Capital humano: uma renda estável funciona como um investimento seguro '
        'e permite mais risco no resto do patrimônio.'
  ),
  (
    'Harry Markowitz (1952)',
    'Risco e retorno andam juntos: carteiras que podem render mais também '
        'oscilam mais.'
  ),
  (
    'Daniel Kahneman e Amos Tversky (1979)',
    'Teoria do prospecto: perdas doem mais que ganhos equivalentes, por isso '
        'a pergunta sobre a queda de R\$ 10.000 para R\$ 8.000.'
  ),
  (
    'Grable e Lytton (1999)',
    'Questionários de tolerância a risco que combinam escolhas hipotéticas '
        'e situação financeira.'
  ),
  (
    'Resolução CVM 30 (2021)',
    'Regra brasileira de suitability: o perfil considera objetivo, situação '
        'financeira e conhecimento sobre investimentos.'
  ),
];
