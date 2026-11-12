// lib/screens/dashboard/legal_info_screen.dart
//
// Paramètres → Informations légales : pages publiques (Conditions d'utilisation, confidentialité, suppression de compte) et
// version des conditions acceptée par le compte (GET /me/terms/). Une nouvelle version n'est jamais acceptée à la place de la
// personne : elle coche la case puis confirme (POST /me/terms/ {version, accept: true}) ; le serveur enregistre version et date.
// Les liens restent disponibles même si le statut ne peut pas être lu (hors connexion, serveur antérieur).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/legal.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/labels.dart' show dateFr, dateTimeFr;
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

class LegalInfoScreen extends StatefulWidget {
  const LegalInfoScreen({super.key, this.opener});

  /// Ouverture d'une page (tests) ; par défaut le navigateur intégré.
  final LegalOpener? opener;

  @override
  State<LegalInfoScreen> createState() => _LegalInfoScreenState();
}

class _LegalInfoScreenState extends State<LegalInfoScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  Map<String, dynamic>? _status;
  bool _loading = true;
  bool _unavailable = false;
  bool _accept = false; // jamais précochée
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _unavailable = false;
    });
    try {
      final s = await _api.getMap('/me/terms/');
      if (mounted) setState(() => _status = s);
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acceptCurrent(String version) async {
    setState(() => _busy = true);
    try {
      final s = await _api.post('/me/terms/', {'version': version, 'accept': true, 'source': 'app'});
      if (!mounted) return;
      setState(() {
        _status = s;
        _accept = false;
      });
      showMessage(context, 'Votre acceptation des Conditions d’utilisation est enregistrée.');
    } catch (e) {
      if (!mounted) return;
      if (outdatedTermsVersion(e) != null) {
        setState(() => _accept = false);
        await _load();                       // une version plus récente vient d'être publiée : la personne la relit
      }
      if (mounted) showMessage(context, friendlyError(e, 'L’acceptation n’a pas pu être enregistrée. Réessayez.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _statusCard() {
    if (_loading) return const Padding(padding: EdgeInsets.all(TtSpace.s4), child: Center(child: CircularProgressIndicator()));
    final s = _status;
    if (_unavailable || s == null) {
      return TratraAlert(
        tone: TratraAlertTone.info,
        title: 'Statut indisponible',
        message: 'La version que vous avez acceptée n’a pas pu être chargée. Les pages ci-dessous restent consultables.',
        action: TextButton(onPressed: _load, child: const Text('Réessayer')),
      );
    }
    final current = (s['current'] as Map?)?.cast<String, dynamic>() ?? const {};
    final version = '${current['version'] ?? ''}';
    final accepted = s['accepted_version'] as String?;
    final acceptedAt = s['accepted_at'] as String?;
    final upToDate = s['up_to_date'] == true;
    return TratraCard(
      key: const ValueKey('legal-status'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Conditions d’utilisation', style: TratraTheme.style(TtType.h3)),
        const SizedBox(height: TtSpace.s1),
        Text('Version en vigueur : $version, du ${dateFr('${current['updated_on'] ?? ''}')}',
            style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        const SizedBox(height: TtSpace.s3),
        if (upToDate)
          TratraAlert(
            tone: TratraAlertTone.success,
            title: 'Version acceptée',
            message: 'Vous avez accepté cette version le ${dateTimeFr(acceptedAt)}.',
          )
        else ...[
          TratraAlert(
            tone: TratraAlertTone.warning,
            title: 'Nouvelle version à lire',
            message: accepted != null
                ? 'Vous avez accepté la version $accepted le ${dateTimeFr(acceptedAt)}. Une nouvelle version est en vigueur.'
                : acceptedAt != null
                    ? 'Vous avez accepté les conditions le ${dateTimeFr(acceptedAt)}, avant leur version actuelle.'
                    : 'Aucune acceptation n’est enregistrée pour ce compte.',
          ),
          const SizedBox(height: TtSpace.s2),
          TermsConsent(
            key: const ValueKey('legal-consent'),
            value: _accept,
            enabled: !_busy,
            opener: widget.opener,
            onChanged: (v) => setState(() => _accept = v),
          ),
          const SizedBox(height: TtSpace.s2),
          TratraButton(
            key: const ValueKey('legal-accept'),
            label: 'Enregistrer mon acceptation',
            block: true,
            loading: _busy,
            onPressed: _accept && !_busy && version.isNotEmpty ? () => _acceptCurrent(version) : null,
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.opener ?? openLegalPage;
    final links = <(IconData, String, String, Uri, Key)>[
      (Icons.gavel_rounded, 'Conditions d’utilisation', 'Règles du service pour les clients et les professionnels', LegalLinks.terms, const ValueKey('legal-terms')),
      (Icons.privacy_tip_outlined, 'Politique de confidentialité', 'Données collectées, conservation, vos droits', LegalLinks.privacy, const ValueKey('legal-privacy')),
      (Icons.person_remove_outlined, 'Suppression de compte', 'Comment supprimer votre compte et vos données', LegalLinks.accountDeletion, const ValueKey('legal-deletion')),
    ];
    return DashPage(
      title: 'Informations légales',
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s8),
          children: [
            _statusCard(),
            const SizedBox(height: TtSpace.s4),
            TratraCard(
              padding: const EdgeInsets.symmetric(horizontal: TtSpace.s2, vertical: TtSpace.s1),
              child: Column(children: [
                for (var i = 0; i < links.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    key: links[i].$5,
                    leading: Icon(links[i].$1, color: TtColors.primary),
                    title: Text(links[i].$2),
                    subtitle: Text(links[i].$3, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                    trailing: const Icon(Icons.open_in_new_rounded, color: TtColors.ash, size: 20),
                    onTap: () => open(context, links[i].$4),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
