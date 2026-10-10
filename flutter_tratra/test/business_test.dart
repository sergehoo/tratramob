// Tratra Business (mobile) : capacités décidées par le serveur, formats et QR d'équipement.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/screens/business/business_screens.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/trust/identity_api.dart';

void main() {
  group('OrgCtx', () {
    final org = OrgCtx({
      'id': 7,
      'name': 'Acme',
      'currency': 'XOF',
      'role_label': 'Demandeur',
      'capabilities': ['requests.create', 'view.structure'],
    });

    test('les capacités viennent du serveur : rien d’autre n’est autorisé', () {
      expect(org.can('requests.create'), isTrue);
      expect(org.can('requests.approve'), isFalse);
      expect(org.can('budgets.manage'), isFalse);
      expect(org.path('requests/'), '/business/orgs/7/requests/');
    });

    test('payload partiel : devise par défaut, aucune capacité', () {
      final bare = OrgCtx({'id': 1, 'name': 'X'});
      expect(bare.currency, 'XOF');
      expect(bare.can('requests.create'), isFalse);
    });
  });

  group('formats', () {
    test('montants en FCFA, séparateur de milliers, valeur inconnue = tiret', () {
      expect(money('80000'), '80 000 FCFA');
      expect(money(1250000), '1 250 000 FCFA');
      expect(money(null), '—');
      expect(money('abc'), '—');
      expect(money('500', 'EUR'), '500 EUR');
    });

    test('dates courtes', () {
      expect(shortDate('2026-10-12T09:30:00Z').length, 10);
      expect(shortDate(null), '—');
    });

    test('tous les statuts de demande ont un libellé français', () {
      for (final s in ['pending_approval', 'approved', 'dispatched', 'scheduled', 'in_progress', 'completed', 'rejected', 'cancelled']) {
        expect(requestStatus[s], isNotNull, reason: s);
      }
      expect(requestStatus['pending_approval']!.$1, 'À valider');
    });
  });

  group('QR d’équipement', () {
    test('URL ou code nu, jamais une URL étrangère', () {
      expect(parseQr('https://tratra.ci/equipment/EQ-ABCD-EFGH'), isA<EquipTarget>());
      expect((parseQr('eq-abcd-efgh') as EquipTarget).code, 'EQ-ABCD-EFGH');
      expect(parseQr('https://evil.example/equipment/../../x'), isNull);
      expect(parseQr('EQ-ABCD-EFG0'), isNull);
      expect(parseQr('TR-ABCD-EFGH'), isA<IdTarget>()); // les badges restent reconnus
    });
  });

  test('DashData expose la capacité business du compte', () {
    final d = DashData({
      'user': {'id': 1, 'first_name': 'A', 'display_name': 'A', 'is_verified': true},
      'capabilities': {'client': true, 'provider': false, 'publishable': false, 'company': false, 'business': true},
    });
    expect(d.isBusiness, isTrue);
    expect(DashData(<String, dynamic>{}).isBusiness, isFalse);
  });
}
