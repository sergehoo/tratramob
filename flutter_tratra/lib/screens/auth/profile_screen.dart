// ===============================
// lib/screens/profile_screen.dart ✅ (Provider + token OK)
// ===============================
import 'package:flutter/material.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/user.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/auth/delete_account_screen.dart';
import 'package:flutter_tratra/screens/auth/profile_extras.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart' show showMessage;
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
  bool _isLoggingOut = false;

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
      if (!mounted) return;
      if (cached != null) setState(() => _user = cached);

      // 2) source of truth: API
      final me = await _auth.getCurrentUser();
      if (!mounted) return;
      setState(() => _user = me);
      await _storage.saveUserData(me);
    } catch (e) {
      debugPrint('Erreur: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _edit(User u) async {
    final saved = await showTratraSheet<bool>(context, title: 'Modifier mon profil', child: ProfileEditForm(user: u));
    if (saved == true && mounted) {
      showMessage(context, 'Profil enregistré.');
      _retry();
    }
  }

  Future<void> _photo(User u) async {
    if (await changeProfilePhoto(context, u) && mounted) {
      showMessage(context, 'Photo mise à jour.');
      _retry();
    }
  }

  /// Relance le chargement en réaffichant le squelette (retour visuel sur « Réessayer »).
  void _retry() {
    setState(() => _isLoading = true);
    _loadUserData();
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    try {
      await context.read<Session>().logout();
    } catch (_) {
      if (mounted) setState(() => _isLoggingOut = false);
      rethrow;
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      RouteNames.login,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_isLoading) {
      body = const _ProfileSkeleton(key: ValueKey('profile-loading'));
    } else if (_user != null) {
      body = _buildProfile(_user!);
    } else {
      body = _buildError();
    }

    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: const TratraAppBar(title: 'Profil'),
      body: AnimatedSwitcher(
        duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
            ? Duration.zero
            : TtMotion.base,
        switchInCurve: TtMotion.emphasized,
        child: body,
      ),
    );
  }

  Widget _buildProfile(User u) {
    final phone = u.phoneNumber;
    final joined = u.dateJoined;

    return ListView(
      key: const ValueKey('profile-content'),
      padding: const EdgeInsets.fromLTRB(
        TtLayout.gutterMobile,
        TtSpace.s4,
        TtLayout.gutterMobile,
        TtSpace.s8,
      ),
      children: [
        TratraCard(
          variant: TratraCardVariant.night,
          padding: const EdgeInsets.symmetric(
            horizontal: TtSpace.s5,
            vertical: TtSpace.s6,
          ),
          child: Column(
            children: [
              Semantics(
                button: true,
                label: 'Changer ma photo',
                child: GestureDetector(
                  onTap: () => _photo(u),
                  child: Stack(alignment: Alignment.bottomRight, children: [
                    TratraAvatar(name: u.fullName, photoUrl: u.profileImage, size: 96),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: TtColors.accent, shape: BoxShape.circle),
                      child: const Icon(Icons.photo_camera_outlined, size: 16, color: TtColors.ink),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: TtSpace.s4),
              Semantics(
                header: true,
                child: Text(
                  u.fullName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.h2, color: Colors.white),
                ),
              ),
              if (u.email.isNotEmpty) ...[
                const SizedBox(height: TtSpace.s1),
                Text(
                  u.email,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TratraTheme.style(TtType.bodySm, color: Colors.white70),
                ),
              ],
              const SizedBox(height: TtSpace.s4),
              TratraBadge(
                _roleLabel(u.userType),
                tone: TratraTone.accent,
                dot: true,
              ),
              const SizedBox(height: TtSpace.s3),
              TratraButton(
                label: 'Modifier mon profil',
                size: TratraButtonSize.sm,
                variant: TratraButtonVariant.outline,
                leading: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _edit(u),
              ),
            ],
          ),
        ),
        const SizedBox(height: TtSpace.s4),
        TratraCard(
          padding: const EdgeInsets.symmetric(
            horizontal: TtSpace.s5,
            vertical: TtSpace.s2,
          ),
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Téléphone',
                value: phone ?? 'Non renseigné',
                muted: phone == null,
              ),
              if (phone != null) ...[
                const Divider(),
                if (u.isVerified)
                  const _InfoRow(
                    icon: Icons.verified_outlined,
                    label: 'Vérification',
                    value: 'Téléphone vérifié',
                  )
                else
                  InkWell(
                    onTap: () => Navigator.pushNamed(context, RouteNames.verifyPhone,
                        arguments: const OtpArgs(nextRoute: RouteNames.profile)),
                    child: const Row(
                      children: [
                        Expanded(
                          child: _InfoRow(
                            icon: Icons.sms_outlined,
                            label: 'Vérification',
                            value: 'Vérifier mon téléphone',
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: TtColors.ash),
                      ],
                    ),
                  ),
              ],
              if (joined != null) ...[
                const Divider(),
                _InfoRow(
                  icon: Icons.event_outlined,
                  label: 'Membre depuis',
                  value: _memberSince(joined),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: TtSpace.s4),
        const AccountShortcuts(),
        const SizedBox(height: TtSpace.s6),
        TratraButton(
          label: 'Déconnexion',
          variant: TratraButtonVariant.outline,
          size: TratraButtonSize.lg,
          block: true,
          loading: _isLoggingOut,
          leading: const Icon(Icons.logout_rounded),
          onPressed: _logout,
        ),
        const SizedBox(height: TtSpace.s2),
        TratraButton(
          label: 'Supprimer mon compte',
          variant: TratraButtonVariant.ghost,
          block: true,
          leading: const Icon(Icons.delete_outline_rounded, color: TtColors.danger),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DeleteAccountScreen())),
        ),
      ],
    );
  }

  Widget _buildError() {
    return TratraEmptyState(
      key: const ValueKey('profile-error'),
      icon: Icons.cloud_off_outlined,
      title: 'Erreur de chargement du profil',
      description: 'Vérifiez votre connexion puis réessayez.',
      actions: [
        TratraButton(
          label: 'Réessayer',
          leading: const Icon(Icons.refresh_rounded),
          onPressed: _retry,
        ),
      ],
    );
  }

  /// Libellé du compte (affichage uniquement ; un même compte demande et propose des services) ; valeur brute si inconnue.
  static String _roleLabel(String userType) => switch (userType) {
        AppConstants.roleClient || AppConstants.roleEmployer || AppConstants.roleHandyman => 'Membre',
        AppConstants.roleCompany => 'Entreprise',
        AppConstants.roleAdmin => 'Administrateur',
        _ => userType,
      };

  static const List<String> _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  static String _memberSince(DateTime date) {
    final d = date.toLocal();
    return '${_months[d.month - 1]} ${d.year}';
  }
}

/// Ligne d'information en lecture seule (aucune action : ce n'est pas un bouton).
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TtSpace.s3),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: TtColors.primarySoft,
                borderRadius: TtRadius.controlAll,
              ),
              child: SizedBox(
                width: TtLayout.touchTarget,
                height: TtLayout.touchTarget,
                child: Icon(icon, size: 20, color: TtColors.primaryDark),
              ),
            ),
            const SizedBox(width: TtSpace.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TratraTheme.style(TtType.caption, color: TtColors.ash),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TratraTheme.style(
                      TtType.title,
                      color: muted ? TtColors.ash : TtColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Squelette du profil (carte d'identité + lignes d'infos), annoncé une seule fois.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement du profil',
      liveRegion: true,
      child: ExcludeSemantics(
        child: TratraShimmer(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              TtLayout.gutterMobile,
              TtSpace.s4,
              TtLayout.gutterMobile,
              TtSpace.s8,
            ),
            child: Column(
              children: [
                _skeletonCard(
                  Column(
                    children: const [
                      TratraSkeletonBox(height: 96, circle: true),
                      SizedBox(height: TtSpace.s4),
                      TratraSkeletonBox(width: 180, height: 22),
                      SizedBox(height: TtSpace.s3),
                      TratraSkeletonBox(width: 140, height: 14),
                    ],
                  ),
                ),
                const SizedBox(height: TtSpace.s4),
                _skeletonCard(
                  Column(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(height: TtSpace.s4),
                        const Row(
                          children: [
                            TratraSkeletonBox(
                              width: TtLayout.touchTarget,
                              height: TtLayout.touchTarget,
                            ),
                            SizedBox(width: TtSpace.s4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TratraSkeletonBox(width: 90, height: 12),
                                  SizedBox(height: TtSpace.s2),
                                  TratraSkeletonBox(width: 150, height: 16),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _skeletonCard(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(TtSpace.s5),
        decoration: BoxDecoration(
          color: TtColors.surface,
          borderRadius: TtRadius.cardAll,
          border: Border.all(color: TtColors.lineSoft),
          boxShadow: TtShadows.soft,
        ),
        child: child,
      );
}
