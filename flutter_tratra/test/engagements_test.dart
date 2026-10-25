// Engagements récurrents et de longue durée : formats, liens profonds, client d'API (Idempotency-Key, erreurs typées) et écrans
// (acceptation sur l'empreinte exacte, paiement confirmé par la CONTREPARTIE seulement) — sans réseau.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/continuity/activity.dart';
import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/deep_links.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/contract_pay.dart';
import 'package:flutter_tratra/engagements/contract_screen.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_home.dart';
import 'package:flutter_tratra/engagements/labels.dart';
import 'package:flutter_tratra/engagements/posting_screen.dart';

Map<String, dynamic> contract({String status = 'pending_acceptance', String role = 'worker', List<String> actions = const ['accept', 'send_back', 'decline'], List<String> acceptedBy = const ['principal']}) => {
      'id': 1,
      'title': 'Gardien de nuit',
      'status': status,
      'my_role': role,
      'mission_type': 'long_term',
      'work_relationship': 'independent',
      'category': {'id': 1, 'name': 'Plomberie'},
      'start_date': '2027-01-04',
      'end_date': null,
      'ends_on': null,
      'is_indefinite': true,
      'amount': '150000.00',
      'period': 'monthly',
      'currency': 'XOF',
      'payment_day': 5,
      'hours_per_week': '20.00',
      'worker': {'id': 2, 'name': 'Moussa A.'},
      'principal': {'id': 3, 'name': 'Awa C.'},
      'counterpart': role == 'worker' ? {'id': 3, 'name': 'Awa C.'} : {'id': 2, 'name': 'Moussa A.'},
      'organization': null,
      'version': 3,
      'terms_version': 2,
      'terms_hash': 'a828c222fb116a4e0123456789abcdef0123456789abcdef0123456789abcdef',
      'accepted_by': acceptedBy,
      'actions': actions,
      'pending_amendment': null,
      'description': 'Surveillance et accueil.',
      'conditions': 'Tenue fournie.',
      'schedule': [
        {'weekday': 0, 'start': '08:00', 'end': '12:00'},
        {'weekday': 1, 'start': '08:00', 'end': '12:00'},
      ],
      'location_city': 'Abidjan',
      'location_address': '',
      'auto_renew': false,
      'notice_period_days': 7,
      'proration_mode': 'none',
      'bookings_mode': 'none',
      'suspensions': [],
      'legal_notice': 'Prestation indépendante : aucune relation de travail salarié n’est créée par Tratra.',
      'rules': {'min_days_for_evaluation': 30, 'evaluation_interval_days': 90},
    };

class _Call {
  _Call(this.method, this.path, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, String> headers;
  final String body;
}

({EngagementsApi api, List<_Call> calls}) fakeApi(Future<http.Response> Function(http.Request r) handler) {
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'access'});
  final calls = <_Call>[];
  final base = BaseApi(client: MockClient((r) async {
    calls.add(_Call(r.method, r.url.path, r.headers, r.body));
    return handler(r);
  }));
  return (api: EngagementsApi(base), calls: calls);
}

http.Response ok(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

Widget host(EngagementsApi api, Widget home) => Provider<EngagementsApi>.value(value: api, child: MaterialApp(theme: TratraTheme.light(), home: home));

void main() {
  group('formats', () {
    test('montants, dates et planning en français, sans décalage de fuseau', () {
      expect(fcfa('150000.00'), '150 000 FCFA');
      expect(fcfa(null), '—');
      expect(fcfa('abc'), '—');
      expect(fcfa('-20000'), '-20 000 FCFA');
      expect(dateFr('2027-01-04'), '4 janvier 2027');
      expect(dateShortFr('2027-01-04'), 'lun. 4 janv.');
      expect(dateFr(''), '—');
      expect(timeFr('08:00:00'), '08 h 00');
      expect(scheduleLabel([for (var d = 0; d < 5; d++) {'weekday': d, 'start': '08:00', 'end': '12:00'}]), 'lun, mar, mer, jeu, ven · 08 h 00 – 12 h 00');
      expect(scheduleLabel([]), 'Aucun planning fixe');
      expect(durationLabel({'start_date': '2027-01-04', 'end_date': '2028-01-03'}), '12 mois');
      expect(durationLabel({'start_date': '2027-01-04', 'end_date': null, 'is_indefinite': true}), 'Durée indéterminée');
      expect(isoDay(DateTime(2027, 3, 4)), '2027-03-04');
    });

    test('statuts et cibles des tâches « à faire »', () {
      expect(contractStatus('suspended').$1, 'Suspendu');
      expect(installmentStatus('overdue').$2, TratraTone.danger);
      expect(applicationStatus('selected').$1, 'Retenue');
      expect(todoTarget({'kind': 'confirm_payment', 'contract_id': 5}), (TodoTarget.contractPay, 5));
      expect(todoTarget({'kind': 'validate_event', 'contract_id': 5}), (TodoTarget.contractPlanning, 5));
      expect(todoTarget({'kind': 'answer_replacement'}), (TodoTarget.replacements, null));
      expect(todoTarget({'kind': 'review_applications', 'posting_id': 9}), (TodoTarget.posting, 9));
      expect(todoTarget({'kind': 'accept_contract', 'contract_id': 7}), (TodoTarget.contract, 7));
    });

    test('clé d’idempotence : stable pour un même contenu, différente sinon, format accepté par le serveur', () {
      final a = intentKey('pay', 'abc123', {'amount': '1000'});
      expect(a, intentKey('pay', 'abc123', {'amount': '1000'}));
      expect(a, isNot(intentKey('pay', 'abc123', {'amount': '2000'})));
      expect(RegExp(r'^[A-Za-z0-9_\-:.]{8,80}$').hasMatch(a), isTrue);
      expect(intentKey('x' * 100, 'abc', 1).length, lessThanOrEqualTo(80));
      expect(randomHex(), isNot(randomHex()));
    });
  });

  group('liens profonds et activités', () {
    test('contrat, besoin, remplacements', () {
      expect(parseDeepLink({'deeplink': 'tratra://contract/7'}), const DeepLink(DeepLinkKind.contract, id: 7));
      expect(parseDeepLink({'deeplink': 'tratra://posting/4'}), const DeepLink(DeepLinkKind.posting, id: 4));
      expect(parseDeepLink({'deeplink': 'tratra://replacements'}), const DeepLink(DeepLinkKind.replacements));
      expect(parseDeepLink({'kind': 'contract', 'id': 12}), const DeepLink(DeepLinkKind.contract, id: 12));
      expect(parseDeepLink({'deeplink': 'tratra://contract'}), const DeepLink(DeepLinkKind.notifications)); // identifiant manquant → centre de notifications
    });

    test('un contrat s’affiche comme activité en cours', () {
      final a = Activity.fromJson({'kind': 'contract', 'id': 7, 'role': 'worker', 'status': 'active', 'status_label': 'En cours', 'title': 'Gardien', 'counterpart': 'Awa C.', 'deeplink': 'tratra://contract/7', 'resume_label': 'Voir mon contrat', 'active': true});
      expect(a.kind, 'contract');
      expect(parseDeepLink({'deeplink': a.deeplink}).kind, DeepLinkKind.contract);
    });
  });

  group('client d’API', () {
    test('écriture sensible : Idempotency-Key envoyée, jeton d’accès présent', () async {
      final f = fakeApi((r) async => ok({'id': 1}, 201));
      await f.api.post('/contracts/1/accept/', {'terms_hash': 'x'}, 'accept-abc12345');
      final c = f.calls.single;
      expect(c.method, 'POST');
      expect(c.path, endsWith('/engagements/contracts/1/accept/'));
      expect(c.headers['Idempotency-Key'], 'accept-abc12345');
      expect(c.headers['Authorization'], 'Bearer access');
      expect(jsonDecode(c.body), {'terms_hash': 'x'});
    });

    test('refus métier : message du serveur en français, jamais le JSON brut', () async {
      final f = fakeApi((r) async => ok({'code': 'terms_changed', 'detail': 'Les conditions ont changé depuis votre lecture.'}, 409));
      await expectLater(
        f.api.post('/contracts/1/accept/', {'terms_hash': 'old'}),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Les conditions ont changé depuis votre lecture.').having((e) => e.statusCode, 'statut', 409)),
      );
    });

    test('pages et listes', () async {
      final f = fakeApi((r) async => ok({'count': 3, 'limit': 2, 'offset': 0, 'next_offset': 2, 'results': [{'id': 1}, {'id': 2}]}));
      final page = await f.api.getPage('/contracts/?limit=2');
      expect((page.count, page.nextOffset, page.results.length), (3, 2, 2));
    });

    test('pièce jointe : envoi multipart avec clé d’idempotence, sans Content-Type JSON', () async {
      final f = fakeApi((r) async => ok({'id': 5}, 201));
      await f.api.postForm('/installments/1/payments/', {'amount': '1000', 'method': 'cash', 'reference': ''}, idempotencyKey: 'pay-abc12345');
      final c = f.calls.single;
      expect(c.headers['Idempotency-Key'], 'pay-abc12345');
      expect(c.headers['content-type'], startsWith('multipart/form-data'));
      expect(c.body, contains('name="amount"'));
      expect(c.body, isNot(contains('name="reference"'))); // champ vide : non envoyé
    });
  });

  group('écrans', () {
    testWidgets('accueil : tâches à faire et contrats réels, rien de fictif', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final f = fakeApi((r) async {
        if (r.url.path.endsWith('/me/overview/')) {
          return ok({
            'counts': {'pending_acceptance': 1, 'active': 2, 'suspended': 0, 'notice': 0},
            'todo_count': 1,
            'todo': [
              {'kind': 'accept_contract', 'label': 'Contrat à relire et accepter', 'contract_id': 1, 'title': 'Gardien de nuit', 'at': '2026-10-10T10:00:00Z'}
            ],
            'organizations': [],
          });
        }
        if (r.url.path.endsWith('/contracts/')) return ok({'count': 1, 'next_offset': null, 'results': [contract()]});
        return ok({'count': 0, 'results': []});
      });
      await t.pumpWidget(host(f.api, const EngagementsHomeScreen()));
      await settle(t);
      expect(find.text('À faire'), findsOneWidget);
      expect(find.text('Contrat à relire et accepter'), findsOneWidget);
      expect(find.text('Gardien de nuit'), findsWidgets);
      expect(find.text('À accepter'), findsOneWidget); // statut du contrat
      expect(find.textContaining('2 en cours'), findsOneWidget);
    });

    testWidgets('contrat à accepter : bouton inactif tant que les conditions ne sont pas lues, acceptation sur l’empreinte exacte', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var accepted = false;
      final f = fakeApi((r) async {
        if (r.method == 'POST' && r.url.path.endsWith('/accept/')) {
          accepted = true;
          return ok(contract(status: 'accepted', actions: const [], acceptedBy: const ['principal', 'worker']));
        }
        if (r.url.path.endsWith('/contracts/1/')) return ok(accepted ? contract(status: 'accepted', actions: const [], acceptedBy: const ['principal', 'worker']) : contract());
        return ok({'results': []});
      });
      await t.pumpWidget(host(f.api, const ContractScreen(id: 1)));
      await settle(t);
      expect(find.text('Ce contrat attend votre réponse'), findsOneWidget);
      final button = find.widgetWithText(TratraButton, 'Accepter le contrat');
      expect(t.widget<TratraButton>(button).onPressed, isNull); // pas avant d'avoir lu
      await t.tap(find.byType(CheckboxListTile).first);
      await t.pump();
      expect(t.widget<TratraButton>(button).onPressed, isNotNull);
      await t.tap(button);
      await settle(t);
      final post = f.calls.firstWhere((c) => c.method == 'POST');
      expect(jsonDecode(post.body), {'terms_hash': 'a828c222fb116a4e0123456789abcdef0123456789abcdef0123456789abcdef'});
      expect(post.headers['Idempotency-Key'], isNotEmpty);
      expect(find.text('Ce contrat attend votre réponse'), findsNothing);
      expect(find.text('Accepté · début à venir'), findsOneWidget);
    });

    testWidgets('besoin publié : l’auteur invite un professionnel vérifié puis peut retirer l’invitation', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final invitations = <Map<String, dynamic>>[];
      final f = fakeApi((r) async {
        final path = r.url.path;
        if (r.method == 'POST' && path.endsWith('/postings/5/invitations/')) {
          invitations.add({'id': 7, 'status': 'sent', 'message': '', 'invitee': {'name': 'Moussa A.'}});
          return ok(invitations.last, 201);
        }
        if (r.method == 'POST' && path.endsWith('/invitations/7/cancel/')) {
          invitations[0] = {...invitations[0], 'status': 'cancelled'};
          return ok(invitations[0]);
        }
        if (path.endsWith('/postings/5/invitations/')) return ok({'results': invitations});
        if (path.endsWith('/workers/')) return ok({'results': [{'id': 2, 'name': 'Moussa A.', 'commune': 'Cocody'}]});
        if (path.endsWith('/postings/5/')) {
          return ok({'id': 5, 'title': 'Nounou à domicile', 'status': 'open', 'mine': true, 'category': {'id': 1, 'name': 'Garde d’enfants'}, 'city': 'Abidjan',
            'mission_type': 'long_term', 'work_relationship': 'independent', 'amount': '120000.00', 'period': 'monthly', 'currency': 'XOF', 'schedule': [],
            'benefits': 'Repas fourni', 'duration_months': 12, 'description': '', 'conditions': '', 'publisher': {'name': 'Awa C.'}, 'organization': null});
        }
        return ok({'results': []});
      });
      await t.pumpWidget(host(f.api, const PostingScreen(id: 5)));
      await settle(t);
      expect(find.text('Inviter un professionnel'), findsOneWidget);
      expect(find.text('12 mois'), findsOneWidget);
      expect(find.text('Repas fourni'), findsOneWidget);
      final send = find.widgetWithText(TratraButton, 'Envoyer l’invitation');
      expect(t.widget<TratraButton>(send).onPressed, isNull); // personne choisi
      await t.enterText(find.byType(TextField).first, 'Mo');
      await t.pump(const Duration(milliseconds: 400));
      await settle(t);
      await t.tap(find.text('Moussa A.').first);
      await t.pump();
      await t.tap(send);
      await settle(t);
      final post = f.calls.firstWhere((c) => c.method == 'POST');
      expect(post.path, endsWith('/postings/5/invitations/'));
      expect(jsonDecode(post.body), {'invitee': 2, 'message': ''});
      expect(find.text('Envoyée'), findsOneWidget);
      await t.tap(find.widgetWithText(TratraButton, 'Retirer'));
      await settle(t);
      expect(find.text('Le professionnel ne pourra plus répondre à cette invitation.'), findsOneWidget); // confirmation demandée
      await t.tap(find.text('Retirer').last);
      await settle(t);
      expect(f.calls.where((c) => c.method == 'POST' && c.path.endsWith('/invitations/7/cancel/')), hasLength(1));
      expect(find.text('Retirée'), findsOneWidget);
    });

    testWidgets('contrat à signer : statut « à signer », signature seulement après lecture, consentement explicite envoyé', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      Map<String, dynamic> sealed(String status, Map<String, String?> signatures) => {
            ...contract(status: status, actions: status == 'accepted' ? const ['sign', 'decline'] : const [], acceptedBy: const ['principal', 'worker']),
            'signature_required': true,
            'reference': 'TRT-CTR-2027-000001',
            'signatures': signatures,
            'documents': [
              {'id': 9, 'kind': 'contract', 'stage': 'for_signature', 'version': 2, 'reference': 'TRT-CTR-2027-000001', 'download': '/handy/engagements/documents/9/pdf/',
               'issued_at': '2027-01-02T10:00:00Z', 'revoked_at': null, 'sha256': 'ab' * 32},
            ],
          };
      var signed = false;
      final f = fakeApi((r) async {
        if (r.method == 'POST' && r.url.path.endsWith('/contracts/1/sign/')) {
          signed = true;
          return ok(sealed('signed', {'principal': '2027-01-02T11:00:00Z', 'worker': '2027-01-02T12:00:00Z'}));
        }
        if (r.url.path.endsWith('/contracts/1/')) {
          return ok(signed ? sealed('signed', {'principal': '2027-01-02T11:00:00Z', 'worker': '2027-01-02T12:00:00Z'}) : sealed('accepted', {'principal': '2027-01-02T11:00:00Z', 'worker': null}));
        }
        return ok({'results': []});
      });
      await t.pumpWidget(host(f.api, const ContractScreen(id: 1)));
      await settle(t);
      expect(find.text('Accepté · à signer'), findsOneWidget);
      expect(find.text('Accepté · début à venir'), findsNothing);
      expect(find.text('Contrat à signer'), findsOneWidget);
      final button = find.widgetWithText(TratraButton, 'Signer le contrat');
      expect(t.widget<TratraButton>(button).onPressed, isNull); // pas avant d'avoir lu
      await t.tap(find.byType(CheckboxListTile).first);
      await t.pump();
      expect(t.widget<TratraButton>(button).onPressed, isNotNull);
      await t.tap(button);
      await settle(t);
      final post = f.calls.firstWhere((c) => c.method == 'POST');
      expect(jsonDecode(post.body), {'consent': true});
      expect(post.headers['Idempotency-Key'], isNotEmpty);
      expect(find.text('Signé · début à venir'), findsOneWidget);
      expect(find.text('Contrat à signer'), findsNothing);
    });

    testWidgets('paiement : confirmé par la contrepartie seulement, jamais par son auteur', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      Map<String, dynamic> installment({required bool mine}) => {
            'id': 9, 'number': 1, 'period_start': '2027-01-04', 'period_end': '2027-02-03', 'due_date': '2027-02-05', 'status': 'partial', 'currency': 'XOF', 'computed': true,
            'total': '150000.00', 'confirmed': '0.00', 'declared': '87500.00', 'balance': '150000.00', 'remaining_to_declare': '62500.00', 'platform_fee': '0.00', 'can_waive': false,
            'advance_remaining': null, 'lines': [],
            'payments': [
              {'id': 4, 'amount': '87500.00', 'method': 'mobile_money', 'reference': 'OM-1', 'paid_on': '2027-01-10', 'is_advance': true, 'status': 'declared', 'declared_by_role': 'principal', 'mine': mine, 'can_respond': !mine, 'evidence': null}
            ],
          };
      for (final mine in [false, true]) {
        final f = fakeApi((r) async => ok(installment(mine: mine)));
        await t.pumpWidget(host(f.api, Scaffold(body: SingleChildScrollView(child: InstallmentDetail(key: ValueKey(mine), api: f.api, c: contract(status: 'active', role: 'worker'), id: 9, onChanged: () {})))));
        await settle(t);
        expect(find.text('À confirmer'), findsOneWidget);
        if (mine) {
          expect(find.textContaining('ne se confirme jamais soi-même'), findsOneWidget);
          expect(find.textContaining('Je confirme avoir'), findsNothing);
        } else {
          expect(find.text('Je confirme avoir reçu ce montant'), findsOneWidget);
          expect(find.text('Contester'), findsOneWidget);
        }
      }
    });

    testWidgets('paiement confirmé : la mention « Tratra ne vérifie pas ce paiement » est affichée, jamais « vérifié »', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      const note = 'Confirmé par les deux parties. Tratra ne vérifie pas ce paiement auprès d’un prestataire de paiement : il n’a pas transité par Tratra.';
      Map<String, dynamic> installment(String status) => {
            'id': 9, 'number': 1, 'period_start': '2027-01-04', 'period_end': '2027-02-03', 'due_date': '2027-02-05', 'status': 'partial', 'currency': 'XOF', 'computed': true,
            'total': '150000.00', 'confirmed': '87500.00', 'declared': '0.00', 'balance': '62500.00', 'remaining_to_declare': '62500.00', 'platform_fee': '0.00', 'can_waive': false,
            'advance_remaining': null, 'lines': [],
            'payments': [
              {
                'id': 4, 'amount': '87500.00', 'method': 'mobile_money', 'reference': 'OM-1', 'paid_on': '2027-01-10', 'is_advance': true, 'status': status, 'declared_by_role': 'principal',
                'mine': false, 'can_respond': false, 'evidence': null,
                'trust': {'level': status == 'confirmed' ? 'confirmed' : 'declared', 'verified': false, 'note': status == 'confirmed' ? note : 'Déclaré par une partie.'}
              }
            ],
          };
      for (final status in ['declared', 'confirmed']) {
        final f = fakeApi((r) async => ok(installment(status)));
        await t.pumpWidget(host(f.api, Scaffold(body: SingleChildScrollView(child: InstallmentDetail(key: ValueKey(status), api: f.api, c: contract(status: 'active', role: 'worker'), id: 9, onChanged: () {})))));
        await settle(t);
        expect(find.textContaining('Tratra ne vérifie pas ce paiement'), status == 'confirmed' ? findsOneWidget : findsNothing);
        expect(find.textContaining('vérifié par'), findsNothing);
      }
    });
  });
}
