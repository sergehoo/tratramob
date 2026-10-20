// Saisie du téléphone (Flutter) : [drapeau ▼] + numéro national, normalisation E.164 identique au web et à Django (libphonenumber),
// pays présélectionné (préférence, SIM, région, IP connue, Côte d'Ivoire), sélecteur avec recherche, petits écrans.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart' show IsoCode;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tratra/core/phone/phone_value.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/auth/otp_screen.dart' show maskPhone;

const _device = MethodChannel('tratra/device');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('normalisation', () {
    test('numéro national + pays → E.164, sans jamais saisir l’indicatif', () {
      expect(const PhoneValue(IsoCode.CI, '07 00 00 00 00').e164, '+2250700000000');
      expect(const PhoneValue(IsoCode.CI, '0594977511').e164, '+2250594977511');
      expect(const PhoneValue(IsoCode.FR, '06 12 34 56 78').e164, '+33612345678');
      expect(const PhoneValue(IsoCode.SN, '77 123 45 67').e164, '+221771234567');
      expect(const PhoneValue(IsoCode.CI, '07 00').e164, isNull);
    });

    test('messages clairs avec le pays et un exemple', () {
      expect(PhoneValue.empty.error(), 'Saisissez votre numéro de téléphone.');
      expect(const PhoneValue(IsoCode.CI, '07 00').error(), 'Numéro trop court pour Côte d’Ivoire. Exemple : 07 00 00 00 00.');
      expect(const PhoneValue(IsoCode.FR, '06 12 34 56 78 90 12').error(), startsWith('Numéro trop long pour France.'));
      expect(const PhoneValue(IsoCode.CI, '0700000000').error(), isNull);
    });

    test('recherche tolérante (connexion, récupération) : un ancien numéro hors norme reste transmis', () {
      expect(const PhoneValue(IsoCode.CI, '07 12 34 56').lookupE164, '+22507123456');
      expect(const PhoneValue(IsoCode.CI, '0700000000').lookupE164, '+2250700000000');
      expect(const PhoneValue(IsoCode.CI, '07').lookupE164, isNull);
    });

    test('mise en forme pendant la saisie', () {
      expect(formatNational('0700000000', IsoCode.CI), '07 00 00 00 00');
      expect(formatNational('07000000001234', IsoCode.CI), '07 00 00 00 00');
      expect(formatNational('0612345678', IsoCode.FR), '06 12 34 56 78');
      expect(exampleNational(IsoCode.CI), '07 00 00 00 00');
      expect(exampleNational(IsoCode.FR), isNotEmpty);
    });

    test('numéro collé avec son indicatif : le pays suit ; affichage et masquage', () {
      final fr = PhoneValue.splitInternational('+33 6 12 34 56 78')!;
      expect((fr.iso, fr.national), (IsoCode.FR, '06 12 34 56 78'));
      expect(PhoneValue.splitInternational('00225 07 00 00 00 00')!.iso, IsoCode.CI);
      expect(PhoneValue.splitInternational('07 00 00 00 00'), isNull);
      expect(PhoneValue.fromE164('+2250700000000').national, '07 00 00 00 00');
      expect(PhoneValue.fromE164(null).iso, IsoCode.CI);
      expect(displayPhone('+2250700000000'), '+225 07 00 00 00 00');
      expect(displayPhone('+33612345678'), '+33 6 12 34 56 78');
      expect(maskPhone('+2250700000002'), '+225 •• •• •• 02');
      expect(maskPhone('+33612345678'), '+33 •• •• •• 78');
    });

    test('pays : noms français, drapeau, indicatif ; recherche sans accents, par code ou indicatif', () {
      final all = allPhoneCountries();
      expect(all.length, greaterThan(200));
      final ci = all.firstWhere((c) => c.iso == IsoCode.CI);
      expect((ci.name, ci.dial, ci.flag), ('Côte d’Ivoire', '225', flagOf('CI')));
      expect(searchPhoneCountries('cote').first.iso, IsoCode.CI);
      expect(searchPhoneCountries('+225').first.iso, IsoCode.CI);
      expect(searchPhoneCountries('etats').first.iso, IsoCode.US);
      expect(searchPhoneCountries('sn').first.iso, IsoCode.SN);
    });
  });

  group('pays présélectionné', () {
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_device, null));

    void sim(String? code) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_device, (call) async => call.method == 'simCountry' ? code : null);

    test('préférence enregistrée > carte SIM > région de l’appareil > IP connue > Côte d’Ivoire', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sim('SN');
      SharedPreferences.setMockInitialValues({'tratra.phone.country': 'FR'});
      expect(await resolveDefaultPhoneCountry(deviceRegion: 'BE'), IsoCode.FR);
      SharedPreferences.setMockInitialValues({});
      expect(await resolveDefaultPhoneCountry(deviceRegion: 'BE'), IsoCode.SN);
      sim(null);
      expect(await resolveDefaultPhoneCountry(deviceRegion: 'BE'), IsoCode.BE);
      expect(await resolveDefaultPhoneCountry(deviceRegion: 'ZZ', ipRegion: () async => 'GH'), IsoCode.GH);
      expect(await resolveDefaultPhoneCountry(deviceRegion: '', ipRegion: () async => null), IsoCode.CI);
      await rememberPhoneCountry(IsoCode.ML);
      expect(await resolveDefaultPhoneCountry(deviceRegion: 'BE'), IsoCode.ML);
    });
  });

  group('champ', () {
    Widget host(ValueNotifier<PhoneValue> v, {bool autoCountry = false}) => MaterialApp(
          theme: TratraTheme.light(),
          home: Scaffold(
            body: ValueListenableBuilder<PhoneValue>(
              valueListenable: v,
              builder: (_, value, __) => Padding(
                padding: const EdgeInsets.all(16),
                child: TratraPhoneField(value: value, autoCountry: autoCountry, onChanged: (n) => v.value = n, errorText: value.isEmpty ? null : value.error()),
              ),
            ),
          ),
        );

    testWidgets('drapeau et indicatif affichés ; saisie nationale mise en forme', (t) async {
      final v = ValueNotifier(PhoneValue.empty);
      await t.pumpWidget(host(v));
      expect(find.text('+225'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Pays : Côte d’Ivoire, indicatif \\+225')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('phone-national')), '0700000000');
      await t.pump();
      expect(v.value.national, '07 00 00 00 00');
      expect(v.value.e164, '+2250700000000');
      expect(t.widget<EditableText>(find.byType(EditableText)).controller.text, '07 00 00 00 00');   // l'exemple reste en indication
    });

    testWidgets('numéro collé avec son indicatif : le pays change tout seul', (t) async {
      final v = ValueNotifier(PhoneValue.empty);
      await t.pumpWidget(host(v));
      await t.enterText(find.byKey(const ValueKey('phone-national')), '+33612345678');
      await t.pump();
      expect(v.value.iso, IsoCode.FR);
      expect(find.text('+33'), findsOneWidget);
      expect(v.value.e164, '+33612345678');
    });

    testWidgets('sélecteur : recherche « sene », choix du Sénégal, préférence retenue', (t) async {
      final v = ValueNotifier(PhoneValue.empty);
      await t.pumpWidget(host(v));
      await t.tap(find.byKey(const ValueKey('phone-country')));
      await t.pumpAndSettle();
      expect(find.text('Choisir le pays'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('country-search')), 'sene');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('country-SN')), findsOneWidget);
      expect(find.byKey(const ValueKey('country-FR')), findsNothing);
      await t.tap(find.byKey(const ValueKey('country-SN')));
      await t.pumpAndSettle();
      expect(v.value.iso, IsoCode.SN);
      expect(find.text('+221'), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getString('tratra.phone.country'), 'SN');
    });

    testWidgets('pays déduit au démarrage quand rien n’est saisi (préférence enregistrée)', (t) async {
      SharedPreferences.setMockInitialValues({'tratra.phone.country': 'GH'});
      final v = ValueNotifier(PhoneValue.empty);
      await t.pumpWidget(host(v, autoCountry: true));
      await t.pumpAndSettle();
      expect(v.value.iso, IsoCode.GH);
      expect(find.text('+233'), findsOneWidget);
    });

    testWidgets('message d’erreur clair et accessible', (t) async {
      final v = ValueNotifier(const PhoneValue(IsoCode.CI, '07 00'));
      await t.pumpWidget(host(v));
      expect(find.text('Numéro trop court pour Côte d’Ivoire. Exemple : 07 00 00 00 00.'), findsOneWidget);
    });

    testWidgets('petit écran, texte agrandi : champ et liste des pays sans débordement', (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final v = ValueNotifier(const PhoneValue(IsoCode.CI, '07 00 00 00 00'));
      await t.pumpWidget(host(v));
      await t.tap(find.byKey(const ValueKey('phone-country')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('country-search')), 'r');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
