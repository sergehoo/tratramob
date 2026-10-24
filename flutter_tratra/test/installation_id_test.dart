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

  test('stockage chiffré illisible : un identifiant de secours est quand même envoyé, le même pendant l\'exécution', () async {
    final broken = _BrokenStorage();
    final headers = await deviceHeaders(broken);
    expect(headers.keys, ['X-Tratra-Device']);
    expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(headers['X-Tratra-Device']!), isTrue);
    expect(await deviceHeaders(broken), headers);
  });
}

class _BrokenStorage extends FlutterSecureStorage {
  _BrokenStorage();

  @override
  Future<String?> read({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
          WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) =>
      Future.error(Exception('clé du stockage chiffré perdue'));
}
