// lib/screens/dashboard/reputation_screen.dart
//
// « Ma réputation » (artisan) : badges Tratra Trust cumulables, score expliqué, critères restants pour
// EXPERT / SÛR, dossier à compléter, justificatifs professionnels et historique motivé.
// GET /me/trust/ — mêmes données et mêmes règles que le web (/dashboard/reputation).
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/trust/passport_screen.dart' show PassportScreen;
import 'package:flutter_tratra/screens/trust/trust_widgets.dart';

String _s(dynamic v) => '${v ?? ''}';

/// « 85 % · minimum 85 % » : valeur mesurée et seuil à atteindre.
String _criterion(Map<String, dynamic> c) {
  String fmt(dynamic v) {
    if (v is! num) return '—';
    if (c['unit'] == '%') return '${(v * 100).round()} %';
    final unit = _s(c['unit']);
    return '${fmtDecimal(v)}${unit.isEmpty ? '' : (unit.startsWith('/') ? unit : ' $unit')}';
  }

  return '${fmt(c['current'])} · ${c['higher_better'] == false ? 'maximum' : 'minimum'} ${fmt(c['required'])}';
}

class ReputationScreen extends StatefulWidget {
  const ReputationScreen({super.key});
  @override
  State<ReputationScreen> createState() => _ReputationScreenState();
}

class _ReputationScreenState extends State<ReputationScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  int _version = 0;

  Future<void> _addCertification() async {
    final done = await showTratraSheet<bool>(
      context,
      title: 'Ajouter un justificatif',
      description: 'Diplôme, attestation, habilitation… Il compte pour le badge Expert uniquement une fois approuvé par l’équipe Tratra.',
      child: _CertificationForm(api: _api),
    );
    if (done == true && mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = context.watch<DashboardController>().data?.isProvider ?? false;
    return DashPage(
      title: 'Ma réputation',
      body: !isProvider
          ? Center(
              child: TratraEmptyState(
                icon: Icons.workspace_premium_outlined,
                title: 'Aucun profil artisan',
                description: 'Proposez vos services pour obtenir un passeport professionnel, des badges et un score de confiance.',
                actions: [TratraButton(label: 'Proposer un service', onPressed: () => openProvide(context))],
              ),
            )
          : ApiView<Map<String, dynamic>>(
              key: ValueKey('reputation-$_version'),
              errorTitle: 'Réputation indisponible',
              load: () => _api.getMap('/me/trust/'),
              builder: (context, d, reload) {
                final identity = (d['identity'] as Map?)?.cast<String, dynamic>() ?? const {};
                final verified = identity['verified'] == true;
                final codes = trustBadgeCodes(d['badges']);
                final checklist = maps(d['checklist']);
                final next = (d['next_badges'] as Map?)?.cast<String, dynamic>() ?? const {};
                final pending = maps(d['pending_certifications']);
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
                  children: [
                    Text(
                      'Vos badges et votre score sont calculés automatiquement à partir de données réelles : vérification d’identité, justificatifs approuvés, missions, avis et ponctualité.',
                      style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
                    ),
                    const SizedBox(height: TtSpace.s3),
                    if (codes.isEmpty)
                      Text('Aucun badge actif pour le moment.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash))
                    else
                      TratraTrustBadges(codes),
                    const SizedBox(height: TtSpace.s3),
                    if (verified)
                      TratraButton(
                        label: 'Voir ma fiche publique',
                        variant: TratraButtonVariant.outline,
                        block: true,
                        onPressed: () => pushPage(context, PassportScreen(profileId: _s(d['profile_id']))),
                      )
                    else ...[
                      TratraAlert(
                        tone: TratraAlertTone.warning,
                        title: 'Votre identité n’est pas encore vérifiée',
                        message:
                            'Les badges Vérifié, Expert et Sûr — et la publication de votre fiche — dépendent exclusivement de la vérification d’identité (KYC) par l’équipe Tratra.',
                      ),
                      const SizedBox(height: TtSpace.s2),
                      TratraButton(label: 'Compléter mon dossier', variant: TratraButtonVariant.outline, block: true, onPressed: () => openKyc(context)),
                    ],
                    const SizedBox(height: TtSpace.s4),
                    if (!verified) ...[
                      TratraCard(
                        padding: TratraCard.compact,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Ce qu’il reste à faire', style: TratraTheme.style(TtType.h3)),
                          const SizedBox(height: TtSpace.s3),
                          for (final c in checklist)
                            Padding(
                              padding: const EdgeInsets.only(bottom: TtSpace.s2),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Icon(c['done'] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                    size: 18, color: c['done'] == true ? TtColors.success : TtColors.fog),
                                const SizedBox(width: TtSpace.s2),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(_s(c['label']),
                                        style: TratraTheme.style(TtType.bodySm, color: c['done'] == true ? TtColors.inkSoft : TtColors.ink)
                                            .copyWith(fontWeight: FontWeight.w600)),
                                    if (c['done'] != true) Text(_s(c['hint']), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                                  ]),
                                ),
                              ]),
                            ),
                        ]),
                      ),
                      const SizedBox(height: TtSpace.s3),
                    ],
                    for (final code in const ['EXPERT', 'SUR']) ...[
                      _CriteriaCard(code: code, info: (next[code] as Map?)?.cast<String, dynamic>() ?? const {}, verified: verified),
                      const SizedBox(height: TtSpace.s3),
                    ],
                    if (pending.isNotEmpty) ...[
                      TratraCard(
                        padding: TratraCard.compact,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Justificatifs en cours', style: TratraTheme.style(TtType.h3)),
                          Text('Seuls les justificatifs approuvés comptent pour le badge Expert.',
                              style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                          const SizedBox(height: TtSpace.s3),
                          for (final c in pending)
                            Padding(
                              padding: const EdgeInsets.only(bottom: TtSpace.s2),
                              child: Row(children: [
                                Expanded(child: Text(_s(c['title']).isEmpty ? 'Justificatif' : _s(c['title']), style: TratraTheme.style(TtType.bodySm))),
                                Text(c['status'] == 'rejected' ? 'Refusé' : 'En attente de validation',
                                    style: TratraTheme.style(TtType.caption, color: TtColors.ash).copyWith(fontWeight: FontWeight.w700)),
                              ]),
                            ),
                        ]),
                      ),
                      const SizedBox(height: TtSpace.s3),
                    ],
                    TratraButton(
                      label: 'Ajouter un justificatif',
                      variant: TratraButtonVariant.soft,
                      block: true,
                      leading: const Icon(Icons.workspace_premium_outlined),
                      onPressed: _addCertification,
                    ),
                    const SizedBox(height: TtSpace.s4),
                    ScoreBreakdownCard(score: (d['score'] as Map?)?.cast<String, dynamic>() ?? const {}),
                    const SizedBox(height: TtSpace.s3),
                    BadgeHistoryCard(history: maps(d['history'])),
                  ],
                );
              },
            ),
    );
  }
}

/// Critères d'un badge (EXPERT / SÛR) : atteints ou non, valeur mesurée, seuil, provenance.
class _CriteriaCard extends StatelessWidget {
  const _CriteriaCard({required this.code, required this.info, required this.verified});
  final String code;
  final Map<String, dynamic> info;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final criteria = maps(info['criteria']);
    final met = criteria.where((c) => c['met'] == true).length;
    final earned = info['earned'] == true;
    return TratraCard(
      padding: TratraCard.compact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Badge ${_s(info['label'])}', style: TratraTheme.style(TtType.h3)),
        const SizedBox(height: 2),
        Text(
          earned
              ? 'Badge actif — réévalué automatiquement, retiré si les critères ne sont plus atteints.'
              : !verified
                  ? 'Disponible après la vérification de votre identité.'
                  : '$met critère${met > 1 ? 's' : ''} sur ${criteria.length} atteint${met > 1 ? 's' : ''}.',
          style: TratraTheme.style(TtType.caption, color: TtColors.ash),
        ),
        const SizedBox(height: TtSpace.s3),
        for (final c in criteria)
          Padding(
            padding: const EdgeInsets.only(bottom: TtSpace.s2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(c['met'] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 18, color: c['met'] == true ? TtColors.success : TtColors.fog),
              const SizedBox(width: TtSpace.s2),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_s(c['label']), style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600)),
                  Text(_criterion(c), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                ]),
              ),
              SourceTag(_s(c['source'])),
            ]),
          ),
      ]),
    );
  }
}

/// Dépôt d'un justificatif professionnel (photo ou scan). Il reste « en attente » jusqu'à la validation de l'équipe Tratra.
class _CertificationForm extends StatefulWidget {
  const _CertificationForm({required this.api});
  final DashboardApi api;
  @override
  State<_CertificationForm> createState() => _CertificationFormState();
}

class _CertificationFormState extends State<_CertificationForm> {
  final _title = TextEditingController();
  final _issuer = TextEditingController();
  XFile? _file;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _issuer.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final f = await ImagePicker().pickImage(source: source, imageQuality: 80);
      if (f != null && mounted) setState(() => _file = f);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Impossible d’ouvrir la caméra ou la galerie. Vérifiez les autorisations de l’application.');
      }
    }
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty) return setState(() => _error = 'Indiquez l’intitulé du justificatif.');
    if (_file == null) return setState(() => _error = 'Choisissez une photo ou un scan du justificatif.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.postForm(
        '/handyman-docs/',
        {
          'document_type': 'certification',
          'title': _title.text.trim(),
          if (_issuer.text.trim().isNotEmpty) 'issuer': _issuer.text.trim(),
        },
        'file',
        _file!.path,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, 'L’envoi du justificatif a échoué. Réessayez dans un instant.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TratraInput(controller: _title, label: 'Intitulé', hint: 'Ex. CAP Installateur sanitaire', maxLength: 120),
        const SizedBox(height: TtSpace.s3),
        TratraInput(controller: _issuer, label: 'Organisme émetteur (facultatif)', maxLength: 120),
        const SizedBox(height: TtSpace.s3),
        Row(children: [
          Expanded(
            child: TratraButton(
              label: 'Photo',
              variant: TratraButtonVariant.outline,
              leading: const Icon(Icons.photo_camera_outlined),
              onPressed: _busy ? null : () => _pick(ImageSource.camera),
            ),
          ),
          const SizedBox(width: TtSpace.s2),
          Expanded(
            child: TratraButton(
              label: 'Galerie',
              variant: TratraButtonVariant.outline,
              leading: const Icon(Icons.photo_library_outlined),
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
            ),
          ),
        ]),
        if (_file != null) ...[
          const SizedBox(height: TtSpace.s2),
          Text('Fichier choisi : ${_file!.name}', style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft)),
        ],
        if (_error != null) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
        const SizedBox(height: TtSpace.s4),
        TratraButton(label: 'Envoyer le justificatif', block: true, loading: _busy, onPressed: _send),
      ]);
}
