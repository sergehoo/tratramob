// lib/screens/trust/passport_screen.dart
//
// Passeport professionnel public d'un artisan (Tratra Trust) : identité vérifiée, badges cumulables,
// score expliqué, compétences certifiées / déclarées, chiffres mesurés, avis réels et historique.
// GET /handymen/{id}/trust/ et /handymen/{id}/reviews/ — mêmes données et mêmes règles que le web (/artisans/{id}).
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart' show friendlyError;
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/trust/trust_widgets.dart';

class PassportScreen extends StatefulWidget {
  const PassportScreen({super.key, required this.profileId});
  final String profileId;

  @override
  State<PassportScreen> createState() => _PassportScreenState();
}

class _PassportScreenState extends State<PassportScreen> {
  late final BaseApi _api = context.read<BaseApi>();
  Map<String, dynamic>? _passport;
  Map<String, dynamic>? _reviews; // {stats, results}
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Lecture publique : l'en-tête d'authentification n'est jamais indispensable (jeton expiré toléré).
  Future<http.Response> _get(String path) async {
    final uri = Uri.parse('${_api.baseUrl}$path');
    var r = await _api.client.get(uri, headers: await _api.getHeaders(withAuth: true));
    if (r.statusCode == 401) r = await _api.client.get(uri, headers: await _api.getHeaders(withAuth: false));
    return r;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _get('/handymen/${widget.profileId}/trust/');
      if (r.statusCode == 404) throw Exception('Ce passeport n’est pas disponible : le profil n’est pas publié.');
      if (r.statusCode != 200) _api.handleError(r);
      final body = _api.decodeBody(r);
      final rr = await _get('/handymen/${widget.profileId}/reviews/');
      Map<String, dynamic>? reviews;
      if (rr.statusCode == 200) {
        final d = _api.decodeBody(rr);
        if (d is Map) reviews = d.cast<String, dynamic>();
      }
      if (!mounted) return;
      setState(() {
        _passport = (body as Map).cast<String, dynamic>();
        _reviews = reviews;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _passport;
    return DashPage(
      title: 'Passeport professionnel',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? Center(
                  child: TratraEmptyState(
                    icon: Icons.badge_outlined,
                    title: 'Passeport indisponible',
                    description: _error ?? 'Réessayez dans un instant.',
                    actions: [TratraButton(label: 'Réessayer', onPressed: _load)],
                  ),
                )
              : RefreshIndicator(onRefresh: _load, child: PassportBody(passport: p, reviews: _reviews)),
    );
  }
}

/// Corps du passeport (public) : défilant, tirer pour rafraîchir.
class PassportBody extends StatelessWidget {
  const PassportBody({super.key, required this.passport, this.reviews});
  final Map<String, dynamic> passport;
  final Map<String, dynamic>? reviews;

  @override
  Widget build(BuildContext context) {
    final p = passport;
    final identity = (p['identity'] as Map?)?.cast<String, dynamic>() ?? const {};
    final missions = (p['missions'] as Map?)?.cast<String, dynamic>() ?? const {};
    final sat = (p['satisfaction'] as Map?)?.cast<String, dynamic>() ?? const {};
    final pun = (p['punctuality'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rea = (p['reactivity'] as Map?)?.cast<String, dynamic>() ?? const {};
    final exp = (p['experience'] as Map?)?.cast<String, dynamic>() ?? const {};
    final skills = (p['skills'] as Map?)?.cast<String, dynamic>() ?? const {};
    final certified = maps(skills['certified']);
    final declared = maps(skills['declared']);
    final verified = identity['verified'] == true;
    final reviewRows = maps(reviews?['results']);
    final avg = sat['average'];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
      children: [
        TratraCard(
          padding: TratraCard.compact,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              TratraAvatar(name: '${p['display_name']}', photoUrl: p['photo'] as String?, size: 64),
              const SizedBox(width: TtSpace.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['display_name']}', style: TratraTheme.style(TtType.h2)),
                  if ('${p['commune'] ?? ''}'.isNotEmpty)
                    Text('${p['commune']}', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                  Text('Membre depuis ${fmtDate(p['member_since'])}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                ]),
              ),
            ]),
            const SizedBox(height: TtSpace.s3),
            TratraTrustBadges(trustBadgeCodes(p['badges'])),
            const SizedBox(height: TtSpace.s3),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.how_to_reg_outlined, size: 18, color: TtColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  verified
                      ? 'Identité vérifiée par Tratra${identity['verified_on'] != null ? ' le ${fmtDate(identity['verified_on'])}' : ''}'
                      : 'Identité non vérifiée',
                  style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            const SourceTag('vérifié'),
          ]),
        ),
        const SizedBox(height: TtSpace.s3),
        TratraCard(
          padding: TratraCard.compact,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Chiffres clés', style: TratraTheme.style(TtType.h3)),
            Text('Mesurés sur les interventions réelles réalisées via Tratra.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            const SizedBox(height: TtSpace.s3),
            FactTile(
              icon: Icons.workspace_premium_outlined,
              label: 'Missions terminées',
              value: '${missions['completed'] ?? 0}',
              hint: '${missions['completed_window'] ?? 0} sur les ${missions['window_days'] ?? 365} derniers jours',
              source: 'plateforme',
            ),
            const SizedBox(height: TtSpace.s2),
            FactTile(
              icon: Icons.star_outline_rounded,
              label: 'Satisfaction',
              value: avg is num ? '${fmtDecimal(avg)}/5' : '—',
              hint: (sat['count'] ?? 0) > 0 ? '${sat['count']} avis de clients' : 'Pas encore d’avis',
              source: 'plateforme',
            ),
            const SizedBox(height: TtSpace.s2),
            FactTile(
              icon: Icons.schedule_rounded,
              label: 'Ponctualité',
              value: fmtPercent(pun['rate']),
              hint: pun['rate'] != null
                  ? '${pun['on_time']} / ${pun['sample']} missions à l’heure (tolérance ${pun['tolerance_minutes']} min)'
                  : 'Pas encore assez de missions mesurées (${pun['sample'] ?? 0}/${pun['min_sample'] ?? 3})',
              source: 'plateforme',
            ),
            const SizedBox(height: TtSpace.s2),
            FactTile(
              icon: Icons.hourglass_bottom_rounded,
              label: 'Réactivité',
              value: fmtMinutes(rea['median_minutes']),
              hint: rea['median_minutes'] != null
                  ? 'Délai médian de réponse · ${rea['sample']} demandes'
                  : 'Pas encore assez de demandes traitées (${rea['sample'] ?? 0}/${rea['min_sample'] ?? 3})',
              source: 'plateforme',
            ),
            const SizedBox(height: TtSpace.s3),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Expérience déclarée : ${exp['years'] ?? 0} an${(exp['years'] ?? 0) > 1 ? 's' : ''}',
                  style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft)),
              const SourceTag('déclaré'),
            ]),
          ]),
        ),
        const SizedBox(height: TtSpace.s3),
        TratraCard(
          padding: TratraCard.compact,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Compétences', style: TratraTheme.style(TtType.h3)),
            const SizedBox(height: TtSpace.s3),
            Text('Certifiées', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (certified.isEmpty)
              Text('Aucun justificatif approuvé pour le moment.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash))
            else
              for (final c in certified) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(TtSpace.s3),
                  decoration: BoxDecoration(border: Border.all(color: TtColors.lineSoft), borderRadius: BorderRadius.circular(TtRadius.control)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c['title']}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      [
                        (c['category'] as Map?)?['name'],
                        if ('${c['issuer'] ?? ''}'.isNotEmpty) c['issuer'],
                        if (c['issued_on'] != null) 'délivré le ${fmtDate(c['issued_on'])}',
                        if (c['expires_on'] != null) 'valable jusqu’au ${fmtDate(c['expires_on'])}',
                      ].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                      style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                    ),
                    const SizedBox(height: 4),
                    const SourceTag('vérifié'),
                  ]),
                ),
                const SizedBox(height: TtSpace.s2),
              ],
            const SizedBox(height: TtSpace.s2),
            Text('Déclarées', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (declared.isEmpty)
              Text('Aucune spécialité renseignée.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash))
            else
              Wrap(spacing: 6, runSpacing: 6, children: [for (final s in declared) TratraBadge('${s['name']}', tone: TratraTone.gray)]),
            const SizedBox(height: 6),
            const SourceTag('déclaré'),
          ]),
        ),
        const SizedBox(height: TtSpace.s3),
        ScoreBreakdownCard(score: (p['score'] as Map?)?.cast<String, dynamic>() ?? const {}),
        const SizedBox(height: TtSpace.s3),
        TratraCard(
          padding: TratraCard.compact,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Avis des clients', style: TratraTheme.style(TtType.h3)),
            Text('Uniquement des clients ayant réellement fait réaliser une mission terminée.',
                style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            const SizedBox(height: TtSpace.s3),
            if (avg is num && (sat['count'] ?? 0) > 0) ...[
              Text('${fmtDecimal(avg)} / 5', style: TratraTheme.style(TtType.h1)),
              Text('${sat['count']} avis${sat['response_rate'] is num ? ' · ${fmtPercent(sat['response_rate'])} avec réponse de l’artisan' : ''}',
                  style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
              const SizedBox(height: TtSpace.s3),
            ],
            if (reviewRows.isEmpty)
              Text('Cet artisan n’a pas encore reçu d’avis.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash))
            else
              for (final r in reviewRows.take(10)) ...[
                _PublicReview(review: r),
                const SizedBox(height: TtSpace.s2),
              ],
          ]),
        ),
        const SizedBox(height: TtSpace.s3),
        BadgeHistoryCard(history: maps(p['history'])),
      ],
    );
  }
}

class _PublicReview extends StatelessWidget {
  const _PublicReview({required this.review});
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final rating = ((review['rating'] ?? 0) as num).toInt();
    final reply = review['reply'] as Map?;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(TtSpace.s3),
      decoration: BoxDecoration(color: TtColors.canvas, borderRadius: BorderRadius.circular(TtRadius.panel)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 1; i <= 5; i++)
            Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: i <= rating ? TtColors.accent : TtColors.fog),
          const Spacer(),
          Text(fmtDate(review['created_at']), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        ]),
        if ('${review['comment'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('${review['comment']}', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        ],
        if (reply != null) ...[
          const SizedBox(height: 6),
          Text('Réponse de l’artisan : ${reply['text']}', style: TratraTheme.style(TtType.caption, color: TtColors.primaryDark)),
        ],
        const SizedBox(height: 4),
        Text('${review['author']}${review['category'] != null ? ' · ${review['category']}' : ''}',
            style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
      ]),
    );
  }
}
