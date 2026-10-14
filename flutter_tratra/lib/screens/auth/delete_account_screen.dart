// lib/screens/auth/delete_account_screen.dart
//
// Suppression de son propre compte (exigence Google Play + droit à l'effacement). Le serveur reste l'autorité : il liste
// les blocages réels (réservation en cours, solde de retrait, litige ouvert…), vérifie le mot de passe et le mot de
// confirmation, puis anonymise le compte de façon irréversible. L'application ne supprime rien localement avant sa réponse.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const _path = '/me/account/deletion/';

  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _allowed = false;
  String _confirmWord = 'SUPPRIMER';
  List<String> _blockers = const [];
  String? _loadError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final d = await context.read<DashboardApi>().getMap(_path);
      if (!mounted) return;
      setState(() {
        _allowed = d['allowed'] == true;
        _confirmWord = (d['confirm_word'] as String?) ?? 'SUPPRIMER';
        _blockers = _blockerDetails(d['blockers']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = friendlyError(e, 'Impossible de vérifier votre compte pour le moment.');
        _loading = false;
      });
    }
  }

  static List<String> _blockerDetails(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((b) => '${b['detail'] ?? ''}').where((s) => s.isNotEmpty).toList()
      : const [];

  bool get _ready => _allowed && !_busy && _password.text.isNotEmpty && _confirm.text.trim() == _confirmWord;

  Future<void> _delete() async {
    final sure = await showTratraConfirm(
      context,
      title: 'Supprimer définitivement ?',
      message: 'Votre nom, votre numéro, vos messages, vos statuts et vos pièces seront effacés. Cette action est irréversible.',
      confirmLabel: 'Supprimer mon compte',
      danger: true,
    );
    if (!sure || !mounted) return;
    final api = context.read<DashboardApi>();
    final session = context.read<Session>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.post(_path, {'password': _password.text, 'confirm': _confirm.text.trim()});
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409 && e.code == 'blocked') {
        // Un blocage est apparu depuis l'ouverture de l'écran : on rafraîchit la liste plutôt que d'afficher une erreur sèche.
        setState(() => _busy = false);
        await _load();
        return;
      }
      setState(() {
        _busy = false;
        _error = e.code == 'wrong_password'
            ? 'Mot de passe incorrect.'
            : e.code == 'confirm_required'
                ? 'Tapez « $_confirmWord » pour confirmer.'
                : friendlyError(e, 'La suppression n’a pas pu aboutir.');
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(e, 'La suppression n’a pas pu aboutir. Vérifiez votre connexion et réessayez.');
      });
      return;
    }
    // Le serveur a confirmé : on purge le téléphone (jetons, brouillons, file hors ligne) puis retour à la connexion.
    await session.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, RouteNames.login, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: const TratraAppBar(title: 'Supprimer mon compte'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? TratraEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Vérification impossible',
                  description: _loadError!,
                  actions: [TratraButton(label: 'Réessayer', onPressed: _load)],
                )
              : ListView(
                  padding: const EdgeInsets.all(TtSpace.s4),
                  children: [
                    const TratraAlert(
                      tone: TratraAlertTone.danger,
                      title: 'Action définitive',
                      message: 'Votre compte est anonymisé immédiatement : nom, téléphone, e-mail, photo, adresses, messages, statuts, '
                          'pièces d’identité et images du visage sont effacés, et vous êtes déconnecté partout. '
                          'Les réservations, paiements et avis déjà conclus sont conservés sans lien avec votre identité.',
                    ),
                    const SizedBox(height: TtSpace.s4),
                    if (!_allowed) ...[
                      TratraAlert(
                        tone: TratraAlertTone.warning,
                        title: 'Suppression impossible pour le moment',
                        message: _blockers.isEmpty ? 'Une opération est en cours sur votre compte.' : _blockers.map((b) => '• $b').join('\n'),
                      ),
                      const SizedBox(height: TtSpace.s3),
                      Text('Terminez ou annulez ces éléments, puis revenez ici.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                    ] else ...[
                      TratraInput(
                        label: 'Mot de passe',
                        controller: _password,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: TtSpace.s3),
                      TratraInput(
                        label: 'Tapez « $_confirmWord » pour confirmer',
                        controller: _confirm,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (_) => setState(() {}),
                      ),
                      if (_error != null) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
                      const SizedBox(height: TtSpace.s5),
                      TratraButton(
                        label: 'Supprimer mon compte',
                        variant: TratraButtonVariant.danger,
                        size: TratraButtonSize.lg,
                        block: true,
                        loading: _busy,
                        leading: const Icon(Icons.delete_forever_outlined),
                        onPressed: _ready ? _delete : null,
                      ),
                    ],
                  ],
                ),
    );
  }
}
