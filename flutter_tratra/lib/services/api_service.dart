// services/api_service.dart
import 'dart:convert';
import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/models/notification.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tratra/models/artisan.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/models/booking.dart';

import 'package:flutter_tratra/models/user.dart';
import 'package:flutter_tratra/models/review.dart';
import 'package:flutter_tratra/models/conversation.dart';
import 'package:flutter_tratra/models/message.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants.dart';
import '../core/timeout_http_client.dart';

class ApiService {
  ApiService({http.Client? client}) : client = client ?? TimeoutHttpClient(http.Client());

  final String baseUrl = AppConstants.baseUrl;
  // Délai maximal par requête : un serveur muet ne doit jamais figer l'écran (voir core/timeout_http_client.dart).
  final http.Client client;
  String? authToken;

  // Méthode pour définir le token d'authentification
  void setAuthToken(String token) {
    authToken = token.isEmpty ? null : token;
  }

  // Headers communs
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (authToken != null) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  // Gestion des erreurs
  void _handleError(http.Response response) {
    // Message lisible, jamais le JSON brut (voir core/api_exception.dart).
    throw ApiException.fromResponse(response);
  }

  // ============ UTILISATEURS ============
  Future<User> registerUser(User user, String password) async {
    authToken = null; // point d'accès public : jamais le jeton d'une session précédente
    final response = await client.post(
      Uri.parse('$baseUrl${AppConstants.usersEndpoint}/'),
      headers: _headers,
      body: json.encode({
        ...user.toJson(),
        'password': password,
      }),
    );

    if (response.statusCode == 201) {
      return User.fromJson(json.decode(response.body));
    } else {
      _handleError(response);
      throw Exception('Erreur lors de l\'inscription');
    }
  }

  /// Connexion. `remember` (« Se souvenir de moi », coché par défaut) : la session reste ouverte après la fermeture de l'application
  /// et se renouvelle seule ; décoché, elle s'arrête à la fermeture réelle de l'application (jamais en simple arrière-plan) et le
  /// serveur lui donne une durée courte. Aucun mot de passe n'est conservé.
  Future<User> loginWithUsername(String username, String password, {bool remember = true}) async {
    authToken = null; // un jeton périmé/d'un autre compte ferait refuser la connexion (401)
    final resp = await client.post(
      Uri.parse('$baseUrl/auth/login/'),
      headers: _headers,
      body: json.encode({
        'username': username,
        'password': password,
        'remember_me': remember,
      }),
    );

    if (resp.statusCode == 200) {
      final data = json.decode(resp.body);
      final access = data['access'] as String?;
      if (access == null || access.isEmpty) {
        throw Exception("Token d'accès manquant dans la réponse");
      }
      setAuthToken(access);

      // Persiste access + refresh dans le secure storage (clés partagées avec
      // BaseApi -> auto-refresh sur 401 pour toutes les requêtes de l'app).
      final refresh = data['refresh'] as String?;
      const secure = FlutterSecureStorage();
      await secure.write(key: AppConstants.authTokenKey, value: access);
      if (refresh != null && refresh.isNotEmpty) {
        await secure.write(key: AppConstants.refreshTokenKey, value: refresh);
      } else {
        // Évite de réutiliser le refresh token d'une session précédente.
        await secure.delete(key: AppConstants.refreshTokenKey);
      }
      if (remember) {
        await secure.delete(key: AppConstants.sessionOnlyKey);
      } else {
        await secure.write(key: AppConstants.sessionOnlyKey, value: '1');
      }

      // Récupération du profil courant (protégé)
      final me = await getCurrentUser();
      return me;
    } else {
      _handleError(resp);
      // unreachable
      throw Exception('Erreur lors de la connexion');
    }
  }

  Future<void> logout() async {
    const secure = FlutterSecureStorage();
    final refresh = await secure.read(key: AppConstants.refreshTokenKey);
    try {
      if (refresh != null && refresh.isNotEmpty) {
        final resp = await client.post(
          Uri.parse('$baseUrl${AppConstants.authLogoutEndpoint}'),
          headers: _headers,
          body: json.encode({'refresh': refresh}),
        );
        if (resp.statusCode != 200 &&
            resp.statusCode != 204 &&
            resp.statusCode != 205) {
          _handleError(resp);
        }
      }
    } catch (_) {
      // La session locale doit être supprimée même sans réseau.
    } finally {
      setAuthToken('');
      await secure.delete(key: AppConstants.authTokenKey);
      await secure.delete(key: AppConstants.refreshTokenKey);
    }
  }

  Future<User> getCurrentUser() async {
    final response = await client.get(
      Uri.parse('$baseUrl${AppConstants.usersEndpoint}/me/'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return User.fromJson(json.decode(response.body));
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la récupération du profil');
    }
  }

  Future<User> updateUser(User user) async {
    // PATCH évite d'exiger le mot de passe à chaque édition de profil et ne
    // soumet pas de champs serveur en lecture seule.
    final response = await client.patch(
      Uri.parse('$baseUrl${AppConstants.usersEndpoint}/${user.id}/'),
      headers: _headers,
      body: json.encode(user.toProfileUpdateJson()),
    );

    if (response.statusCode == 200) {
      return User.fromJson(json.decode(response.body));
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la mise à jour du profil');
    }
  }

  // ============ ARTISANS ============
  Future<List<Artisan>> getArtisans({
    String? category,
    double? maxDistance,
    double? minRating,
    bool? availableNow,
  }) async {
    final Map<String, String> queryParams = {};
    if (category != null) queryParams['category'] = category;
    if (maxDistance != null)
      queryParams['max_distance'] = maxDistance.toString();
    if (minRating != null) queryParams['min_rating'] = minRating.toString();
    if (availableNow != null)
      queryParams['available_now'] = availableNow.toString();

    final uri = Uri.parse('$baseUrl${AppConstants.artisansEndpoint}')
        .replace(queryParameters: queryParams);

    final response = await client.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Artisan.fromJson(json)).toList();
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la récupération des artisans');
    }
  }

  Future<Artisan> getArtisanById(String artisanId) async {
    final response = await client.get(
      Uri.parse('$baseUrl${AppConstants.artisansEndpoint}/$artisanId/'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return Artisan.fromJson(json.decode(response.body));
    } else {
      _handleError(response);
      throw Exception('Artisan non trouvé');
    }
  }

  // ============ SERVICES ============
  Future<List<Service>> getServices({
    String? category,
    bool? onPromotion,
    bool? urgent,
    double? maxPrice,
  }) async {
    final Map<String, String> queryParams = {};
    if (category != null) queryParams['category'] = category;
    if (onPromotion != null)
      queryParams['on_promotion'] = onPromotion.toString();
    if (urgent != null) queryParams['urgent'] = urgent.toString();
    if (maxPrice != null) queryParams['max_price'] = maxPrice.toString();

    final uri = Uri.parse('$baseUrl${AppConstants.servicesEndpoint}')
        .replace(queryParameters: queryParams);

    final response = await client.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Service.fromJson(json)).toList();
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la récupération des services');
    }
  }

  Future<Service> getServiceById(String serviceId) async {
    final response = await client.get(
      Uri.parse('$baseUrl${AppConstants.servicesEndpoint}/$serviceId/'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return Service.fromJson(json.decode(response.body));
    } else {
      _handleError(response);
      throw Exception('Service non trouvé');
    }
  }

  // ============ RÉSERVATIONS ============
  Future<Booking> createBooking(Booking booking) async {
    final response = await client.post(
      Uri.parse('$baseUrl${AppConstants.bookingsEndpoint}/'),
      headers: _headers,
      body: json.encode(booking.toJson()),
    );

    if (response.statusCode == 201) {
      return Booking.fromJson(json.decode(response.body));
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la création de la réservation');
    }
  }

  Future<List<Booking>> getUserBookings() async {
    final response = await client.get(
      Uri.parse('$baseUrl${AppConstants.bookingsEndpoint}/'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Booking.fromJson(json)).toList();
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la récupération des réservations');
    }
  }

  Future<Booking> getBookingById(String bookingId) async {
    final response = await client.get(
      Uri.parse('$baseUrl${AppConstants.bookingsEndpoint}/$bookingId/'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return Booking.fromJson(json.decode(response.body));
    } else {
      _handleError(response);
      throw Exception('Réservation non trouvée');
    }
  }

  Future<void> cancelBooking(String bookingId) async {
    final response = await client.delete(
      Uri.parse('$baseUrl${AppConstants.bookingsEndpoint}/$bookingId/'),
      headers: _headers,
    );

    if (response.statusCode != 204) {
      _handleError(response);
      throw Exception('Erreur lors de l\'annulation de la réservation');
    }
  }

  Future<Booking> updateBookingStatus(String bookingId, String status) async {
    final response = await client.patch(
      Uri.parse('$baseUrl${AppConstants.bookingsEndpoint}/$bookingId/'),
      headers: _headers,
      body: json.encode({'status': status}),
    );

    if (response.statusCode == 200) {
      return Booking.fromJson(json.decode(response.body));
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la mise à jour du statut');
    }
  }

  // ============ PAIEMENTS ============
  Future<Map<String, dynamic>> initiatePayment(
      double amount, String serviceName) async {
    final response = await client.post(
      Uri.parse('$baseUrl${AppConstants.paymentsEndpoint}/initiate/'),
      headers: _headers,
      body: json.encode({
        'amount': amount,
        'service_name': serviceName,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      _handleError(response);
      throw Exception('Erreur lors de l\'initiation du paiement');
    }
  }

  // ============ AVIS ============
  Future<Review> createReview(Review review) async {
    final response = await client.post(
      Uri.parse('$baseUrl${AppConstants.reviewsEndpoint}/'),
      headers: _headers,
      body: json.encode(review.toJson()),
    );

    if (response.statusCode == 201) {
      return Review.fromJson(json.decode(response.body));
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la création de l\'avis');
    }
  }

  Future<List<Review>> getArtisanReviews(String artisanId) async {
    final response = await client.get(
      Uri.parse('$baseUrl${AppConstants.reviewsEndpoint}/?artisan=$artisanId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Review.fromJson(json)).toList();
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la récupération des avis');
    }
  }

  // ============ MESSAGERIE ============
  Future<List<Conversation>> getConversations() async {
    final response = await client.get(
      Uri.parse('$baseUrl${AppConstants.conversationsEndpoint}/'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Conversation.fromJson(json)).toList();
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la récupération des conversations');
    }
  }

  Future<List<Message>> getMessages(String conversationId) async {
    final response = await client.get(
      Uri.parse(
          '$baseUrl${AppConstants.messagesEndpoint}/?conversation=$conversationId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Message.fromJson(json)).toList();
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la récupération des messages');
    }
  }

  Future<Message> sendMessage(Message message) async {
    final response = await client.post(
      Uri.parse('$baseUrl${AppConstants.messagesEndpoint}/'),
      headers: _headers,
      body: json.encode(message.toJson()),
    );

    if (response.statusCode == 201) {
      return Message.fromJson(json.decode(response.body));
    } else {
      _handleError(response);
      throw Exception('Erreur lors de l\'envoi du message');
    }
  }

  // ============ NOTIFICATIONS ============
  Future<List<Notification>> getNotifications() async {
    final response = await client.get(
      Uri.parse('$baseUrl${AppConstants.notificationsEndpoint}/'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Notification.fromJson(json)).toList();
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la récupération des notifications');
    }
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    final response = await client.patch(
      Uri.parse(
          '$baseUrl${AppConstants.notificationsEndpoint}/$notificationId/'),
      headers: _headers,
      body: json.encode({'read': true}),
    );

    if (response.statusCode != 200) {
      _handleError(response);
      throw Exception('Erreur lors de la mise à jour de la notification');
    }
  }

  // ============ ESTIMATION DE PRIX ============
  Future<Map<String, dynamic>> estimatePrice({
    required String serviceType,
    required double duration,
    required String location,
    Map<String, dynamic>? additionalParams,
  }) async {
    final Map<String, dynamic> body = {
      'service_type': serviceType,
      'duration': duration,
      'location': location,
      ...?additionalParams,
    };

    final response = await client.post(
      Uri.parse('$baseUrl${AppConstants.priceEstimateEndpoint}'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      _handleError(response);
      throw Exception('Erreur lors de l\'estimation du prix');
    }
  }

  // ============ MATCHING ============
  Future<List<Artisan>> findMatchingArtisans({
    required String serviceType,
    required String location,
    DateTime? preferredTime,
    Map<String, dynamic>? preferences,
  }) async {
    final Map<String, dynamic> body = {
      'service_type': serviceType,
      'location': location,
      'preferred_time': preferredTime?.toIso8601String(),
      ...?preferences,
    };

    final response = await client.post(
      Uri.parse('$baseUrl${AppConstants.matchEndpoint}'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Artisan.fromJson(json)).toList();
    } else {
      _handleError(response);
      throw Exception('Erreur lors de la recherche d\'artisans');
    }
  }

// ============ INSCRIPTION AVEC RÉSULTAT DÉTAILLÉ ============
  /// Inscription du compte UNIQUE (POST /users/) : prénom, nom, téléphone (E.164, +225 par défaut),
  /// mot de passe et acceptation des conditions. Ni identifiant ni e-mail : la connexion se fait par
  /// téléphone. Le téléphone reste NON vérifié tant qu'un code OTP n'a pas été validé.
  Future<Map<String, dynamic>> registerWithDetails({
    required String firstName,
    required String lastName,
    required String phone,
    required String password,
    String? phoneCountry,
  }) async {
    authToken = null; // point d'accès public : jamais le jeton d'une session précédente
    final userData = {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      if (phoneCountry != null) 'phone_country': phoneCountry,
      'password': password,
      'accept_terms': true,
    };

    final response = await client.post(
      Uri.parse('$baseUrl${AppConstants.usersEndpoint}/'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: json.encode(userData),
    );

    if (response.statusCode != 201) {
      _handleError(response); // message lisible du serveur (champ invalide, inscription impossible…)
    }

    final user = User.fromJson(json.decode(response.body));

    // Tentative de connexion automatique
    try {
      final loginResponse = await client.post(
        Uri.parse('$baseUrl${AppConstants.authLoginEndpoint}'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: json.encode({'username': phone, 'password': password}),
      );

      if (loginResponse.statusCode == 200) {
        final loginData = json.decode(loginResponse.body);
        final token = loginData['access'] as String?;
        final refresh = loginData['refresh'] as String?;

        if (token != null && token.isNotEmpty) {
          setAuthToken(token); // ⬅️ IMPORTANT : on mémorise le token
          const secure = FlutterSecureStorage();
          await secure.write(key: AppConstants.authTokenKey, value: token);
          if (refresh != null && refresh.isNotEmpty) {
            await secure.write(key: AppConstants.refreshTokenKey, value: refresh);
          } else {
            await secure.delete(key: AppConstants.refreshTokenKey);
          }
        }
        return {
          'success': true,
          'user': user,
          'token': token,
          'autoLogin': token != null,
          'message': token != null
              ? 'Compte créé et connecté'
              : 'Compte créé - Connexion échouée',
        };
      }
    } catch (e) {
      print('Erreur connexion auto: $e');
    }

    return {
      'success': true,
      'user': user,
      'token': null,
      'autoLogin': false,
      'message': 'Compte créé - Veuillez vous connecter manuellement',
    };
  }

  // =======================
  // Inscription simple pour RegisterScreen
  // Retourne User et renseigne authToken si auto-login OK
  // =======================
  Future<User> register({
    required String firstName,
    required String lastName,
    required String phone,
    required String password,
    String? phoneCountry,
  }) async {
    final result = await registerWithDetails(
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      password: password,
      phoneCountry: phoneCountry,
    );

    final user = result['user'] as User;
    final token = result['token'] as String?;
    if (token != null && token.isNotEmpty) {
      setAuthToken(token); // double sécurité
    }
    return user;
  }

}
