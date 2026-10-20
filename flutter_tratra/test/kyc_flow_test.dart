// « Vérifier mon identité » (parcours guidé, progression serveur), espace professionnel (éligibilité en quatre notions, offres et leur état
// de publication, création métier → prestation → description → tarif) et menu Profil regroupé. Inclut des rendus sur petit écran avec
// texte agrandi : aucun débordement (« BOTTOM OVERFLOWED ») n'est toléré.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/kyc/identity_flow_screen.dart';
import 'package:flutter_tratra/kyc/kyc_flow_api.dart';
import 'package:flutter_tratra/screens/auth/profile_extras.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/eligibility_panel.dart';
import 'package:flutter_tratra/screens/dashboard/provider_screens.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: const {'content-type': 'application/json; charset=utf-8'});

const _keys = ['personal', 'document', 'capture', 'quality', 'face', 'review', 'activation'];
const _labels = ['Informations personnelles', 'Choix de la pièce', 'Photo de la pièce', 'Contrôle qualité et lecture', 'Vérification faciale',
  'Revue par l’équipe Tratra', 'Activation du profil professionnel'];

Map<String, dynamic> eligibility({bool authorized = false, String kyc = 'draft', int done = 3, int offers = 0, int active = 0}) => {
      'profile': {
        'complete': done == 5,
        'done': done,
        'total': 5,
        'items': [
          for (final (i, k) in ['bio', 'skills', 'experience', 'zone', 'photo'].indexed)
            {'key': k, 'label': ['Présentation', 'Spécialités', 'Expérience', 'Zone d’intervention', 'Photo de profil'][i], 'hint': 'Aide', 'done': i < done},
        ],
      },
      'kyc': {'status': kyc, 'label': {'draft': 'Identité non vérifiée', 'pending': 'Vérification en cours', 'approved': 'Identité vérifiée', 'rejected': 'Nouvelle pièce demandée'}[kyc], 'reason': null, 'approved': kyc == 'approved'},
      'approval': {'approved': authorized, 'label': authorized ? 'Validé par l’équipe Tratra' : 'Validation de l’équipe en attente'},
      'publication': {
        'authorized': authorized,
        'label': authorized ? 'Publication autorisée' : 'Publication non autorisée',
        'blockers': authorized
            ? []
            : [
                if (done < 5) {'code': 'profile_incomplete', 'label': 'Profil incomplet : expérience, zone d’intervention', 'hint': 'Indiquez vos années d’expérience.', 'action': {'code': 'edit_profile', 'label': 'Compléter mon profil'}},
                if (kyc != 'approved') {'code': 'kyc_$kyc', 'label': 'Identité non vérifiée', 'hint': 'Faites vérifier votre pièce.', 'action': {'code': 'verify_identity', 'label': 'Vérifier mon identité'}},
                if (kyc == 'approved') {'code': 'approval_pending', 'label': 'Validation finale de l’équipe Tratra en attente', 'hint': 'Aucune action n’est nécessaire.', 'action': null},
              ],
      },
      'offers': {'total': offers, 'active': active, 'published': authorized ? active : 0, 'inactive': offers - active,
        'label': offers == 0 ? 'Aucune offre créée' : '$active offre en attente de l’autorisation de publication',
        'action': offers == 0 ? {'code': 'add_service', 'label': 'Ajouter une offre'} : null},
      'next_action': {'code': 'edit_profile', 'label': 'Compléter mon profil'},
    };

Map<String, dynamic> kycState({
  String status = 'draft',
  String current = 'personal',
  Map<String, String> states = const {},
  String first = 'Awa',
  String last = 'Koné',
  String? birth,
  String? kind,
  List<Map<String, dynamic>> captures = const [],
  bool ready = false,
  bool face = false,
  String review = 'none',
  String? reason,
  String? previous,
  String? sentAt,
  Map<String, dynamic>? activation,
  bool editable = true,
}) =>
    {
      'status': status,
      'status_label': {'draft': 'À compléter', 'in_review': 'En cours de revue', 'changes_requested': 'Nouvelle pièce demandée', 'verified': 'Identité vérifiée'}[status],
      'current_step': current,
      'steps': [
        for (final (i, k) in _keys.indexed)
          {'key': k, 'label': _labels[i], 'state': states[k] ?? (k == 'face' && !face ? 'skipped' : k == current ? 'current' : _keys.indexOf(k) < _keys.indexOf(current) ? 'done' : 'todo')},
      ],
      'personal': {'first_name': first, 'last_name': last, 'birth_date': birth, 'complete': birth != null},
      'document': {
        'kind': kind,
        'kinds': [{'value': 'cni', 'label': 'Carte nationale d\'identité', 'sides': 2}, {'value': 'passport', 'label': 'Passeport', 'sides': 1}],
        'captures': captures,
        'ready_to_send': ready,
      },
      'face': {'enabled': face, 'required': false, 'status': 'not_started', 'satisfied': false, 'choice': '', 'human_review_requested': false, 'done': !face,
        'note': face ? 'Comparez votre visage à votre pièce, après votre consentement explicite.' : 'Non requise : l’équipe Tratra vérifie votre pièce elle-même.'},
      'review': {'state': review, 'reason': reason ?? '', 'sent_at': sentAt, 'attempts': sentAt == null ? 0 : 1, 'previous_reason': previous},
      'activation': activation ?? eligibility(),
      'editable': editable,
      'updated_at': '2026-10-20T10:00:00Z',
    };

Map<String, dynamic> side(String side, {bool present = false, String? quality, List<Map<String, dynamic>> problems = const []}) => {
      'side': side,
      'label': side == 'front' ? 'Recto' : 'Verso',
      'present': present,
      'quality': quality,
      'problems': problems,
      'reading': present ? {'status': 'unavailable', 'notes': []} : null,
    };

/// Serveur simulé : mêmes transitions que handy/kyc_flow.py, progression conservée entre deux ouvertures de l'écran.
class KycServer {
  KycServer([Map<String, dynamic>? initial]) : state = initial ?? kycState();
  Map<String, dynamic> state;
  final requests = <http.Request>[];
  final qualities = <String>[];
  bool personalError = false;

  late final client = MockClient((r) async {
    requests.add(r);
    final p = r.url.path;
    if (p.endsWith('/me/kyc/') && r.method == 'GET') return _json(state);
    if (p.endsWith('/me/kyc/') && r.method == 'PATCH') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (body['personal'] != null) {
        if (personalError) {
          return _json({'code': 'invalid_personal', 'detail': 'Vérifiez les informations saisies.', 'fields': {'birth_date': 'Vous devez avoir au moins 18 ans pour proposer vos services.'}}, 400);
        }
        final pers = body['personal'] as Map;
        state = kycState(first: '${pers['first_name']}', last: '${pers['last_name']}', birth: '${pers['birth_date']}', current: 'document');
      }
      if (body['document_kind'] != null) {
        final kind = '${body['document_kind']}';
        state = kycState(birth: '1990-04-12', kind: kind, current: 'capture', captures: [side('front'), if (kind == 'cni') side('back')]);
      }
      return _json(state);
    }
    if (p.endsWith('/me/kyc/capture/')) {
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      final s = RegExp(r'name="side"\r\n\r\n(\w+)').firstMatch(body)!.group(1)!;
      final q = qualities.isEmpty ? 'ok' : qualities.removeAt(0);
      final caps = [
        for (final c in (state['document'] as Map)['captures'] as List)
          (c as Map)['side'] == s
              ? side(s, present: true, quality: q, problems: q == 'warn' ? [{'code': 'blurry', 'label': 'Photo floue : tenez le téléphone immobile et attendez la mise au point.', 'blocking': false}] : [])
              : Map<String, dynamic>.from(c),
      ];
      final all = caps.every((c) => c['present'] == true);
      state = kycState(birth: '1990-04-12', kind: '${(state['document'] as Map)['kind']}', current: all ? 'quality' : 'capture', captures: caps, ready: all);
      return _json({...state, 'check': {'quality': q}});
    }
    if (p.endsWith('/me/kyc/send/')) {
      state = kycState(status: 'in_review', current: 'review', birth: '1990-04-12', kind: 'cni', review: 'pending', sentAt: '2026-10-20T10:00:00Z',
          states: {'review': 'waiting'}, editable: false);
      return _json(state);
    }
    return _json({});
  });
}

class _NoNetController extends DashboardController {
  _NoNetController(DashData? d) : super(DashboardApi(BaseApi(client: MockClient((_) async => _json({}, 503))))) {
    data = d;
  }
}

Finder _field(String label) =>
    find.descendant(of: find.byWidgetPredicate((w) => w is TratraInput && w.label == label), matching: find.byType(TextField));

/// Une photo prise : fichier réel (PNG 1×1 valide) ; l'envoi lit le fichier, d'où `_io` après chaque prise.
Future<String> _photo() async {
  final f = File('${Directory.systemTemp.path}/kyc_${DateTime.now().microsecondsSinceEpoch}.png')
    ..writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));
  addTearDown(() {
    if (f.existsSync()) f.deleteSync();
  });
  return f.path;
}

Widget _host(BaseApi base, Widget child, {DashData? dash}) => MultiProvider(
      providers: [
        Provider<BaseApi>.value(value: base),
        Provider<DashboardApi>.value(value: DashboardApi(base)),
        ChangeNotifierProvider<DashboardController>.value(value: _NoNetController(dash)),
      ],
      child: MaterialApp(theme: TratraTheme.light(), home: child),
    );

BaseApi _base(http.Client client) {
  FlutterSecureStorage.setMockInitialValues({AppConstants.authTokenKey: 'access', AppConstants.refreshTokenKey: 'refresh'});
  return BaseApi(client: client);
}

/// Laisse les lectures de fichier réelles (envoi multipart) se terminer, puis stabilise l'affichage.
Future<void> _io(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle();
}

void _size(WidgetTester t, {Size size = const Size(900, 2400), double text = 1.0}) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Map<String, dynamic> _dashPayload({Map<String, dynamic>? elig}) => {
      'user': {'id': 9, 'first_name': 'Awa', 'display_name': 'Awa K.', 'is_verified': true},
      'capabilities': {'client': true, 'provider': true, 'publishable': false},
      'client': {'bookings': {'total': 0}},
      'provider': {
        'profile_id': 5,
        'publishable': false,
        'completion': {'percent': 100, 'done': 7, 'total': 7, 'items': []},
        'kyc': {'status': 'approved'},
        'eligibility': elig ?? eligibility(),
        'services': {'active': 0, 'total': 0},
        'missions': {'pending': 0, 'confirmed': 0, 'in_progress': 0},
        'earnings': {'available': '0'},
      },
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('parcours « Vérifier mon identité »', () {
    testWidgets('informations → pièce → photos (contrôle qualité) → envoi → revue, en suivant le serveur', (t) async {
      _size(t);
      final server = KycServer()..qualities.addAll(['warn', 'ok', 'ok']);
      final base = _base(server.client);
      final path = await t.runAsync(_photo);
      await t.pumpWidget(_host(base, IdentityFlowScreen(api: KycFlowApi(base), picker: (_) async => path)));
      await t.pumpAndSettle();
      expect(find.text('Étape 1 sur 7'), findsOneWidget);
      expect(find.text('Informations personnelles'), findsWidgets);
      // validation locale : date de naissance obligatoire
      await t.tap(find.byKey(const ValueKey('kyc-personal-save')));
      await t.pumpAndSettle();
      expect(find.text('Indiquez votre date de naissance.'), findsOneWidget);
      expect(server.requests.where((r) => r.method == 'PATCH'), isEmpty);
      // date choisie dans le calendrier
      await t.tap(find.byKey(ValueKey('kyc-birth-null')));
      await t.pumpAndSettle();
      await t.tap(find.text('15'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('kyc-personal-save')));
      await t.pumpAndSettle();
      expect(find.text('Étape 2 sur 7'), findsOneWidget);
      // choix de la pièce
      await t.tap(find.byKey(const ValueKey('kyc-kind-cni')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('kyc-kind-save')));
      await t.pumpAndSettle();
      expect(find.text('Étape 3 sur 7'), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-side-front')), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-side-back')), findsOneWidget);
      // recto : photo floue → conseil explicite, possibilité de reprendre
      await t.tap(find.byKey(const ValueKey('kyc-take-front')));
      await _io(t);
      expect(find.textContaining('Photo floue'), findsOneWidget);
      final upload = server.requests.lastWhere((r) => r.url.path.endsWith('/me/kyc/capture/'));
      expect(upload.headers['content-type'], startsWith('multipart/form-data; boundary='));
      await t.tap(find.byKey(const ValueKey('kyc-take-front')));          // « Reprendre »
      await _io(t);
      expect(find.textContaining('Photo floue'), findsNothing);
      await t.tap(find.byKey(const ValueKey('kyc-take-back')));
      await _io(t);
      // étape 4 : vérification avant envoi
      expect(find.text('Étape 4 sur 7'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('kyc-send')));
      await t.tap(find.byKey(const ValueKey('kyc-send')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kyc-review')), findsOneWidget);
      expect(find.textContaining('Transmise le 20 octobre 2026'), findsOneWidget);
      expect(server.requests.where((r) => r.url.path.endsWith('/me/kyc/send/')), hasLength(1));
    });

    testWidgets('erreurs du serveur affichées sur le bon champ (âge minimal)', (t) async {
      _size(t);
      final server = KycServer(kycState(birth: null))..personalError = true;
      final base = _base(server.client);
      await t.pumpWidget(_host(base, IdentityFlowScreen(api: KycFlowApi(base))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('kyc-birth-null')));
      await t.pumpAndSettle();
      await t.tap(find.text('15'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('kyc-personal-save')));
      await t.pumpAndSettle();
      expect(find.text('Vous devez avoir au moins 18 ans pour proposer vos services.'), findsOneWidget);
      expect(find.text('Étape 1 sur 7'), findsOneWidget);
    });

    testWidgets('reprise après fermeture : l’écran rouvre à l’étape enregistrée par le serveur', (t) async {
      _size(t);
      final server = KycServer(kycState(birth: '1990-04-12', kind: 'cni', current: 'capture', captures: [side('front', present: true, quality: 'ok'), side('back')]));
      final base = _base(server.client);
      await t.pumpWidget(_host(base, IdentityFlowScreen(api: KycFlowApi(base))));
      await t.pumpAndSettle();
      expect(find.text('Étape 3 sur 7'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('kyc-take-front')), matching: find.text('Reprendre')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('kyc-take-back')), matching: find.text('Prendre la photo')), findsOneWidget);
      expect(find.text('Photo nette et lisible'), findsOneWidget);
    });

    testWidgets('refus : motif affiché et nouvelles photos demandées', (t) async {
      _size(t);
      final server = KycServer(kycState(status: 'changes_requested', current: 'capture', birth: '1990-04-12', kind: 'cni', review: 'rejected',
          reason: 'Verso illisible : reflet sur la date.', states: {'capture': 'error'},
          captures: [side('front', present: true, quality: 'ok'), side('back', present: true, quality: 'ok')]));
      final base = _base(server.client);
      await t.pumpWidget(_host(base, IdentityFlowScreen(api: KycFlowApi(base))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kyc-rejection')), findsOneWidget);
      expect(find.text('Verso illisible : reflet sur la date.'), findsOneWidget);
      expect(find.text('Nouvelle pièce demandée'), findsWidgets);
    });

    testWidgets('vérification faciale : absente si désactivée (« Non requise »), proposée avec alternative humaine si activée', (t) async {
      _size(t);
      var server = KycServer(kycState(status: 'in_review', current: 'review', birth: '1990-04-12', kind: 'cni', review: 'pending', sentAt: '2026-10-20T10:00:00Z', states: {'review': 'waiting'}));
      var base = _base(server.client);
      await t.pumpWidget(_host(base, IdentityFlowScreen(api: KycFlowApi(base))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('kyc-steps')));
      await t.pumpAndSettle();
      expect(find.text('Non requise'), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-face')), findsNothing);

      server = KycServer(kycState(face: true, current: 'face', birth: '1990-04-12', kind: 'cni', review: 'pending', sentAt: '2026-10-20T10:00:00Z'));
      base = _base(server.client);
      await t.pumpWidget(_host(base, IdentityFlowScreen(key: const ValueKey('face-on'), api: KycFlowApi(base))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kyc-face')), findsOneWidget);
      expect(find.textContaining('consentement explicite'), findsWidgets);
      expect(find.byKey(const ValueKey('kyc-face-human')), findsOneWidget);
    });

    testWidgets('activation : blocages réels et actions correctives, jamais un faux « activé »', (t) async {
      _size(t);
      final server = KycServer(kycState(status: 'verified', current: 'activation', birth: '1990-04-12', kind: 'cni', review: 'approved',
          activation: eligibility(kyc: 'approved', done: 5)));
      final base = _base(server.client);
      await t.pumpWidget(_host(base, IdentityFlowScreen(api: KycFlowApi(base))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kyc-verified')), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-active')), findsNothing);
      expect(find.byKey(const ValueKey('blocker-approval_pending')), findsOneWidget);
      expect(find.text('Validation finale de l’équipe Tratra en attente'), findsOneWidget);
    });
  });

  group('petit écran et texte agrandi : aucun débordement', () {
    for (final (name, st) in [
      ('informations', kycState()),
      ('pièce', kycState(birth: '1990-04-12', current: 'document')),
      ('photos', kycState(birth: '1990-04-12', kind: 'cni', current: 'capture', captures: [side('front', present: true, quality: 'warn', problems: [{'code': 'blurry', 'label': 'Photo floue : tenez le téléphone immobile et attendez la mise au point.', 'blocking': false}]), side('back')])),
      ('contrôle', kycState(birth: '1990-04-12', kind: 'cni', current: 'quality', ready: true, captures: [side('front', present: true, quality: 'ok'), side('back', present: true, quality: 'ok')])),
      ('revue', kycState(status: 'in_review', current: 'review', birth: '1990-04-12', kind: 'cni', review: 'pending', sentAt: '2026-10-20T10:00:00Z')),
      ('activation', kycState(status: 'verified', current: 'activation', review: 'approved', activation: eligibility(kyc: 'approved', done: 3))),
    ]) {
      testWidgets('parcours, étape $name (320×568, texte ×1,3)', (t) async {
        _size(t, size: const Size(320, 568), text: 1.3);
        final base = _base(KycServer(st).client);
        await t.pumpWidget(_host(base, IdentityFlowScreen(api: KycFlowApi(base))));
        await t.pumpAndSettle();
        await t.drag(find.byType(ListView).first, const Offset(0, -2000));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('« Mes offres » vide : état vide sans hauteur imposée, action « Créer ma première offre »', (t) async {
      _size(t, size: const Size(320, 568), text: 1.3);
      final base = _base(MockClient((r) async => r.url.path.endsWith('/me/services/') ? _json({'publishable': false, 'eligibility': eligibility(), 'results': []}) : _json({})));
      await t.pumpWidget(_host(base, const ProviderHubScreen(), dash: DashData(_dashPayload())));
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView).first, const Offset(0, -2000));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('hub-add-first')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('espace professionnel', () {
    testWidgets('quatre notions distinctes : profil x/5, identité, autorisation de publication, offres — plus de « 7/7 » ambigu', (t) async {
      _size(t);
      await t.pumpWidget(MaterialApp(theme: TratraTheme.light(), home: Scaffold(body: SingleChildScrollView(
          child: EligibilityPanel(eligibility: DashEligibility(eligibility(kyc: 'pending', done: 3, offers: 1, active: 1)))))));
      expect(find.text('3/5'), findsOneWidget);
      expect(find.text('7/7'), findsNothing);
      expect(find.text('Vérification en cours'), findsOneWidget);
      expect(find.text('Non autorisée'), findsOneWidget);
      expect(find.text('0 publiée / 1'), findsOneWidget);
      expect(find.text('Compléter mon profil'), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-profile_incomplete')), findsOneWidget);
    });

    testWidgets('« Mes offres » : état de publication par offre et blocages réels', (t) async {
      _size(t);
      final base = _base(MockClient((r) async => r.url.path.endsWith('/me/services/')
          ? _json({
              'publishable': false,
              'eligibility': eligibility(offers: 2, active: 1),
              'results': [
                {'id': 1, 'title': 'Fuite d’eau', 'category': 'Réparation de fuite', 'trade': 'Plomberie', 'price': '5000', 'price_type': 'fixed', 'is_active': true, 'bookings_count': 0,
                  'publication': {'state': 'waiting', 'label': 'En attente d’autorisation', 'hint': 'Elle sera publiée automatiquement dès que votre publication sera autorisée.'}},
                {'id': 2, 'title': 'Ancienne offre', 'category': 'Plomberie', 'trade': null, 'price': null, 'price_type': 'quote', 'is_active': false, 'bookings_count': 3,
                  'publication': {'state': 'inactive', 'label': 'Désactivée', 'hint': 'Invisible des clients.'}},
              ],
            })
          : _json({})));
      await t.pumpWidget(_host(base, const ProviderHubScreen(), dash: DashData(_dashPayload())));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('hub-blocked')), findsOneWidget);
      expect(find.textContaining('Profil incomplet'), findsWidgets);
      expect(find.text('En attente d’autorisation'), findsOneWidget);
      expect(find.text('Désactivée'), findsOneWidget);
      expect(find.textContaining('Plomberie › Réparation de fuite'), findsOneWidget);
    });

    testWidgets('nouvelle offre : métier → prestation (catalogue commun) → description → tarif ; la prestation est enregistrée', (t) async {
      _size(t);
      Map<String, dynamic>? posted;
      final base = _base(MockClient((r) async {
        if (r.url.path.endsWith('/catalog/')) {
          return _json({'version': 'v1', 'results': [
            {'id': 7, 'name': 'Plomberie', 'slug': 'plomberie', 'parent': null, 'trade': 7, 'kind': 'trade', 'is_active': true},
            {'id': 8, 'name': 'Réparation de fuite', 'slug': 'fuite', 'parent': 7, 'trade': 7, 'kind': 'prestation', 'is_active': true},
            {'id': 9, 'name': 'Nounou', 'slug': 'nounou', 'parent': null, 'trade': 9, 'kind': 'trade', 'is_active': true},
          ]});
        }
        if (r.url.path.endsWith('/services/') && r.method == 'POST') {
          posted = jsonDecode(r.body) as Map<String, dynamic>;
          return _json({'id': 3}, 201);
        }
        return _json({});
      }));
      await t.pumpWidget(_host(base, const Scaffold(body: _Opener()), dash: DashData(_dashPayload())));
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-waiting')), findsOneWidget);       // publication pas encore autorisée : annoncé avant la création
      await t.tap(find.byKey(const ValueKey('new-submit')));
      await t.pumpAndSettle();
      expect(find.text('Choisissez votre métier.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('new-trade')));
      await t.pumpAndSettle();
      await t.tap(find.text('Plomberie').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('new-prestation-7')));
      await t.pumpAndSettle();
      await t.tap(find.text('Réparation de fuite').last);
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Réparation de fuite'), findsOneWidget);   // titre proposé, modifiable
      await t.enterText(_field('Description'), 'Recherche et réparation de fuites, matériel fourni.');
      await t.enterText(_field('Tarif (FCFA)'), '15000');
      await t.ensureVisible(find.byKey(const ValueKey('new-submit')));
      await t.tap(find.byKey(const ValueKey('new-submit')));
      await t.pumpAndSettle();
      expect(posted, isNotNull);
      expect(posted!['category'], 8);
      expect(posted!['title'], 'Réparation de fuite');
      expect(posted!['price'], '15000');
      expect(find.text('Offre créée : elle sera publiée dès que votre publication sera autorisée.'), findsOneWidget);
    });
  });

  group('contrat avec Django (réponses réelles de handy/kyc_flow.py, test/fixtures/kyc_contract.json)', () {
    final fx = jsonDecode(File('test/fixtures/kyc_contract.json').readAsStringSync()) as Map<String, dynamic>;
    Map<String, dynamic> m(String k) => (fx[k] as Map).cast<String, dynamic>();

    test('états du parcours lus sans perte', () {
      final initial = KycFlowState(m('initial'));
      expect(initial.steps.map((s) => s.key), ['personal', 'document', 'capture', 'quality', 'face', 'review', 'activation']);
      expect(initial.currentStep, 'personal');
      expect(initial.kinds.map((k) => '${k.value}:${k.sides}'), ['cni:2', 'passport:1']);
      expect(initial.activation, isNotNull);
      final ready = KycFlowState(m('ready'));
      expect(ready.readyToSend, isTrue);
      expect(ready.captures.map((c) => '${c.side}:${c.present}:${c.quality}'), ['front:true:ok', 'back:true:ok']);
      expect(ready.birthDate, DateTime(1990, 4, 12));
      final review = KycFlowState(m('in_review'));
      expect((review.status, review.currentStep, review.editable, review.sentAt != null), ('in_review', 'review', false, true));
      final rejected = KycFlowState(m('rejected'));
      expect((rejected.status, rejected.currentStep, rejected.reviewReason), ('changes_requested', 'capture', 'Verso illisible.'));
      expect(rejected.step('capture')!.state, 'error');
    });

    test('éligibilité et état des offres lus sans perte', () {
      final services = m('services');
      final e = DashEligibility((services['eligibility'] as Map).cast<String, dynamic>());
      expect(e.authorized, isFalse);
      expect(e.blockers, isNotEmpty);
      expect(e.blockers.every((b) => b.label.isNotEmpty), isTrue);
      final provider = DashProvider(m('dashboard_provider'));
      expect(provider.eligibility, isNotNull);
      expect(provider.eligibility!.profileTotal, 5);
      expect(provider.eligibility!.kycStatus, 'rejected');                // relevé après le refus du verso : même état que le parcours
      expect(provider.kycStatus, 'rejected');
    });

    testWidgets('l’écran affiche la vraie réponse « nouvelle pièce demandée »', (t) async {
      _size(t);
      final base = _base(KycServer(m('rejected')).client);
      await t.pumpWidget(_host(base, IdentityFlowScreen(api: KycFlowApi(base))));
      await t.pumpAndSettle();
      expect(find.text('Verso illisible.'), findsOneWidget);
      expect(find.text('Étape 3 sur 7'), findsOneWidget);
    });
  });

  group('menu Profil regroupé', () {
    testWidgets('sections thématiques ; chaque destination une seule fois ; une seule entrée d’identité', (t) async {
      _size(t);
      final base = _base(MockClient((_) async => _json({})));
      await t.pumpWidget(_host(base, const Scaffold(body: SingleChildScrollView(child: AccountShortcuts())),
          dash: DashData(_dashPayload(elig: eligibility(kyc: 'pending')))));
      for (final title in ['Compte', 'Activité', 'Espace professionnel', 'Confiance et vérification', 'Paramètres']) {
        expect(find.byKey(ValueKey('shortcuts-$title')), findsOneWidget, reason: title);
      }
      for (final label in ['Mes offres et missions', 'Mon profil professionnel', 'Vérifier mon identité', 'Documents et justificatifs', 'Mes réservations',
        'Notifications et confidentialité', 'Sécurité du compte']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final gone in ['Mes services', 'Mes missions', 'Vérification faciale', 'Vérification d’identité (KYC)']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      expect(find.text('Vérification en cours'), findsOneWidget);          // état réel de l'identité sous l'entrée
      expect(find.text('Profil 3/5 · non publié'), findsOneWidget);
    });

    testWidgets('compte client seul : « Proposer un service », sans section de vérification', (t) async {
      _size(t);
      final payload = _dashPayload()
        ..['capabilities'] = {'client': true, 'provider': false}
        ..['provider'] = null;
      await t.pumpWidget(_host(_base(MockClient((_) async => _json({}))), const Scaffold(body: SingleChildScrollView(child: AccountShortcuts())), dash: DashData(payload)));
      expect(find.text('Proposer un service'), findsOneWidget);
      expect(find.byKey(const ValueKey('shortcuts-Confiance et vérification')), findsNothing);
    });
  });
}

class _Opener extends StatelessWidget {
  const _Opener();
  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewServiceScreen())), child: const Text('ouvrir'));
}
