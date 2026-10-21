// lib/core/session.dart
//
// État de session applicatif : utilisateur courant + rôle. Source unique de
// vérité pour le routage par persona (client / artisan / entreprise).
import 'package:flutter/foundation.dart';

import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/user.dart';
import 'package:flutter_tratra/services/auth_service.dart';
import 'package:flutter_tratra/services/storage_service.dart';

class Session extends ChangeNotifier {
  final AuthService _auth;
  final StorageService _storage;

  Session(this._auth, this._storage);

  User? _user;
  User? get user => _user;

  bool get isAuthenticated => _user != null;
  String get role => _user?.userType ?? '';

  bool get isClient =>
      role == AppConstants.roleClient || role == AppConstants.roleEmployer;
  bool get isHandyman => role == AppConstants.roleHandyman;
  bool get isCompany => role == AppConstants.roleCompany;
  bool get isAdmin => role == AppConstants.roleAdmin;

  /// Hydrate la session depuis le stockage chiffré (au démarrage).
  Future<void> loadFromStorage() async {
    _user = await _storage.getUserData();
    notifyListeners();
  }

  /// Met à jour l'utilisateur courant (après login / refresh profil) et persiste.
  Future<void> setUser(User user) async {
    _user = user;
    await _storage.saveUserData(user);
    notifyListeners();
  }

  /// Recharge le profil depuis l'API (source de vérité du rôle).
  Future<User?> refreshProfile() async {
    try {
      final fresh = await _auth.getCurrentUser();
      await setUser(fresh);
      return fresh;
    } catch (_) {
      return _user;
    }
  }

  /// Exécuté avant la révocation du jeton (ex. retrait de l'appareil des notifications push, qui exige encore un
  /// jeton valide). Best-effort : n'empêche jamais la déconnexion.
  Future<void> Function()? onBeforeLogout;

  /// Purges locales exécutées APRÈS la révocation, uniquement à la déconnexion VOLONTAIRE (brouillons, file hors
  /// ligne, dernier état des activités : aucune donnée sensible ne reste sur le téléphone). Une session expirée, elle,
  /// ne purge rien : l'utilisateur retrouve ses brouillons à la reconnexion.
  final List<Future<void> Function()> _logoutWipes = [];
  void addLogoutWipe(Future<void> Function() wipe) => _logoutWipes.add(wipe);

  /// « Se souvenir de moi » décoché : au DÉMARRAGE À FROID (l'application avait été réellement fermée), la session précédente est
  /// révoquée et effacée comme une déconnexion. Une mise en arrière-plan ne redémarre pas l'application : la session y survit.
  /// Réseau absent : la purge locale a lieu quand même (révocation et retrait du push limités à 3 s chacun).
  Future<bool> endSessionOnlyAtColdStart() async {
    if (!await _storage.isSessionOnly()) return false;
    try {
      await onBeforeLogout?.call().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await _auth.logout().timeout(const Duration(seconds: 3));
    } catch (_) {}
    await _storage.clearAuthData();
    for (final wipe in _logoutWipes) {
      try {
        await wipe();
      } catch (_) {}
    }
    _user = null;
    notifyListeners();
    return true;
  }

  /// Déconnexion : révoque côté backend (best-effort) puis purge local.
  Future<void> logout() async {
    try {
      await onBeforeLogout?.call();
    } catch (_) {}
    try {
      await _auth.logout();
    } catch (_) {}
    await _storage.clearAuthData();
    for (final wipe in _logoutWipes) {
      try {
        await wipe();
      } catch (_) {}
    }
    _user = null;
    notifyListeners();
  }

  /// Route d'accueil : l'espace unifié (un même compte peut être client ET artisan ;
  /// les fonctions artisan s'affichent selon la présence réelle d'un profil professionnel).
  String homeRoute() => '/';
}
