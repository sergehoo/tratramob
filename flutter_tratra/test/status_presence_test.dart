// Anneaux des statuts, comme WhatsApp : un segment par statut (vert non vu, gris vu), présence partagée par toute l'application, avatar qui
// ouvre les statuts du membre, pastille de l'icône, écran « Actualités » (Mon statut, Récentes, Vues) et identifiant du compte d'un artisan.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';
import 'package:flutter_tratra/messaging/messaging_api.dart';
import 'package:flutter_tratra/models/artisan.dart';
import 'package:flutter_tratra/statuses/status_api.dart';
import 'package:flutter_tratra/statuses/status_bar.dart';
import 'package:flutter_tratra/statuses/status_presence.dart';
import 'package:flutter_tratra/statuses/status_viewer.dart';
import 'package:flutter_tratra/statuses/statuses_screen.dart';

import 'statuses_test.dart' show Server, apiFor, authorGroup, feedPayload, status, tall;

Widget hostWithPresence(Server s, Widget child, {void Function(StatusPresence)? onPresence}) {
  final base = apiFor(s);
  final api = StatusApi(base);
  final inbox = InboxController(base, MessagingApi(base));
  final presence = StatusPresence(api, inbox)..bindUser('1');
  onPresence?.call(presence);
  return MultiProvider(
    providers: [
      Provider<StatusApi>.value(value: api),
      Provider<MessagingApi>.value(value: MessagingApi(base)),
      ChangeNotifierProvider<InboxController>.value(value: inbox),
      ChangeNotifierProvider<StatusPresence>.value(value: presence),
    ],
    child: MaterialApp(theme: TratraTheme.light(), home: Scaffold(body: child)),
  );
}

void main() {
  test('anneau : un segment par statut (30 au plus), les non vus en dernier', () {
    final p = StatusRingPainter(count: 3, unseen: 2);
    expect((p.segments, p.unseen), (3, 2));
    expect(StatusRingPainter(count: 50, unseen: 50).segments, 30);
    expect(StatusRingPainter(count: 0, unseen: 4).unseen, 1);              // au moins un segment, jamais plus de non vus que de segments
    expect(const StatusRing(unseen: true, count: 4, child: SizedBox()).unseenCount, 4);
    expect(const StatusRing(unseen: false, count: 4, child: SizedBox()).unseenCount, 0);
  });

  testWidgets('présence : anneau sur l\'avatar d\'un membre qui a un statut, avatar simple sinon ; le toucher ouvre ses statuts', (t) async {
    final s = Server()
      ..presence = [
        {'id': 7, 'count': 2, 'unseen': 1, 'mine': false},
        {'id': 1, 'count': 1, 'unseen': 0, 'mine': true},
      ]
      ..authors = {7: authorGroup(7, 'Awa K.', [status(11, seen: true), status(12)])};
    late StatusPresence presence;
    await t.pumpWidget(hostWithPresence(
      s,
      const Column(children: [StatusAvatar(userId: 7, name: 'Awa K.'), StatusAvatar(userId: 8, name: 'Moussa A.')]),
      onPresence: (p) => presence = p,
    ));
    await t.pumpAndSettle();
    expect(presence.hasUnseen, isTrue);
    expect(find.byKey(const ValueKey('status-avatar-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('status-avatar-8')), findsNothing);   // aucun statut : pas d'anneau
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Statuts de Awa K., 1 non lu'), findsOneWidget);
    final ring = t.widget<StatusRing>(find.byType(StatusRing));
    expect((ring.count, ring.unseenCount), (2, 1));
    await t.tap(find.byKey(const ValueKey('status-avatar-7')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(s.requests.any((r) => r.url.path.endsWith('/statuses/authors/7/')), isTrue);
    expect(find.byType(StatusViewerScreen), findsOneWidget);
  });

  testWidgets('présence : seuls les statuts des AUTRES membres allument la pastille ; changement de compte = rien de l\'ancien', (t) async {
    final s = Server()..presence = [{'id': 1, 'count': 2, 'unseen': 0, 'mine': true}];
    late StatusPresence presence;
    await t.pumpWidget(hostWithPresence(s, const SizedBox(), onPresence: (p) => presence = p));
    await t.pumpAndSettle();
    expect(presence.of(1)?.count, 2);
    expect(presence.hasUnseen, isFalse);
    presence.bindUser('2');
    expect(presence.of(1), isNull);
  });

  testWidgets('écran des statuts : « Actualités » avec Mon statut, Récentes puis Vues, contacts et membres publics réunis', (t) async {
    tall(t);
    final s = Server()
      ..feed = feedPayload(contacts: [authorGroup(7, 'Awa K.', [status(1, seen: true)]), authorGroup(8, 'Moussa A.', [status(2)])], discover: 1)
      ..discover = [authorGroup(9, 'Koffi B.', [status(3)])];
    await t.pumpWidget(hostWithPresence(s, const StatusesScreen()));
    await t.pumpAndSettle();
    expect(find.text('Actualités'), findsOneWidget);
    expect(find.text('Mon statut'), findsOneWidget);
    expect(find.text('Appuyez pour ajouter un statut'), findsOneWidget);
    final texts = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().toList();
    expect(texts.indexOf('RÉCENTES'), lessThan(texts.indexOf('Moussa A.')));
    expect(texts.indexOf('Koffi B.'), lessThan(texts.indexOf('VUES')));        // non vus (contact et public) avant les vus
    expect(texts.indexOf('VUES'), lessThan(texts.indexOf('Awa K.')));
    expect(find.textContaining('Partagé avec tous'), findsOneWidget);            // membre public signalé, pas un contact
    expect(s.requests.where((r) => r.url.path.endsWith('/view/')), isEmpty);    // afficher la liste ne compte aucune vue
  });

  test('artisan : identifiant du compte lu depuis « user », « user_detail » ou « user_id »', () {
    expect(Artisan.fromJson({'id': 3, 'user': 41}).userId, 41);
    expect(Artisan.fromJson({'id': 3, 'user_detail': {'id': 42}}).userId, 42);
    expect(Artisan.fromJson({'id': 3, 'user_id': '43'}).userId, 43);
    expect(Artisan.fromJson({'id': 3}).userId, isNull);
  });
}
