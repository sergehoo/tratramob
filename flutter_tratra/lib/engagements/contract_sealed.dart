// lib/engagements/contract_sealed.dart
//
// Contrats établis sur un modèle VALIDÉ par revue juridique : signature électronique SIMPLE des parties (distincte du scellement
// numérique de Tratra), articles figés, documents scellés (référence TRT-CTR, QR de vérification publique, empreinte SHA-256).
// Le PDF ne s'ouvre que pour les parties, dans l'application (même lecteur que les pièces justificatives).
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/evidence_viewer.dart';
import 'package:flutter_tratra/engagements/labels.dart';

const _stageFr = {'for_signature': 'Version à signer', 'final': 'Contrat signé'};

Future<void> openSealedPdf(BuildContext context, EngagementsApi api, Json doc) async {
  try {
    final bytes = await api.download(doc.s('download'));
    if (!context.mounted) return;
    if (!EvidenceFiles.looksLikePdf(bytes)) throw const FormError('Document illisible.');
    await Navigator.of(context).push<void>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EvidencePdfPage(bytes: bytes, title: '${doc.s('reference')} (v${doc.s('version')})'),
    ));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageOf(e, 'Document indisponible.'))));
    }
  }
}

/// Signature d'une partie : porte sur le document à signer EXACT (empreinte) ; les deux signatures émettent le contrat final scellé.
class SignContractCard extends StatefulWidget {
  const SignContractCard({super.key, required this.api, required this.c, required this.onChanged});
  final EngagementsApi api;
  final Json c;
  final Future<void> Function() onChanged;
  @override
  State<SignContractCard> createState() => _SignContractCardState();
}

class _SignContractCardState extends State<SignContractCard> {
  final _base = randomHex();
  bool _read = false;
  bool _busy = false;
  String? _error;

  Json? get _toSign {
    final docs = widget.c.l('documents').where((d) =>
        d.s('kind') == 'contract' && d.s('stage') == 'for_signature' && d.s('version') == widget.c.s('terms_version') && d.sn('revoked_at') == null);
    return docs.isEmpty ? null : docs.last;
  }

  Future<void> _sign() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('/contracts/${widget.c.i('id')}/sign/', {'consent': true}, intentKey('sign', _base, widget.c.s('terms_version')));
      await widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => _error = messageOf(e, 'Signature impossible. Rien n’a été enregistré.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    if (!c.b('signature_required') || c.s('status') != 'accepted') return const SizedBox.shrink();
    final role = c.s('my_role');
    final sigs = c.m('signatures');
    final mine = sigs.sn(role);
    final theirs = sigs.sn(role == 'worker' ? 'principal' : 'worker');
    if (mine != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TratraAlert(
          tone: TratraAlertTone.info,
          title: 'Vous avez signé',
          message: 'Signé le ${dateTimeFr(mine)}.${theirs == null ? ' ${c.m('counterpart').s('name')} doit encore signer : vous serez prévenu(e).' : ''}',
        ),
      );
    }
    final doc = _toSign;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TratraCard(
        variant: TratraCardVariant.accent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Contrat à signer', style: TratraTheme.style(TtType.h2)),
          const SizedBox(height: 6),
          Text('Les conditions sont acceptées par les deux parties. Lisez le document ${c.s('reference')} puis signez : votre signature porte sur ce fichier exact.',
              style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
          if (doc != null) ...[
            const SizedBox(height: 10),
            TratraButton(label: 'Lire le document à signer (PDF)', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline,
                onPressed: () => openSealedPdf(context, widget.api, doc)),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _read,
            onChanged: (v) => setState(() => _read = v == true),
            title: Text('J’ai lu le contrat ${c.s('reference')} (version ${c.s('terms_version')}) et je le signe électroniquement.', style: TratraTheme.style(TtType.bodySm)),
          ),
          Text('Signature électronique simple : votre compte, la date, l’heure et l’empreinte du document sont enregistrés. Après les deux signatures, Tratra '
              'émet le contrat final, scellé numériquement et vérifiable par son QR code.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          if (theirs != null) ...[const SizedBox(height: 6), Text('${c.m('counterpart').s('name')} a déjà signé le ${dateTimeFr(theirs)}.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft))],
          if (_error != null) ...[const SizedBox(height: 10), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
          const SizedBox(height: 12),
          TratraButton(label: 'Signer le contrat', block: true, loading: _busy, onPressed: _read && !_busy ? _sign : null),
        ]),
      ),
    );
  }
}

/// Articles figés du contrat (texte exact accepté puis signé).
class ContractArticlesCard extends StatelessWidget {
  const ContractArticlesCard({super.key, required this.c});
  final Json c;
  @override
  Widget build(BuildContext context) {
    final articles = c.l('articles');
    if (articles.isEmpty) return const SizedBox.shrink();
    final t = c['template'] is Map ? c.m('template') : null;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TratraCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Articles du contrat', style: TratraTheme.style(TtType.h2)),
          if (t != null) ...[
            const SizedBox(height: 4),
            Text('Modèle « ${t.s('title')} » (version ${t.s('version')}) — ${t.s('status_label').toLowerCase()}.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          ],
          const SizedBox(height: 10),
          for (final a in articles) ...[
            Text('Article ${a.s('number')} — ${a.s('title')}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(a.s('body'), style: TratraTheme.style(TtType.body, color: TtColors.inkSoft)),
            const SizedBox(height: 12),
          ],
        ]),
      ),
    );
  }
}

/// Documents scellés : référence, empreinte, ouverture du PDF (parties uniquement). L'original n'est jamais modifié par un avenant.
class ContractDocumentsCard extends StatelessWidget {
  const ContractDocumentsCard({super.key, required this.api, required this.c});
  final EngagementsApi api;
  final Json c;
  @override
  Widget build(BuildContext context) {
    final docs = c.l('documents');
    if (docs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TratraCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Documents scellés', style: TratraTheme.style(TtType.h2)),
          const SizedBox(height: 4),
          Text('Chaque document porte une référence unique, un QR code de vérification publique et le scellement numérique de Tratra. Un avenant produit '
              'un nouveau document : l’original n’est jamais modifié.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          const SizedBox(height: 8),
          for (final d in docs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(d.sn('revoked_at') != null ? Icons.gpp_bad_outlined : Icons.verified_outlined,
                  color: d.sn('revoked_at') != null ? TtColors.danger : TtColors.primary),
              title: Text(d.s('reference'), style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${d.s('kind') == 'amendment' ? 'Avenant' : _stageFr[d.s('stage')] ?? d.s('stage')} · version ${d.s('version')} · ${dateTimeFr(d.sn('issued_at'))}'
                '${d.sn('revoked_at') != null ? '\nRévoqué : ${d.s('revoked_reason')}' : ''}',
                style: TratraTheme.style(TtType.caption, color: TtColors.ash),
              ),
              trailing: IconButton(
                tooltip: 'Ouvrir le PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => openSealedPdf(context, api, d),
              ),
            ),
        ]),
      ),
    );
  }
}
