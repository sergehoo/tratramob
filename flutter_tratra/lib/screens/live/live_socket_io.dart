// Connexion WebSocket du suivi live — mobile : un ping toutes les 15 s. Sans réponse, la connexion est fermée par
// Dart (et donc rouverte par LiveController) ; sans cela, un changement de réseau (Wi-Fi ↔ données mobiles) laisse
// une connexion « fantôme » qui n'apparaît jamais comme coupée et fige le suivi.
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectLiveSocket(Uri uri) => IOWebSocketChannel.connect(uri, pingInterval: const Duration(seconds: 15));
