// Adresse retenue depuis une suggestion du serveur : lieu nommé, rue, quartier, commune, ville — sans doublon ni élément vide.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/widgets/address_autocomplete.dart';

void main() {
  test('lieu nommé, rue, quartier et commune réunis ; la commune sert à la zone', () {
    final p = AddressPick.fromSuggestion({'name': 'Pharmacie Saint-Jean', 'street': 'Boulevard André Latrille', 'quartier': 'Vieux Cocody',
        'commune': 'Cocody', 'city': 'Abidjan', 'latitude': 5.3488, 'longitude': -3.9921}, 'geocoder');
    expect(p.label, 'Pharmacie Saint-Jean, Boulevard André Latrille, Vieux Cocody, Cocody, Abidjan');
    expect((p.commune, p.city, p.lat), ('Cocody', 'Abidjan', 5.3488));
  });

  test('ancien format (sans nom ni quartier) inchangé, doublons retirés', () {
    expect(AddressPick.fromSuggestion({'street': 'Rue 1', 'commune': 'Cocody', 'city': 'Abidjan'}, 'geocoder').label, 'Rue 1, Cocody, Abidjan');
    expect(AddressPick.describe({'name': 'Cocody', 'quartier': 'cocody', 'commune': 'Cocody', 'city': 'Abidjan'}), 'Cocody, Abidjan');
    expect(AddressPick.fromSuggestion({'label': 'Quelque part'}, 'geocoder').label, 'Quelque part');
  });
}
