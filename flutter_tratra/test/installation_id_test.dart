// Identifiant d'installation (anti-fraude) : UUID v4 aléatoire, stable pour une installation, envoyé dans X-Tratra-Device.
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/core/installation_id.dart';

void main() {
  test('UUID v4 bien formé, différent à chaque génération', () {
    final a = newInstallationId(Random(1));
    final b = newInstallationId(Random(2));
    final uuid4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    expect(uuid4.hasMatch(a), isTrue, reason: a);
    expect(uuid4.hasMatch(b), isTrue);
    expect(a, isNot(b));
  });

  test('stable pour une installation ; en-tête X-Tratra-Device', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    final first = await installationId(storage);
    expect(await installationId(storage), first);
    expect(await deviceHeaders(storage), {'X-Tratra-Device': first});
  });
}
