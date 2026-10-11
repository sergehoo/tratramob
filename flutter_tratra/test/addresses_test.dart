import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tratra/screens/dashboard/addresses_screen.dart';

void main() {
  test('addressLine assemble rue, quartier, ville, pays sans champs vides', () {
    expect(addressLine({'street': 'Rue des Jardins', 'commune': 'Cocody', 'city': 'Abidjan', 'country': 'Côte d’Ivoire'}),
        'Rue des Jardins, Cocody, Abidjan, Côte d’Ivoire');
    expect(addressLine({'street': '', 'commune': null, 'city': 'Bouaké', 'country': ' '}), 'Bouaké');
  });
}
