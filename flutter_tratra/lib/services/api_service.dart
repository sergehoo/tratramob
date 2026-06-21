// services/api_service.dart
import 'dart:convert';
import 'package:flutter_tratra/models/notification.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tratra/models/artisan.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/models/booking.dart';

import 'package:flutter_tratra/models/user.dart';
import 'package:flutter_tratra/models/review.dart';
import 'package:flutter_tratra/models/conversation.dart';
import 'package:flutter_tratra/models/message.dart';
import '../core/constants.dart';

class ApiService {
  final String baseUrl = AppConstants.baseUrl;
  final http.Client client = http.Client();
  String? authToken;

  // Méthode pour définir le token d'authentification
  void setAuthToken(String token) {
    authToken = token;
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
    if (response.statusCode == 401) {
      throw Exception('Non autorisé - Veuillez vous reconnecter');
    } else if (response.statusCode == 403) {
      throw Exception('Accès refusé');
    } else if (response.statusCode == 404) {
      throw Exception('Ressource non trouvée');
    } else if (response.statusCode >= 500) {
      throw Exception('Erreur serveur: ${response.statusCode}');
    } else {
      throw Exception('Erreur: ${response.statusCode} - ${response.body}');
    }
  }

  // ============ UTILISATEURS ============
  Future<User> registerUser(User user, String password) async {
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

  Future<User> loginWithUsername(String username, String password) async {
    final resp = await client.post(
      Uri.parse('$baseUrl/auth/login/'),
      headers: _headers,
      body: json.encode({
        'username': username,
        'password': password,
      }),
    );

    if (resp.statusCode == 200) {
      final data = json.decode(resp.body);
      final access = data['access'] as String?;
      if (access == null || access.isEmpty) {
        throw Exception("Token d'accès manquant dans la réponse");
      }
      setAuthToken(access);

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
    // Optionnel: si tu as mis en place le blacklist (refresh token)
    final resp = await client.post(
      Uri.parse('$baseUrl/auth/logout/'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      _handleError(resp);
    }
    setAuthToken('');
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
    final response = await client.put(
      Uri.parse('$baseUrl${AppConstants.usersEndpoint}/${user.id}/'),
      headers: _headers,
      body: json.encode(user.toJson()),
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
  Future<Map<String, dynamic>> registerWithDetails({
    required String firstName,
    required String lastName,
    required String email,
    required String username,
    required String phone,
    required String password,
  }) async {
    final userData = {
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'username': username,
      'phone': phone,
      'password': password,
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
      if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        final errorMessage = _parseRegistrationError(errorData);
        throw Exception(errorMessage);
      }
      _handleError(response);
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
        body: json.encode({'username': username, 'password': password}),
      );

      if (loginResponse.statusCode == 200) {
        final loginData = json.decode(loginResponse.body);
        final token = loginData['access'] as String?;

        if (token != null && token.isNotEmpty) {
          setAuthToken(token); // ⬅️ IMPORTANT : on mémorise le token
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
    required String email,
    required String username,
    required String phone,
    required String password,
  }) async {
    final result = await registerWithDetails(
      firstName: firstName,
      lastName: lastName,
      email: email,
      username: username,
      phone: phone,
      password: password,
    );

    final user = result['user'] as User;
    final token = result['token'] as String?;

    // Si pas de token (auto-login KO), on peut tenter un fallback sûr:
    if (token != null && token.isNotEmpty) {
      setAuthToken(token); // ⬅️ double sécurité
    } else {
      // Fallback optionnel si ta vue de login attend un autre champ:
      // await loginWithUsername(username, password);
    }

    return user;
  }

  String _parseRegistrationError(dynamic errorData) {
    // errorData typiquement: {"email":["user with this email already exists."],"username":["..."], "password": ["..."]}
    if (errorData is Map) {
      final messages = <String>[];
      errorData.forEach((key, value) {
        if (value is List) {
          messages.add('$key: ${value.join(", ")}');
        } else if (value is String) {
          messages.add('$key: $value');
        } else {
          messages.add('$key: ${value.toString()}');
        }
      });
      if (messages.isNotEmpty) return messages.join(' | ');
    }
    return 'Erreur de validation';
  }
}
