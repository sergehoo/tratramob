// Notifications push : l'appareil suit toujours le compte connecté, rien ne plante sans Firebase.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/services/push_service.dart';

class FakeGateway implements PushGateway {
  FakeGateway({this.configured = true, this.permission = true, this.tokenValue = 'tok-1'});
  bool configured;
  bool permission;
  String? tokenValue;
  int permissionAsked = 0;
  int tokensDeleted = 0;
  PushMessage? launch;
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  @override
  Future<bool> init() async => configured;
  @override
  Future<bool> requestPermission() async {
    permissionAsked++;
    return permission;
  }

  @override
  Future<String?> token() async => tokenValue;
  @override
  Future<void> deleteToken() async => tokensDeleted++;
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Stream<PushMessage> get onForegroundMessage => foreground.stream;
  @override
  Stream<PushMessage> get onOpenedFromBackground => opened.stream;
  @override
  Future<PushMessage?> initialMessage() async => launch;
}

class Recorded {
  Recorded(this.method, this.path, this.auth, this.body);
  final String method;
  final String path;
  final String? auth;
  final Map<String, dynamic>? body;
}

(PushService, FakeGateway, List<Recorded>) build({
  FakeGateway? gateway,
  bool supported = true,
  int status = 201,
  bool offline = false,
}) {
  FlutterSecureStorage.setMockInitialValues({AppConstants.authTokenKey: 'access-A'});
  final calls = <Recorded>[];
  var nextId = 40;
  final client = MockClient((http.Request r) async {
    if (offline) throw http.ClientException('réseau coupé');
    Map<String, dynamic>? body;
    if (r.body.isNotEmpty) body = (jsonDecode(r.body) as Map).cast<String, dynamic>();
    calls.add(Recorded(r.method, r.url.path, r.headers['Authorization'], body));
    if (r.method == 'DELETE') return http.Response('', 204);
    return http.Response(jsonEncode({'id': ++nextId, 'device_token': body?['device_token']}), status);
  });
  final gw = gateway ?? FakeGateway();
  return (PushService(BaseApi(client: client), gateway: gw, supported: supported), gw, calls);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plateforme non prise en charge : aucun appel, statut explicite', () async {
    final (push, gw, calls) = build(supported: false);
    await push.start();
    await push.bindUser('1');
    expect(push.status, PushStatus.unsupported);
    expect(gw.permissionAsked, 0);
    expect(calls, isEmpty);
  });

  test('sans projet Firebase : l’application continue, aucun enregistrement, aucune exception', () async {
    final (push, gw, calls) = build(gateway: FakeGateway(configured: false));
    await push.start();
    await push.bindUser('1');
    expect(push.status, PushStatus.unconfigured);
    expect(gw.permissionAsked, 0);
    expect(calls, isEmpty);
    await push.unregister(); // ne lève rien non plus
  });

  test('connexion : permission demandée puis appareil Android enregistré sur le compte courant', () async {
    final (push, gw, calls) = build();
    await push.start();
    await push.bindUser('1');
    expect(gw.permissionAsked, 1);
    expect(calls.single.method, 'POST');
    expect(calls.single.path, '/handy/devices/');
    expect(calls.single.auth, 'Bearer access-A');
    // Aucun identifiant utilisateur envoyé ; l'application Android annonce qu'elle affiche elle-même l'alerte Tratra Flash.
    expect(calls.single.body, {'device_token': 'tok-1', 'device_type': 'android', 'capabilities': ['flash1', 'rich1']});
    expect(push.status, PushStatus.registered);
    expect(await const FlutterSecureStorage().read(key: PushService.deviceIdKey), '41');
  });

  test('iOS : l’appareil est enregistré avec le type « ios »', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final (push, _, calls) = build();
    await push.start();
    await push.bindUser('1');
    expect(calls.single.body!['device_type'], 'ios');
  });

  test('notifications refusées : l’appareil est tout de même enregistré (réglage modifiable ensuite)', () async {
    final (push, _, calls) = build(gateway: FakeGateway(permission: false));
    await push.start();
    await push.bindUser('1');
    expect(calls, hasLength(1));
    expect(push.status, PushStatus.denied);
  });

  test('jeton renouvelé : réenregistré si connecté, ignoré sinon', () async {
    final (push, gw, calls) = build();
    await push.start();
    gw.refresh.add('tok-orphan');
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty); // personne n'est connecté : rien à rattacher
    await push.bindUser('1');
    gw.refresh.add('tok-2');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls.map((c) => c.body?['device_token']), ['tok-1', 'tok-2']);
    expect(calls.first.body!.containsKey('previous_token'), isFalse);
    expect(calls.last.body!['previous_token'], 'tok-1'); // l'ancien jeton est retiré du compte côté serveur
  });

  test('changement de compte sur le même téléphone : le jeton est réenregistré pour le nouveau compte', () async {
    final (push, _, calls) = build();
    await push.start();
    await push.bindUser('1');
    await push.bindUser('2');
    expect(calls.where((c) => c.method == 'POST'), hasLength(2));
    await push.bindUser('2'); // même compte : aucun doublon
    expect(calls.where((c) => c.method == 'POST'), hasLength(2));
  });

  test('déconnexion : l’appareil est supprimé côté serveur, le jeton FCM invalidé, rien ne reste stocké', () async {
    final (push, gw, calls) = build();
    await push.start();
    await push.bindUser('1');
    await push.unregister();
    final del = calls.last;
    expect(del.method, 'DELETE');
    expect(del.path, '/handy/devices/41/');
    expect(del.auth, 'Bearer access-A'); // encore authentifié au moment du retrait
    expect(gw.tokensDeleted, 1);
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: PushService.deviceIdKey), isNull);
    expect(await storage.read(key: PushService.deviceTokenKey), isNull);
  });

  test('hors ligne : ni enregistrement ni retrait ne lèvent d’exception', () async {
    final (push, gw, _) = build(offline: true);
    await push.start();
    await push.bindUser('1');
    expect(push.status, PushStatus.error);
    await push.unregister();
    expect(gw.tokensDeleted, 1); // le jeton FCM est tout de même invalidé localement
  });

  test('erreur serveur : statut erreur, aucun identifiant mémorisé', () async {
    final (push, _, _) = build(status: 500);
    await push.start();
    await push.bindUser('1');
    expect(push.status, PushStatus.error);
    expect(await const FlutterSecureStorage().read(key: PushService.deviceIdKey), isNull);
  });

  test('messages : bandeau application ouverte, ouverture depuis l’arrière-plan et depuis le lancement', () async {
    final gw = FakeGateway()..launch = const PushMessage(title: 'Lancement', data: {'t': 'live'});
    final (push, _, _) = build(gateway: gw);
    final fg = <PushMessage>[];
    final taps = <PushMessage>[];
    push
      ..onForeground = fg.add
      ..onTap = taps.add;
    await push.start();
    expect(taps.single.title, 'Lancement'); // l'application a été lancée en touchant la notification
    gw.foreground.add(const PushMessage(title: 'Moussa est en route', body: 'Suivez son arrivée.', data: {'t': 'live', 'id': '12'}));
    gw.opened.add(const PushMessage(title: 'Réservation', data: {'t': 'booking'}));
    await Future<void>.delayed(Duration.zero);
    expect(fg.single.body, 'Suivez son arrivée.');
    expect(fg.single.data['id'], '12');
    expect(taps, hasLength(2));
  });
}
