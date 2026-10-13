// lib/screens/auth/profile_extras.dart
//
// Compte unique (miroir du profil web) : modification du nom, du prénom, de l'e-mail et de la photo, et accès à tout ce que le même compte
// demande ou propose (services, réservations, missions, engagements, évaluations, badges, adresses, notifications et confidentialité,
// sécurité). Le serveur reste l'autorité : un changement n'est affiché qu'après sa confirmation.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/user.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/notification_preferences_screen.dart';

/// Modifie nom, prénom et e-mail (facultatif). Renvoie `true` si le serveur a enregistré le changement.
class ProfileEditForm extends StatefulWidget {
  const ProfileEditForm({super.key, required this.user});
  final User user;
  @override
  State<ProfileEditForm> createState() => _ProfileEditFormState();
}

class _ProfileEditFormState extends State<ProfileEditForm> {
  late final TextEditingController _first = TextEditingController(text: widget.user.firstName ?? '');
  late final TextEditingController _last = TextEditingController(text: widget.user.lastName ?? '');
  late final TextEditingController _email = TextEditingController(text: widget.user.email);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _valid => _first.text.trim().isNotEmpty && _last.text.trim().isNotEmpty;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<DashboardApi>().patch('/users/${widget.user.id}/', {
        'first_name': _first.text.trim(),
        'last_name': _last.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, 'Le profil n’a pas pu être enregistré.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TratraInput(label: 'Prénom', controller: _first, required: true, onChanged: (_) => setState(() {})),
        const SizedBox(height: TtSpace.s3),
        TratraInput(label: 'Nom', controller: _last, required: true, onChanged: (_) => setState(() {})),
        const SizedBox(height: TtSpace.s3),
        TratraInput(label: 'Adresse e-mail', controller: _email, keyboardType: TextInputType.emailAddress, helper: 'Facultative : vous vous connectez avec votre numéro de téléphone.'),
        if (_error != null) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
        const SizedBox(height: TtSpace.s4),
        TratraButton(label: 'Enregistrer', block: true, loading: _busy, onPressed: _valid && !_busy ? _save : null),
      ]);
}

/// Choisit une photo dans la galerie et l'envoie (type déterminé par le contenu). Renvoie `true` si le serveur l'a enregistrée.
Future<bool> changeProfilePhoto(BuildContext context, User user) async {
  final api = context.read<DashboardApi>();
  final XFile? picked;
  try {
    picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1280);
  } catch (_) {
    if (context.mounted) showMessage(context, 'Impossible d’ouvrir la galerie. Vérifiez les autorisations de l’application.', error: true);
    return false;
  }
  if (picked == null) return false;
  try {
    await api.patchFile('/users/${user.id}/', 'profile_picture', picked.path);
    return true;
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e, 'La photo n’a pas pu être enregistrée.'), error: true);
    return false;
  }
}

/// « Mon espace » : tout ce que le même compte demande ou propose, plus sécurité et confidentialité.
class AccountShortcuts extends StatelessWidget {
  const AccountShortcuts({super.key});

  @override
  Widget build(BuildContext context) {
    final isProvider = context.watch<DashboardController>().data?.isProvider ?? false;
    final items = <(IconData, String, String, VoidCallback)>[
      if (isProvider)
        (Icons.handyman_outlined, 'Mes services', 'Publier et gérer mes prestations', () => openProviderHub(context))
      else
        (Icons.add_business_outlined, 'Proposer un service', 'Créer mon profil professionnel avec ce compte', () => openProvide(context)),
      (Icons.place_outlined, 'Mes adresses', 'Principale, secondaires et favorites', () => openAddresses(context)),
      (Icons.event_note_outlined, 'Mes réservations', 'Ce que j’ai demandé', () => openBookings(context)),
      if (isProvider) (Icons.work_outline_rounded, 'Mes missions', 'Ce que j’exécute pour d’autres', () => openProviderHub(context)),
      (Icons.description_outlined, 'Mes engagements', 'Contrats récurrents et longue durée', () => openEngagements(context)),
      (Icons.star_outline_rounded, 'Mes évaluations', 'Avis donnés et reçus, réputation', () => openReviews(context)),
      if (isProvider) (Icons.workspace_premium_outlined, 'Mes badges', 'Badges Trust et justificatifs', () => openReputation(context)),
      if (isProvider) (Icons.verified_user_outlined, 'Vérification d’identité (KYC)', 'Pièces et justificatifs', () => openKyc(context)),
      (Icons.notifications_none_rounded, 'Notifications et confidentialité', 'Alertes, communications promotionnelles', () => pushPage(context, const NotificationPreferencesScreen())),
      (Icons.lock_outline_rounded, 'Sécurité du compte', 'Changer mon mot de passe par code SMS', () => Navigator.pushNamed(context, RouteNames.forgotPassword)),
    ];
    return TratraCard(
      padding: const EdgeInsets.symmetric(horizontal: TtSpace.s2, vertical: TtSpace.s1),
      child: Column(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          ListTile(
            leading: Icon(items[i].$1, color: TtColors.primary),
            title: Text(items[i].$2),
            subtitle: Text(items[i].$3, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            trailing: const Icon(Icons.chevron_right_rounded, color: TtColors.ash),
            onTap: items[i].$4,
          ),
        ],
      ]),
    );
  }
}
