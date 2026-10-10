// lib/services/firebase_config.dart
//
// Configuration Firebase injectée AU BUILD (jamais committée) : permet Android ET iOS sans google-services.json /
// GoogleService-Info.plist dans le dépôt. Les valeurs viennent du projet Firebase de Tratra (Console → Paramètres du projet) :
//
//   flutter build apk --release \
//     --dart-define=FIREBASE_PROJECT_ID=… --dart-define=FIREBASE_MESSAGING_SENDER_ID=… \
//     --dart-define=FIREBASE_API_KEY_ANDROID=… --dart-define=FIREBASE_APP_ID_ANDROID=…
//   flutter build ipa \
//     … --dart-define=FIREBASE_API_KEY_IOS=… --dart-define=FIREBASE_APP_ID_IOS=… --dart-define=FIREBASE_IOS_BUNDLE_ID=com.tratra
//
// Sans ces valeurs, l'initialisation retombe sur la configuration native (fichier google-services.json / plist) ; sans elle non
// plus, l'application fonctionne sans push (statut « unconfigured »). Aucune clé de compte de service ne vit jamais dans l'app.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseDefines {
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const apiKeyAndroid = String.fromEnvironment('FIREBASE_API_KEY_ANDROID');
  static const appIdAndroid = String.fromEnvironment('FIREBASE_APP_ID_ANDROID');
  static const apiKeyIos = String.fromEnvironment('FIREBASE_API_KEY_IOS');
  static const appIdIos = String.fromEnvironment('FIREBASE_APP_ID_IOS');
  static const iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
  static const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static Map<String, String> get values => {
        'projectId': projectId,
        'senderId': senderId,
        'apiKeyAndroid': apiKeyAndroid,
        'appIdAndroid': appIdAndroid,
        'apiKeyIos': apiKeyIos,
        'appIdIos': appIdIos,
        'iosBundleId': iosBundleId,
        'storageBucket': storageBucket,
      };
}

/// Options Firebase de la plateforme, ou `null` si une valeur obligatoire manque (on retombe alors sur la configuration native).
FirebaseOptions? firebaseOptionsFor(TargetPlatform platform, [Map<String, String>? values]) {
  final v = values ?? FirebaseDefines.values;
  String? need(String k) => (v[k] ?? '').trim().isEmpty ? null : v[k]!.trim();
  final projectId = need('projectId'), senderId = need('senderId');
  if (projectId == null || senderId == null) return null;
  switch (platform) {
    case TargetPlatform.android:
      final key = need('apiKeyAndroid'), app = need('appIdAndroid');
      if (key == null || app == null) return null;
      return FirebaseOptions(apiKey: key, appId: app, messagingSenderId: senderId, projectId: projectId, storageBucket: need('storageBucket'));
    case TargetPlatform.iOS:
      final key = need('apiKeyIos'), app = need('appIdIos'), bundle = need('iosBundleId');
      if (key == null || app == null || bundle == null) return null;
      return FirebaseOptions(apiKey: key, appId: app, messagingSenderId: senderId, projectId: projectId, iosBundleId: bundle, storageBucket: need('storageBucket'));
    default:
      return null;
  }
}
