// Aucune donnée ni jeton d'une session ne doit survivre à la suivante.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/services/booking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les services métier relisent le jeton courant (changement de compte)', () async {
    FlutterSecureStorage.setMockInitialValues({AppConstants.authTokenKey: 'jeton-compte-A'});
    final base = BaseApi();
    final bookings = BookingService(base); // instance distincte, comme dans l'application

    expect((await bookings.headers)['Authorization'], 'Bearer jeton-compte-A');

    // Un autre compte se connecte : le jeton stocké change ; plus aucun service ne réutilise l'ancien.
    await base.setAuthToken('jeton-compte-B');
    expect((await bookings.headers)['Authorization'], 'Bearer jeton-compte-B');
    expect((await base.headers)['Authorization'], 'Bearer jeton-compte-B');

    // Déconnexion : aucun en-tête d'autorisation résiduel.
    await base.clearTokens();
    expect((await bookings.headers).containsKey('Authorization'), isFalse);
  });

  test('le tableau de bord est vidé dès que le compte change', () async {
    final c = DashboardController(DashboardApi(BaseApi()));
    c.bindUser('1');
    c.data = DashData({
      'user': {'id': 1, 'display_name': 'A'},
      'capabilities': {'client': true, 'provider': false},
    });
    expect(c.data, isNotNull);
    c.bindUser('1'); // même compte : conservé
    expect(c.data, isNotNull);
    c.bindUser('2'); // autre compte : purgé
    expect(c.data, isNull);
    c.bindUser(null); // déconnexion
    expect(c.data, isNull);
  });
}
