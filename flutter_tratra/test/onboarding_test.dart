// « Inscription accompagnée » : une question par écran, voix du téléphone, brouillon gardé sur le téléphone AVANT le compte (rien n'est
// envoyé au serveur) puis synchronisé APRÈS, reprise au même écran, bascule vers le formulaire classique sans perte, annonce créée par le
// serveur (apply), KYC simplifié prérempli par la lecture de la pièce, tableau de bord débutant (un seul « Continuer »), petits écrans.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/kyc/identity_flow_screen.dart';
import 'package:flutter_tratra/kyc/kyc_flow_api.dart';
import 'package:flutter_tratra/models/user.dart';
import 'package:flutter_tratra/onboarding/guided_onboarding_screen.dart';
import 'package:flutter_tratra/onboarding/onboarding_api.dart';
import 'package:flutter_tratra/onboarding/onboarding_entry.dart';
import 'package:flutter_tratra/onboarding/voice_guide.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/services/auth_service.dart';
import 'package:flutter_tratra/services/storage_service.dart';

import 'kyc_flow_test.dart' show kycState, side;

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: const {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _row(int id, String name, {int? parent, bool featured = false, String? icon}) => {
      'id': id,
      'name': name,
      'slug': name.toLowerCase(),
      'description': '',
      'icon': null,
      'icon_key': icon,
      'parent': parent,
      'trade': parent ?? id,
      'kind': parent == null ? 'trade' : 'service',
      'position': id,
      'order': id,
      'is_featured': featured,
      'is_active': true,
      'offers_count': 0,
      'offers_total': 0,
      'prestations_count': parent == null ? 2 : 0,
    };

final _catalog = {
  'count': 5,
  'version': 'v1',
  'results': [
    _row(12, 'Nounou', featured: true, icon: 'baby'),
    _row(121, 'Garde d’enfants', parent: 12),
    _row(122, 'Sortie d’école', parent: 12),
    _row(13, 'Ménage', featured: true, icon: 'broom'),
    _row(14, 'Plomberie'),
  ],
};

final _config = {
  'trade': {'id': 12, 'name': 'Nounou'},
  'prestations': [
    {'id': 121, 'name': 'Garde d’enfants'},
    {'id': 122, 'name': 'Sortie d’école'}
  ],
  'questions': [
    {
      'key': 'experience',
      'text': 'Depuis combien de temps faites-vous ce travail ?',
      'help': '',
      'kind': 'single',
      'target': 'experience',
      'required': true,
      'options': [
        {'value': 'lt1', 'label': 'Moins d’un an', 'emoji': '🌱', 'years': 1},
        {'value': '1_3', 'label': '1 à 3 ans', 'emoji': '👍', 'years': 2}
      ]
    },
    {
      'key': 'days',
      'text': 'Quels jours pouvez-vous travailler ?',
      'help': '',
      'kind': 'multi',
      'target': 'days',
      'required': true,
      'options': [
        {'value': 'monday', 'label': 'Lundi'},
        {'value': 'saturday', 'label': 'Samedi'}
      ]
    },
  ],
  'communes': ['Cocody', 'Yopougon'],
};

const _journey = [
  ('trade', 'Métier'),
  ('zone', 'Zone'),
  ('questions', 'Questions'),
  ('account', 'Compte'),
  ('phone', 'Téléphone'),
  ('offer', 'Annonce'),
  ('photo', 'Photo'),
  ('identity', 'Identité'),
  ('approval', 'Validation')
];

/// Serveur simulé : mêmes routes et mêmes champs que handy/api/onboarding.py.
class OnbServer {
  Map<String, dynamic> draft = {};
  bool applied = false;
  Map<String, String> states = {};
  Map<String, dynamic>? next;
  bool published = false;
  final requests = <http.Request>[];

  Map<String, dynamic> state() {
    final steps = [
      for (final (k, l) in _journey) {'key': k, 'label': l, 'state': states[k] ?? (k == 'offer' && applied ? 'done' : 'todo')}
    ];
    return {
      'path': 'guided',
      'trade': draft['trade'] == null ? null : {'id': draft['trade'], 'name': 'Nounou'},
      'prestations': draft['prestations'] ?? [],
      'commune': draft['commune'] ?? '',
      'quartier': draft['quartier'] ?? '',
      'answers': draft['answers'] ?? {},
      'step': draft['step'] ?? '',
      'offer': draft['trade'] == null ? null : {'title': 'Nounou à Cocody', 'description': 'Je propose mes services de nounou.'},
      'steps': steps,
      'done': steps.where((s) => s['state'] == 'done').length,
      'total': steps.length,
      'next_action': next ?? {'code': 'resume', 'label': 'Répondre aux questions', 'step': 'questions'},
      'published': published,
    };
  }

  Iterable<http.Request> get puts => requests.where((r) => r.method == 'PUT');
  Iterable<http.Request> get private => requests.where((r) => r.url.path.contains('/me/') || r.url.path.contains('/handymen/'));

  late final client = MockClient((r) async {
    requests.add(r);
    final p = r.url.path;
    if (p.endsWith('/catalog/')) return _json(_catalog);
    if (p.endsWith('/onboarding/config/')) return _json(_config);
    if (p.endsWith('/me/onboarding/') && r.method == 'GET') return _json(state());
    if (p.endsWith('/me/onboarding/') && r.method == 'PUT') {
      draft = (jsonDecode(r.body) as Map).cast<String, dynamic>();
      return _json(state());
    }
    if (p.endsWith('/me/onboarding/apply/')) {
      applied = true;
      return _json(state());
    }
    if (p.endsWith('/handymen/5/')) return _json({'id': 5});
    return _json({});
  });
}

class _Session extends Session {
  _Session([this._u]) : super(AuthService(BaseApi()), StorageService());
  User? _u;
  @override
  User? get user => _u;
  @override
  bool get isAuthenticated => _u != null;
  @override
  Future<User?> refreshProfile() async => _u;
  @override
  Future<void> setUser(User user) async {
    _u = user;
    notifyListeners();
  }
}

const _awa = User(id: '9', email: '', firstName: 'Awa', lastName: 'Koné', userType: 'client', isActive: true, isVerified: true);

class _Ctrl extends DashboardController {
  _Ctrl(BaseApi base) : super(DashboardApi(base)) {
    data = DashData({
      'user': {'id': 9, 'first_name': 'Awa', 'display_name': 'Awa K.', 'is_verified': true},
      'capabilities': {'client': true, 'provider': true, 'publishable': false},
      'client': {
        'bookings': {'total': 0}
      },
      'provider': {
        'profile_id': 5,
        'publishable': false,
        'completion': {'percent': 60, 'done': 3, 'total': 5, 'items': []},
        'kyc': {'status': 'draft'},
        'services': {'active': 0, 'total': 1},
        'missions': {'pending': 0, 'confirmed': 0, 'in_progress': 0},
        'earnings': {'available': '0'},
      },
    });
  }
}

BaseApi _base(http.Client client) {
  FlutterSecureStorage.setMockInitialValues({AppConstants.authTokenKey: 'access', AppConstants.refreshTokenKey: 'refresh'});
  return BaseApi(client: client);
}

Widget _host(BaseApi base, Session session, Widget child) => MultiProvider(
      providers: [
        Provider<BaseApi>.value(value: base),
        Provider<DashboardApi>.value(value: DashboardApi(base)),
        ChangeNotifierProvider<Session>.value(value: session),
        ChangeNotifierProvider<DashboardController>.value(value: _Ctrl(base)),
      ],
      child: MaterialApp(
        key: ObjectKey(child), // écran neuf = navigation neuve (application rouverte)
        theme: TratraTheme.light(),
        home: child,
        onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => Scaffold(body: Text('route ${s.name}'))),
      ),
    );

void _size(WidgetTester t, {Size size = const Size(900, 2000), double text = 1.0}) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

final _spoken = <String>[];

void _mockVoice() {
  _spoken.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (call) async {
    if (call.method == 'speak') _spoken.add('${call.arguments}');
    if (call.method == 'isLanguageAvailable') return true;
    return 1;
  });
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> _continue(WidgetTester t) => _tap(t, find.byKey(const ValueKey('onb-continue')));

bool _enabled(WidgetTester t) => t.widget<TratraButton>(find.byKey(const ValueKey('onb-continue'))).onPressed != null;

Finder _input(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

/// Métier → prestation → commune → quartier (passé) → expérience → jours : jusqu'à l'aperçu de l'annonce.
Future<void> _answerAll(WidgetTester t) async {
  await _continue(t); // intro → métier
  expect(_enabled(t), isFalse, reason: 'aucun métier choisi');
  await _tap(t, find.text('Nounou'));
  await _continue(t);
  expect(find.text('Que proposez-vous exactement ?'), findsOneWidget);
  await _tap(t, find.byKey(const ValueKey('onb-prest-121')));
  await _continue(t);
  await _tap(t, find.byKey(const ValueKey('onb-commune-Cocody')));
  await _continue(t);
  await _tap(t, find.byKey(const ValueKey('onb-secondary'))); // quartier : « Passer »
  expect(find.text('Depuis combien de temps faites-vous ce travail ?'), findsOneWidget);
  await _tap(t, find.byKey(const ValueKey('onb-opt-experience-lt1')));
  await _continue(t);
  await _tap(t, find.byKey(const ValueKey('onb-opt-days-monday')));
  await _tap(t, find.byKey(const ValueKey('onb-opt-days-saturday')));
  await _continue(t);
  expect(find.byKey(const ValueKey('onb-offer')), findsOneWidget);
}

Future<Map<String, dynamic>?> _localDraft() async {
  final raw = (await SharedPreferences.getInstance()).getString('tratra.onboarding.draft.v1');
  return raw == null ? null : (jsonDecode(raw) as Map).cast<String, dynamic>();
}

/// Laisse les lectures de fichier réelles (envoi multipart) se terminer.
Future<void> _io(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle();
}

Future<String> _photo() async {
  final f = File('${Directory.systemTemp.path}/onb_${DateTime.now().microsecondsSinceEpoch}.png')
    ..writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));
  addTearDown(() {
    if (f.existsSync()) f.deleteSync();
  });
  return f.path;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mockVoice();
  });

  group('parcours accompagné', () {
    testWidgets('compte connecté : une question par écran, voix, aperçu, annonce créée par le serveur, photo, identité', (t) async {
      _size(t);
      final server = OnbServer();
      final base = _base(server.client);
      final path = await t.runAsync(_photo);
      await t.pumpWidget(_host(base, _Session(_awa), GuidedOnboardingScreen(photoPicker: () async => path)));
      await t.pumpAndSettle();

      expect(find.text('Proposez vos services, pas à pas'), findsOneWidget);
      expect(find.textContaining('Étape 1 sur'), findsOneWidget);
      expect(_spoken.single, startsWith('Bienvenue !'), reason: 'la voix lit l’écran');
      await _tap(t, find.byKey(const ValueKey('onb-replay')));
      expect(_spoken, hasLength(2), reason: '« Réécouter »');

      await _answerAll(t);
      expect(find.text('Je propose mes services de nounou à Cocody.'), findsOneWidget);
      expect(find.text('Disponible lundi et samedi.'), findsOneWidget);
      expect(find.text('Je débute dans ce métier.'), findsOneWidget);
      expect(_spoken.last, contains('Je propose mes services de nounou à Cocody.'), reason: 'la voix lit l’annonce');
      expect(server.applied, isFalse);

      await _continue(t); // « Mon annonce me convient »
      expect(server.applied, isTrue, reason: 'profil et annonce créés par le serveur, sans IA');
      final body = jsonDecode(server.puts.last.body) as Map;
      expect(body['trade'], 12);
      expect(body['prestations'], [121]);
      expect(body['commune'], 'Cocody');
      expect(body['answers'], {
        'experience': 'lt1',
        'days': ['monday', 'saturday']
      });
      expect(body.containsKey('password'), isFalse);
      expect(find.text('Votre photo'), findsOneWidget);
      expect(find.text('Comment vous appelez-vous ?'), findsNothing, reason: 'compte déjà connecté : pas de création de compte');

      await t.tap(find.byKey(const ValueKey('onb-continue'))); // « Prendre ma photo »
      await _io(t, () => find.text('Vérifier votre identité').evaluate().isNotEmpty);
      final upload = server.requests.where((r) => r.url.path.endsWith('/handymen/5/'));
      expect(upload, hasLength(1));
      expect(upload.single.method, 'PATCH');
      server.states = {'photo': 'done'};

      await _tap(t, find.byKey(const ValueKey('onb-secondary'))); // identité : « Plus tard »
      expect(find.text('Votre annonce est enregistrée'), findsOneWidget, reason: 'fin honnête : la pièce n’a pas été envoyée');
      expect(find.textContaining('Il vous reste à faire vérifier votre pièce d’identité.'), findsOneWidget);
      expect(await t.runAsync(_localDraft), isNull, reason: 'le brouillon local est vidé une fois l’annonce créée');
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('sans compte : rien n’est envoyé avant la création du compte, brouillon gardé sur le téléphone et reprise au même écran', (t) async {
      _size(t);
      final server = OnbServer();
      final base = _base(server.client);
      final session = _Session();
      final signups = <String>[];
      Widget screen(String key) => GuidedOnboardingScreen(
            key: ValueKey(key),
            signUp: (ctx, {required first, required last, required phone, required password}) async {
              signups.add('$first|$last|${phone.e164}');
              await session.setUser(const User(id: '9', email: '', firstName: 'Awa', lastName: 'Koné', userType: 'client', isActive: true, isVerified: true));
              return true;
            },
          );
      await t.pumpWidget(_host(base, session, screen('a')));
      await t.pumpAndSettle();
      await _continue(t);
      await _tap(t, find.text('Nounou'));
      await _continue(t);
      await _tap(t, find.byKey(const ValueKey('onb-prest-121')));
      await _continue(t);
      await _tap(t, find.byKey(const ValueKey('onb-commune-Cocody')));
      await _continue(t);
      await _tap(t, find.byKey(const ValueKey('onb-secondary')));
      await _tap(t, find.byKey(const ValueKey('onb-opt-experience-1_3')));
      await t.pump(const Duration(seconds: 1));

      expect(server.private, isEmpty, reason: 'seuls le catalogue et la configuration publique sont lus');
      final local = await t.runAsync(_localDraft);
      expect(local!['trade'], 12);
      expect(local['commune'], 'Cocody');
      expect(local['step'], 'q:experience');
      expect(local['answers'], {'experience': '1_3'});

      // L'application est fermée puis rouverte : même écran, même réponse.
      await t.pumpWidget(_host(base, session, const SizedBox()));
      await t.pumpWidget(_host(base, session, screen('b')));
      await t.pumpAndSettle();
      expect(find.text('Depuis combien de temps faites-vous ce travail ?'), findsOneWidget);
      expect(_enabled(t), isTrue, reason: 'la réponse « 1 à 3 ans » est retrouvée');

      // Retour arrière : l'écran précédent, puis on avance de nouveau.
      await _tap(t, find.byTooltip('Retour'));
      expect(find.text('Dans quel quartier ?'), findsOneWidget);
      await _tap(t, find.byKey(const ValueKey('onb-secondary')));
      await _continue(t);
      await _tap(t, find.byKey(const ValueKey('onb-opt-days-monday')));
      await _continue(t);
      await _continue(t); // aperçu → compte

      expect(find.text('Comment vous appelez-vous ?'), findsOneWidget);
      expect(_enabled(t), isFalse);
      await t.enterText(_input('onb-first'), 'Awa');
      await t.enterText(_input('onb-last'), 'Koné');
      await t.pumpAndSettle();
      await _continue(t);
      final national = find.descendant(of: find.byType(TratraPhoneField), matching: find.byType(TextField));
      await t.enterText(national, '07 00');
      await _continue(t);
      expect(find.textContaining('Numéro trop court'), findsOneWidget);
      await t.enterText(national, '0700000000');
      await t.pumpAndSettle();
      await _continue(t);
      expect(find.text('Choisissez votre mot de passe'), findsOneWidget);
      await t.enterText(_input('onb-password'), 'abc');
      await t.pumpAndSettle();
      expect(_enabled(t), isFalse, reason: 'règles du mot de passe visibles et respectées');
      const secret = 'Essai2026x';
      await t.enterText(_input('onb-password'), secret);
      await t.enterText(_input('onb-confirm'), secret);
      await t.pumpAndSettle();
      expect(server.private, isEmpty);
      expect('${await t.runAsync(_localDraft)}', isNot(contains(secret)), reason: 'jamais de mot de passe dans le brouillon');

      await _continue(t); // « Créer mon compte »
      expect(signups, ['Awa|Koné|+2250700000000']);
      expect(server.puts, isNotEmpty, reason: 'le brouillon rejoint le compte dès sa création');
      expect(jsonDecode(server.puts.first.body)['answers'], {
        'experience': '1_3',
        'days': ['monday']
      });
      expect(server.applied, isTrue);
      expect(find.text('Votre photo'), findsOneWidget);
      expect(await t.runAsync(_localDraft), isNull);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('code SMS : « Plus tard » crée quand même l’annonce ; numéro vérifié entre-temps → aucun nouveau code', (t) async {
      _size(t);
      SharedPreferences.setMockInitialValues({
        'tratra.onboarding.draft.v1': jsonEncode({
          'trade': 12, 'trade_name': 'Nounou', 'prestations': [121], 'commune': 'Cocody', 'step': 'password',
          'answers': {'experience': 'lt1', 'days': ['monday']}, 'first_name': 'Awa', 'last_name': 'Koné',
        }),
      });
      final server = OnbServer();
      final base = _base(server.client);
      final session = _Session();
      const unverified = User(id: '9', email: '', firstName: 'Awa', lastName: 'Koné', userType: 'client', isActive: true);
      await t.pumpWidget(_host(
          base,
          session,
          GuidedOnboardingScreen(signUp: (ctx, {required first, required last, required phone, required password}) async {
            await session.setUser(unverified);
            return true;
          })));
      await t.pumpAndSettle();
      expect(find.text('Choisissez votre mot de passe'), findsOneWidget, reason: 'reprise à l’écran enregistré');
      await t.enterText(_input('onb-password'), 'Essai2026x');
      await t.enterText(_input('onb-confirm'), 'Essai2026x');
      await t.pumpAndSettle();
      await _continue(t);
      expect(find.text('Confirmez votre numéro'), findsOneWidget);
      expect(server.applied, isFalse);
      await _tap(t, find.byKey(const ValueKey('onb-secondary')));             // « Plus tard »
      expect(server.applied, isTrue, reason: 'l’annonce est créée ; le numéro sera confirmé depuis le tableau de bord');
      expect(find.text('Votre photo'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));

      // Reprise sur l'écran du code alors que le numéro a été vérifié ailleurs : pas de nouveau code, on avance.
      server
        ..applied = false
        ..draft = {...server.draft, 'step': 'verify'};
      await session.setUser(unverified);
      await t.pumpWidget(_host(base, session, const GuidedOnboardingScreen(key: ValueKey('again'))));
      await t.pumpAndSettle();
      expect(find.text('Confirmez votre numéro'), findsOneWidget);
      await session.setUser(const User(id: '9', email: '', firstName: 'Awa', lastName: 'Koné', userType: 'client', isActive: true, isVerified: true));
      await _continue(t);
      expect(find.text('Vérifiez votre téléphone'), findsNothing);
      expect(server.applied, isTrue);
      expect(find.text('Votre photo'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('« Passer au formulaire classique » garde les réponses (sans compte : inscription classique)', (t) async {
      _size(t);
      final server = OnbServer();
      final base = _base(server.client);
      await t.pumpWidget(_host(base, _Session(), const GuidedOnboardingScreen()));
      await t.pumpAndSettle();
      await _continue(t);
      await _tap(t, find.text('Ménage'));
      await _tap(t, find.byTooltip('Plus d’options'));
      await _tap(t, find.text('Passer au formulaire classique'));
      expect(find.text('route /register'), findsOneWidget);
      expect((await t.runAsync(_localDraft))!['trade'], 13);
      expect(server.private, isEmpty);
    });

    testWidgets('voix coupée : préférence gardée, plus de lecture automatique', (t) async {
      _size(t);
      final base = _base(OnbServer().client);
      await t.pumpWidget(_host(base, _Session(_awa), const GuidedOnboardingScreen()));
      await t.pumpAndSettle();
      expect(_spoken, hasLength(1));
      await _tap(t, find.byKey(const ValueKey('onb-voice-toggle')));
      await _continue(t);
      expect(find.text('Quel est votre métier ?'), findsOneWidget);
      expect(_spoken, hasLength(1));
      expect((await t.runAsync(SharedPreferences.getInstance))!.getBool('tratra.voice.autoplay'), isFalse);
    });

    testWidgets('sans voix française installée : aucun bouton de voix, l’écran reste utilisable', (t) async {
      _size(t);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (call) async {
        if (call.method == 'isLanguageAvailable') return false;
        return 1;
      });
      final base = _base(OnbServer().client);
      await t.pumpWidget(_host(base, _Session(_awa), GuidedOnboardingScreen(voice: VoiceGuide())));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('onb-replay')), findsNothing);
      await _continue(t);
      expect(find.text('Quel est votre métier ?'), findsOneWidget);
    });
  });

  test('aperçu de l’annonce : mêmes phrases que le serveur (handy/test_onboarding.py), sans IA ni réseau', () {
    Map<String, dynamic> o(String v, String l, {String phrase = '', int? years, int? amount, String? unit}) =>
        {'value': v, 'label': l, 'phrase': phrase, 'years': years, 'amount': amount, 'unit': unit};
    Map<String, dynamic> q(String key, String target, String kind, List<Map<String, dynamic>> options) =>
        {'key': key, 'text': key, 'kind': kind, 'target': target, 'options': options};
    final config = OnbConfig({
      'trade': {'id': 1, 'name': 'Nousnou'},
      'prestations': [
        {'id': 11, 'name': 'Garde de nuit'},
        {'id': 12, 'name': 'Sortie d’école'}
      ],
      'questions': [
        q('experience', 'experience', 'single', [o('4', '3 à 5 ans', years: 4)]),
        q('nanny_skills', 'strengths', 'multi', [
          o('babies', 'M’occuper des bébés', phrase: 'soins des bébés'),
          o('school', 'Les accompagner à l’école', phrase: 'accompagnement à l’école'),
        ]),
        q('nanny_lodging', 'info', 'single', [o('no', 'Non', phrase: 'sans hébergement')]),
        q('nanny_price', 'price', 'single', [
          o('m60000', '60 000 FCFA par mois', amount: 60000, unit: 'month'),
          o('h', '2 000 FCFA de l’heure', amount: 2000, unit: 'hour'),
        ]),
        q('days', 'days', 'multi', [for (final d in ['monday', 'tuesday', 'wednesday', 'thursday', 'friday']) o(d, d)]),
        q('slots', 'slots', 'multi', [o('morning', 'Le matin'), o('afternoon', 'L’après-midi')]),
      ],
    });
    final draft = OnbDraft(tradeId: 1, tradeName: 'Nousnou', prestations: [11], commune: 'Cocody', quartier: 'Riviera 2', answers: {
      'experience': '4',
      'nanny_skills': ['babies', 'school'],
      'nanny_lodging': 'no',
      'nanny_price': 'm60000',
      'days': ['friday', 'monday', 'tuesday', 'wednesday', 'thursday'],
      'slots': ['morning', 'afternoon'],
    });
    final (title, lines, price) = offerPreview(config, draft);
    expect(title, 'Garde de nuit à Cocody');
    expect(
        lines.join(' '),
        'Je propose mes services de nousnou à Cocody (Riviera 2). Ce que je fais : soins des bébés et accompagnement à l’école. '
        'Sans hébergement. Disponible du lundi au vendredi le matin et l’après-midi. 4 ans d’expérience environ. '
        'Tarif souhaité : 60 000 FCFA par mois (à discuter).');
    expect(price, isNull, reason: 'salaire mensuel : à discuter, jamais un faux forfait');
    draft.answers['nanny_price'] = 'h';
    expect(offerPreview(config, draft).$3, '2 000 FCFA de l’heure');
  });

  group('entrées et tableau de bord débutant', () {
    testWidgets('« Proposer mes services » : accompagnée (recommandée) ou classique, et « Continuer mon inscription » si commencée', (t) async {
      _size(t);
      final base = _base(OnbServer().client);
      await t.pumpWidget(_host(base, _Session(_awa), const OnboardingChoiceScreen()));
      await t.pumpAndSettle();
      expect(find.text('Inscription accompagnée'), findsOneWidget);
      expect(find.text('Recommandée si vous débutez'), findsOneWidget);
      expect(find.text('Inscription classique'), findsOneWidget);
      expect(find.text('Continuer mon inscription'), findsNothing);
      await _tap(t, find.byKey(const ValueKey('choice-classic')));
      expect(find.text('Devenez artisan avec votre compte actuel'), findsOneWidget, reason: 'parcours classique inchangé');

      SharedPreferences.setMockInitialValues({
        'tratra.onboarding.draft.v1': jsonEncode({'trade': 12, 'trade_name': 'Nounou', 'step': 'commune'})
      });
      await t.pumpWidget(_host(base, _Session(_awa), const OnboardingChoiceScreen(key: ValueKey('again'))));
      await t.pumpAndSettle();
      expect(find.text('Continuer mon inscription'), findsOneWidget);
      expect(find.textContaining('(Nounou)'), findsOneWidget);
    });

    testWidgets('tableau de bord : progression, prochaine action et UN bouton « Continuer » ; caché si rien commencé ou publié', (t) async {
      _size(t);
      final server = OnbServer()
        ..draft = {'trade': 12, 'step': 'identity'}
        ..applied = true
        ..states = {'trade': 'done', 'zone': 'done', 'questions': 'done', 'account': 'done', 'phone': 'done', 'photo': 'done'}
        ..next = {'code': 'verify_identity', 'label': 'Vérifier mon identité', 'step': 'identity'};
      final base = _base(server.client);
      await t.pumpWidget(_host(base, _Session(_awa), const Scaffold(body: BeginnerProgressCard())));
      await t.pumpAndSettle();
      expect(find.text('Mon inscription professionnelle'), findsOneWidget);
      expect(find.text('7/9'), findsOneWidget);
      expect(find.text('Prochaine étape : Vérifier mon identité'), findsOneWidget);
      expect(find.byType(TratraButton), findsOneWidget);
      expect(find.text('Continuer'), findsOneWidget);

      server.next = {'code': 'wait', 'label': 'Nous vérifions votre dossier', 'step': 'identity'};
      await t.pumpWidget(_host(base, _Session(_awa), const Scaffold(body: BeginnerProgressCard(key: ValueKey('wait')))));
      await t.pumpAndSettle();
      expect(find.text('Voir mon dossier'), findsOneWidget);
      expect(find.textContaining('vérifie votre dossier'), findsOneWidget);

      server.published = true;
      await t.pumpWidget(_host(base, _Session(_awa), const Scaffold(body: BeginnerProgressCard(key: ValueKey('pub')))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('beginner-card')), findsNothing);

      final empty = OnbServer();
      await t.pumpWidget(_host(_base(empty.client), _Session(_awa), const Scaffold(body: BeginnerProgressCard(key: ValueKey('none')))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('beginner-card')), findsNothing, reason: 'inscription classique : aucune carte en plus');
    });

    testWidgets('après une inscription classique, le brouillon du téléphone rejoint le compte (rien n’est perdu)', (t) async {
      _size(t);
      SharedPreferences.setMockInitialValues({
        'tratra.onboarding.draft.v1': jsonEncode({'trade': 12, 'trade_name': 'Nounou', 'commune': 'Cocody', 'step': 'quartier'})
      });
      final server = OnbServer();
      final base = _base(server.client);
      await t.pumpWidget(_host(base, _Session(_awa), const Scaffold(body: BeginnerProgressCard())));
      await t.pumpAndSettle();
      expect(server.puts, hasLength(1));
      expect(jsonDecode(server.puts.single.body)['commune'], 'Cocody');
      expect(find.byKey(const ValueKey('beginner-card')), findsOneWidget);
    });
    testWidgets('le brouillon gardé pour un AUTRE compte n’est jamais envoyé ni montré', (t) async {
      _size(t);
      SharedPreferences.setMockInitialValues({
        'tratra.onboarding.draft.v1': jsonEncode({'trade': 12, 'commune': 'Cocody', 'step': 'quartier', 'owner': '7'})
      });
      final server = OnbServer();
      final base = _base(server.client);
      await t.pumpWidget(_host(base, _Session(_awa), const Scaffold(body: BeginnerProgressCard())));
      await t.pumpAndSettle();
      expect(server.puts, isEmpty);
      expect(find.byKey(const ValueKey('beginner-card')), findsNothing);
      await t.pumpWidget(_host(base, _Session(_awa), const GuidedOnboardingScreen()));
      await t.pumpAndSettle();
      expect(find.text('Proposez vos services, pas à pas'), findsOneWidget, reason: 'nouveau départ, sans les réponses de l’autre compte');
      expect(server.puts, isEmpty);
    });
  });

  group('KYC simplifié', () {
    testWidgets('la pièce d’abord, puis les informations préremplies par la lecture de la pièce, à confirmer', (t) async {
      _size(t);
      var state = kycState(birth: null, current: 'personal');
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        requests.add(r);
        final p = r.url.path;
        if (p.endsWith('/me/kyc/') && r.method == 'GET') return _json(state);
        if (p.endsWith('/me/kyc/') && r.method == 'PATCH') {
          state = kycState(birth: null, kind: 'passport', current: 'personal', captures: [side('front')]);
          return _json(state);
        }
        if (p.endsWith('/me/kyc/capture/')) {
          state = kycState(birth: null, kind: 'passport', current: 'personal', captures: [side('front', present: true, quality: 'ok')], ready: false);
          return _json({
            ...state,
            'check': {'quality': 'ok'},
            'suggestions': {'first_name': 'Awa', 'last_name': 'KONÉ', 'birth_date': '1990-04-12'}
          });
        }
        return _json({});
      });
      final base = _base(client);
      final path = await t.runAsync(_photo);
      await t.pumpWidget(_host(base, _Session(_awa), IdentityFlowScreen(api: KycFlowApi(base), picker: (_) async => path, simplified: true)));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kyc-kind-passport')), findsOneWidget, reason: 'mode simplifié : le choix de la pièce d’abord');
      expect(find.byKey(const ValueKey('kyc-personal-save')), findsNothing);
      await _tap(t, find.byKey(const ValueKey('kyc-kind-passport')));
      await _tap(t, find.byKey(const ValueKey('kyc-kind-save')));
      await t.ensureVisible(find.byKey(const ValueKey('kyc-take-front')));
      await t.tap(find.byKey(const ValueKey('kyc-take-front')));
      await _io(t, () => find.byKey(const ValueKey('kyc-read')).evaluate().isNotEmpty);
      expect(find.byKey(const ValueKey('kyc-read')), findsOneWidget);
      expect(t.widget<TextField>(_input('kyc-first')).controller!.text, 'Awa');
      expect(t.widget<TextField>(_input('kyc-last')).controller!.text, 'KONÉ');
      expect(find.byKey(ValueKey('kyc-birth-${DateTime(1990, 4, 12).toIso8601String()}')), findsOneWidget);
      expect(requests.where((r) => r.method == 'PATCH'), hasLength(1), reason: 'rien n’est enregistré sans confirmation');
    });
  });

  group('petits écrans', () {
    for (final (name, size, text) in [('320×640, texte ×1,3', const Size(320, 640), 1.3), ('360×740, texte ×1,0', const Size(360, 740), 1.0)]) {
      testWidgets('aucun débordement — $name', (t) async {
        _size(t, size: size, text: text);
        final base = _base(OnbServer().client);
        await t.pumpWidget(_host(base, _Session(_awa), const GuidedOnboardingScreen()));
        await t.pumpAndSettle();
        await _continue(t); // grille des métiers
        await _tap(t, find.text('Nounou'));
        await _continue(t);
        await _continue(t); // prestations (non choisies : bouton inactif)
        expect(t.takeException(), isNull);
        await t.pumpWidget(_host(base, _Session(_awa), const OnboardingChoiceScreen()));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final started = OnbServer()
          ..draft = {'trade': 12, 'step': 'identity'}
          ..next = {'code': 'verify_identity', 'label': 'Vérifier mon identité', 'step': 'identity'};
        await t.pumpWidget(_host(_base(started.client), _Session(_awa), const Scaffold(body: SingleChildScrollView(child: BeginnerProgressCard()))));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('beginner-card')), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 1));
      });
    }
  });
}
