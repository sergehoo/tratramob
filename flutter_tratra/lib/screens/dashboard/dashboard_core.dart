// lib/screens/dashboard/dashboard_core.dart
//
// Socle de l'espace utilisateur unifié (miroir de frontend/src/lib/dashboard.tsx) :
// accès API borné au compte courant, modèle du tableau de bord et contrôleur partagé.
// Aucune règle métier ici : le backend (GET /me/dashboard/) reste la source de vérité.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_tratra/core/upload_file.dart';
import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/base_api.dart';

/// Appels JSON authentifiés (JWT + refresh automatique via [BaseApi]). Toujours l'instance
/// socle : un changement de compte n'utilise donc jamais le jeton d'un autre utilisateur.
class DashboardApi {
  DashboardApi(this._base);
  final BaseApi _base;

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final uri = Uri.parse('${_base.baseUrl}$path');
    final headers = await _base.headers;
    final encoded = body == null ? null : json.encode(body);
    final http.Response r;
    switch (method) {
      case 'POST':
        r = await _base.client.post(uri, headers: headers, body: encoded);
      case 'PATCH':
        r = await _base.client.patch(uri, headers: headers, body: encoded);
      case 'PUT':
        r = await _base.client.put(uri, headers: headers, body: encoded);
      case 'DELETE':
        r = await _base.client.delete(uri, headers: headers);
      default:
        r = await _base.client.get(uri, headers: headers);
    }
    if (r.statusCode < 200 || r.statusCode >= 300) _base.handleError(r);
    if (r.bodyBytes.isEmpty) return null;
    return _base.decodeBody(r);
  }

  Future<Map<String, dynamic>> getMap(String path) async {
    final d = await _send('GET', path);
    return d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// Liste paginée DRF (`results`) ou liste simple.
  Future<List<Map<String, dynamic>>> getList(String path) async {
    final d = await _send('GET', path);
    return _base.extractResults(d).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  Future<Map<String, dynamic>> post(String path, [Object? body]) async {
    final d = await _send('POST', path, body: body);
    return d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> put(String path, Object body) async {
    final d = await _send('PUT', path, body: body);
    return d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<void> delete(String path) async {
    await _send('DELETE', path);
  }

  Future<Map<String, dynamic>> patch(String path, Object body) async {
    final d = await _send('PATCH', path, body: body);
    return d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// POST multipart (photo d'un avis…) : `http` pose lui-même le Content-Type avec sa frontière.
  Future<Map<String, dynamic>> postFile(String path, String field, String filePath) async {
    final req = http.MultipartRequest('POST', Uri.parse('${_base.baseUrl}$path'));
    final h = await _base.headers;
    h.remove('Content-Type');
    req.headers.addAll(h);
    req.files.add(await multipartFromPath(field, filePath));
    final r = await http.Response.fromStream(await _base.client.send(req));
    if (r.statusCode < 200 || r.statusCode >= 300) _base.handleError(r);
    final d = _base.decodeBody(r);
    return d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// POST multipart avec champs texte (justificatif professionnel…).
  Future<Map<String, dynamic>> postForm(String path, Map<String, String> fields, String fileField, String filePath) async {
    final req = http.MultipartRequest('POST', Uri.parse('${_base.baseUrl}$path'));
    final h = await _base.headers;
    h.remove('Content-Type');
    req.headers.addAll(h);
    req.fields.addAll(fields);
    req.files.add(await multipartFromPath(fileField, filePath));
    final r = await http.Response.fromStream(await _base.client.send(req));
    if (r.statusCode < 200 || r.statusCode >= 300) _base.handleError(r);
    final d = _base.decodeBody(r);
    return d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// PATCH multipart (photo de profil) : `http` pose lui-même le Content-Type avec sa frontière.
  Future<void> patchFile(String path, String field, String filePath) async {
    final req = http.MultipartRequest('PATCH', Uri.parse('${_base.baseUrl}$path'));
    final h = await _base.headers;
    h.remove('Content-Type');
    req.headers.addAll(h);
    req.files.add(await multipartFromPath(field, filePath));
    final r = await http.Response.fromStream(await _base.client.send(req));
    if (r.statusCode < 200 || r.statusCode >= 300) _base.handleError(r);
  }
}

/// Message lisible (jamais de JSON brut) pour toute erreur de chargement ou d'action.
String friendlyError(Object error, [String fallback = 'Une erreur est survenue. Réessayez.']) {
  if (error is ApiException) return error.message;
  return fallback;
}

// ------------------------------------------------------------------ modèle

num _n(dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
int _i(dynamic v) => _n(v).toInt();
bool _b(dynamic v) => v == true;
String? _s(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
Map<String, dynamic> _m(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> _l(dynamic v) => v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];

/// Cible neutre d'une « action à traiter » (le client choisit l'écran correspondant).
enum DashTarget { provider, profile, profileKyc, reviews, messages, verifyPhone, unknown }

DashTarget _target(String? t) => switch (t) {
      'provider' => DashTarget.provider,
      'profile' => DashTarget.profile,
      'profile_kyc' => DashTarget.profileKyc,
      'reviews' => DashTarget.reviews,
      'messages' => DashTarget.messages,
      'verify_phone' => DashTarget.verifyPhone,
      _ => DashTarget.unknown,
    };

class DashItem {
  DashItem(Map<String, dynamic> j)
      : id = _i(j['id']),
        role = _s(j['role']) ?? 'client',
        title = _s(j['title']) ?? 'Réservation',
        category = _s(j['category']),
        status = _s(j['status']) ?? 'pending',
        bookingDate = DateTime.tryParse(_s(j['booking_date']) ?? ''),
        city = _s(j['city']),
        counterpart = _s(j['counterpart']) ?? 'Membre Tratra';
  final int id;

  /// `client` : j'ai réservé ; `handyman` : on m'a réservé.
  final String role;
  final String title;
  final String? category;
  final String status;
  final DateTime? bookingDate;
  final String? city;
  final String counterpart;
  bool get isMission => role == 'handyman';
}

class DashAction {
  DashAction(Map<String, dynamic> j)
      : key = _s(j['key']) ?? '',
        severity = _s(j['severity']) ?? 'info',
        title = _s(j['title']) ?? '',
        description = _s(j['description']) ?? '',
        target = _target(_s(j['target']));
  final String key;
  final String severity;
  final String title;
  final String description;
  final DashTarget target;
}

class DashChecklistItem {
  DashChecklistItem(Map<String, dynamic> j)
      : key = _s(j['key']) ?? '',
        label = _s(j['label']) ?? '',
        hint = _s(j['hint']),
        done = _b(j['done']);
  final String key;
  final String label;
  final String? hint;
  final bool done;
}

/// Action corrective proposée par le serveur (`edit_profile`, `verify_identity`, `add_service`, `manage_services`, `contact_support`).
class DashActionRef {
  DashActionRef(Map<String, dynamic> j)
      : code = _s(j['code']) ?? '',
        label = _s(j['label']) ?? '';
  final String code;
  final String label;
  static DashActionRef? maybe(dynamic v) => v is Map ? DashActionRef(_m(v)) : null;
}

/// Blocage réel de la publication, avec son explication et, s'il y en a une, l'action pour le lever.
class DashBlocker {
  DashBlocker(Map<String, dynamic> j)
      : code = _s(j['code']) ?? '',
        label = _s(j['label']) ?? '',
        hint = _s(j['hint']),
        action = DashActionRef.maybe(j['action']);
  final String code;
  final String label;
  final String? hint;
  final DashActionRef? action;
}

/// Synthèse d'éligibilité calculée par le serveur (`handy/eligibility.py`, `eligibility_summary`) : quatre notions DISTINCTES.
class DashEligibility {
  DashEligibility(Map<String, dynamic> j)
      : profileComplete = _b(_m(j['profile'])['complete']),
        profileDone = _i(_m(j['profile'])['done']),
        profileTotal = _i(_m(j['profile'])['total']),
        profileItems = _l(_m(j['profile'])['items']).map(DashChecklistItem.new).toList(),
        kycStatus = _s(_m(j['kyc'])['status']) ?? 'draft',
        kycLabel = _s(_m(j['kyc'])['label']) ?? 'Identité non vérifiée',
        kycReason = _s(_m(j['kyc'])['reason']),
        approved = _b(_m(j['approval'])['approved']),
        approvalLabel = _s(_m(j['approval'])['label']) ?? '',
        authorized = _b(_m(j['publication'])['authorized']),
        publicationLabel = _s(_m(j['publication'])['label']) ?? '',
        blockers = _l(_m(j['publication'])['blockers']).map(DashBlocker.new).toList(),
        offersTotal = _i(_m(j['offers'])['total']),
        offersActive = _i(_m(j['offers'])['active']),
        offersPublished = _i(_m(j['offers'])['published']),
        offersLabel = _s(_m(j['offers'])['label']) ?? '',
        offersAction = DashActionRef.maybe(_m(j['offers'])['action']),
        nextAction = DashActionRef.maybe(j['next_action']);
  final bool profileComplete;
  final int profileDone;
  final int profileTotal;
  final List<DashChecklistItem> profileItems;

  /// draft | pending | rejected | approved (pièce d'identité uniquement).
  final String kycStatus;
  final String kycLabel;
  final String? kycReason;
  final bool approved;
  final String approvalLabel;
  final bool authorized;
  final String publicationLabel;
  final List<DashBlocker> blockers;
  final int offersTotal;
  final int offersActive;
  final int offersPublished;
  final String offersLabel;
  final DashActionRef? offersAction;
  final DashActionRef? nextAction;
  bool get kycApproved => kycStatus == 'approved';
}

class DashProvider {
  DashProvider(Map<String, dynamic> j)
      : profileId = _i(j['profile_id']),
        badgeCodes = _l(j['badges']).map((b) => '${b['code']}').toList(),
        trustScore = j['trust_score'] is num ? (j['trust_score'] as num).round() : null,
        online = _b(j['online']),
        publishable = _b(j['publishable']),
        percent = _i(_m(j['completion'])['percent']),
        done = _i(_m(j['completion'])['done']),
        total = _i(_m(j['completion'])['total']),
        checklist = _l(_m(j['completion'])['items']).map(DashChecklistItem.new).toList(),
        kycStatus = _s(_m(j['kyc'])['status']) ?? 'none',
        kycReason = _s(_m(j['kyc'])['rejection_reason']),
        eligibility = j['eligibility'] is Map ? DashEligibility(_m(j['eligibility'])) : null,
        servicesActive = _i(_m(j['services'])['active']),
        servicesTotal = _i(_m(j['services'])['total']),
        pending = _i(_m(j['missions'])['pending']),
        confirmed = _i(_m(j['missions'])['confirmed']),
        inProgress = _i(_m(j['missions'])['in_progress']),
        completed = _i(_m(j['missions'])['completed']),
        earnings = _n(_m(j['earnings'])['available']),
        nextMissions = _l(j['next_missions']).map(DashItem.new).toList(),
        recentMissions = _l(j['recent_missions']).map(DashItem.new).toList();
  final int profileId;

  /// Badges Tratra Trust actuels (NOUVEAU tant que l'identité n'est pas vérifiée) et score s'il est calculable.
  final List<String> badgeCodes;
  final int? trustScore;
  final bool online;
  final bool publishable;
  final int percent;
  final int done;
  final int total;
  final List<DashChecklistItem> checklist;
  final String kycStatus;
  final String? kycReason;

  /// Profil complet / identité / autorisation de publication / offres, avec blocages et actions (règle unique du serveur).
  final DashEligibility? eligibility;
  final int servicesActive;
  final int servicesTotal;
  final int pending;
  final int confirmed;
  final int inProgress;
  final int completed;
  final num earnings;
  final List<DashItem> nextMissions;
  final List<DashItem> recentMissions;
}

class DashData {
  DashData(Map<String, dynamic> j)
      : userId = _i(_m(j['user'])['id']),
        firstName = _s(_m(j['user'])['first_name']),
        displayName = _s(_m(j['user'])['display_name']) ?? 'Membre Tratra',
        phoneVerified = _b(_m(j['user'])['is_verified']),
        isProvider = _b(_m(j['capabilities'])['provider']),
        isCompany = _b(_m(j['capabilities'])['company']),
        isBusiness = _b(_m(j['capabilities'])['business']),
        bookingsTotal = _i(_m(_m(j['client'])['bookings'])['total']),
        bookingsActive = _i(_m(_m(j['client'])['bookings'])['pending']) +
            _i(_m(_m(j['client'])['bookings'])['confirmed']) +
            _i(_m(_m(j['client'])['bookings'])['in_progress']),
        bookingsCompleted = _i(_m(_m(j['client'])['bookings'])['completed']),
        recentBookings = _l(_m(j['client'])['recent_bookings']).map(DashItem.new).toList(),
        provider = j['provider'] is Map ? DashProvider(_m(j['provider'])) : null,
        upcoming = _l(j['upcoming']).map(DashItem.new).toList(),
        reviewsToWrite = _i(_m(j['reviews'])['to_write']),
        reviewsReceived = _i(_m(j['reviews'])['received_count']),
        unreadNotifications = _i(_m(j['unread'])['notifications']),
        unreadMessages = _i(_m(j['unread'])['messages']),
        actions = _l(j['actions']).map(DashAction.new).toList();

  final int userId;
  final String? firstName;
  final String displayName;
  final bool phoneVerified;
  final bool isProvider;
  final bool isCompany;
  final bool isBusiness;
  final int bookingsTotal;
  final int bookingsActive;
  final int bookingsCompleted;
  final List<DashItem> recentBookings;
  final DashProvider? provider;
  final List<DashItem> upcoming;
  final int reviewsToWrite;
  final int reviewsReceived;
  final int unreadNotifications;
  final int unreadMessages;
  final List<DashAction> actions;

  String get greeting => firstName ?? displayName;
}

/// Données du tableau de bord partagées par l'accueil, les pastilles de navigation et les pages.
/// Lié au compte courant : un changement d'utilisateur vide immédiatement les données.
class DashboardController extends ChangeNotifier {
  DashboardController(this._api);
  final DashboardApi _api;

  DashData? data;
  bool loading = false;
  String? error;

  /// Session refusée par le serveur (jeton expiré ou révoqué, renouvellement impossible) : réessayer ne sert à rien, il faut se reconnecter.
  bool sessionExpired = false;
  String? _userKey;

  /// À appeler quand la session change : purge si le compte n'est plus le même.
  void bindUser(String? userKey) {
    if (userKey == _userKey) return;
    _userKey = userKey;
    data = null;
    error = null;
    loading = false;
    // Appelé pendant la construction des providers : notification différée.
    Future.microtask(notifyListeners);
  }

  Future<void> load() async {
    if (_userKey == null) return;
    final key = _userKey;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final raw = await _api.getMap('/me/dashboard/');
      if (key != _userKey) return; // le compte a changé pendant la requête
      data = DashData(raw);
    } catch (e) {
      if (key != _userKey) return;
      sessionExpired = e is ApiException && e.statusCode == 401;
      error = sessionExpired
          ? 'Votre session a expiré. Reconnectez-vous pour retrouver votre espace.'
          : friendlyError(e, 'Le tableau de bord n’a pas pu être chargé.');
    } finally {
      if (key == _userKey) {
        loading = false;
        notifyListeners();
      }
    }
  }
}
