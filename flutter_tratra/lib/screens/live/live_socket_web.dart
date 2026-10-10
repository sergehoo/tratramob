// Connexion WebSocket du suivi live — version web : le navigateur gère lui-même les pings.
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectLiveSocket(Uri uri) => WebSocketChannel.connect(uri);
