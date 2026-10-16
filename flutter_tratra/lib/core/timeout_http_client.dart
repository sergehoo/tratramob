// lib/core/timeout_http_client.dart
//
// Client HTTP avec délai maximal d'attente. Sans lui, un serveur qui ne répond pas du tout (paquets perdus, serveur arrêté,
// portail captif) laisse l'écran en chargement indéfiniment : aucune erreur, aucune issue. Au bout du délai, la requête échoue
// avec une `TimeoutException`, que les écrans traduisent en « Impossible de joindre le service ».
// Les envois de fichiers (multipart) ont un délai plus long.
import 'dart:async';

import 'package:http/http.dart' as http;

class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient(
    this._inner, {
    this.timeout = const Duration(seconds: 20),
    this.uploadTimeout = const Duration(minutes: 5),
  });

  final http.Client _inner;
  final Duration timeout;
  final Duration uploadTimeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(request is http.MultipartRequest ? uploadTimeout : timeout);

  @override
  void close() => _inner.close();
}
