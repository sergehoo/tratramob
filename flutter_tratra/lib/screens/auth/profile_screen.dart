// ===============================
// lib/screens/profile_screen.dart ✅ (Provider + token OK)
// ===============================
import 'package:flutter/material.dart';
import 'package:flutter_tratra/models/user.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/services/auth_service.dart';
import 'package:flutter_tratra/services/storage_service.dart';
import 'package:provider/provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AuthService _auth;
  late final StorageService _storage;

  User? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthService>();
    _storage = context.read<StorageService>();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      // 1) rapide: cache local si dispo
      final cached = await _storage.getUserData();
      if (cached != null) setState(() => _user = cached);

      // 2) source of truth: API
      final me = await _auth.getCurrentUser();
      setState(() => _user = me);
      await _storage.saveUserData(me);
    } catch (e) {
      debugPrint('Erreur: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await _auth.logout();
    await _storage.clearAuthData();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, RouteNames.login);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: _user != null ? _buildProfile() : _buildError(),
    );
  }

  Widget _buildProfile() {
    final u = _user!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CircleAvatar(
          radius: 50,
          backgroundImage:
              (u.profileImage != null && u.profileImage!.isNotEmpty)
                  ? NetworkImage(u.profileImage!)
                  : null,
          child: (u.profileImage == null || u.profileImage!.isEmpty)
              ? const Icon(Icons.person, size: 50)
              : null,
        ),
        const SizedBox(height: 16),
        Text(u.fullName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        Text(u.email, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ListTile(
          leading: const Icon(Icons.phone),
          title: const Text('Téléphone'),
          subtitle: Text(u.phoneNumber ?? 'Non renseigné'),
        ),
        ListTile(
          leading: const Icon(Icons.person),
          title: const Text("Type d'utilisateur"),
          subtitle: Text(u.userType),
        ),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: _logout, child: const Text('Déconnexion')),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Erreur de chargement du profil'),
          const SizedBox(height: 12),
          ElevatedButton(
              onPressed: _loadUserData, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}
