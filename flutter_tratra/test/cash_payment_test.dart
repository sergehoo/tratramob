// Paiement en espèces d'une réservation (client et artisan) : déclaration, confirmation par l'AUTRE partie seulement, historique,
// justificatif facultatif, et jamais une mention « vérifié par un prestataire » — sans réseau.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/detail_shared/cash_payment_card.dart';
import 'package:flutter_tratra/services/cash_service.dart';

const note = 'Les espèces remises en main propre ne passent pas par Tratra : une confirmation prouve l’accord des deux parties, pas un encaissement vérifié par un prestataire de paiement.';

Map<String, dynamic> decl(int id, {String status = 'declared', String by = 'artisan', bool mine = false, bool canRespond = false, String reason = '', bool receipt = false}) => {
      'id': id, 'amount': '10000.00', 'paid_on': '2026-10-10', 'note': '', 'status': status, 'declared_by_role': by, 'mine': mine, 'can_respond': canRespond,
      'rejection_reason': reason, 'declared_at': '2026-10-10T10:00:00Z', 'responded_at': null, 'receipt': receipt ? {'url': '/handy/payments/cash/$id/receipt/'} : null,
    };

Map<String, dynamic> cash({String state = 'none', String role = 'artisan', bool canDeclare = false, List<Map<String, dynamic>> history = const [], String? remaining = '10000.00', String confirmed = '0.00'}) => {
      'method': 'cash', 'currency': 'XOF', 'state': state, 'verification': 'manual', 'due': '10000.00', 'confirmed': confirmed, 'declared': '0.00', 'remaining': remaining,
      'my_role': role, 'can_declare': canDeclare, 'note': note, 'history': history,
    };

Map<String, dynamic> block(Map<String, dynamic>? c) => {'booking_id': 9, 'booking_status': 'in_progress', 'payment': null, 'cash': c};

class _Call {
  _Call(this.method, this.path, this.headers, this.body);
  final String method, path, body;
  final Map<String, String> headers;
}

({CashService api, List<_Call> calls}) fake(http.Response Function(http.Request r) handler) {
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'access'});
  final calls = <_Call>[];
  final api = CashService(BaseApi(), client: MockClient((r) async {
    calls.add(_Call(r.method, r.url.path, r.headers, r.body));
    return handler(r);
  }));
  return (api: api, calls: calls);
}

http.Response ok(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

Widget host(CashService api, {String status = 'in_progress', Object? key}) => Provider<CashService>.value(
      value: api,
      child: MaterialApp(theme: TratraTheme.light(), home: Scaffold(body: SingleChildScrollView(child: CashPaymentCard(key: ValueKey(key ?? 'card'), bookingId: 9, bookingStatus: status)))),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({'auth_token': 'access'}));

  testWidgets('aucun paiement déclaré : l’artisan peut déclarer, la mention d’honnêteté est affichée, jamais « vérifié »', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final f = fake((r) => ok(block(cash(canDeclare: true))));
    await t.pumpWidget(host(f.api));
    await settle(t);
    expect(find.text('Paiement en espèces'), findsOneWidget);
    expect(find.text('Aucun paiement déclaré'), findsOneWidget);
    expect(find.text('Aucun paiement déclaré pour l’instant.'), findsOneWidget);
    expect(find.text('Déclarer un paiement en espèces'), findsOneWidget);
    expect(find.textContaining('pas un encaissement vérifié par un prestataire'), findsOneWidget);
    expect(find.textContaining('Vérifié par'), findsNothing);
    expect(f.calls.single.path, endsWith('/bookings/9/payment/'));
  });

  testWidgets('prestation pas commencée : rien à déclarer, message clair', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final f = fake((r) => ok(block(cash())));
    await t.pumpWidget(host(f.api, status: 'confirmed'));
    await settle(t);
    expect(find.text('Le paiement se déclare une fois la prestation commencée.'), findsOneWidget);
    expect(find.text('Déclarer un paiement en espèces'), findsNothing);
  });

  testWidgets('déclaration par l’autre partie : le client confirme, l’auteur ne le peut jamais', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    // Vue client : l'artisan a déclaré.
    final toConfirm = cash(state: 'awaiting_confirmation', role: 'client', history: [decl(4, canRespond: true)], remaining: '0.00');
    final paid = cash(state: 'paid', role: 'client', history: [decl(4, status: 'confirmed')], remaining: '0.00', confirmed: '10000.00');
    var confirmed = false;
    final f = fake((r) {
      if (r.method == 'POST') {
        confirmed = true;
        return ok({'declaration': decl(4, status: 'confirmed'), 'cash': paid});
      }
      return ok(block(confirmed ? paid : toConfirm));
    });
    await t.pumpWidget(host(f.api));
    await settle(t);
    expect(find.text('À confirmer'), findsWidgets);
    expect(find.text('Une déclaration attend votre confirmation.'), findsOneWidget);
    expect(find.text('Je confirme avoir payé ce montant'), findsOneWidget);
    expect(find.text('Contester'), findsOneWidget);
    await t.tap(find.text('Je confirme avoir payé ce montant'));
    await settle(t);
    final post = f.calls.firstWhere((c) => c.method == 'POST');
    expect(post.path, endsWith('/payments/cash/4/respond/'));
    expect(jsonDecode(post.body), {'confirm': true, 'reason': ''});
    expect(find.text('Réglé en espèces'), findsOneWidget);
    expect(find.text('Je confirme avoir payé ce montant'), findsNothing);
    expect(find.textContaining('Vérifié par'), findsNothing);

    // Vue de l'auteur : en attente, aucun bouton de confirmation.
    final mine = cash(state: 'awaiting_confirmation', role: 'artisan', history: [decl(5, mine: true)], remaining: '0.00');
    final g = fake((r) => ok(block(mine)));
    await t.pumpWidget(host(g.api, key: 'auteur'));
    await settle(t);
    expect(find.textContaining('un paiement ne se confirme jamais soi-même'), findsOneWidget);
    expect(find.textContaining('Je confirme avoir'), findsNothing);
    expect(find.text('Contester'), findsNothing);
  });

  testWidgets('historique : la contestation et son motif restent visibles, le justificatif est consultable', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final f = fake((r) => ok(block(cash(state: 'contested', role: 'artisan', canDeclare: true, history: [decl(6, status: 'rejected', mine: true, reason: 'Je n’ai remis que 6000', receipt: true)]))));
    await t.pumpWidget(host(f.api));
    await settle(t);
    expect(find.text('Contesté'), findsWidgets);
    expect(find.text('Motif de contestation : Je n’ai remis que 6000'), findsOneWidget);
    expect(find.text('Voir la pièce jointe'), findsOneWidget);
    expect(find.text('Déclarer un paiement en espèces'), findsOneWidget);       // une nouvelle déclaration reste possible
  });

  testWidgets('contestation : la feuille demande un motif', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final f = fake((r) => ok(block(cash(state: 'awaiting_confirmation', role: 'client', history: [decl(4, canRespond: true)]))));
    await t.pumpWidget(host(f.api));
    await settle(t);
    await t.tap(find.text('Contester'));
    await settle(t);
    expect(find.text('Contester cette déclaration'), findsOneWidget);
    expect(find.textContaining('Motif de la contestation'), findsWidgets);
  });

  testWidgets('déclaration : le montant proposé est le solde, l’envoi porte une clé d’idempotence et le serveur fait foi', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    var declared = false;
    final f = fake((r) {
      if (r.method == 'POST') {
        declared = true;
        return ok({'declaration': decl(7, mine: true), 'cash': cash(state: 'awaiting_confirmation', history: [decl(7, mine: true)], remaining: '0.00')}, 201);
      }
      return ok(block(declared ? cash(state: 'awaiting_confirmation', history: [decl(7, mine: true)], remaining: '0.00') : cash(canDeclare: true)));
    });
    await t.pumpWidget(host(f.api));
    await settle(t);
    await t.tap(find.text('Déclarer un paiement en espèces'));
    await settle(t);
    expect(find.text('Déclarer des espèces reçues'), findsOneWidget);
    expect(find.textContaining('ne passent pas par Tratra'), findsWidgets);
    expect(find.text('10000'), findsOneWidget);                                   // montant proposé = solde restant
    await t.tap(find.text('Déclarer'));
    await settle(t);
    final post = f.calls.firstWhere((c) => c.method == 'POST');
    expect(post.path, endsWith('/bookings/9/payment/cash/'));
    expect(post.headers['Idempotency-Key'], matches(RegExp(r'^cash-[A-Za-z0-9_\-:.]{8,75}$')));
    expect(post.headers['Content-Type'], startsWith('multipart/form-data'));
    expect(post.body, contains('10000'));
    expect(find.text('À confirmer'), findsWidgets);
    expect(find.textContaining('un paiement ne se confirme jamais soi-même'), findsOneWidget);
  });

  testWidgets('erreur serveur au chargement : message honnête, aucune donnée inventée', (t) async {
    final f = fake((r) => ok({'detail': 'Introuvable.'}, 404));
    await t.pumpWidget(host(f.api));
    await settle(t);
    expect(find.text('Paiement en espèces'), findsNothing);
    expect(find.byType(TratraAlert), findsOneWidget);
  });

  testWidgets('règlement par un prestataire : aucune carte « espèces »', (t) async {
    final f = fake((r) => ok(block(null)));
    await t.pumpWidget(host(f.api));
    await settle(t);
    expect(find.text('Paiement en espèces'), findsNothing);
    expect(find.byType(TratraAlert), findsNothing);
  });

  test('le service refuse les justificatifs d’une autre origine (jeton jamais envoyé ailleurs)', () async {
    final f = fake((r) => http.Response('x', 200));
    await expectLater(f.api.download('https://pirate.example/vol'), throwsA(isA<ApiException>()));
    expect(f.calls, isEmpty);
  });
}
