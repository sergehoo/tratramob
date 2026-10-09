import 'package:flutter/material.dart';

import '../tokens.dart';

/// Nom de l'application « Tratra » en script de marque (Bonskin) — seul endroit où cette police
/// est utilisée (miroir de `BrandWordmark` côté web). `onNight` : fond sombre (blanc + jaune) ;
/// sinon fond clair (encre + vert). Décoratif : le nom accessible est « Tratra ».
class TratraWordmark extends StatelessWidget {
  const TratraWordmark({super.key, this.size = 30, this.onNight = false});

  final double size;
  final bool onNight;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: TtFont.brand,
      fontSize: size,
      height: 1.1,
      letterSpacing: 0,
      color: onNight ? Colors.white : TtColors.ink,
    );
    return Semantics(
      label: 'Tratra',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            const TextSpan(text: 'Tra'),
            TextSpan(text: 'tra', style: base.copyWith(color: onNight ? TtColors.accent : TtColors.primary)),
          ],
        ),
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}
