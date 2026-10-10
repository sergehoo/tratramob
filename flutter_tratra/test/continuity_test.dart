// Continuité des activités : aucune demande, réservation ni mission perdue après fermeture, déconnexion, coupure réseau,
// plantage ou changement de téléphone ; rien de critique affiché comme réussi sans confirmation du serveur.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_tratra/continuity/activities_controller.dart';
import 'package:flutter_tratra/continuity/activity.dart';
import 'package:flutter_tratra/continuity/drafts.dart';
import 'package:flutter_tratra/continuity/offline_queue.dart';
import 'package:flutter_tratra/continuity/vault.dart';
import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/models/booking.dart';
import 'package:flutter_tratra/services/auth_service.dart';
import 'package:flutter_tratra/services/storage_service.dart';

Map<String, dynamic> mission({int id = 7, String status = 'in_progress', bool active = true, String title = 'Dépannage fuite', int version = 2}) => {
      'kind': 'mission',
      'id': id,
      'role': 'handyman',
      'status': status,
      'status_label': status == 'in_progress' ? 'En cours' : 'Annulé',
      'version': version,
      'title': title,
      'counterpart': 'Awa K.',
      'booking_date': '2026-10-11T09:00:00Z',
      'city': 'Abidjan',
      'updated_at': '2026-10-10T10:00:00Z',
      'active': active,
      'deeplink': 'tratra://mission/$id',
      'resume_label': 'Reprendre ma mission',
    };

Map<String, dynamic> payload(List<Map<String, dynamic>> items, {String time = '2026-10-10T10:00:00Z', List<Map<String, dynamic>> changes = const []}) => {
      'server_time': time,
      'has_active': items.isNotEmpty,
      'primary': items.isEmpty ? null : items.first,
      'activities': items,
      if (changes.isNotEmpty) 'changes': changes,
    };

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('modèles et erreurs typées', () {
    test('activité : lecture et sérialisation du cache', () {
      final a = Activity.fromJson(mission());
      expect((a.kind, a.id, a.role, a.version, a.isMission, a.key), ('mission', 7, 'handyman', 2, true, 'mission:7'));
      expect(Activity.fromJson(a.toJson()).toJson(), a.toJson());
      expect(Activity.fromJson({'id': 'x'}).title, 'Intervention'); // payload partiel : jamais de plantage
    });

    test('Booking porte la version vue (1 par défaut)', () {
      expect(Booking.fromJson({'id': 3, 'status': 'pending', 'client': 1, 'handyman': 2, 'service': 4, 'version': 5}).version, 5);
      expect(Booking.fromJson({'id': 3, 'status': 'pending', 'client': 1, 'handyman': 2, 'service': 4}).version, 1);
    });

    test('ApiException : conflit de version et doublon de réservation', () {
      final conflict = ApiException.fromResponse(http.Response(jsonEncode({'code': 'version_conflict', 'detail': 'Modifiée'}), 409));
      expect((conflict.isVersionConflict, conflict.code), (true, 'version_conflict'));
      final dup = ApiException.fromResponse(http.Response(jsonEncode({'code': 'duplicate_booking', 'detail': 'Déjà', 'existing_id': 31}), 409));
      expect((dup.existingBookingId, dup.isVersionConflict), (31, false));
      final plain = ApiException.fromResponse(http.Response(jsonEncode({'detail': 'Refusé'}), 400));
      expect((plain.code, plain.isVersionConflict, plain.existingBookingId), (null, false, null));
      expect(ApiException.fromResponse(http.Response('pas du json', 500)).code, isNull);
    });
  });

  group('activités : reprise', () {
    test('le dernier état connu s’affiche AVANT la réponse du serveur, puis le serveur fait foi', () async {
      final vault = ContinuityVault();
      await vault.write('1', 'activities', {
        'synced_at': '2026-10-10T09:00:00Z',
        'cursor': '2026-10-10T09:00:00Z',
        'items': [Activity.fromJson(mission(status: 'confirmed')).toJson()],
      });
      final gate = Completer<Map<String, dynamic>>();
      final c = ActivitiesController(fetch: (_) => gate.future, vault: vault);
      final done = c.bindUser('1');
      await settle();
      expect(c.items.single.status, 'confirmed'); // application rouverte : la mission est là immédiatement
      expect(c.fromCache, isTrue);
      gate.complete(payload([mission(status: 'in_progress')]));
      await done;
      expect((c.items.single.status, c.fromCache, c.offline), ('in_progress', false, false));
      expect(c.primary!.deeplink, 'tratra://mission/7');
    });

    test('hors ligne : état connu conservé et signalé, nouvelle tentative automatique au retour du réseau', () async {
      final vault = ContinuityVault();
      var online = false;
      var calls = 0;
      final c = ActivitiesController(
        vault: vault,
        retryBase: const Duration(milliseconds: 20),
        retryMax: const Duration(milliseconds: 40),
        fetch: (_) async {
          calls++;
          if (!online) throw http.ClientException('réseau coupé');
          return payload([mission()]);
        },
      );
      online = true;
      await c.bindUser('1'); // première synchro réussie
      expect(c.items, hasLength(1));
      online = false;
      await c.refresh(force: true);
      expect(c.offline, isTrue);
      expect(c.items.single.id, 7); // jamais vidé par une coupure
      expect(c.syncedAt, isNotNull);
      online = true; // le réseau revient : aucune action de l'utilisateur
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect((c.offline, c.items.single.id), (false, 7));
      expect(calls, greaterThanOrEqualTo(3));
    });

    test('plantage / redémarrage : une nouvelle instance retrouve l’état et demande les changements depuis la dernière synchro', () async {
      final vault = ContinuityVault();
      final first = ActivitiesController(vault: vault, fetch: (_) async => payload([mission()], time: '2026-10-10T10:00:00Z'));
      await first.bindUser('1');
      final paths = <String>[];
      final second = ActivitiesController(vault: vault, fetch: (p) async {
        paths.add(p);
        return payload([], time: '2026-10-10T11:00:00Z', changes: [mission(status: 'cancelled', active: false)]);
      });
      await second.bindUser('1');
      expect(paths.single, '/me/activities/?since=2026-10-10T10%3A00%3A00Z');
      expect(second.items, isEmpty);
      expect(second.notice, contains('Dépannage fuite')); // la mission a été annulée pendant que l’application était fermée
      second.clearNotice();
      expect(second.notice, isNull);
    });

    test('changement de compte : aucune donnée du compte précédent, réponse tardive ignorée', () async {
      final vault = ContinuityVault();
      final slow = Completer<Map<String, dynamic>>();
      var user = '1';
      final c = ActivitiesController(vault: vault, fetch: (_) {
        if (user == '1') return Future.value(payload([mission(id: 1)]));
        return slow.future;
      });
      await c.bindUser('1');
      expect(c.items.single.id, 1);
      user = '2';
      final pending = c.bindUser('2');
      await settle();
      expect(c.items, isEmpty); // compte 2 : état vide, pas celui du compte 1
      await c.bindUser(null);
      slow.complete(payload([mission(id: 99)])); // réponse tardive du compte 2 alors qu'il est déconnecté
      await pending;
      expect(c.items, isEmpty);
      expect(await vault.read('2', 'activities'), isNull);
    });

    test('retour au premier plan : nouvelle synchro ; la synchro réussie déclenche le vidage de la file', () async {
      var calls = 0;
      var flushed = 0;
      final c = ActivitiesController(vault: ContinuityVault(), fetch: (_) async {
        calls++;
        return payload([mission()]);
      })
        ..onSynced = () async => flushed++;
      await c.bindUser('1');
      expect((calls, flushed), (1, 1));
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
      expect((calls, flushed), (2, 2));
      c.dispose();
    });

    test('anti-rafale : plusieurs relèves rapprochées = une seule requête (sauf reprise forcée)', () async {
      var calls = 0;
      final c = ActivitiesController(vault: ContinuityVault(), fetch: (_) async {
        calls++;
        return payload([mission()]);
      });
      await c.bindUser('1');
      await c.refresh();
      await c.refresh();
      expect(calls, 1);
    });

    test('déconnexion volontaire : mémoire et coffre vidés', () async {
      final vault = ContinuityVault();
      final c = ActivitiesController(vault: vault, fetch: (_) async => payload([mission()]));
      await c.bindUser('1');
      expect(await vault.read('1', 'activities'), isNotNull);
      await c.wipe();
      expect(c.items, isEmpty);
      expect(c.primary, isNull);
      expect(c.userId, isNull);
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
    });
  });

  group('file hors ligne : actions sûres uniquement', () {
    OfflineQueue queue(List<int> codes, List<String> sent, {ContinuityVault? vault, bool offline = false}) {
      final it = codes.iterator;
      return OfflineQueue(
        vault: vault ?? ContinuityVault(),
        send: (a) async {
          if (offline) throw http.ClientException('réseau coupé');
          sent.add('${a.method} ${a.path}');
          return it.moveNext() ? it.current : 200;
        },
      );
    }

    test('les actions critiques sont REFUSÉES : jamais rejouées en silence', () async {
      final q = queue([], []);
      await q.bindUser('1');
      for (final (m, p) in [
        ('POST', '/bookings/'),
        ('POST', '/bookings/5/transition/'),
        ('POST', '/payments/initiate/'),
        ('DELETE', '/devices/3/'),
        ('PATCH', '/bookings/5/'),
        ('POST', '/me/announcements/4/dismiss/'),
      ]) {
        expect(() => q.enqueue(m, p, {'status': 'completed'}), throwsArgumentError, reason: '$m $p');
      }
      expect(() => q.enqueue('PATCH', '/notifications/3/', {'is_read': false}), throwsArgumentError); // pas de « dé-lecture »
      expect(q.pending, 0);
    });

    test('hors ligne : conservée dans l’ordre, persistée, rejouée au retour du réseau', () async {
      final vault = ContinuityVault();
      final off = queue([], [], vault: vault, offline: true);
      await off.bindUser('1');
      await off.enqueue('PATCH', '/notifications/3/', {'is_read': true});
      await off.enqueue('POST', '/me/announcements/4/seen/');
      await off.enqueue('POST', '/me/announcements/4/seen/'); // doublon exact : fusionné
      expect(off.pending, 2);
      expect(off.items.first.attempts, greaterThanOrEqualTo(1)); // chaque ajout retente l'envoi, la panne est comptée

      final sent = <String>[];
      final back = queue([], sent, vault: vault); // l'application a redémarré, le réseau est revenu
      await back.bindUser('1');
      expect(back.pending, 2); // retrouvée sur le disque
      await back.flush();
      expect(sent, ['PATCH /notifications/3/', 'POST /me/announcements/4/seen/']); // dans l'ordre
      expect(back.pending, 0);
      expect(await vault.read('1', 'queue'), isNull);
    });

    test('codes de réponse : définitif = abandon, conflit = signalé, panne = conservée', () async {
      final sent = <String>[];
      final q = queue([404, 409, 500, 200], sent);
      await q.bindUser('1');
      await q.enqueue('PATCH', '/notifications/1/', {'is_read': true}); // 404 : abandonnée (n'existe plus)
      expect(q.pending, 0);
      await q.enqueue('PATCH', '/notifications/2/', {'is_read': true}); // 409 : abandonnée et signalée
      expect(q.pending, 0);
      expect(q.lastProblem, isNotNull);
      q.clearProblem();
      await q.enqueue('PATCH', '/notifications/3/', {'is_read': true}); // 500 : conservée, rien n'est perdu
      expect(q.pending, 1);
      await q.flush(); // le serveur répond de nouveau
      expect(q.pending, 0);
    });

    test('isolation par compte et effacement à la déconnexion volontaire', () async {
      final vault = ContinuityVault();
      final q = queue([], [], vault: vault, offline: true);
      await q.bindUser('1');
      await q.enqueue('POST', '/notifications/mark-read/', {});
      expect(await vault.read('1', 'queue'), isNotNull);
      await q.bindUser('2');
      expect(q.pending, 0); // le compte 2 ne voit pas la file du compte 1
      await q.bindUser('1');
      expect(q.pending, 1);
      await q.wipe();
      expect(q.pending, 0);
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
    });

    test('actions trop anciennes (> 7 jours) abandonnées au chargement', () async {
      final vault = ContinuityVault();
      final old = QueuedAction(method: 'POST', path: '/notifications/mark-read/', createdAt: DateTime.now().subtract(const Duration(days: 8)));
      await vault.write('1', 'queue', [old.toJson()]);
      final q = queue([], [], vault: vault);
      await q.bindUser('1');
      expect(q.pending, 0);
    });
  });

  group('brouillons de réservation', () {
    BookingDraft draft({String address = 'Rue 12', String base = 'abc123'}) =>
        BookingDraft(serviceId: '4', base: base, date: DateTime.utc(2026, 10, 12), hour: 9, minute: 30, address: address, city: 'Abidjan', postalCode: '00225');

    test('même demande = même clé (renvoi après plantage) ; contenu modifié = nouvelle clé', () {
      expect(draft().idempotencyKey, draft().idempotencyKey);
      expect(draft().idempotencyKey, isNot(draft(address: 'Rue 13').idempotencyKey));
      expect(draft().idempotencyKey, isNot(draft(base: 'autre').idempotencyKey));
      expect(RegExp(r'^[A-Za-z0-9_\-:.]{8,80}$').hasMatch(draft().idempotencyKey), isTrue); // accepté par le serveur
      expect(fingerprint('a'), fingerprint('a'));
      expect(randomHex(12), isNot(randomHex(12)));
    });

    test('un brouillon survit au redémarrage, est cloisonné par compte et effacé après succès', () async {
      final vault = ContinuityVault();
      final store = DraftStore(vault);
      await store.save('1', draft());
      expect((await DraftStore(vault).load('1', '4'))!.address, 'Rue 12');
      expect(await store.load('2', '4'), isNull); // autre compte du même téléphone
      expect(await store.load('1', '5'), isNull); // autre service
      await store.discard('1', '4');
      expect(await store.load('1', '4'), isNull);
    });

    test('un brouillon vide n’est pas conservé ; un brouillon périmé est supprimé', () async {
      final store = DraftStore(ContinuityVault());
      await store.save('1', BookingDraft(serviceId: '4', base: 'b', date: DateTime.utc(2026, 10, 12), hour: 9, minute: 0));
      expect(await store.load('1', '4'), isNull);
      await store.save('1', draft());
      expect(await store.load('1', '4', now: DateTime.now().add(const Duration(days: 8))), isNull);
      expect(await store.load('1', '4'), isNull); // supprimé, pas seulement masqué
    });
  });

  group('déconnexion', () {
    Session session(ContinuityVault vault, {bool revokeFails = false}) {
      FlutterSecureStorage.setMockInitialValues({AppConstants.authTokenKey: 'a', AppConstants.refreshTokenKey: 'r'});
      final api = BaseApi(client: MockClient((r) async => revokeFails ? throw http.ClientException('hors ligne') : http.Response('{}', 200)));
      final s = Session(AuthService(api), StorageService());
      s.addLogoutWipe(vault.wipeAll);
      return s;
    }

    test('déconnexion volontaire : jetons ET données de continuité effacés, même si la révocation échoue hors ligne', () async {
      final vault = ContinuityVault();
      final s = session(vault, revokeFails: true);
      await vault.write('1', 'draft.4', draft2());
      await vault.write('1', 'queue', []);
      await s.logout();
      final left = await const FlutterSecureStorage().readAll();
      expect(left.keys.where((k) => k.startsWith('cont.')), isEmpty);
      expect(left[AppConstants.authTokenKey], isNull);
    });

    test('sans déconnexion volontaire (session expirée) rien n’est effacé : brouillons retrouvés à la reconnexion', () async {
      final vault = ContinuityVault();
      session(vault);
      await vault.write('1', 'draft.4', draft2());
      await const FlutterSecureStorage().delete(key: AppConstants.authTokenKey); // jeton expiré : simple purge des jetons
      expect(await vault.read('1', 'draft.4'), isNotNull);
    });
  });
}

Map<String, dynamic> draft2() => BookingDraft(serviceId: '4', base: 'b', date: DateTime.utc(2026, 10, 12), hour: 9, minute: 0, address: 'Rue 12').toJson();
