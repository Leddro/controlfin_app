import 'package:financas_app/models/bank_notification.dart';
import 'package:flutter_test/flutter_test.dart';

const nubank = 'com.nu.production';
const itau = 'com.itau';

var _seq = 0;

CapturedNotification n(String package, String title, String text,
        {DateTime? at, String? status}) =>
    CapturedNotification(
      id: 'n${_seq++}',
      package: package,
      title: title,
      text: text,
      postedAt: at ?? DateTime(2026, 11, 18, 12, 47),
      status: status,
    );

ParsedNotification parse(String package, String title, String text,
        {DateTime? at}) =>
    parseBankNotification(n(package, title, text, at: at));

void main() {
  group('Nubank (textos reais)', () {
    test('compra no crédito com o final do cartão', () {
      final p = parse(nubank, 'Compra no crédito aprovada',
          'Compra de R\$ 3.661,11 APROVADA em CASASBAHIACOM para o cartão com final 4821.');
      expect(p.kind, NotificationKind.creditPurchase);
      expect(p.amount, 3661.11);
      expect(p.counterpart, 'Casasbahiacom');
      expect(p.last4, '4821');
      expect(p.date, DateTime(2026, 11, 18));
    });

    test('transferência recebida (Android, com ponto final)', () {
      final p = parse(nubank, 'Transferência recebida',
          'Você recebeu uma transferência de R\$ 0,01 de Joao Pereira da Silva Junior.');
      expect(p.kind, NotificationKind.pixIn);
      expect(p.amount, 0.01);
      expect(p.counterpart, 'Joao Pereira da Silva Junior');
      expect(p.description, 'Pix de Joao Pereira da Silva Junior');
    });

    test('transferência recebida sem espaço depois do R\$', () {
      final p = parse(nubank, 'Transferência recebida',
          'Você recebeu uma transferência de R\$1000,00 de PAGFAST');
      expect(p.kind, NotificationKind.pixIn);
      expect(p.amount, 1000);
      expect(p.counterpart, 'Pagfast');
    });

    test('compra cancelada', () {
      final p =
          parse(nubank, 'Nubank', 'Compra de R\$ 3.661,11 foi cancelada.');
      expect(p.kind, NotificationKind.cancel);
      expect(p.amount, 3661.11);
    });

    test('verificação com valor zerado também é ignorada', () {
      final p = parse(nubank, 'Cartão verificado',
          'Amazon.com.br acabou de verificar se o seu cartão com final 4821 está ativo. R\$ 0,00');
      expect(p.kind, NotificationKind.ignored);
    });

    test('cartão verificado não vira lançamento', () {
      final p = parse(nubank, 'Cartão verificado',
          'CASASBAHIA acabou de verificar se o seu cartão com final 4821 está ativo.');
      expect(p.kind, NotificationKind.ignored);
    });
  });

  group('Nubank (exemplos da web)', () {
    test('compra no débito pelo título', () {
      final p = parse(nubank, 'Compra no débito aprovada',
          'Compra de R\$ 17,00 em ACADEMIA CEMI');
      expect(p.kind, NotificationKind.debitPurchase);
      expect(p.counterpart, 'Academia Cemi');
    });

    test('NuPay no débito', () {
      final p = parse(nubank, 'NuPay',
          'R\$ 53,58 no débito com NuPay APROVADO em KeetaBR.');
      expect(p.kind, NotificationKind.debitPurchase);
      expect(p.amount, 53.58);
      expect(p.counterpart, 'KeetaBR');
    });

    test('Pix recebido e enviado', () {
      final inn = parse(
          nubank, '', 'Você recebeu um Pix de R\$ 2.300,00 de FULANO DE TAL');
      expect(inn.kind, NotificationKind.pixIn);
      expect(inn.counterpart, 'Fulano de Tal');
      final out = parse(nubank, '', 'Pix enviado: R\$ 39,75 para MARIA SILVA');
      expect(out.kind, NotificationKind.pixOut);
      expect(out.amount, 39.75);
      expect(out.description, 'Pix para Maria Silva');
    });

    test('recusada e pagamento de fatura são ignorados', () {
      expect(
          parse(nubank, '',
                  'Compra de R\$ 99,00 RECUSADA em LOJA X para o cartão com final 7310')
              .kind,
          NotificationKind.ignored);
      expect(
          parse(nubank, '', 'Pagamento da fatura de R\$ 830,10 realizado').kind,
          NotificationKind.ignored);
    });
  });

  group('Itaú (texto real)', () {
    test('compra aprovada com dia e hora no texto', () {
      final p = parse(itau, 'Sua compra foi aprovada 💳',
          'Olá! Compra aprovada de R\$ 82,41 em MADRE LEONIA no dia 05/01 às 17:45 no seu cartão Itau. Boas compras.',
          at: DateTime(2027, 1, 5, 17, 46));
      expect(p.kind, NotificationKind.creditPurchase);
      expect(p.amount, 82.41);
      expect(p.counterpart, 'Madre Leonia');
      expect(p.date, DateTime(2027, 1, 5));
    });

    test('compra de dezembro avisada em janeiro fica no ano anterior', () {
      final p = parse(itau, '',
          'Compra aprovada de R\$ 10,00 em LOJA no dia 31/12 às 23:59 no seu cartão Itau.',
          at: DateTime(2027, 1, 1, 0, 1));
      expect(p.date, DateTime(2026, 12, 31));
    });

    test('a carteira do celular repete a compra e é ignorada', () {
      final p = parse(
          'com.google.android.apps.walletnfcrel', 'Madre Leonia', 'R\$ 82,41');
      expect(p.kind, NotificationKind.ignored);
    });
  });

  group('propagandas e avisos (textos reais)', () {
    test('Mercado Pago: deposite e receba', () {
      final p = parse(
          'com.mercadopago.wallet',
          'Carlos, deposite R\$50 e receba R\$50 🎁',
          'Aceite o desafio agora e participe da oferta. ✨');
      expect(p.kind, NotificationKind.ignored);
    });

    test('limite e saldo', () {
      expect(parse(nubank, '', 'Seu limite subiu para R\$ 5.000').kind,
          NotificationKind.ignored);
      expect(
          parse(nubank, '', 'Ganhe R\$ 20 na sua primeira compra no app').kind,
          NotificationKind.ignored);
    });

    test('formato desconhecido com valor vira "não entendi"', () {
      final p = parse('br.com.xp.carteira', 'Aviso',
          'Aconteceu algo com R\$ 20,00 na sua conta');
      expect(p.kind, NotificationKind.unknown);
      expect(p.amount, 20);
    });
  });

  group('certeza: só a dúvida vai para a revisão', () {
    Confidence c(String package, String title, String text) =>
        parse(package, title, text).confidence;

    test('formatos conferidos com texto real passam direto', () {
      expect(
          c(nubank, 'Compra no crédito aprovada',
              'Compra de R\$ 3.661,11 APROVADA em CASASBAHIACOM para o cartão com final 4821.'),
          Confidence.high);
      expect(
          c(nubank, 'Transferência recebida',
              'Você recebeu uma transferência de R\$ 0,01 de Joao Pereira.'),
          Confidence.high);
      expect(c(nubank, 'Nubank', 'Compra de R\$ 3.661,11 foi cancelada.'),
          Confidence.high);
      expect(
          c(itau, 'Sua compra foi aprovada',
              'Olá! Compra aprovada de R\$ 82,41 em MADRE LEONIA no dia 05/01 às 17:45 no seu cartão Itau. Boas compras.'),
          Confidence.high);
    });

    test('o que quase certamente não é movimentação nem vem', () {
      expect(c(nubank, 'Cartão verificado', 'CASASBAHIA acabou de verificar'),
          Confidence.low);
      expect(
          c('com.mercadopago.wallet',
              'Carlos, deposite R\$50 e receba R\$50 🎁', 'Aceite o desafio.'),
          Confidence.low);
      expect(c(nubank, '', 'Pagamento da fatura de R\$ 830,10 realizado'),
          Confidence.low);
      expect(
          c('com.google.android.apps.walletnfcrel', 'Madre Leonia',
              'R\$ 82,41'),
          Confidence.low);
    });

    test('dúvida vai para a revisão', () {
      // Formato desconhecido.
      expect(c('br.com.xp.carteira', 'Aviso', 'Aconteceu algo com R\$ 20,00'),
          Confidence.medium);
      // Mesmo formato do Nubank, mas em banco ainda não conferido.
      expect(
          c('com.santander.app', '',
              'Compra de R\$ 10,00 APROVADA em LOJA para o cartão com final 1234'),
          Confidence.medium);
      // Formatos do Nubank vindos só de exemplos da web.
      expect(
          c(nubank, 'Compra no débito aprovada',
              'Compra de R\$ 17,00 em ACADEMIA CEMI'),
          Confidence.medium);
      expect(c(nubank, '', 'Pix enviado: R\$ 39,75 para MARIA SILVA'),
          Confidence.medium);
      // Propaganda que fala de Pix: confere.
      expect(
          c(nubank, '', 'Ganhe R\$ 10 no seu primeiro Pix'), Confidence.medium);
      expect(parse(nubank, '', 'Pix enviado: R\$ 39,75 para MARIA').needsReview,
          isTrue);
    });
  });

  group('dados trocados para a revisão', () {
    test('compra: valor, final do cartão e data viram exemplos', () {
      final a = anonymizeNotification(n(nubank, 'Compra no crédito aprovada',
          'Compra de R\$ 3.661,11 APROVADA em CASASBAHIACOM para o cartão com final 4821.'));
      expect(a.text,
          'Compra de R\$ 99,99 APROVADA em CASASBAHIACOM para o cartão com final 0000.');
      // A leitura continua a mesma com os dados trocados.
      final p = parseBankNotification(n(nubank, a.title, a.text));
      expect(p.kind, NotificationKind.creditPurchase);
      expect(p.counterpart, 'Casasbahiacom');
    });

    test('Pix: o nome da pessoa some', () {
      final a = anonymizeNotification(n(nubank, 'Transferência recebida',
          'Você recebeu uma transferência de R\$1000,00 de Joao Pereira da Silva Junior.'));
      expect(a.text, 'Você recebeu uma transferência de R\$99,99 de FULANO.');
      expect(parseBankNotification(n(nubank, a.title, a.text)).kind,
          NotificationKind.pixIn);
    });

    test('Itaú: data, hora e nome do usuário', () {
      final a = anonymizeNotification(
          n(itau, 'Olá, Carlos!',
              'Compra aprovada de R\$ 82,41 em MADRE LEONIA no dia 05/01 às 17:45 no seu cartão Itau.'),
          userName: 'Carlos Almeida');
      expect(a.title, 'Olá, USUÁRIO!');
      expect(a.text,
          'Compra aprovada de R\$ 99,99 em MADRE LEONIA no dia 01/01 às 12:00 no seu cartão Itau.');
    });

    test('textos iguais têm o mesmo identificador', () {
      final id1 = sampleId(nubank, 'T', 'Compra de R\$ 99,99');
      final id2 = sampleId(nubank, 'T', 'Compra de R\$ 99,99');
      expect(id1, id2);
      expect(id1, hasLength(16));
      expect(sampleId(itau, 'T', 'Compra de R\$ 99,99'), isNot(id1));
    });
  });

  group('fila de confirmação', () {
    test('compra cancelada logo depois sai da confirmação', () {
      final buy = n(nubank, 'Compra no crédito aprovada',
          'Compra de R\$ 3.661,11 APROVADA em CASASBAHIACOM para o cartão com final 4821.',
          at: DateTime(2026, 11, 18, 12, 30));
      final cancel = n(
          nubank, 'Nubank', 'Compra de R\$ 3.661,11 foi cancelada.',
          at: DateTime(2026, 11, 18, 12, 38));
      final again = n(nubank, 'Compra no crédito aprovada',
          'Compra de R\$ 3.661,11 APROVADA em CASASBAHIACOM para o cartão com final 4821.',
          at: DateTime(2026, 11, 18, 12, 47));
      final inbox = buildInbox([buy, cancel, again]);
      final state = {for (final e in inbox) e.notification.id: e.state};
      expect(state[buy.id], InboxState.cancelled);
      expect(state[cancel.id], InboxState.cancelled);
      expect(state[again.id], InboxState.pending);
      // Mais recentes primeiro.
      expect(inbox.first.notification.id, again.id);
    });

    test('cancelamento sem compra pendente fica para o usuário decidir', () {
      final cancel = n(nubank, 'Nubank', 'Compra de R\$ 50,00 foi cancelada.');
      expect(buildInbox([cancel]).single.state, InboxState.pending);
    });

    test('decisões salvas e ignoradas', () {
      final ok =
          n(nubank, '', 'Pix enviado: R\$ 10,00 para ANA', status: 'confirmed');
      final promo = n(nubank, '', 'Ganhe R\$ 20 na sua primeira compra');
      final state = {
        for (final e in buildInbox([ok, promo])) e.notification.id: e.state
      };
      expect(state[ok.id], InboxState.confirmed);
      expect(state[promo.id], InboxState.ignored);
    });
  });
}
