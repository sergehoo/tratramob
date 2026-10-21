// lib/core/route_observer.dart
//
// Observateur des routes de l'application : un écran peut savoir qu'on revient sur lui (ex. l'accueil se recharge au retour
// d'une vérification d'identité, d'une publication ou du profil professionnel).
import 'package:flutter/widgets.dart';

final RouteObserver<ModalRoute<void>> appRouteObserver = RouteObserver<ModalRoute<void>>();
