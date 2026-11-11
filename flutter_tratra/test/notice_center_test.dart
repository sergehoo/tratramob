// Rubans de notification, application ouverte : file d'attente sans superposition, dédoublonnage par identifiant d'évènement,
// priorité Tratra Flash, disparition automatique, pause pendant l'écran Tratra Flash, objets déjà à l'écran, ruban affiché
// (icône, catégorie, heure, titre, message, fermeture, toucher, glissement).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/deep_links.dart';
import 'package:flutter_tratra/notifications/notice_banner.dart';
import 'package:flutter_tratra/notifications/notice_center.dart';
import 'package:flutter_tratra/notifications/screen_presence.dart';
import 'package:flutter_tratra/services/push_service.dart';

PushMessage msg(int nid, {String cat = 'booking', String? link, String? body = 'Texte', String? messageId, DateTime? sent}) => PushMessage(
      title: 'Titre $nid',
      body: body,
      data: {'nid': '$nid', 'cat': cat, if (link != null) 'deeplink': link},
      messageId: messageId,
      sentTime: sent,
    );

PushMessage flash(int nid, {String link = 'tratra://flash_request/7'}) => msg(nid, cat: 'booking', link: link);

const second = Duration(seconds: 1);
const gap = Duration(milliseconds: 350);

/// Écran « objet » de test : s'annonce comme une conversation.
class _Object extends StatefulWidget {
  const _Object(this.target);
  final String target;
  @override
  State<_Object> createState() => _ObjectState();
}

class _ObjectState extends State<_Object> with ScreenPresenceMixin<_Object> {
  @override
  String get presenceTarget => widget.target;
  @override
  Widget build(BuildContext context) => Scaffold(body: Text('objet ${widget.target}'));
}

void main() {
  group('identifiant d\'évènement', () {
    test('évènement, puis notification, puis annonce, puis message FCM', () {
      expect(noticeKey(const PushMessage(data: {'eid': 'x1', 'nid': '4'}, messageId: 'm')), 'e:x1');
      expect(noticeKey(const PushMessage(data: {'nid': 4}, messageId: 'm')), 'n:4');
      expect(noticeKey(const PushMessage(data: {'t': 'announcement', 'id': '9', 'nid': '0'}, messageId: 'm')), 'a:9');
      expect(noticeKey(const PushMessage(data: {'nid': '0'}, messageId: 'm')), 'm:m');
      expect(noticeKey(const PushMessage(data: {'nid': ''})), isNull);
    });

    test('contenu du ruban : catégorie, priorité Tratra Flash, catégories discrètes', () {
      final booking = AppNotice.fromPush(msg(1))!;
      expect((booking.category, booking.priority, booking.quiet), ('booking', false, false));
      expect(AppNotice.fromPush(msg(2, cat: 'flash'))!.priority, isTrue);
      // Contre-offre, désistement, annulation : catégorie « réservation » mais lien vers la demande Tratra Flash → prioritaire.
      expect(AppNotice.fromPush(flash(3))!.priority, isTrue);
      expect(AppNotice.fromPush(msg(4, link: 'tratra://flash_offer/5'))!.priority, isTrue);
      final ann = AppNotice.fromPush(const PushMessage(title: 'Offre', data: {'t': 'announcement', 'id': '3'}))!;
      expect((ann.category, ann.quiet), ('announcement', true));
      expect(AppNotice.fromPush(const PushMessage(body: 'Seul', data: {}))!.title, 'Seul');
      expect(AppNotice.fromPush(const PushMessage(data: {'t': 'flash_closed'})), isNull);   // message de synchronisation : rien à afficher
      expect(booking.link.kind, DeepLinkKind.notifications);
    });
  });

  group('file d\'attente', () {
    testWidgets('un ruban à la fois, dans l\'ordre, 5 secondes chacun, jamais de superposition', (tester) async {
      final c = NoticeCenter()..attach();
      final shown = <String>[];
      c.onShow = (n, replay) => shown.add(n.title);
      expect(c.offer(msg(1)), isTrue);
      expect(c.offer(msg(2)), isTrue);
      expect(c.offer(msg(3)), isTrue);
      expect(c.current!.title, 'Titre 1');
      expect(c.waiting, 2);
      await tester.pump(const Duration(milliseconds: 4900));
      expect(c.current!.title, 'Titre 1');
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.current, isNull);                       // le premier sort avant que le suivant n'entre
      await tester.pump(gap);
      expect(c.current!.title, 'Titre 2');
      await tester.pump(second * 5 + gap);
      expect(c.current!.title, 'Titre 3');
      await tester.pump(second * 5 + gap);
      expect(c.current, isNull);
      expect(shown, ['Titre 1', 'Titre 2', 'Titre 3']);
      c.dispose();
    });

    testWidgets('même évènement reçu deux fois : un seul ruban ; sans identifiant, le message FCM départage', (tester) async {
      final c = NoticeCenter()..attach();
      expect(c.offer(msg(1)), isTrue);
      expect(c.offer(msg(1)), isFalse);
      expect(c.offer(const PushMessage(title: 'A', data: {}, messageId: 'fcm-1')), isTrue);
      expect(c.offer(const PushMessage(title: 'A', data: {}, messageId: 'fcm-1')), isFalse);
      expect(c.offer(const PushMessage(title: 'A', data: {}, messageId: 'fcm-2')), isTrue);
      expect(c.offer(const PushMessage(data: {'nid': '8'})), isFalse);   // aucun texte
      expect(c.waiting, 2);
      await tester.pump(second * 20);
      // Déjà affiché puis disparu : toujours pas de second ruban.
      expect(c.offer(msg(1)), isFalse);
      c.dispose();
    });

    testWidgets('Tratra Flash passe devant et remplace le ruban ordinaire en cours', (tester) async {
      final c = NoticeCenter()..attach();
      final shown = <(String, bool)>[];
      c.onShow = (n, replay) => shown.add((n.title, replay));
      c.offer(msg(1));
      c.offer(msg(2));
      await tester.pump(second * 3);                   // « Titre 1 » vu assez longtemps
      c.offer(flash(9));
      expect(c.current, isNull);
      await tester.pump(gap);
      expect(c.current!.title, 'Titre 9');
      expect(c.current!.priority, isTrue);
      await tester.pump(second * 5 + gap);
      expect(c.current!.title, 'Titre 2');             // « Titre 1 » n'est pas rejoué
      await tester.pump(second * 5 + gap);
      expect(shown, [('Titre 1', false), ('Titre 9', false), ('Titre 2', false)]);
      c.dispose();
    });

    testWidgets('ruban ordinaire à peine affiché puis remplacé : rejoué ensuite, sans second signal sonore', (tester) async {
      final c = NoticeCenter()..attach();
      final shown = <(String, bool)>[];
      c.onShow = (n, replay) => shown.add((n.title, replay));
      c.offer(msg(1));
      await tester.pump(second);
      c.offer(flash(9));
      c.offer(flash(10));                              // deux priorités : dans l'ordre d'arrivée, sans s'interrompre
      await tester.pump(gap);
      expect(c.current!.title, 'Titre 9');
      await tester.pump(second * 5 + gap);
      expect(c.current!.title, 'Titre 10');
      await tester.pump(second * 5 + gap);
      expect(c.current!.title, 'Titre 1');
      expect(shown, [('Titre 1', false), ('Titre 9', false), ('Titre 10', false), ('Titre 1', true)]);
      await tester.pump(second * 6);
      c.dispose();
    });

    testWidgets('file bornée : les plus anciens rubans ordinaires cèdent la place, jamais Tratra Flash', (tester) async {
      final c = NoticeCenter()..attach();
      final shown = <String>[];
      c.onShow = (n, replay) => shown.add(n.title);
      c.offer(flash(100));                             // affiché
      for (var i = 1; i <= 7; i++) {
        c.offer(msg(i));
      }
      c.offer(flash(101));
      expect(c.waiting, 5);
      await tester.pump(second * 60);
      expect(shown, ['Titre 100', 'Titre 101', 'Titre 4', 'Titre 5', 'Titre 6', 'Titre 7']);
      c.dispose();
    });

    testWidgets('écran Tratra Flash affiché : aucun ruban ; ils reprennent à sa fermeture', (tester) async {
      final c = NoticeCenter()..attach();
      final shown = <(String, bool)>[];
      c.onShow = (n, replay) => shown.add((n.title, replay));
      c.offer(msg(1));
      c.hold(true);
      expect(c.current, isNull);
      c.offer(msg(2));
      await tester.pump(second * 30);
      expect(c.current, isNull);
      c.hold(false);
      await tester.pump(gap);
      expect(c.current!.title, 'Titre 1');
      await tester.pump(second * 5 + gap);
      expect(c.current!.title, 'Titre 2');
      expect(shown, [('Titre 1', false), ('Titre 1', true), ('Titre 2', false)]);
      await tester.pump(second * 6);
      c.dispose();
    });

    testWidgets('ruban resté trop longtemps en attente : plus affiché (le centre de notifications le garde)', (tester) async {
      final c = NoticeCenter();                        // zone d'affichage absente : les rubans attendent
      c.offer(msg(1));
      await tester.pump(second * 60);
      expect(c.current, isNull);
      c.offer(msg(2));
      await tester.pump(second * 90);                  // « Titre 1 » attend depuis 2 min 30, « Titre 2 » depuis 1 min 30
      c.attach();
      expect(c.current!.title, 'Titre 2');
      await tester.pump(second * 6);
      c.dispose();
    });

    testWidgets('objet déjà à l\'écran : pas de ruban, y compris s\'il le devient pendant l\'attente', (tester) async {
      final c = NoticeCenter()..attach();
      var onScreen = <String>{};
      c.suppress = (n) => onScreen.contains(ScreenPresence.targetOf(n.link));
      onScreen = {'conversation:12'};
      expect(c.offer(msg(1, cat: 'message', link: 'tratra://conversation/12')), isFalse);
      expect(c.offer(msg(2, cat: 'message', link: 'tratra://conversation/13')), isTrue);
      expect(c.offer(msg(3, cat: 'message', link: 'tratra://conversation/14')), isTrue);
      onScreen = {'conversation:14'};                  // l'utilisateur ouvre la conversation 14 pendant que son ruban attend
      await tester.pump(second * 5 + gap);
      expect(c.current, isNull);
      expect(c.markSeen(msg(5)), isTrue);
      expect(c.markSeen(msg(5)), isFalse);
      expect(c.offer(msg(5)), isFalse);
      c.dispose();
    });

    testWidgets('toucher : ouvre une seule fois ; déconnexion : tout est oublié', (tester) async {
      final c = NoticeCenter()..attach();
      final opened = <String>[];
      c.onOpen = (n) => opened.add(n.title);
      c.offer(msg(1));
      c.open();
      expect(opened, ['Titre 1']);
      expect(c.current, isNull);
      c.open();                                        // plus de ruban : rien
      expect(opened, ['Titre 1']);
      expect(c.firstOpen(msg(1)), isFalse);            // déjà ouverte par le ruban
      expect(c.firstOpen(msg(2)), isTrue);             // touchée dans la barre du système
      expect(c.firstOpen(msg(2)), isFalse);            // remise une seconde fois par le système
      expect(c.offer(msg(2)), isFalse);                // déjà vue : pas de ruban en plus
      expect(c.firstOpen(const PushMessage(title: 'x', data: {})), isTrue);   // sans identifiant : toujours ouverte
      c.offer(msg(3));
      await c.clear();
      expect(c.current, isNull);
      expect(c.waiting, 0);
      expect(c.firstOpen(msg(1)), isTrue);
      await tester.pump(second);
      c.dispose();
    });
  });

  group('ruban affiché', () {
    Future<NoticeCenter> host(WidgetTester tester) async {
      final c = NoticeCenter();
      addTearDown(c.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<NoticeCenter>.value(
        value: c,
        child: MaterialApp(
          builder: (context, child) => NoticeHost(child: child!),
          home: const Scaffold(body: Center(child: Text('écran'))),
        ),
      ));
      return c;
    }

    testWidgets('icône, catégorie, heure, titre, message et bouton fermer ; disparition après 5 secondes', (tester) async {
      final c = await host(tester);
      c.offer(msg(1, body: 'Votre réservation est confirmée.', sent: DateTime(2026, 11, 11, 9, 5)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('RÉSERVATION'), findsOneWidget);
      expect(find.text('09:05'), findsOneWidget);
      expect(find.text('Titre 1'), findsOneWidget);
      expect(find.text('Votre réservation est confirmée.'), findsOneWidget);
      expect(find.byIcon(Icons.event_available_outlined), findsOneWidget);
      expect(find.bySemanticsLabel('Fermer la notification'), findsOneWidget);
      expect(find.text('écran'), findsOneWidget);      // l'écran reste dessous
      await tester.pump(second * 5);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(NoticeBanner), findsNothing);
    });

    testWidgets('Tratra Flash : ruban prioritaire à l\'éclair', (tester) async {
      final c = await host(tester);
      c.offer(flash(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('TRATRA FLASH'), findsOneWidget);
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      c.dismiss();
      await tester.pump();
      await tester.pump(second);
    });

    testWidgets('plusieurs notifications : jamais deux rubans à l\'écran, même pendant les animations', (tester) async {
      final c = await host(tester);
      c.offer(msg(1));
      c.offer(msg(2));
      c.offer(flash(3));
      final seen = <String>{};
      for (var i = 0; i < 340; i++) {                  // 17 secondes, par pas de 50 ms
        await tester.pump(const Duration(milliseconds: 50));
        final banners = tester.widgetList<NoticeBanner>(find.byType(NoticeBanner)).toList();
        expect(banners.length, lessThanOrEqualTo(1));
        seen.addAll(banners.map((b) => b.notice.title));
      }
      expect(seen, {'Titre 1', 'Titre 2', 'Titre 3'});
      expect(find.byType(NoticeBanner), findsNothing);
    });

    testWidgets('toucher ouvre l\'objet ; la croix et le glissement vers le haut ferment sans ouvrir', (tester) async {
      final c = await host(tester);
      final opened = <String>[];
      c.onOpen = (n) => opened.add(n.title);

      c.offer(msg(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Titre 1'));
      await tester.pump();
      await tester.pump(second);
      expect(opened, ['Titre 1']);
      expect(find.byType(NoticeBanner), findsNothing);

      c.offer(msg(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.bySemanticsLabel('Fermer la notification'));
      await tester.pump();
      await tester.pump(second);
      expect(find.byType(NoticeBanner), findsNothing);

      c.offer(msg(3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.drag(find.text('Titre 3'), const Offset(0, -60));
      await tester.pump();
      await tester.pump(second);
      expect(find.byType(NoticeBanner), findsNothing);
      expect(opened, ['Titre 1']);
    });
  });

  group('écrans déjà ouverts', () {
    setUp(ScreenPresence.reset);

    test('cible d\'un lien', () {
      expect(ScreenPresence.targetOf(parseDeepLink({'deeplink': 'tratra://conversation/12'})), 'conversation:12');
      expect(ScreenPresence.targetOf(parseDeepLink({'deeplink': 'tratra://flash_request/7'})), 'flash_request:7');
      expect(ScreenPresence.targetOf(parseDeepLink({'deeplink': 'tratra://booking/3'})), isNull);
    });

    testWidgets('écran visible, recouvert, puis retrouvé sans en empiler un second', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold(body: Text('accueil'))));
      expect(ScreenPresence.isVisible('conversation:12'), isFalse);
      expect(ScreenPresence.reveal('conversation:12'), isFalse);

      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const _Object('conversation:12')));
      await tester.pumpAndSettle();
      expect(ScreenPresence.isVisible('conversation:12'), isTrue);
      expect(ScreenPresence.isVisible('conversation:13'), isFalse);

      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('détail'))));
      await tester.pumpAndSettle();
      expect(ScreenPresence.isVisible('conversation:12'), isFalse);   // recouvert : le ruban est affiché

      expect(ScreenPresence.reveal('conversation:12'), isTrue);       // notification touchée : retour sur l'écran ouvert
      await tester.pumpAndSettle();
      expect(find.text('objet conversation:12'), findsOneWidget);
      expect(find.text('détail'), findsNothing);
      expect(ScreenPresence.isVisible('conversation:12'), isTrue);

      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(ScreenPresence.isVisible('conversation:12'), isFalse);
      expect(ScreenPresence.reveal('conversation:12'), isFalse);
    });
  });
}
