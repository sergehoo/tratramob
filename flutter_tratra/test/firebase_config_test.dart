// Configuration Firebase injectée au build : complète ou absente, jamais à moitié ; aucun secret dans Git.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/services/firebase_config.dart';

const _full = {
  'projectId': 'tratra-test',
  'senderId': '123456789',
  'apiKeyAndroid': 'android-key',
  'appIdAndroid': '1:123456789:android:abc',
  'apiKeyIos': 'ios-key',
  'appIdIos': '1:123456789:ios:def',
  'iosBundleId': 'com.tratra',
  'storageBucket': '',
};

void main() {
  test('options Android et iOS complètes', () {
    final a = firebaseOptionsFor(TargetPlatform.android, _full)!;
    expect((a.projectId, a.appId, a.messagingSenderId), ('tratra-test', '1:123456789:android:abc', '123456789'));
    final i = firebaseOptionsFor(TargetPlatform.iOS, _full)!;
    expect((i.iosBundleId, i.appId), ('com.tratra', '1:123456789:ios:def'));
  });

  test('une valeur obligatoire manquante → null (repli sur la configuration native, jamais d’options à moitié renseignées)', () {
    for (final k in ['projectId', 'senderId', 'apiKeyAndroid', 'appIdAndroid']) {
      expect(firebaseOptionsFor(TargetPlatform.android, {..._full, k: ''}), isNull, reason: k);
    }
    expect(firebaseOptionsFor(TargetPlatform.iOS, {..._full, 'iosBundleId': ''}), isNull);
    expect(firebaseOptionsFor(TargetPlatform.android, {..._full, 'appIdAndroid': '  '}), isNull);
    expect(firebaseOptionsFor(TargetPlatform.android, const {}), isNull);
    expect(firebaseOptionsFor(TargetPlatform.macOS, _full), isNull); // plateforme non prise en charge
  });

  test('sans --dart-define, aucune option (valeurs de compilation vides)', () {
    expect(firebaseOptionsFor(TargetPlatform.android), isNull);
    expect(firebaseOptionsFor(TargetPlatform.iOS), isNull);
  });

  test('aucun fichier ni secret Firebase / signature n’est suivi par Git', () async {
    final git = await Process.run('git', ['ls-files'], workingDirectory: Directory.current.path);
    if (git.exitCode != 0) return; // pas de dépôt Git (copie sans historique)
    final files = (git.stdout as String).split('\n');
    final bad = files.where((f) => RegExp(r'(google-services\.json|GoogleService-Info\.plist|firebase-adminsdk|service-account.*\.json|\.p8|\.p12|\.mobileprovision|\.jks|\.keystore|key\.properties)$').hasMatch(f));
    expect(bad.toList(), isEmpty);
    final pem = RegExp('-----BEGIN (RSA |EC )?PRIVATE KEY-----');
    final googleKey = RegExp(r'AIza[0-9A-Za-z_\-]{35}');
    for (final f in files.where((f) => f.endsWith('.dart') || f.endsWith('.json') || f.endsWith('.plist') || f.endsWith('.gradle') || f.endsWith('.yaml'))) {
      final file = File(f);
      if (!file.existsSync() || f.contains('firebase_config_test.dart')) continue;
      final text = file.readAsStringSync();
      expect(pem.hasMatch(text) || googleKey.hasMatch(text), isFalse, reason: f);
    }
  });
}
