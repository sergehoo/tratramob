import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/screens/dashboard/service_modes.dart';

void main() {
  test('le ponctuel est toujours ouvert ; récurrent et contractuel suivent la règle du métier', () {
    expect(allowedModes(null), {'one_off'});
    expect(allowedModes({'allow_recurring': true, 'allow_long_term': false}), {'one_off', 'recurring'});
    expect(allowedModes({'allow_recurring': true, 'allow_long_term': true}), {'one_off', 'recurring', 'contract'});
  });

  test('un changement de métier retire les modes non ouverts, ordre canonique conservé', () {
    expect(sanitizeModes(['contract', 'one_off'], {'allow_recurring': true, 'allow_long_term': false}), ['one_off']);
    expect(sanitizeModes(['contract', 'one_off'], {'allow_recurring': false, 'allow_long_term': true}), ['one_off', 'contract']);
    expect(sanitizeModes(['recurring'], null), ['recurring']); // règle pas encore chargée : rien n'est retiré
  });

  test('libellés lisibles', () {
    expect(modesLabel(['one_off', 'contract']), 'Ponctuel, Contractuel (mensuel)');
    expect(modesLabel(null), '');
  });
}
