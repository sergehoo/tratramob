// lib/screens/dashboard/wallet_screen.dart
//
// « Portefeuille » : paiements du compte et, pour un artisan, gains disponibles + retraits.
// Le montant d'un retrait est contrôlé par le serveur (sous verrou) ; ici : confirmation et erreurs.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

const _paymentStatus = <String, TratraStatusView>{
  'pending': TratraStatusView('En attente', TratraTone.accent),
  'held': TratraStatusView('Sous séquestre', TratraTone.info),
  'released': TratraStatusView('Versé à l’artisan', TratraTone.success),
  'completed': TratraStatusView('Payé', TratraTone.success),
  'failed': TratraStatusView('Échoué', TratraTone.danger),
  'refunded': TratraStatusView('Remboursé', TratraTone.gray),
};

const _payoutStatus = <String, TratraStatusView>{
  'pending': TratraStatusView('En attente', TratraTone.accent),
  'sent': TratraStatusView('Envoyé', TratraTone.success),
  'failed': TratraStatusView('Échoué', TratraTone.danger),
};

class _Wallet {
  _Wallet(this.payments, this.payouts, this.available);
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> payouts;
  final num available;
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  final _amount = TextEditingController();
  int _version = 0; // change la clé de la vue → recharge les données
  bool _payouts = false;
  bool _busy = false;
  String? _notice;
  String? _failure;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<_Wallet> _load(bool isProvider) async {
    final payments = await _api.getList('/payments/?ordering=-created_at&page_size=50');
    if (!isProvider) return _Wallet(payments, const [], 0);
    final payouts = await _api.getList('/payouts/?page_size=50');
    final av = await _api.getMap('/payouts/available/');
    return _Wallet(payments, payouts, num.tryParse('${av['available']}') ?? 0);
  }

  Future<void> _request(num available) async {
    final value = num.tryParse(_amount.text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));
    if (value == null || value <= 0) {
      setState(() => _failure = 'Saisissez un montant valide.');
      return;
    }
    if (value > available) {
      setState(() => _failure = 'Ce montant dépasse vos gains disponibles.');
      return;
    }
    final ok = await showTratraConfirm(
      context,
      title: 'Confirmer le retrait',
      message: 'Vous demandez le retrait de ${formatFcfa(value)}. Cette demande sera traitée par l’équipe Tratra.',
    );
    if (!ok || !mounted) return;
    final dash = context.read<DashboardController>();
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await _api.post('/payouts/', {'amount': '$value'});
      _amount.clear();
      _notice = 'Votre demande de retrait a bien été enregistrée.';
      _payouts = true;
      dash.load();
      _version++;
    } catch (e) {
      _failure = friendlyError(e, 'La demande de retrait a échoué.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = context.watch<DashboardController>().data?.isProvider ?? false;
    return DashPage(
      title: 'Portefeuille',
      body: ApiView<_Wallet>(
        key: ValueKey('wallet-$isProvider-$_version'),
        errorTitle: 'Portefeuille indisponible',
        load: () => _load(isProvider),
        builder: (context, w, reload) {
          final list = _payouts ? w.payouts : w.payments;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
            children: [
              if (isProvider) ...[
                TratraCard(
                  variant: TratraCardVariant.night,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('GAINS DISPONIBLES', style: TratraTheme.style(TtType.eyebrow, color: Colors.white60)),
                    const SizedBox(height: TtSpace.s1),
                    Text(fcfaOrZero(w.available), style: TratraTheme.style(TtType.h1, color: Colors.white)),
                    const SizedBox(height: TtSpace.s1),
                    Text('Montants versés après la fin des prestations, hors retraits déjà demandés.',
                        style: TratraTheme.style(TtType.caption, color: Colors.white60)),
                    const SizedBox(height: TtSpace.s4),
                    if (w.available > 0) ...[
                      Text('Montant à retirer (FCFA)', style: TratraTheme.style(TtType.bodySm, color: Colors.white).copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TratraInput(
                        controller: _amount,
                        hint: 'Max. ${formatFcfa(w.available)}',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
                      ),
                      const SizedBox(height: TtSpace.s3),
                      TratraButton(
                        label: 'Demander un retrait',
                        variant: TratraButtonVariant.accent,
                        block: true,
                        loading: _busy,
                        leading: const Icon(Icons.south_rounded, size: 18),
                        onPressed: () => _request(w.available),
                      ),
                    ] else
                      Text('Aucun gain disponible pour le moment : un retrait devient possible une fois une prestation payée et terminée.',
                          style: TratraTheme.style(TtType.bodySm, color: Colors.white70)),
                  ]),
                ),
                const SizedBox(height: TtSpace.s3),
              ],
              if (_notice != null) TratraAlert(tone: TratraAlertTone.success, message: _notice!),
              if (_failure != null) TratraAlert(tone: TratraAlertTone.danger, message: _failure!),
              if (isProvider)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: TtSpace.s3),
                  child: Wrap(spacing: TtSpace.s2, children: [
                    TratraChip(label: 'Paiements (${w.payments.length})', selected: !_payouts, onTap: () => setState(() => _payouts = false)),
                    TratraChip(label: 'Retraits (${w.payouts.length})', selected: _payouts, onTap: () => setState(() => _payouts = true)),
                  ]),
                ),
              if (list.isEmpty)
                SizedBox(
                  height: 280,
                  child: TratraEmptyState(
                    icon: _payouts ? Icons.south_rounded : Icons.account_balance_wallet_outlined,
                    title: _payouts ? 'Aucun retrait' : 'Aucun paiement',
                    description: _payouts
                        ? 'Vos demandes de retrait et leur traitement apparaîtront ici.'
                        : 'Vos paiements apparaîtront ici dès votre première réservation payée.',
                  ),
                )
              else
                for (final p in list) ...[
                  _PaymentRow(row: p, payout: _payouts),
                  const SizedBox(height: TtSpace.s2),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.row, required this.payout});
  final Map<String, dynamic> row;
  final bool payout;

  @override
  Widget build(BuildContext context) {
    final amount = num.tryParse('${row['amount']}') ?? 0;
    final detail = row['booking_detail'];
    final svc = detail is Map ? detail['service_detail'] : null;
    final title = payout
        ? 'Retrait n° ${row['id']}'
        : (svc is Map && svc['title'] != null ? '${svc['title']}' : 'Réservation n° ${row['booking'] ?? row['id']}');
    final dateRaw = payout ? row['requested_at'] : (row['payment_date'] ?? row['created_at']);
    final date = DateTime.tryParse('${dateRaw ?? ''}');
    final processed = payout ? DateTime.tryParse('${row['processed_at'] ?? ''}') : null;
    final meta = [
      if (date != null) payout ? 'Demandé le ${formatWhen(date)}' : formatWhen(date),
      if (processed != null) 'traité le ${formatWhen(processed)}',
      if (!payout && row['method'] != null) '${row['method']}',
    ].join(' · ');
    return TratraCard(
      padding: TratraCard.compact,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.title)),
            Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          ]),
        ),
        const SizedBox(width: TtSpace.s2),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fcfaOrZero(amount), style: TratraTheme.style(TtType.title)),
          const SizedBox(height: 4),
          TratraStatusBadge(payout ? _payoutStatus : _paymentStatus, '${row['status']}'),
        ]),
      ]),
    );
  }
}
