// « Vérifier mon identité » (parcours guidé, progression serveur), espace professionnel (éligibilité en trois niveaux, offres et leur état
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
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/screens/dashboard/catalog_pickers.dart';
import 'package:flutter_tratra/screens/dashboard/provider_screens.dart';
import 'package:flutter_tratra/services/catalog_repository.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: const {'content-type': 'application/json; charset=utf-8'});

const _keys = ['personal', 'document', 'capture', 'quality', 'face', 'review', 'activation'];
const _labels = ['Informations personnelles', 'Choix de la pièce', 'Photo de la pièce', 'Contrôle qualité et lecture', 'Vérification faciale',
  'Revue par l’équipe Tratra', 'Activation du profil professionnel'];

/// Même forme que `eligibility_summary` (handy/eligibility.py) : trois niveaux distincts — publication (sans vérification d'identité),
/// commandes (pièce approuvée), badge « Vérifié » (vérification faciale validée). `face` : done | pending | retry | todo | unavailable.
Map<String, dynamic> eligibility({
  bool published = false,
  bool orders = false,
  String kyc = 'draft',
  int done = 3,
  int offers = 0,
  int active = 0,
  String face = 'unavailable',
  bool faceRequired = false,
}) {
  const keys = ['skills', 'zone', 'experience', 'bio', 'photo'];
  const labels = ['Métier', 'Zone d’intervention', 'Expérience', 'Présentation', 'Photo de profil'];
  Map<String, dynamic> action(String code, String label, [String? step]) => {'code': code, 'label': label, if (step != null) 'step': step};
  final missing = [for (var i = done; i < 2; i++) labels[i].toLowerCase()];
  final level = orders && face == 'done' ? 'VERIFIE' : kyc == 'approved' ? 'IDENTITE_VERIFIEE' : 'NON_VERIFIE';
  final levelLabel = {'VERIFIE': 'Vérifié', 'IDENTITE_VERIFIEE': 'Identité vérifiée', 'NON_VERIFIE': 'Non vérifié'}[level];
  final publicationBlockers = <Map<String, dynamic>>[
    if (!published && missing.isNotEmpty)
      {'code': 'profile_incomplete', 'label': 'À renseigner pour publier : ${missing.join(', ')}', 'hint': 'Aide', 'action': action('edit_profile', 'Compléter mon profil')},
    if (!published && missing.isEmpty)
      {'code': 'phone_unverified', 'label': 'Numéro de téléphone non confirmé', 'hint': 'Confirmez votre numéro avec le code reçu par SMS pour publier votre service.',
        'action': action('verify_phone', 'Confirmer mon téléphone')},
  ];
  final faceMissing = faceRequired && face != 'done';
  final ordersBlockers = <Map<String, dynamic>>[
    if (!orders && !published) {'code': 'not_published', 'label': 'Service non publié', 'hint': 'Publiez d’abord votre service.', 'action': publicationBlockers.first['action']},
    if (!orders && kyc == 'draft')
      {'code': 'kyc_draft', 'label': 'Identité non vérifiée', 'hint': 'Faites vérifier votre pièce d’identité pour recevoir des commandes : quelques minutes suffisent.',
        'action': action('verify_identity', 'Activer mes commandes')},
    if (!orders && kyc == 'pending')
      {'code': 'kyc_pending', 'label': 'Pièce d’identité en cours de revue', 'hint': 'L’équipe Tratra examine votre pièce : aucune action n’est nécessaire.', 'action': null},
    if (!orders && kyc == 'rejected')
      {'code': 'kyc_rejected', 'label': 'Nouvelle pièce d’identité demandée', 'hint': 'Verso illisible.', 'action': action('verify_identity', 'Reprendre ma vérification')},
    if (!orders && kyc == 'approved' && !faceMissing)
      {'code': 'approval_pending', 'label': 'Activation des commandes par l’équipe Tratra en attente',
        'hint': 'Votre pièce est approuvée ; l’équipe termine un contrôle avant d’activer vos commandes. Aucune action n’est nécessaire.', 'action': null},
    if (!orders && faceMissing)
      {'code': 'face_required', 'label': face == 'pending' ? 'Vérification faciale en cours de revue' : 'Vérification faciale demandée', 'hint': 'Votre métier la demande avant toute commande.',
        'action': face == 'pending' ? null : action('verify_identity', 'Faire la vérification faciale', 'face')},
  ];
  final badge = action('verify_identity', 'Obtenir le badge Vérifié', 'face');
  return {
    'profile': {
      'complete': done == 5,
      'ready': missing.isEmpty,
      'done': done,
      'total': 5,
      'items': [for (final (i, k) in keys.indexed) {'key': k, 'label': labels[i], 'hint': 'Aide', 'done': i < done, 'required': i < 2}],
    },
    'kyc': {'status': kyc, 'label': {'draft': 'Identité non vérifiée', 'pending': 'Vérification en cours', 'approved': 'Identité vérifiée', 'rejected': 'Nouvelle pièce demandée'}[kyc],
      'reason': kyc == 'rejected' ? 'Verso illisible.' : null, 'started': kyc != 'draft', 'approved': kyc == 'approved'},
    'approval': {'approved': orders, 'label': orders ? 'Commandes activées' : 'Commandes non activées'},
    'suspended': false,
    'publication': {'authorized': published, 'label': published ? 'Profil publié' : 'Profil non publié', 'blockers': publicationBlockers},
    'orders': {'authorized': orders, 'label': orders ? 'Commandes activées' : 'Commandes non activées', 'blockers': ordersBlockers, 'face_required': faceRequired},
    'verification': {'level': level, 'label': levelLabel, 'badge': level == 'VERIFIE',
      'face': {'enabled': face != 'unavailable', 'required': faceRequired, 'satisfied': face == 'done', 'status': face == 'done' ? 'approved' : 'not_started', 'state': face}},
    'stages': [
      {'key': 'publication', 'label': 'Service publié', 'state': published && active > 0 ? 'done' : 'todo',
        'status': published ? (active > 0 ? 'Publié' : 'Profil visible, aucun service actif') : 'Non publié',
        'benefit': 'Votre service est visible par les clients, avec la mention « Non vérifié ». Aucune commande tant que votre identité n’est pas vérifiée.'},
      {'key': 'identity', 'label': 'Pièce d’identité',
        'state': {'draft': 'todo', 'pending': 'pending', 'rejected': 'retry', 'approved': orders ? 'done' : 'pending'}[kyc],
        'status': {'draft': 'À faire', 'pending': 'En cours de revue', 'rejected': 'Nouvelle pièce demandée', 'approved': orders ? 'Identité vérifiée' : 'Activation par l’équipe en attente'}[kyc],
        'benefit': 'Active vos commandes : réservations, missions Tratra Flash et contrats.'},
      {'key': 'face', 'label': 'Vérification faciale', 'required': faceRequired,
        'state': kyc == 'draft' && (face == 'todo' || face == 'retry') ? 'locked' : face,
        'status': kyc == 'draft' && (face == 'todo' || face == 'retry')
            ? 'Après la pièce d’identité'
            : {'done': 'Validée', 'pending': 'En cours de revue', 'retry': 'À reprendre', 'todo': 'À faire', 'unavailable': 'Pas encore proposée'}[face],
        'benefit': 'Attribue le badge « Vérifié », affiché sur votre profil et vos offres.'},
    ],
    'offers': {
      'total': offers,
      'active': active,
      'published': published ? active : 0,
      'inactive': offers - active,
      'accepting_orders': orders,
      'label': offers == 0
          ? 'Aucune offre créée'
          : active == 0
              ? 'Aucune offre active'
              : !published
                  ? '$active offre en attente de publication'
                  : '$active offre publiée${orders ? '' : ' — commandes non activées'}',
      'action': offers == 0 ? action('add_service', 'Publier un service') : active == 0 ? action('manage_services', 'Gérer mes offres') : null,
    },
    'next_action': !published
        ? publicationBlockers.first['action']
        : offers == 0
            ? action('add_service', 'Publier un service')
            : !orders
                ? ordersBlockers.map((b) => b['action']).firstWhere((a) => a != null, orElse: () => null)
                : (face == 'todo' || face == 'retry')
                    ? badge
                    : null,
  };
}

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
  bool faceRequired = false,
  bool? faceDone,
  bool faceSatisfied = false,
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
          {'key': k, 'label': _labels[i], 'state': states[k] ?? (k == 'face' && !face ? 'skipped' : k == 'face' && !faceRequired && !(faceDone ?? false) ? 'optional' : k == current ? 'current' : _keys.indexOf(k) < _keys.indexOf(current) ? 'done' : 'todo')},
      ],
      'personal': {'first_name': first, 'last_name': last, 'birth_date': birth, 'complete': birth != null},
      'document': {
        'kind': kind,
        'kinds': [{'value': 'cni', 'label': 'Carte nationale d\'identité', 'sides': 2}, {'value': 'passport', 'label': 'Passeport', 'sides': 1}],
        'captures': captures,
        'ready_to_send': ready,
      },
      'face': {'enabled': face, 'required': faceRequired, 'status': faceSatisfied ? 'approved' : 'not_started', 'satisfied': faceSatisfied, 'choice': '',
        'human_review_requested': false, 'done': faceDone ?? !face,
        'note': face ? 'Comparez votre visage à votre pièce, après votre consentement explicite.' : 'Pas demandée pour le moment : l’équipe Tratra vérifie votre pièce elle-même.',
        'benefit': 'Attribue le badge « Vérifié », affiché sur votre profil et vos offres.'},
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
/// L'attente dure tant que l'envoi est en cours (quelle que soit la charge de la machine), au plus 15 s.
Future<void> _io(WidgetTester t) async {
  for (var i = 0; i < 300; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 50));
    if (i >= 2 && find.textContaining('Envoi et contrôle').evaluate().isEmpty) break;
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

Finder _within(String key, String text) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text));

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
      expect(find.text('Étape 1 sur 6'), findsOneWidget);
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
      expect(find.text('Étape 2 sur 6'), findsOneWidget);
      // choix de la pièce
      await t.tap(find.byKey(const ValueKey('kyc-kind-cni')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('kyc-kind-save')));
      await t.pumpAndSettle();
      expect(find.text('Étape 3 sur 6'), findsOneWidget);
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
      expect(find.text('Étape 4 sur 6'), findsOneWidget);
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
      expect(find.text('Étape 1 sur 6'), findsOneWidget);
    });

    testWidgets('reprise après fermeture : l’écran rouvre à l’étape enregistrée par le serveur', (t) async {
      _size(t);
      final server = KycServer(kycState(birth: '1990-04-12', kind: 'cni', current: 'capture', captures: [side('front', present: true, quality: 'ok'), side('back')]));
      final base = _base(server.client);
      await t.pumpWidget(_host(base, IdentityFlowScreen(api: KycFlowApi(base))));
      await t.pumpAndSettle();
      expect(find.text('Étape 3 sur 6'), findsOneWidget);
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

    testWidgets('nouvelle tentative : le motif précédent est rappelé en avertissement ; étapes comptées sans l’étape non requise', (t) async {
      _size(t);
      final server = KycServer(kycState(current: 'capture', birth: '1990-04-12', kind: 'cni', previous: 'Verso flou.', captures: [side('front', present: true, quality: 'ok'), side('back')]));
      final base = _base(server.client);
      await t.pumpWidget(_host(base, IdentityFlowScreen(api: KycFlowApi(base))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kyc-previous')), findsOneWidget);
      expect(find.text('Motif du refus précédent'), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-rejection')), findsNothing);
      expect(find.text('2 sur 6 terminées'), findsOneWidget);        // la vérification faciale « non requise » n'est pas comptée
    });

    testWidgets('vérification faciale : absente si désactivée, facultative une fois la pièce envoyée (jamais imposée), exigée pour un métier sensible', (t) async {
      _size(t);
      Future<KycServer> open(String key, Map<String, dynamic> state, {String? initialStep}) async {
        final server = KycServer(state);
        final base = _base(server.client);
        await t.pumpWidget(_host(base, IdentityFlowScreen(key: ValueKey(key), api: KycFlowApi(base), initialStep: initialStep)));
        await t.pumpAndSettle();
        return server;
      }

      // Désactivée : ni étape, ni proposition.
      await open('face-off', kycState(status: 'in_review', current: 'review', birth: '1990-04-12', kind: 'cni', review: 'pending', sentAt: '2026-10-20T10:00:00Z', states: {'review': 'waiting'}));
      expect(find.byKey(const ValueKey('kyc-face-offer')), findsNothing);
      await t.tap(find.byKey(const ValueKey('kyc-steps')));
      await t.pumpAndSettle();
      expect(find.text('Les 6 étapes'), findsOneWidget);
      expect(find.text('Vérification faciale'), findsNothing);
      expect(find.byKey(const ValueKey('kyc-face')), findsNothing);

      // Facultative : la pièce est envoyée, l'écran reste sur la revue ; le badge est PROPOSÉ, « Plus tard » n'envoie rien.
      var server = await open('face-optional', kycState(face: true, status: 'in_review', current: 'review', birth: '1990-04-12', kind: 'cni', review: 'pending',
          sentAt: '2026-10-20T10:00:00Z', states: {'review': 'waiting'}, activation: eligibility(published: true, kyc: 'pending', offers: 1, active: 1, face: 'todo')));
      expect(find.byKey(const ValueKey('kyc-review')), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-face')), findsNothing);
      expect(find.text('Étape 5 sur 6'), findsOneWidget);                // l'étape facultative n'allonge pas le parcours annoncé
      expect(find.textContaining('mention « Non vérifié »'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('kyc-face-open')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kyc-face')), findsOneWidget);
      expect(_within('kyc-face', 'Facultatif'), findsOneWidget);
      expect(find.textContaining('consentement explicite'), findsWidgets);
      expect(find.byKey(const ValueKey('kyc-face-human')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('kyc-face-later')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kyc-review')), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-face')), findsNothing);
      expect(server.requests.where((r) => r.method != 'GET'), isEmpty);

      // « Obtenir le badge Vérifié » depuis l'accueil : l'étape s'ouvre d'emblée ; la refuser laisse les commandes activées, sans badge.
      await open('face-direct', kycState(face: true, status: 'verified', current: 'activation', birth: '1990-04-12', kind: 'cni', review: 'approved',
          activation: eligibility(published: true, orders: true, kyc: 'approved', done: 5, offers: 1, active: 1, face: 'todo')), initialStep: 'face');
      expect(find.byKey(const ValueKey('kyc-face')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('kyc-face-later')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kyc-active')), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-badge')), findsNothing);
      expect(find.byKey(const ValueKey('kyc-face-offer')), findsOneWidget);

      // Métier sensible : exigée avant les commandes — ni « Facultatif », ni « Plus tard » ; la revue humaine reste proposée.
      await open('face-required', kycState(face: true, faceRequired: true, status: 'in_review', current: 'face', birth: '1990-04-12', kind: 'cni', review: 'pending',
          sentAt: '2026-10-20T10:00:00Z', activation: eligibility(published: true, kyc: 'pending', offers: 1, active: 1, face: 'todo', faceRequired: true)));
      expect(find.byKey(const ValueKey('kyc-face')), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-face-human')), findsOneWidget);
      expect(_within('kyc-face', 'Facultatif'), findsNothing);
      expect(find.byKey(const ValueKey('kyc-face-later')), findsNothing);
      expect(find.byKey(const ValueKey('kyc-face-offer')), findsNothing);
    });

    testWidgets('activation : pièce approuvée ≠ commandes activées ≠ badge « Vérifié » — jamais un faux « activé » ni un faux badge', (t) async {
      _size(t);
      Future<void> open(String key, Map<String, dynamic> activation, {bool face = false, bool? faceDone, bool faceSatisfied = false}) async {
        final base = _base(KycServer(kycState(status: 'verified', current: 'activation', birth: '1990-04-12', kind: 'cni', review: 'approved',
            face: face, faceDone: faceDone, faceSatisfied: faceSatisfied, activation: activation)).client);
        await t.pumpWidget(_host(base, IdentityFlowScreen(key: ValueKey(key), api: KycFlowApi(base))));
        await t.pumpAndSettle();
      }

      // Pièce approuvée, activation retenue par l'équipe : ni « Commandes activées », ni badge.
      await open('held', eligibility(published: true, kyc: 'approved', done: 5, offers: 1, active: 1));
      expect(find.byKey(const ValueKey('kyc-verified')), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-active')), findsNothing);
      expect(find.byKey(const ValueKey('kyc-badge')), findsNothing);
      expect(find.byKey(const ValueKey('blocker-approval_pending')), findsOneWidget);
      expect(find.text('Activation des commandes par l’équipe Tratra en attente'), findsWidgets);
      expect(_within('elig-level', 'Identité vérifiée'), findsOneWidget);
      expect(_within('elig-kyc', 'Non activées'), findsOneWidget);

      // Commandes activées, vérification faciale possible : le badge est proposé, pas attribué.
      await open('active', eligibility(published: true, orders: true, kyc: 'approved', done: 5, offers: 1, active: 1, face: 'todo'), face: true);
      expect(find.byKey(const ValueKey('kyc-active')), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-badge')), findsNothing);
      expect(_within('elig-kyc', 'Activées'), findsOneWidget);
      expect(_within('elig-level', 'Identité vérifiée'), findsOneWidget);
      expect(_within('elig-badge', 'À faire'), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-face-offer')), findsOneWidget);

      // Vérification faciale transmise, en revue : toujours pas de badge.
      await open('face-review', eligibility(published: true, orders: true, kyc: 'approved', done: 5, offers: 1, active: 1, face: 'pending'), face: true, faceDone: true);
      expect(find.byKey(const ValueKey('kyc-active')), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-badge')), findsNothing);
      expect(find.byKey(const ValueKey('kyc-face-pending')), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-face-offer')), findsNothing);
      expect(_within('elig-badge', 'En cours de revue'), findsOneWidget);

      // Vérification faciale validée : badge « Vérifié ».
      await open('badge', eligibility(published: true, orders: true, kyc: 'approved', done: 5, offers: 1, active: 1, face: 'done'), face: true, faceDone: true, faceSatisfied: true);
      expect(find.byKey(const ValueKey('kyc-badge')), findsOneWidget);
      expect(find.byKey(const ValueKey('kyc-active')), findsNothing);
      expect(find.byKey(const ValueKey('kyc-face-offer')), findsNothing);
      expect(find.byKey(const ValueKey('kyc-face-pending')), findsNothing);
      expect(_within('elig-level', 'Vérifié'), findsOneWidget);
      expect(_within('elig-badge', 'Attribué'), findsOneWidget);
    });
  });

  group('petit écran et texte agrandi : aucun débordement', () {
    for (final (name, st) in [
      ('informations', kycState()),
      ('pièce', kycState(birth: '1990-04-12', current: 'document')),
      ('photos', kycState(birth: '1990-04-12', kind: 'cni', current: 'capture', captures: [side('front', present: true, quality: 'warn', problems: [{'code': 'blurry', 'label': 'Photo floue : tenez le téléphone immobile et attendez la mise au point.', 'blocking': false}]), side('back')])),
      ('contrôle', kycState(birth: '1990-04-12', kind: 'cni', current: 'quality', ready: true, captures: [side('front', present: true, quality: 'ok'), side('back', present: true, quality: 'ok')])),
      ('revue', kycState(status: 'in_review', current: 'review', birth: '1990-04-12', kind: 'cni', review: 'pending', sentAt: '2026-10-20T10:00:00Z')),
      ('activation', kycState(status: 'verified', current: 'activation', review: 'approved', activation: eligibility(published: true, kyc: 'approved', done: 3))),
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

    testWidgets('nouvelle offre, suggestions ouvertes et clavier (320×568, texte ×1,3)', (t) async {
      _size(t, size: const Size(320, 568), text: 1.3);
      final base = _base(MockClient((r) async => r.url.path.endsWith('/catalog/')
          ? _json({'version': 'v1', 'results': [
              for (var i = 1; i <= 12; i++) {'id': i, 'name': 'Métier numéro $i au nom assez long pour passer à la ligne', 'slug': 'm$i', 'parent': null, 'trade': i, 'kind': 'trade', 'is_active': true},
            ]})
          : _json({})));
      await t.pumpWidget(_host(base, const NewServiceScreen(), dash: DashData(_dashPayload())));
      await t.pumpAndSettle();
      await t.tap(_field('Métier'));
      await t.enterText(_field('Métier'), 'metier');
      t.view.viewInsets = const FakeViewPadding(bottom: 260);           // clavier ouvert
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      expect(find.byType(ListTile), findsWidgets);
      expect(t.takeException(), isNull);
    });

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
    testWidgets('trois niveaux distincts : publication, commandes, badge « Vérifié » — puis profil x/5 et offres, plus de « 7/7 » ambigu', (t) async {
      _size(t);
      Future<void> show(Map<String, dynamic> e) => t.pumpWidget(MaterialApp(theme: TratraTheme.light(), home: Scaffold(body: SingleChildScrollView(
          child: EligibilityPanel(key: UniqueKey(), eligibility: DashEligibility(e))))));

      // Non publié : seuls les blocages de la publication sont listés (la pièce en revue n'en fait pas partie).
      await show(eligibility(kyc: 'pending', done: 1, offers: 1, active: 1));
      expect(find.text('1/5'), findsOneWidget);
      expect(find.text('7/7'), findsNothing);
      expect(_within('elig-level', 'Non vérifié'), findsOneWidget);
      expect(_within('elig-publication', 'Non publié'), findsOneWidget);
      expect(_within('elig-kyc', 'Non activées'), findsOneWidget);
      expect(find.text('Vérification en cours'), findsOneWidget);
      expect(find.text('0 publiée / 1'), findsOneWidget);
      expect(find.text('Ce qui bloque la publication'), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-profile_incomplete')), findsOneWidget);
      expect(find.text('Compléter mon profil'), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-kyc_pending')), findsNothing);

      // Publié sans vérification d'identité : visible « Non vérifié », commandes fermées, une action : « Activer mes commandes ».
      await show(eligibility(published: true, offers: 1, active: 1));
      expect(_within('elig-publication', 'Publié'), findsOneWidget);
      expect(find.textContaining('avec la mention « Non vérifié »'), findsOneWidget);
      expect(_within('elig-level', 'Non vérifié'), findsOneWidget);
      expect(_within('elig-kyc', 'Non activées'), findsOneWidget);
      expect(find.text('1 publiée / 1'), findsOneWidget);
      expect(find.text('Ce qui manque pour recevoir des commandes'), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-kyc_draft')), findsOneWidget);
      expect(find.text('Activer mes commandes'), findsOneWidget);
      expect(find.text('Vérifié'), findsNothing);

      // Commandes activées (pièce approuvée) : « Identité vérifiée », badge encore à obtenir.
      await show(eligibility(published: true, orders: true, kyc: 'approved', done: 5, offers: 1, active: 1, face: 'todo'));
      expect(_within('elig-level', 'Identité vérifiée'), findsOneWidget);
      expect(_within('elig-kyc', 'Activées'), findsOneWidget);
      expect(_within('elig-badge', 'À faire'), findsOneWidget);
      expect(find.text('Ce qui manque pour recevoir des commandes'), findsNothing);
      expect(find.text('Vérifié'), findsNothing);

      // Vérification faciale validée : seul cet état affiche « Vérifié ».
      await show(eligibility(published: true, orders: true, kyc: 'approved', done: 5, offers: 1, active: 1, face: 'done'));
      expect(_within('elig-level', 'Vérifié'), findsOneWidget);
      expect(_within('elig-badge', 'Attribué'), findsOneWidget);

      // Serveur plus ancien (sans les niveaux) : pas de ligne « Badge », jamais « Vérifié ».
      await show(eligibility(published: true, orders: true, kyc: 'approved', done: 5, offers: 1, active: 1, face: 'done')
        ..remove('verification')
        ..remove('orders')
        ..remove('stages'));
      expect(find.byKey(const ValueKey('elig-badge')), findsNothing);
      expect(_within('elig-level', 'Identité vérifiée'), findsOneWidget);
      expect(find.text('Vérifié'), findsNothing);
    });

    testWidgets('« Mes offres » : modes affichés et modifiables dans les limites du métier', (t) async {
      _size(t);
      Map<String, dynamic>? patched;
      final base = _base(MockClient((r) async {
        if (r.url.path.endsWith('/me/services/')) {
          return _json({'publishable': true, 'eligibility': eligibility(published: true, offers: 1, active: 1), 'results': [
            {'id': 4, 'title': 'Nounou à domicile', 'category': 'Nounou', 'category_id': 9, 'trade': null, 'price': '120000', 'price_type': 'fixed', 'is_active': true,
              'bookings_count': 0, 'modes': ['one_off'], 'publication': {'state': 'published', 'label': 'Publiée · Non vérifié', 'orders': false}},
          ]});
        }
        if (r.url.path.endsWith('/engagements/rules/')) {
          expect(r.url.queryParameters['category'], '9');
          return _json({'allow_recurring': false, 'allow_long_term': true});
        }
        if (r.method == 'PATCH' && r.url.path.endsWith('/services/4/')) {
          patched = jsonDecode(r.body) as Map<String, dynamic>;
          return _json({'id': 4});
        }
        return _json({});
      }));
      await t.pumpWidget(_host(base, const ProviderHubScreen(), dash: DashData(_dashPayload())));
      await t.pumpAndSettle();
      expect(find.text('Modes : Ponctuel'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('service-modes-4')));
      await t.pumpAndSettle();
      expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('mode-recurring'))).onChanged, isNull);   // non ouvert pour ce métier
      await t.tap(find.byKey(const ValueKey('mode-contract')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('modes-save')));
      await t.pumpAndSettle();
      expect(patched, {'modes': ['one_off', 'contract']});
      expect(find.text('Modes enregistrés.'), findsOneWidget);
    });

    testWidgets('« Mes offres » : état de publication par offre, blocages réels, « publié » distinct de « commandes activées »', (t) async {
      _size(t);
      Map<String, dynamic> offer(Map<String, dynamic> publication) => {'id': 1, 'title': 'Fuite d’eau', 'category': 'Réparation de fuite', 'trade': 'Plomberie', 'price': '5000',
        'price_type': 'fixed', 'is_active': true, 'bookings_count': 0, 'publication': publication};
      const old = {'id': 2, 'title': 'Ancienne offre', 'category': 'Plomberie', 'trade': null, 'price': null, 'price_type': 'quote', 'is_active': false, 'bookings_count': 3,
        'publication': {'state': 'inactive', 'label': 'Désactivée', 'orders': false, 'hint': 'Invisible des clients.'}};
      Future<void> open(String key, Map<String, dynamic> elig, Map<String, dynamic> publication) async {
        final base = _base(MockClient((r) async => r.url.path.endsWith('/me/services/')
            ? _json({'publishable': elig['publication']['authorized'], 'eligibility': elig, 'results': [offer(publication), old]})
            : _json({})));
        await t.pumpWidget(_host(base, ProviderHubScreen(key: ValueKey(key)), dash: DashData(_dashPayload())));
        await t.pumpAndSettle();
      }

      // Profil non publiable : l'offre active n'est pas visible, le blocage réel est nommé.
      await open('blocked', eligibility(done: 1, offers: 2, active: 1),
          {'state': 'waiting', 'label': 'Non publiée', 'orders': false, 'hint': 'À renseigner pour publier : zone d’intervention'});
      expect(find.byKey(const ValueKey('hub-blocked')), findsOneWidget);
      expect(find.byKey(const ValueKey('hub-no-orders')), findsNothing);
      expect(find.textContaining('À renseigner pour publier'), findsWidgets);
      expect(find.text('Non publiée'), findsOneWidget);
      expect(find.text('Désactivée'), findsOneWidget);
      expect(find.textContaining('Plomberie › Réparation de fuite'), findsOneWidget);

      // Publié sans vérification d'identité : visible « Non vérifié », jamais présenté comme autorisé à recevoir des commandes.
      await open('no-orders', eligibility(published: true, offers: 2, active: 1),
          {'state': 'published', 'label': 'Publiée · Non vérifié', 'orders': false, 'hint': 'Visible des clients avec la mention « Non vérifié ».'});
      expect(find.byKey(const ValueKey('hub-no-orders')), findsOneWidget);
      expect(find.byKey(const ValueKey('hub-authorized')), findsNothing);
      expect(find.byKey(const ValueKey('hub-blocked')), findsNothing);
      expect(find.textContaining('mention « Non vérifié »'), findsWidgets);
      expect(find.text('Activer mes commandes'), findsOneWidget);
      expect(find.text('Publiée · Non vérifié'), findsOneWidget);

      // Commandes activées.
      await open('orders', eligibility(published: true, orders: true, kyc: 'approved', done: 5, offers: 2, active: 1),
          {'state': 'published', 'label': 'Publiée', 'orders': true, 'hint': 'Visible des clients. Vous pouvez recevoir des commandes.'});
      expect(find.byKey(const ValueKey('hub-authorized')), findsOneWidget);
      expect(find.byKey(const ValueKey('hub-no-orders')), findsNothing);
      expect(find.text('Publiée'), findsOneWidget);
    });

    BaseApi offerApi(void Function(Map<String, dynamic>) onPost) => _base(MockClient((r) async {
          if (r.url.path.endsWith('/catalog/')) {
            return _json({'version': 'v1', 'results': [
              {'id': 7, 'name': 'Plomberie', 'slug': 'plomberie', 'parent': null, 'trade': 7, 'kind': 'trade', 'is_active': true},
              {'id': 8, 'name': 'Réparation de fuite', 'slug': 'fuite', 'parent': 7, 'trade': 7, 'kind': 'prestation', 'is_active': true},
              {'id': 11, 'name': 'Débouchage', 'slug': 'debouchage', 'parent': 7, 'trade': 7, 'kind': 'prestation', 'is_active': true},
              {'id': 9, 'name': 'Nounou', 'slug': 'nounou', 'parent': null, 'trade': 9, 'kind': 'trade', 'is_active': true},
              {'id': 10, 'name': 'Électricité', 'slug': 'electricite', 'parent': null, 'trade': 10, 'kind': 'trade', 'is_active': true},
            ]});
          }
          if (r.url.path.endsWith('/services/') && r.method == 'POST') {
            onPost(jsonDecode(r.body) as Map<String, dynamic>);
            return _json({'id': 3}, 201);
          }
          return _json({});
        }));

    Future<void> fillAndSubmit(WidgetTester t) async {
      await t.enterText(_field('Description'), 'Recherche et réparation de fuites, matériel fourni.');
      await t.enterText(_field('Tarif (FCFA)'), '15000');
      await t.ensureVisible(find.byKey(const ValueKey('new-submit')));
      await t.tap(find.byKey(const ValueKey('new-submit')));
      await t.pumpAndSettle();
    }

    testWidgets('nouvelle offre : « Métier » en autocomplétion — une prestation se trouve directement (« fuite »), son métier est déduit', (t) async {
      _size(t);
      Map<String, dynamic>? posted;
      await t.pumpWidget(_host(offerApi((b) => posted = b), const Scaffold(body: _Opener()), dash: DashData(_dashPayload())));
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-waiting')), findsOneWidget);       // publication pas encore autorisée : annoncé avant la création
      // saisie libre sans choix dans la liste : refusée (aucun métier inventé)
      await t.enterText(_field('Métier'), 'xyz');
      await t.pumpAndSettle();
      // aucune suggestion (les cases « Modes proposés » du formulaire ne sont pas des suggestions)
      expect(find.byType(ListTile).evaluate().where((e) => e.findAncestorWidgetOfExactType<CheckboxListTile>() == null), isEmpty);
      await t.ensureVisible(find.byKey(const ValueKey('new-submit')));
      await t.tap(find.byKey(const ValueKey('new-submit')));
      await t.pumpAndSettle();
      expect(find.text('Choisissez votre métier dans la liste proposée.'), findsOneWidget);
      expect(posted, isNull);
      // « fuite » propose la prestation avec son rattachement
      await t.enterText(_field('Métier'), 'fuite');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('option-8')), findsOneWidget);
      expect(find.text('Prestation · Plomberie'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('option-8')));
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Plomberie › Réparation de fuite'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Réparation de fuite'), findsOneWidget);   // titre proposé, modifiable
      expect(find.byKey(const ValueKey('new-prestation-7')), findsNothing);           // prestation déjà choisie
      expect(find.text('2'), findsOneWidget);                                          // étapes renumérotées : 1 métier, 2 description, 3 tarif, 4 modes
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsNothing);
      // métier sans règle d'engagement : seul le ponctuel est ouvert
      expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('mode-contract'))).onChanged, isNull);
      await fillAndSubmit(t);
      expect(posted!['category'], 8);
      expect(posted!['modes'], ['one_off']);
      expect(posted!['title'], 'Réparation de fuite');
      expect(posted!['price'], '15000');
      expect(find.text('Offre créée : elle sera publiée dès que votre publication sera autorisée.'), findsOneWidget);
    });

    testWidgets('autocomplétion sans accents ni majuscules ; un métier à prestations demande ensuite la prestation', (t) async {
      _size(t);
      Map<String, dynamic>? posted;
      await t.pumpWidget(_host(offerApi((b) => posted = b), const Scaffold(body: _Opener()), dash: DashData(_dashPayload())));
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      await t.enterText(_field('Métier'), 'ELECTRI');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('option-10')), findsOneWidget);                // « Électricité »
      await t.enterText(_field('Métier'), 'plomb');
      await t.pumpAndSettle();
      expect(find.text('Métier · 2 prestations'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('option-7')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-prestation-7')), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('new-submit')));
      await t.tap(find.byKey(const ValueKey('new-submit')));
      await t.pumpAndSettle();
      expect(find.text('Choisissez la prestation proposée.'), findsOneWidget);
      await t.enterText(_field('Prestation'), 'debou');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('option-11')));
      await t.pumpAndSettle();
      await fillAndSubmit(t);
      expect(posted!['category'], 11);
      expect(posted!['title'], 'Débouchage');
    });

    test('recherche du catalogue : accents, majuscules, débuts de mot d’abord', () {
      final c = Catalog([
        for (final m in [
          {'id': 1, 'name': 'Électricité', 'parent': null, 'trade': 1},
          {'id': 2, 'name': 'Dépannage électrique', 'parent': 1, 'trade': 1},
          {'id': 3, 'name': 'Nounou', 'parent': null, 'trade': 3},
        ])
          Category.fromJson(m),
      ]);
      expect(catalogFold('  Électricité-Générale '), 'electricite generale');
      expect(c.search('ELEC').map((x) => x.name), ['Électricité', 'Dépannage électrique']);
      expect(c.search('').map((x) => x.name), ['Électricité', 'Nounou']);              // saisie vide : tous les métiers
      expect(c.search('elec', tradeId: '1').map((x) => x.name), ['Dépannage électrique']);
      expect(c.pathOf(c.byId('2')!), 'Électricité › Dépannage électrique');
    });
  });

  group('spécialités du profil professionnel', () {
    Catalog cat() => Catalog([
          for (final m in [
            {'id': 7, 'name': 'Plomberie', 'parent': null, 'trade': 7},
            {'id': 8, 'name': 'Réparation de fuite', 'parent': 7, 'trade': 7},
            {'id': 11, 'name': 'Débouchage', 'parent': 7, 'trade': 7},
            {'id': 9, 'name': 'Nounou', 'parent': null, 'trade': 9},
            for (var i = 20; i < 32; i++) {'id': i, 'name': 'Métier $i', 'parent': null, 'trade': i},
          ])
            Category.fromJson(m),
        ]);

    Widget picker(Set<int> selected, {Size? size}) => MaterialApp(
          theme: TratraTheme.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SkillsPicker(catalog: cat(), selected: selected, onChanged: (n) => set(() => selected..clear()..addAll(n))),
              ),
            ),
          ),
        );

    testWidgets('choisir un métier le fait remonter en haut et disparaître de la liste ; la croix le remet', (t) async {
      _size(t);
      final selected = <int>{};
      await t.pumpWidget(picker(selected));
      expect(find.byKey(const ValueKey('skills-none')), findsOneWidget);
      expect(find.byKey(const ValueKey('family-9')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('family-9')));                      // « Nounou » : métier sans prestation, ajout direct
      await t.pumpAndSettle();
      expect(selected, {9});
      expect(find.byKey(const ValueKey('skill-chosen-9')), findsOneWidget);
      expect(find.byKey(const ValueKey('family-9')), findsNothing);              // la liste se resserre
      expect(find.text('1 choisie'), findsOneWidget);
      await t.tap(find.descendant(of: find.byKey(const ValueKey('skill-chosen-9')), matching: find.byIcon(Icons.close_rounded)));
      await t.pumpAndSettle();
      expect(selected, isEmpty);
      expect(find.byKey(const ValueKey('family-9')), findsOneWidget);
    });

    testWidgets('famille dépliable : prestations choisies une à une, le métier disparaît quand tout est choisi', (t) async {
      _size(t);
      final selected = <int>{};
      await t.pumpWidget(picker(selected));
      await t.tap(find.byKey(const ValueKey('family-7')));
      await t.pumpAndSettle();
      expect(find.text('2 prestations à choisir'), findsOneWidget);
      expect(find.byKey(const ValueKey('family-all-7')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('family-item-8')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('family-item-8')), findsNothing);
      expect(find.text('Plomberie › Réparation de fuite'), findsOneWidget);    // remontée en haut, avec son métier
      await t.tap(find.byKey(const ValueKey('family-item-11')));
      await t.pumpAndSettle();
      expect(find.text('Ajouter le métier entier'), findsOneWidget);              // prestations toutes choisies
      await t.tap(find.byKey(const ValueKey('family-7')));
      await t.pumpAndSettle();
      expect(selected, {7, 8, 11});
      expect(find.byKey(const ValueKey('family-7')), findsNothing);
    });

    testWidgets('recherche : quelques lettres suffisent, les spécialités déjà choisies ne sont plus proposées, le champ se vide', (t) async {
      _size(t);
      final selected = <int>{8};
      await t.pumpWidget(picker(selected));
      await t.enterText(_field('Ajouter une spécialité'), 'fuit');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('option-8')), findsNothing);              // déjà choisie
      await t.enterText(_field('Ajouter une spécialité'), 'NOUN');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('option-9')));
      await t.pumpAndSettle();
      expect(selected, {8, 9});
      expect(find.widgetWithText(TextField, 'Nounou'), findsNothing);            // champ vidé, prêt pour la suivante
    });

    testWidgets('liste longue : 8 métiers d’abord, « Voir les autres métiers » ; petit écran sans débordement', (t) async {
      _size(t, size: const Size(320, 568), text: 1.3);
      await t.pumpWidget(picker(<int>{7, 8}));
      expect(find.text('Voir les 6 autres métiers'), findsOneWidget);           // 14 familles restantes, 8 affichées
      await t.ensureVisible(find.byKey(const ValueKey('skills-more')));
      await t.tap(find.byKey(const ValueKey('skills-more')));
      await t.pumpAndSettle();
      expect(find.text('Réduire la liste'), findsOneWidget);
      expect(t.takeException(), isNull);
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
      expect(e.hasLevels, isTrue);                                        // trois niveaux distincts fournis par le serveur
      expect((e.ordersAuthorized, e.verificationLevel, e.verificationLabel, e.verified), (false, 'NON_VERIFIE', 'Non vérifié', false));
      expect(e.ordersBlockers.map((b) => b.code), containsAll(['not_published', 'kyc_rejected']));
      expect(e.stages.map((s) => s.key), ['publication', 'identity', 'face']);
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
      expect(find.text('Étape 3 sur 6'), findsOneWidget);
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
