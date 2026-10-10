// Fabrique de WebSocket selon la plateforme (mobile : pings de détection de coupure ; web : standard).
export 'live_socket_web.dart' if (dart.library.io) 'live_socket_io.dart';
