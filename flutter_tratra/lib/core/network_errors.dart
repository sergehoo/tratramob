// lib/core/network_errors.dart
//
// Échecs d'envoi HORS réponse du serveur (une réponse d'erreur devient une ApiException avec son propre message) : coupure du réseau,
// connexion réinitialisée, délai dépassé, réponse illisible. Une coupure se rejoue sans risque quand l'envoi est idempotent
// (`client_id`) ; le message affiché porte une courte référence technique (jamais de donnée personnelle) pour le support.
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Coupure du transport (connexion refusée, réinitialisée, fermée avant la réponse, poignée de main TLS interrompue).
bool isTransientNetworkError(Object e) =>
    e is SocketException || e is HttpException || e is HandshakeException || e is TlsException || e is http.ClientException;

/// Référence courte de l'échec : « NET-104 » (code système), « CONN », « TLS », « DELAI », « REPONSE ».
String transferErrorRef(Object e) {
  if (e is SocketException) {
    final code = e.osError?.errorCode;
    return code == null ? 'NET' : 'NET-$code';
  }
  if (e is HandshakeException || e is TlsException) return 'TLS';
  if (e is http.ClientException || e is HttpException) return 'CONN';
  if (e is TimeoutException) return 'DELAI';
  if (e is FormatException || e is TypeError) return 'REPONSE';
  return 'APP';
}

/// Message d'un envoi idempotent qui a échoué malgré les nouveaux essais automatiques. `item` : « votre statut », « le message »…
String transferFailureMessage(Object e, {required String retryHint}) {
  final ref = transferErrorRef(e);
  if (e is TimeoutException) return 'L’envoi prend trop de temps (connexion lente). $retryHint (réf. $ref)';
  if (e is FormatException || e is TypeError) {
    return 'Réponse inattendue du serveur : l’envoi a peut-être abouti. $retryHint (réf. $ref)';
  }
  return 'Connexion interrompue pendant l’envoi. Vérifiez votre connexion. $retryHint (réf. $ref)';
}
