/// Notificações dos bancos lidas no Android e o que o app entende delas.
///
/// Dart puro: o texto chega pelo canal nativo (BankNotificationListener.kt)
/// e é interpretado aqui, com testes em test/bank_notification_test.dart.
library;

/// Notificação guardada no celular, como chegou do banco.
class CapturedNotification {
  final String id;
  final String package;
  final String title;
  final String text;
  final DateTime postedAt;

  /// Decisão do usuário na confirmação: 'confirmed' ou 'discarded'.
  final String? status;

  /// Já enviada (com os dados trocados) para a revisão do desenvolvedor.
  final bool sent;

  const CapturedNotification({
    required this.id,
    required this.package,
    required this.title,
    required this.text,
    required this.postedAt,
    this.status,
    this.sent = false,
  });

  factory CapturedNotification.fromMap(Map<String, dynamic> m) =>
      CapturedNotification(
        id: m['id'] as String,
        package: (m['package'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        text: (m['text'] ?? '') as String,
        postedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['postedAt'] as num?)?.toInt() ?? 0),
        status: m['status'] as String?,
        sent: m['sent'] == true,
      );

  String get bankName => bankNameOf(package);
}

/// Nome do banco pelo pacote do app no Android.
String bankNameOf(String package) => switch (package) {
      'com.nu.production' => 'Nubank',
      'br.com.xp.carteira' => 'XP',
      'com.itau' => 'Itaú',
      'com.santander.app' => 'Santander',
      'com.mercadopago.wallet' => 'Mercado Pago',
      'br.com.intermedium' => 'Inter',
      'com.c6bank.app' => 'C6 Bank',
      'com.bradesco' => 'Bradesco',
      'br.com.bb.android' => 'Banco do Brasil',
      'br.com.gabba.Caixa' => 'Caixa',
      'com.picpay' => 'PicPay',
      'br.com.uol.ps.myaccount' => 'PagBank',
      'com.google.android.apps.walletnfcrel' => 'Google Wallet',
      'com.samsung.android.spay' => 'Samsung Wallet',
      _ => package,
    };

/// Carteiras do celular: repetem a compra que o banco já avisou.
const walletPackages = {
  'com.google.android.apps.walletnfcrel',
  'com.samsung.android.spay',
};

/// Certeza da leitura de uma notificação.
enum Confidence {
  /// Formato conferido com texto real daquele banco: passa direto.
  high,

  /// Dúvida: vai para a revisão do desenvolvedor.
  medium,

  /// Quase certo que não é movimentação: nem vai para a revisão.
  low,
}

/// Formatos conferidos com notificações reais, por app de banco. Um
/// formato marcado como Certo na revisão entra aqui e passa a ir direto.
const verifiedFormats = <String, Set<String>>{
  'com.nu.production': {'approvedIn', 'receivedTransfer', 'cancel'},
  'com.itau': {'approvedOf'},
};

enum NotificationKind {
  creditPurchase,
  debitPurchase,
  pixIn,
  pixOut,

  /// Compra cancelada ou estornada.
  cancel,

  /// Não é movimentação (propaganda, aviso, recusa, carteira repetida...).
  ignored,

  /// Tem valor, mas o formato é desconhecido.
  unknown,
}

extension NotificationKindLabel on NotificationKind {
  String get label => switch (this) {
        NotificationKind.creditPurchase => 'Compra no crédito',
        NotificationKind.debitPurchase => 'Compra no débito',
        NotificationKind.pixIn => 'Pix/transferência recebida',
        NotificationKind.pixOut => 'Pix/transferência enviada',
        NotificationKind.cancel => 'Compra cancelada',
        NotificationKind.ignored => 'Ignorada',
        NotificationKind.unknown => 'Não entendi',
      };

  bool get isMovement =>
      this == NotificationKind.creditPurchase ||
      this == NotificationKind.debitPurchase ||
      this == NotificationKind.pixIn ||
      this == NotificationKind.pixOut;
}

/// O que o app entendeu de uma notificação.
class ParsedNotification {
  final NotificationKind kind;
  final double? amount;

  /// Estabelecimento (compras) ou pessoa (Pix).
  final String? counterpart;

  /// Final do cartão, quando a notificação informa.
  final String? last4;

  /// Dia da movimentação (o do texto, quando há; senão o da notificação).
  final DateTime date;

  /// Por que foi ignorada.
  final String? reason;

  /// Caminho de leitura usado (ex.: 'approvedIn'), para saber se o formato
  /// daquele banco já foi conferido com texto real.
  final String rule;

  /// Certeza da leitura. Só a média vai para a revisão do desenvolvedor.
  final Confidence confidence;

  const ParsedNotification({
    required this.kind,
    required this.date,
    this.amount,
    this.counterpart,
    this.last4,
    this.reason,
    this.rule = '',
    this.confidence = Confidence.medium,
  });

  ParsedNotification _withConfidence(Confidence c) => ParsedNotification(
        kind: kind,
        date: date,
        amount: amount,
        counterpart: counterpart,
        last4: last4,
        reason: reason,
        rule: rule,
        confidence: c,
      );

  /// Precisa que o desenvolvedor confira (vai para a revisão).
  bool get needsReview => confidence == Confidence.medium;

  /// Descrição sugerida para o lançamento.
  String get description => switch (kind) {
        NotificationKind.pixIn =>
          counterpart != null ? 'Pix de $counterpart' : 'Pix recebido',
        NotificationKind.pixOut =>
          counterpart != null ? 'Pix para $counterpart' : 'Pix enviado',
        _ => counterpart ?? '',
      };

  /// Resumo para a tela de validação.
  String summary(String Function(double) money) {
    if (kind == NotificationKind.ignored) return 'Ignorada: $reason';
    final parts = [
      kind.label,
      if (amount != null) money(amount!),
      if (counterpart != null)
        kind == NotificationKind.pixIn
            ? 'de $counterpart'
            : kind == NotificationKind.pixOut
                ? 'para $counterpart'
                : 'em $counterpart',
      if (last4 != null) 'cartão final $last4',
      '${_two(date.day)}/${_two(date.month)}',
    ];
    return parts.join(' • ');
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

// --- Leitura --------------------------------------------------------------

const _money = r'R\$\s*((?:\d{1,3}(?:\.\d{3})+|\d+)(?:,\d{1,2})?)';
const _ci = false; // caseSensitive

RegExp _re(String pattern) =>
    RegExp(pattern, caseSensitive: _ci, multiLine: true);

final _anyAmount = _re(_money);
final _declined = _re(r'recusad|negad|n[ãa]o (?:foi )?aprovad');

// "CASASBAHIA acabou de verificar se o seu cartão com final 4821 está ativo"
final _verification =
    _re(r'verifica(?:r|ndo|ção|cao|do)|cart[ãa]o verificado');
final _cancel = _re(
    '(?:compra|transa[çc][ãa]o|pagamento)[^\\n]{0,60}?(?:foi )?(?:cancelad|estornad)|estorno de $_money');

// Nubank crédito: "Compra de R$ 3.661,11 APROVADA em CASASBAHIACOM para o
// cartão com final 4821"
final _approvedIn = _re(
    'compra de $_money\\s+aprovad[ao]\\s+em\\s+(.+?)(?:\\s+para o cart[ãa]o(?: com)?(?: final)?\\s*(\\d{4}))?\\s*\\.?\$');

// NuPay: "R$ 53,58 no débito com NuPay APROVADO em KeetaBR."
final _payApproved = _re(
    '$_money\\s+no\\s+(d[ée]bito|cr[ée]dito)[^\\n]{0,25}?aprovad[ao]\\s+em\\s+(.+?)\\s*\\.?\$');

// Itaú: "Compra aprovada de R$ 82,41 em MADRE LEONIA no dia 05/01 às 17:45
// no seu cartão Itau. Boas compras."
final _approvedOf = _re(
    'compra aprovada de $_money\\s+em\\s+(.+?)(?:\\s+no dia\\s+(\\d{1,2})/(\\d{1,2})(?:\\s+[àa]s\\s+\\d{1,2}[:h]\\d{2})?)?(?:\\s+no seu cart[ãa]o[^.\\n]*?(?:final\\s*(\\d{4}))?[^.\\n]*)?\\s*[.!]?(?:\\s*boas compras.*)?\$');

// Nubank débito (com o título "Compra no débito aprovada"):
// "Compra de R$ 17,00 em ACADEMIA CEMI"
final _purchaseIn = _re('compra de $_money\\s+em\\s+(.+?)\\s*\\.?\$');

// "Você recebeu uma transferência de R$ 1000,00 de PAGFAST",
// "Você recebeu um Pix de R$ 2.300,00 de FULANO", "Recebemos sua
// transferência de R$ 10,00."
final _received = _re(
    '(?:voc[êe] )?receb(?:eu|emos)\\s+(?:sua |uma |um )?(?:transfer[êe]ncia|pix)(?: via pix)?\\s+de\\s+$_money(?:\\s+de\\s+(.+?))?\\s*\\.?\$');

// "Pix enviado: R$ 39,75 para MARIA SILVA", "Você enviou R$ 50,00 para
// FULANO", "Transferência enviada de R$ 20,00 para FULANO"
final _sent = [
  _re('pix enviado:?\\s*(?:de\\s+)?$_money(?:\\s+para\\s+(.+?))?\\s*\\.?\$'),
  _re('(?:voc[êe] )?(?:enviou|transferiu|fez um pix de|pagou um pix de)\\s+(?:um pix de |uma transfer[êe]ncia de )?$_money(?:\\s+para\\s+(.+?))?\\s*\\.?\$'),
  _re('transfer[êe]ncia (?:enviada|realizada)[^\\n]*?$_money(?:\\s+para\\s+(.+?))?\\s*\\.?\$'),
];

final _billPayment = _re(
    r'pagamento (?:da|de) (?:sua )?fatura|fatura (?:paga|fechou|fechada|dispon[íi]vel|vence|venceu|est[áa])');
final _promo = _re(
    r'\b(?:ganhe|receba|deposite|aproveite|oferta|desconto|cashback|cupom|promo\w*|limite|pr[ée]-aprovad\w*|empr[ée]stimo|investi\w*|rend\w*|saldo|parcele|convide|sorteio|pontos|blackíssima|black friday)\b');

/// Lê "1.234,56", "1000,00" e "50".
double? parseBrlAmount(String raw) {
  final s = raw.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(s);
}

/// "CASASBAHIACOM" vira "Casasbahiacom"; nomes já com minúsculas ficam.
String tidyName(String raw) {
  var s = raw
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[.!,;:\s]+$'), '');
  if (s.isEmpty) return s;
  if (s == s.toUpperCase()) {
    const small = {'de', 'da', 'do', 'das', 'dos', 'e'};
    s = s.split(' ').map((w) {
      final lower = w.toLowerCase();
      if (small.contains(lower)) return lower;
      return lower.isEmpty ? w : lower[0].toUpperCase() + lower.substring(1);
    }).join(' ');
  }
  return s;
}

/// Interpreta uma notificação de banco.
/// Interpreta uma notificação de banco e diz a certeza da leitura.
ParsedNotification parseBankNotification(CapturedNotification n) {
  final p = _parse(n);
  return p._withConfidence(_confidenceFor(n, p));
}

/// Palavras de movimentação: propaganda que fala delas merece revisão.
final _movementWords = _re(
    r'aprovad|recebeu|recebemos|enviad|transfer|\bpix\b|compra de|d[ée]bito|cr[ée]dito');

Confidence _confidenceFor(CapturedNotification n, ParsedNotification p) {
  if (p.rule == 'ignore.promo') {
    return _movementWords.hasMatch('${n.title}\n${n.text}')
        ? Confidence.medium
        : Confidence.low;
  }
  if (p.rule.startsWith('ignore.')) return Confidence.low;
  if (p.kind == NotificationKind.unknown) return Confidence.medium;
  return verifiedFormats[n.package]?.contains(p.rule) == true
      ? Confidence.high
      : Confidence.medium;
}

ParsedNotification _parse(CapturedNotification n) {
  final title = _clean(n.title);
  final text = _clean(n.text);
  final all = '$title\n$text';
  final day = DateTime(n.postedAt.year, n.postedAt.month, n.postedAt.day);

  ParsedNotification ignore(String rule, String reason, [double? amount]) =>
      ParsedNotification(
          kind: NotificationKind.ignored,
          date: day,
          amount: amount,
          reason: reason,
          rule: 'ignore.$rule');

  if (walletPackages.contains(n.package)) {
    return ignore(
        'wallet', 'repetida pela carteira do celular (o banco já avisa)');
  }
  final firstAmount = _anyAmount.firstMatch(all);
  if (firstAmount == null) return ignore('noValue', 'sem valor em reais');
  final anyValue = parseBrlAmount(firstAmount.group(1)!);

  if (_declined.hasMatch(all)) {
    return ignore('declined', 'compra recusada', anyValue);
  }
  if (_verification.hasMatch(all)) {
    return ignore(
        'verification', 'verificação do cartão (não é compra)', anyValue);
  }
  if (anyValue == 0) return ignore('zero', 'valor zero', anyValue);

  if (_cancel.hasMatch(all)) {
    return ParsedNotification(
        kind: NotificationKind.cancel,
        date: day,
        amount: anyValue,
        rule: 'cancel');
  }

  final titleLower = title.toLowerCase();
  final saysDebit = RegExp(r'd[ée]bito').hasMatch(titleLower);
  final saysCredit = RegExp(r'cr[ée]dito').hasMatch(titleLower);

  ParsedNotification purchase(String rule, double? amount, String? place,
      {bool? credit, String? last4, DateTime? date}) {
    final isCredit = credit ?? !saysDebit;
    return ParsedNotification(
      kind: isCredit
          ? NotificationKind.creditPurchase
          : NotificationKind.debitPurchase,
      date: date ?? day,
      amount: amount,
      counterpart: place == null ? null : tidyName(place),
      last4: last4,
      rule: rule,
    );
  }

  if (_approvedIn.firstMatch(text) case final m?) {
    return purchase('approvedIn', parseBrlAmount(m.group(1)!), m.group(2),
        credit: saysDebit ? false : true, last4: m.group(3));
  }
  if (_payApproved.firstMatch(text) case final m?) {
    final debit = m.group(2)!.toLowerCase().startsWith('d');
    return purchase('payApproved', parseBrlAmount(m.group(1)!), m.group(3),
        credit: !debit);
  }
  if (_approvedOf.firstMatch(text) case final m?) {
    DateTime? date;
    final d = int.tryParse(m.group(3) ?? '');
    final mo = int.tryParse(m.group(4) ?? '');
    if (d != null && mo != null && mo >= 1 && mo <= 12) {
      // Sem ano no texto: o da notificação (compra de dezembro avisada em
      // janeiro é do ano anterior).
      final year =
          mo > n.postedAt.month ? n.postedAt.year - 1 : n.postedAt.year;
      date = DateTime(year, mo, d);
    }
    return purchase('approvedOf', parseBrlAmount(m.group(1)!), m.group(2),
        credit: saysDebit ? false : true, last4: m.group(5), date: date);
  }
  if (_purchaseIn.firstMatch(text) case final m?) {
    // Sem dizer crédito ou débito no texto: vale o título.
    final credit = saysCredit || (!saysDebit && text.contains('cart'));
    return purchase('purchaseIn', parseBrlAmount(m.group(1)!), m.group(2),
        credit: credit);
  }
  if (_received.firstMatch(text) case final m?) {
    final who = m.group(2);
    final viaPix = m.group(0)!.toLowerCase().contains('pix');
    return ParsedNotification(
      kind: NotificationKind.pixIn,
      date: day,
      amount: parseBrlAmount(m.group(1)!),
      counterpart: who == null ? null : tidyName(who),
      rule: viaPix ? 'receivedPix' : 'receivedTransfer',
    );
  }
  for (final re in _sent) {
    if (re.firstMatch(text) case final m?) {
      final who = m.group(2);
      return ParsedNotification(
        kind: NotificationKind.pixOut,
        date: day,
        amount: parseBrlAmount(m.group(1)!),
        counterpart: who == null ? null : tidyName(who),
        rule: 'sent',
      );
    }
  }

  if (_billPayment.hasMatch(all)) {
    return ignore('bill', 'pagamento ou aviso de fatura (as compras já contam)',
        anyValue);
  }
  if (_promo.hasMatch(all)) {
    return ignore('promo', 'propaganda ou aviso', anyValue);
  }

  return ParsedNotification(
      kind: NotificationKind.unknown,
      date: day,
      amount: anyValue,
      rule: 'unknown');
}

String _clean(String s) =>
    s.replaceAll(' ', ' ').replaceAll(RegExp(r'[ \t]+'), ' ').trim();

// --- Revisão do desenvolvedor ---------------------------------------------

/// Texto da notificação com os dados pessoais trocados por exemplos, para
/// sair do celular: valores viram "R$ 99,99", datas "01/01", horários
/// "12:00", números com 2 ou mais dígitos viram zeros (final do cartão,
/// conta, CPF), o nome da pessoa do Pix vira "FULANO" e o primeiro nome do
/// usuário vira "USUÁRIO". Nomes de lojas ficam (são o que o leitor precisa
/// reconhecer).
({String title, String text}) anonymizeNotification(CapturedNotification n,
    {String? userName}) {
  final parsed = parseBankNotification(n);
  final who = parsed.kind == NotificationKind.pixIn ||
          parsed.kind == NotificationKind.pixOut
      ? parsed.counterpart
      : null;
  final first = userName?.trim().split(RegExp(r'\s+')).first;

  String scrub(String raw) {
    var t = raw.replaceAll(' ', ' ');
    if (who != null && who.length >= 3) {
      t = t.replaceAll(
          RegExp(RegExp.escape(who), caseSensitive: false), 'FULANO');
    }
    if (first != null && first.length >= 3) {
      t = t.replaceAll(
          RegExp('\\b${RegExp.escape(first)}\\b', caseSensitive: false),
          'USUÁRIO');
    }
    // Os exemplos entram como marcadores para o último passo (zerar
    // números) não zerar também os próprios exemplos.
    t = t.replaceAllMapped(RegExp(r'R\$(\s*)\d[\d.,]*\d|R\$(\s*)\d'), (m) {
      final space = m.group(1) ?? m.group(2) ?? '';
      return 'R\$$space\u0001A';
    });
    t = t.replaceAllMapped(RegExp(r'\b\d{1,2}/\d{1,2}(/\d{2,4})?\b'),
        (m) => m.group(1) == null ? '\u0001D' : '\u0001Y');
    t = t.replaceAll(RegExp(r'\b\d{1,2}[:h]\d{2}\b'), '\u0001T');
    t = t.replaceAllMapped(RegExp(r'\d{2,}'), (m) => '0' * m.group(0)!.length);
    return t
        .replaceAll('\u0001A', '99,99')
        .replaceAll('\u0001Y', '01/01/2026')
        .replaceAll('\u0001D', '01/01')
        .replaceAll('\u0001T', '12:00');
  }

  return (title: scrub(n.title), text: scrub(n.text));
}

/// Identificador estável de um texto (iguais em celulares diferentes viram
/// o mesmo item na revisão). FNV-1a de 32 bits com duas sementes.
String sampleId(String package, String title, String text) {
  final units = '$package\n$title\n$text'.codeUnits;
  int fnv(int seed) {
    var h = seed;
    for (final u in units) {
      h ^= u & 0xff;
      h = (h * 16777619) & 0xffffffff;
      h ^= u >> 8;
      h = (h * 16777619) & 0xffffffff;
    }
    return h;
  }

  String hex(int v) => v.toRadixString(16).padLeft(8, '0');
  return '${hex(fnv(0x811c9dc5))}${hex(fnv(0x050c5d1f))}';
}

// --- Fila de confirmação ----------------------------------------------------

enum InboxState {
  /// Esperando o usuário confirmar.
  pending,
  confirmed,
  discarded,

  /// Não é movimentação.
  ignored,

  /// Compra cancelada logo depois: some sozinha da confirmação.
  cancelled,
}

class InboxEntry {
  final CapturedNotification notification;
  final ParsedNotification parsed;
  final InboxState state;

  /// Para a compra cancelada: a notificação que a cancelou, e vice-versa.
  final String? linkedId;

  const InboxEntry(this.notification, this.parsed, this.state, {this.linkedId});
}

/// Interpreta todas as notificações e decide o estado de cada uma.
///
/// Um cancelamento com o mesmo valor, do mesmo banco, até 3 dias depois de
/// uma compra ainda não confirmada cancela essa compra: as duas saem da
/// confirmação. Sem compra pendente, o cancelamento fica para o usuário
/// decidir (a compra pode já ter sido salva).
List<InboxEntry> buildInbox(List<CapturedNotification> items) {
  final sorted = [...items]..sort((a, b) => a.postedAt.compareTo(b.postedAt));
  final parsed = {for (final n in sorted) n.id: parseBankNotification(n)};
  final cancelledBy = <String, String>{}; // compra -> cancelamento
  final cancels = <String, String>{}; // cancelamento -> compra

  for (final c in sorted) {
    final pc = parsed[c.id]!;
    if (pc.kind != NotificationKind.cancel || c.status != null) continue;
    for (final p in sorted.reversed) {
      final pp = parsed[p.id]!;
      if (p.status != null || cancelledBy.containsKey(p.id)) continue;
      if (p.package != c.package || !p.postedAt.isBefore(c.postedAt)) continue;
      if (c.postedAt.difference(p.postedAt).inDays > 3) continue;
      if (pp.kind != NotificationKind.creditPurchase &&
          pp.kind != NotificationKind.debitPurchase) {
        continue;
      }
      if (pp.amount == null || pc.amount == null) continue;
      if ((pp.amount! - pc.amount!).abs() > 0.004) continue;
      cancelledBy[p.id] = c.id;
      cancels[c.id] = p.id;
      break;
    }
  }

  return [
    for (final n in sorted.reversed)
      InboxEntry(
        n,
        parsed[n.id]!,
        switch (n.status) {
          'confirmed' => InboxState.confirmed,
          'discarded' => InboxState.discarded,
          _ when cancelledBy.containsKey(n.id) => InboxState.cancelled,
          _ when cancels.containsKey(n.id) => InboxState.cancelled,
          _ when parsed[n.id]!.kind == NotificationKind.ignored =>
            InboxState.ignored,
          _ => InboxState.pending,
        },
        linkedId: cancelledBy[n.id] ?? cancels[n.id],
      ),
  ];
}
