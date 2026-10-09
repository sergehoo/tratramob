import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/design/design.dart';

Widget _host(Widget child) => MaterialApp(
      theme: TratraTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
    );

void main() {

  group('Jetons & thème', () {
    test('la marque reprend les valeurs de la landing', () {
      expect(TtColors.primary, const Color(0xFF2E8B57));
      expect(TtColors.accent, const Color(0xFFF6C90E));
      expect(TtColors.night, const Color(0xFF0B1210));
      expect(TtRadius.card, 24);
      expect(TtLayout.touchTarget, 44);
    });

    test('ColorScheme : texte blanc sur primaryDark (AA), Material 3', () {
      final theme = TratraTheme.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, TtColors.primaryDark);
      expect(theme.colorScheme.onPrimary, Colors.white);
      expect(theme.colorScheme.secondary, TtColors.accent);
    });
  });

  group('TratraButton', () {
    testWidgets('déclenche onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(TratraButton(label: 'Réserver', onPressed: () => taps++)));
      await tester.tap(find.text('Réserver'));
      expect(taps, 1);
    });

    testWidgets('désactivé quand onPressed est null', (tester) async {
      await tester.pumpWidget(_host(const TratraButton(label: 'Réserver', onPressed: null)));
      final semantics = tester.getSemantics(find.byType(TratraButton));
      expect(semantics.getSemanticsData().flagsCollection.isEnabled.toString(), isNot(contains('true')));
    });

    testWidgets('loading neutralise les appuis et affiche un spinner', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(TratraButton(label: 'Envoyer', loading: true, onPressed: () => taps++)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(TratraButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('respecte la cible tactile minimale de 44', (tester) async {
      await tester.pumpWidget(_host(TratraButton(label: 'OK', onPressed: () {})));
      expect(tester.getSize(find.byType(TratraButton)).height, greaterThanOrEqualTo(TtLayout.touchTarget));
    });
  });

  group('TratraInput', () {
    testWidgets('affiche étiquette, aide et erreur', (tester) async {
      await tester.pumpWidget(_host(const TratraInput(
        label: 'Téléphone',
        required: true,
        errorText: 'Numéro invalide',
      )));
      expect(find.textContaining('Téléphone'), findsOneWidget);
      expect(find.text('Numéro invalide'), findsOneWidget);
    });

    testWidgets('bascule l’affichage du mot de passe', (tester) async {
      await tester.pumpWidget(_host(const TratraInput(label: 'Mot de passe', obscureText: true)));
      EditableText editable() => tester.widget<EditableText>(find.byType(EditableText));
      expect(editable().obscureText, isTrue);
      await tester.tap(find.byTooltip('Afficher le mot de passe'));
      await tester.pump();
      expect(editable().obscureText, isFalse);
    });

    testWidgets('valide dans un Form', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(_host(Form(
        key: key,
        child: TratraInput(label: 'Nom', validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null),
      )));
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Requis'), findsOneWidget);
    });
  });

  group('TratraBadge / statuts', () {
    testWidgets('libellé français du statut de réservation', (tester) async {
      await tester.pumpWidget(_host(const TratraStatusBadge(TratraStatus.booking, 'confirmed')));
      expect(find.text('Confirmée'), findsOneWidget);
    });

    test('statut inconnu : valeur brute en gris', () {
      final v = TratraStatus.of(TratraStatus.booking, 'bizarre');
      expect(v.label, 'bizarre');
      expect(v.tone, TratraTone.gray);
    });
  });

  group('TratraBottomNav', () {
    testWidgets('notifie l’onglet touché et expose l’état sélectionné', (tester) async {
      var current = 0;
      await tester.pumpWidget(MaterialApp(
        theme: TratraTheme.light(),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            bottomNavigationBar: TratraBottomNav(
              currentIndex: current,
              onTap: (i) => setState(() => current = i),
              items: const [
                TratraNavItem(icon: Icons.home_outlined, label: 'Accueil'),
                TratraNavItem(icon: Icons.person_outline, label: 'Profil', badge: 3),
              ],
            ),
          ),
        ),
      ));
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.text('Profil'));
      await tester.pump();
      expect(current, 1);
    });
  });

  group('TratraEmptyState / Skeleton', () {
    testWidgets('affiche titre, description et action', (tester) async {
      await tester.pumpWidget(_host(TratraEmptyState(
        title: 'Aucune réservation',
        description: 'Vos réservations apparaîtront ici.',
        actions: [TratraButton(label: 'Trouver un service', onPressed: () {})],
      )));
      expect(find.text('Aucune réservation'), findsOneWidget);
      expect(find.text('Trouver un service'), findsOneWidget);
    });

    testWidgets('le squelette s’anime sans erreur', (tester) async {
      await tester.pumpWidget(_host(const TratraSkeletonList(count: 2)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TratraSkeletonCard), findsNWidgets(2));
    });
  });

  testWidgets('TratraAvatar : initiales quand il n’y a pas de photo', (tester) async {
    await tester.pumpWidget(_host(const TratraAvatar(name: 'Aya Konan')));
    expect(find.text('AK'), findsOneWidget);
  });

  testWidgets('TratraWordmark : nom « Tratra » en police de marque', (tester) async {
    await tester.pumpWidget(_host(const TratraWordmark(size: 32, onNight: true)));
    expect(find.bySemanticsLabel('Tratra'), findsOneWidget);
    final rich = tester.widget<RichText>(
        find.descendant(of: find.byType(TratraWordmark), matching: find.byType(RichText)));
    final wordmark = (rich.text as TextSpan).children!.single as TextSpan; // le style de marque est celui du TextSpan fourni
    expect(wordmark.style?.fontFamily, TtFont.brand);
    expect(TtFont.brand, 'Kaushan Script');
  });
}
