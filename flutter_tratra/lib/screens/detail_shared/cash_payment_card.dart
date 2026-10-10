// lib/screens/detail_shared/cash_payment_card.dart
//
// Carte « Paiement en espèces » d'une réservation, commune à la vue client (suivi) et à la vue artisan (mission) : état, historique,
// déclaration (justificatif facultatif) et confirmation par l'AUTRE partie. Rien n'est présenté comme vérifié par un prestataire :
// les espèces remises en main propre ne passent pas par Tratra — la mention du serveur est affichée telle quelle.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/evidence_viewer.dart' show PdfBodyBuilder;
import 'package:flutter_tratra/engagements/labels.dart';
import 'package:flutter_tratra/services/cash_service.dart';

const _stateFr = {
  'none': 'Aucun paiement déclaré',
  'awaiting_confirmation': 'À confirmer',
  'partial': 'Réglé en partie',
  'paid': 'Réglé en espèces',
  'contested': 'Contesté',
};

TratraTone _stateTone(String s) => switch (s) {
      'paid' => TratraTone.success,
      'contested' => TratraTone.danger,
      'none' => TratraTone.gray,
      _ => TratraTone.accent,
    };

class CashPaymentCard extends StatefulWidget {
  const CashPaymentCard({super.key, required this.bookingId, required this.bookingStatus, this.pdfBodyBuilder});
  final int bookingId;
  final String bookingStatus;

  /// Remplaçable dans les tests (le moteur PDF natif n'existe pas hors appareil).
  final PdfBodyBuilder? pdfBodyBuilder;

  @override
  State<CashPaymentCard> createState() => _CashPaymentCardState();
}

class _CashPaymentCardState extends State<CashPaymentCard> {
  Json? _cash;
  bool _loaded = false;
  String? _error;
  final String _base = randomHex();

  CashService get _api => context.read<CashService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CashPaymentCard old) {
    super.didUpdateWidget(old);
    if (old.bookingStatus != widget.bookingStatus || old.bookingId != widget.bookingId) _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _cash = r['cash'] is Map ? (r['cash'] as Map).cast<String, dynamic>() : null;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = messageOf(e, 'Le paiement ne peut pas être chargé pour le moment.');
          _loaded = true;
        });
      }
    }
  }

  void _apply(Map<String, dynamic> r) {
    if (!mounted) return;
    setState(() => _cash = r['cash'] is Map ? (r['cash'] as Map).cast<String, dynamic>() : _cash);
  }

  Future<void> _declare(Json cash) async {
    String? file;
    final today = DateTime.now();
    final remaining = cash['remaining'] == null ? null : num.tryParse(cash.s('remaining'));
    final done = await showActionSheet(
      context,
      title: cash.s('my_role') == 'client' ? 'Déclarer un paiement en espèces remis' : 'Déclarer des espèces reçues',
      description: 'Cette déclaration ne comptera qu’une fois confirmée par ${cash.s('my_role') == 'client' ? 'l’artisan' : 'le client'}. '
          'Les espèces ne passent pas par Tratra : déclarez uniquement un montant réellement remis en main propre.',
      confirmLabel: 'Déclarer',
      header: AttachPicker(onPicked: (p) => file = p),
      fields: [
        FieldSpec('amount', 'Montant (FCFA)',
            kind: FieldKind.number, required: true, initial: remaining != null && remaining > 0 ? '${remaining.round()}' : '',
            hint: remaining != null ? 'Solde restant à régler : ${fcfa(remaining)}.' : 'Indiquez le montant réellement remis.'),
        FieldSpec('paid_on', 'Date de la remise', kind: FieldKind.date, required: true, initial: isoDay(today), lastDate: today),
        const FieldSpec('note', 'Précision', optional: true, hint: 'Ex. remis à la fin de l’intervention.', maxLength: 200),
      ],
      submit: (v) async {
        final r = await _api.declare(widget.bookingId, {'amount': v['amount'] ?? '', 'paid_on': v['paid_on'] ?? '', 'note': v['note'] ?? ''},
            filePath: file, idempotencyKey: intentKey('cash', _base, {...v, 'f': file}));
        _apply(r);
      },
    );
    if (done && mounted) _load();
  }

  Future<void> _contest(Json d) async {
    final done = await showActionSheet(
      context,
      title: 'Contester cette déclaration',
      description: 'Le motif est transmis à l’autre partie et conservé dans l’historique. Vous pourrez ensuite déclarer le montant exact.',
      confirmLabel: 'Contester',
      danger: true,
      fields: const [FieldSpec('reason', 'Motif de la contestation', kind: FieldKind.multiline, required: true, hint: '5 caractères au minimum.', maxLength: 500)],
      submit: (v) async => _apply(await _api.respond(d.i('id'), false, v['reason'] ?? '')),
    );
    if (done && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const TratraSkeletonList(count: 1);
    if (_error != null && _cash == null) return TratraAlert(message: _error!, tone: TratraAlertTone.danger);
    final cash = _cash;
    if (cash == null) return const SizedBox.shrink(); // règlement par un prestataire : pas de carte « espèces »
    final history = cash.l('history');
    final state = cash.s('state');
    return TratraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Paiement en espèces', style: TratraTheme.style(TtType.h3)),
          const SizedBox(height: 2),
          Text('Déclaré par une partie, confirmé par l’autre.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          const SizedBox(height: TtSpace.s3),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            TratraBadge(_stateFr[state] ?? state, tone: _stateTone(state)),
            if (cash['due'] != null) Text('Convenu : ${fcfa(cash.s('due'))} · confirmé : ${fcfa(cash.s('confirmed'))}', style: TratraTheme.style(TtType.bodySm)),
          ]),
          const SizedBox(height: TtSpace.s3),
          if (history.isEmpty)
            Text(['in_progress', 'completed'].contains(widget.bookingStatus) ? 'Aucun paiement déclaré pour l’instant.' : 'Le paiement se déclare une fois la prestation commencée.',
                style: TratraTheme.style(TtType.bodySm, color: TtColors.ash))
          else
            for (final d in history)
              _DeclarationTile(
                key: ValueKey('decl-${d.i('id')}'),
                d: d,
                api: _api,
                pdfBodyBuilder: widget.pdfBodyBuilder,
                onConfirm: () async => _apply(await _api.respond(d.i('id'), true)),
                onContest: () => _contest(d),
              ),
          if (history.any((d) => d.b('can_respond'))) ...[
            const SizedBox(height: TtSpace.s2),
            const TratraAlert(message: 'Une déclaration attend votre confirmation.', tone: TratraAlertTone.info),
          ],
          if (cash.b('can_declare')) ...[
            const SizedBox(height: TtSpace.s3),
            TratraButton(label: 'Déclarer un paiement en espèces', leading: const Icon(Icons.payments_outlined, size: 18), onPressed: () => _declare(cash)),
          ],
          const SizedBox(height: TtSpace.s3),
          Text(cash.s('note'), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        ],
      ),
    );
  }
}

class _DeclarationTile extends StatelessWidget {
  const _DeclarationTile({super.key, required this.d, required this.api, required this.onConfirm, required this.onContest, this.pdfBodyBuilder});
  final Json d;
  final CashService api;
  final Future<void> Function() onConfirm;
  final VoidCallback onContest;
  final PdfBodyBuilder? pdfBodyBuilder;

  @override
  Widget build(BuildContext context) {
    final status = d.s('status');
    final tone = status == 'confirmed' ? TratraTone.success : (status == 'declared' ? TratraTone.accent : TratraTone.danger);
    final label = status == 'confirmed' ? 'Confirmé' : (status == 'declared' ? 'À confirmer' : 'Contesté');
    final who = d.b('mine') ? 'vous' : (d.s('declared_by_role') == 'artisan' ? 'l’artisan' : 'le client');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: TtColors.canvas, borderRadius: BorderRadius.circular(TtRadius.control)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(fcfa(d.s('amount')), style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700))),
          TratraBadge(label, tone: tone),
        ]),
        const SizedBox(height: 2),
        Text('Déclaré par $who · remis le ${dateFr(d.sn('paid_on'))}${d.s('note').isNotEmpty ? ' · ${d.s('note')}' : ''}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        if (status == 'rejected' && d.s('rejection_reason').isNotEmpty)
          Text('Motif de contestation : ${d.s('rejection_reason')}', style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk)),
        if (d['receipt'] is Map) EvidenceLink(api: api, evidence: {'name': 'justificatif', 'url': d.m('receipt').s('url')}, pdfBodyBuilder: pdfBodyBuilder),
        if (status == 'declared' && d.b('mine'))
          Text('En attente de confirmation de l’autre partie : un paiement ne se confirme jamais soi-même.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        if (d.b('can_respond'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              AsyncAction(label: 'Je confirme avoir ${d.s('declared_by_role') == 'artisan' ? 'payé' : 'reçu'} ce montant', run: onConfirm),
              TratraButton(label: 'Contester', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: onContest),
            ]),
          ),
      ]),
    );
  }
}
