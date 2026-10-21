// Hybrid Matching (application) : choix du mode après le métier (conseil du serveur, choix du client conservé), choix du professionnel
// (profils, favoris), envoi de la commande unique, bascule confirmée depuis le suivi, « choix attendu » quand le pro choisi refuse.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/flash/flash_client.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/flash/flash_hybrid.dart';
import 'package:flutter_tratra/flash/flash_native.dart';
import 'package:flutter_tratra/models/category.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: const {'content-type': 'application/json; charset=utf-8'});

class _Native implements FlashNative {
  @override
  Future<FlashAction?> takeLaunchAction() async => null;
  @override
  Stream<FlashAction> get actions => const Stream.empty();
  @override
  Future<({bool sound, bool vibration})> prefs() async => (sound: true, vibration: true);
  @override
  Future<void> setPrefs({required bool sound, required bool vibration}) async {}
  @override
  Future<FlashPlayback> play(String sound, {bool withSound = true, bool withVibration = true}) async => const FlashPlayback();
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel(int offerId) async {}
}

final Category plomberie = Category.fromJson(const {'id': 3, 'name': 'Plomberie', 'slug': 'plomberie', 'parent': null, 'trade': 3, 'kind': 'trade', 'is_active': true});

Map<String, dynamic> proCard(int id, String name, {bool favorite = false}) => {
      'id': id, 'name': name, 'photo': null, 'commune': 'Cocody', 'trust_score': 82, 'badges': ['VERIFIE'], 'rating': 4.6, 'reviews': 12,
      'completed': 30, 'experience': '8 ans', 'distance_km': 2.4, 'favorite': favorite, 'price_from': 12000, 'score': 71.0,
      'offers': [{'id': 50 + id, 'title': 'Débouchage', 'price': 12000, 'price_type': 'fixed', 'category': 3}],
      'why': [{'label': 'Proximité', 'detail': '2,4 km'}],
    };

class Server {
  Server({this.suggested = 'direct', this.preselected = 'direct'});
  final String suggested;
  final String preselected;
  final posts = <String, Map<String, dynamic>>{};
  Map<String, dynamic> request = {
    'id': 9, 'status': 'awaiting', 'status_label': 'Votre choix est attendu', 'matching': 'direct', 'category': {'id': 3, 'name': 'Plomberie'},
    'commune': 'Cocody', 'when_label': 'Maintenant', 'amount_label': '12 000 FCFA', 'progress': {'contacted': 1, 'waiting': 0, 'declined': 1, 'no_answer': 0},
    'target': {'id': 7, 'name': 'Yao K.'}, 'awaiting_reason': "n'est pas disponible pour cette demande", 'can_switch': true, 'can_cancel': true,
    'can_relaunch': false, 'version': 4, 'scheduled_for': '2026-10-22T10:00:00+00:00',
  };
  late final client = MockClient((r) async {
    final path = r.url.path;
    if (path.endsWith('/catalog/')) {
      return _json({'version': 'v1', 'results': [{'id': 3, 'name': 'Plomberie', 'slug': 'plomberie', 'parent': null, 'trade': 3, 'kind': 'trade', 'is_active': true}]});
    }
    if (path.endsWith('/flash/suggest/')) {
      return _json({'suggested': suggested, 'preselected': preselected, 'reason': 'Mission planifiée : comparez les profils.', 'note': '', 'remembered': false,
                    'available_pros': 2, 'favorites': []});
    }
    if (path.endsWith('/flash/pros/')) return _json({'count': 2, 'results': [proCard(7, 'Yao K.', favorite: true), proCard(8, 'Awa D.')]});
    if (path.endsWith('/me/addresses/')) {
      return _json({'results': [{'id': 4, 'label': 'Maison', 'street': 'Rue des Jardins', 'commune': 'Cocody', 'city': 'Abidjan', 'latitude': 5.36, 'longitude': -3.99}]});
    }
    if (path.endsWith('/geo/search/')) {
      return _json({'results': [{'label': 'Riviera 3, Cocody, Abidjan', 'street': 'Boulevard Mitterrand', 'commune': 'Riviera 3', 'city': 'Abidjan',
                                 'latitude': 5.3712, 'longitude': -3.9561}], 'provider': 'nominatim'});
    }
    if (r.method == 'POST') {
      posts[path] = (jsonDecode(r.body) as Map).cast<String, dynamic>();
      if (path.endsWith('/flash/requests/')) return _json({...request, 'id': 21, 'status': 'searching'}, 201);
      if (path.endsWith('/switch/')) {
        request = {...request, 'status': 'searching', 'matching': posts[path]!['to'], 'version': 5};
        return _json(request);
      }
    }
    if (path.endsWith('/flash/requests/9/')) return _json(request);
    return _json({});
  });
}

Future<Server> pump(WidgetTester t, Widget home, {Server? server}) async {
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final s = server ?? Server();
  final base = BaseApi(client: s.client);
  final c = FlashController(api: FlashApi(base), native: _Native(), navigatorKey: GlobalKey<NavigatorState>(), isAuthenticated: () => true);
  await t.pumpWidget(MultiProvider(
    providers: [Provider<BaseApi>.value(value: base), ChangeNotifierProvider<FlashController>.value(value: c)],
    child: MaterialApp(theme: TratraTheme.light(), home: home),
  ));
  await t.pumpAndSettle();
  return s;
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'acc'});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('après le métier : conseil du serveur, choix du pro (favori d’abord), commande DIRECT envoyée', (t) async {
    final s = await pump(t, FlashRequestFormScreen(initialCategory: plomberie));
    expect(find.text('Comment trouver votre professionnel ?'), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-reason')), findsOneWidget);
    expect(find.text('Conseillé'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('flash-pick-pro')));
    await t.pumpAndSettle();
    expect(find.text('Yao K.'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);                       // favori signalé
    await t.tap(find.byKey(const ValueKey('choose-7')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('flash-chosen-pro')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('flash-address')).first, 'Rue 1');
    await t.enterText(find.byKey(const ValueKey('flash-commune')).first, 'Cocody');
    await t.ensureVisible(find.byKey(const ValueKey('flash-submit')));
    await t.tap(find.byKey(const ValueKey('flash-submit')));
    await t.pumpAndSettle();
    final body = s.posts['/handy/flash/requests/']!;
    expect(body['matching'], 'direct');
    expect(body['target'], 7);
    expect(body['service'], 57);
    expect(body['amount'], 12000);                                              // prix de l'offre repris
  });

  testWidgets('le choix explicite du client n’est jamais écrasé par le conseil', (t) async {
    final s = await pump(t, FlashRequestFormScreen(initialCategory: plomberie, initialMatching: kAuto));
    expect(find.byKey(const ValueKey('flash-pick-pro')), findsNothing);       // reste en « Trouvez-moi un professionnel »
    await t.enterText(find.byKey(const ValueKey('flash-address')).first, 'Rue 1');
    await t.enterText(find.byKey(const ValueKey('flash-commune')).first, 'Cocody');
    await t.enterText(find.byKey(const ValueKey('flash-amount-input')).first, '15000');
    await t.ensureVisible(find.byKey(const ValueKey('flash-submit')));
    await t.tap(find.byKey(const ValueKey('flash-submit')));
    await t.pumpAndSettle();
    expect(s.posts['/handy/flash/requests/']!['matching'], 'auto');
    expect(s.posts['/handy/flash/requests/']!.containsKey('target'), isFalse);
  });

  testWidgets('choix attendu : le client bascule vers « Trouvez-moi un professionnel » après confirmation, version envoyée', (t) async {
    final s = await pump(t, const FlashRequestScreen(requestId: 9));
    expect(find.byKey(const ValueKey('flash-awaiting')), findsOneWidget);
    expect(find.textContaining('Yao K.'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('flash-switch-auto')));
    await t.pumpAndSettle();
    expect(find.text('Trouvez-moi un professionnel ?'), findsOneWidget);       // confirmation exigée
    await t.tap(find.byKey(const ValueKey('confirm-switch')));
    await t.pump(const Duration(milliseconds: 400));                           // recherche relancée : animations continues
    expect(s.posts['/handy/flash/requests/9/switch/'], {'to': 'auto', 'confirm': true, 'expected_version': 4});
    expect(find.byKey(const ValueKey('flash-awaiting')), findsNothing);
  });

  testWidgets('bascule vers un autre professionnel : le pro déjà sollicité est exclu de la liste', (t) async {
    final s = await pump(t, const FlashRequestScreen(requestId: 9));
    await t.tap(find.byKey(const ValueKey('flash-switch-direct')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('pro-7')), findsNothing);
    await t.tap(find.byKey(const ValueKey('choose-8')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('confirm-switch')));
    await t.pump(const Duration(milliseconds: 400));
    expect(s.posts['/handy/flash/requests/9/switch/'], {'to': 'direct', 'confirm': true, 'target': 8, 'expected_version': 4});
  });

  testWidgets('adresse : mes adresses d’abord, puis suggestions (commune, quartier) ; la position choisie est envoyée', (t) async {
    final s = await pump(t, FlashRequestFormScreen(initialCategory: plomberie, initialMatching: kAuto));
    await t.tap(find.byKey(const ValueKey('address-input')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('address-saved-4')), findsOneWidget);    // adresse enregistrée proposée
    await t.enterText(find.byKey(const ValueKey('address-input')), 'Riviera');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('address-suggestion-0')));
    await t.pumpAndSettle();
    final commune = t.widget<TratraInput>(find.byKey(const ValueKey('flash-commune')));
    expect(commune.controller!.text, 'Riviera 3');
    await t.enterText(find.byKey(const ValueKey('flash-amount-input')).first, '15000');
    await t.ensureVisible(find.byKey(const ValueKey('flash-submit')));
    await t.tap(find.byKey(const ValueKey('flash-submit')));
    await t.pumpAndSettle();
    final body = s.posts['/handy/flash/requests/']!;
    expect(body['address'], 'Boulevard Mitterrand, Riviera 3, Abidjan');
    expect(body['commune'], 'Riviera 3');
    expect((body['lat'] as num).toDouble(), closeTo(5.3712, 1e-6));
  });

  testWidgets('fiche métier : les deux entrées ouvrent la commande dans le bon mode', (t) async {
    await pump(t, Scaffold(body: Builder(builder: (_) => ModeChoiceButtons(category: plomberie))));
    expect(find.text('Trouvez-moi un professionnel'), findsOneWidget);
    expect(find.text('Choisir mon professionnel'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('mode-direct-3')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('flash-pick-pro')), findsOneWidget);
  });
}
