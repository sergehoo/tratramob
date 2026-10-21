// lib/flash/flash_pro.dart
//
// Côté professionnel : bouton Disponible / Indisponible (règle d'éligibilité unique côté serveur ; aucune mission IMMÉDIATE n'est proposée
// à un professionnel « Indisponible »), propositions en attente et historique de ses réponses.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/screens/worker/mission_detail_screen.dart';

class FlashAvailabilityCard extends StatefulWidget {
  const FlashAvailabilityCard({super.key});
  @override
  State<FlashAvailabilityCard> createState() => _FlashAvailabilityCardState();
}

class _FlashAvailabilityCardState extends State<FlashAvailabilityCard> {
  Map<String, dynamic>? _state;
  bool _busy = false;
  String? _error;

  FlashApi? get _flashApi => context.read<FlashController?>()?.api;
  FlashApi get _api => _flashApi!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_flashApi == null) return;   // écran hors application complète (tests) : aucune carte
    try {
      final s = await _api.availability();
      if (mounted) setState(() => _state = s);
    } on FlashApiError catch (e) {
      if (mounted) setState(() => _error = e.status == 404 ? null : e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Disponibilité indisponible hors connexion.');
    }
  }

  Future<void> _toggle(bool online) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await _api.setAvailability(online);
      if (mounted) setState(() => _state = s);
    } on FlashApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Connexion impossible : réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    if (s == null) return const SizedBox.shrink();
    final online = s['online'] == true;
    final eligible = s['eligible'] == true;
    final pending = int.tryParse('${s['pending_offers'] ?? 0}') ?? 0;
    final missed = int.tryParse('${s['missed_streak'] ?? 0}') ?? 0;
    final pauseAfter = int.tryParse('${s['auto_pause_after'] ?? 0}') ?? 0;
    return TratraCard(
      key: const ValueKey('flash-availability'),
      padding: TratraCard.compact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: online ? TtColors.primarySoft : TtColors.lineSoft, borderRadius: BorderRadius.circular(TtRadius.control)),
            child: Icon(Icons.bolt_rounded, color: online ? TtColors.primary : TtColors.ash),
          ),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tratra Flash', style: TratraTheme.style(TtType.title)),
              Text(online ? 'Disponible : vous recevez les missions immédiates' : 'Indisponible : aucune mission immédiate',
                  key: const ValueKey('flash-availability-label'), style: TratraTheme.style(TtType.bodySm, color: online ? TtColors.successInk : TtColors.ash)),
            ]),
          ),
          Switch(
            key: const ValueKey('flash-availability-switch'),
            value: online,
            onChanged: _busy || (!eligible && !online) ? null : _toggle,
          ),
        ]),
        if (!eligible && s['reason'] != null) ...[
          const SizedBox(height: TtSpace.s2),
          Text('${s['reason']}', style: TratraTheme.style(TtType.caption, color: TtColors.warningInk)),
        ],
        if (missed > 0 && pauseAfter > 0 && online) ...[
          const SizedBox(height: TtSpace.s2),
          Text('$missed proposition${missed > 1 ? 's' : ''} sans réponse. Après $pauseAfter, vous passez « Indisponible » '
              '(aucune conséquence sur votre réputation).', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        ],
        if (_error != null) ...[
          const SizedBox(height: TtSpace.s2),
          Text(_error!, style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk)),
        ],
        const SizedBox(height: TtSpace.s2),
        Row(children: [
          if (pending > 0)
            TratraButton(
              key: const ValueKey('flash-pending'),
              label: 'Répondre ($pending)',
              size: TratraButtonSize.sm,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FlashOffersScreen())).then((_) => _load()),
            ),
          const Spacer(),
          TextButton(
            key: const ValueKey('flash-history'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FlashOffersScreen())).then((_) => _load()),
            child: const Text('Mes propositions'),
          ),
        ]),
      ]),
    );
  }
}

class FlashOffersScreen extends StatefulWidget {
  const FlashOffersScreen({super.key});
  @override
  State<FlashOffersScreen> createState() => _FlashOffersScreenState();
}

class _FlashOffersScreenState extends State<FlashOffersScreen> {
  late Future<List<FlashOffer>> _future = context.read<FlashController>().api.offers();

  void _reload() => setState(() => _future = context.read<FlashController>().api.offers());

  static const _labels = {
    'pending': ('En attente de votre réponse', TratraTone.accent),
    'accepted': ('Acceptée — mission confirmée', TratraTone.success),
    'quoted': ('Devis envoyé', TratraTone.info),
    'declined': ('Refusée (sans conséquence)', TratraTone.gray),
    'expired': ('Sans réponse dans le délai', TratraTone.gray),
    'withdrawn': ('Attribuée à un autre ou annulée', TratraTone.gray),
  };

  Future<void> _open(FlashOffer o) async {
    final c = context.read<FlashController>();
    if (o.accepted && o.bookingId != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MissionDetailScreen(bookingId: '${o.bookingId}')));
    } else {
      await c.present(o.id);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes propositions Tratra Flash')),
      body: FutureBuilder<List<FlashOffer>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return Center(child: TratraEmptyState(icon: Icons.wifi_off_rounded, title: 'Propositions indisponibles', description: '${snap.error}'));
          }
          final items = snap.data ?? const [];
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(TtSpace.s4),
              itemCount: items.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: TtSpace.s2),
              itemBuilder: (_, index) {
                if (index == 0) {
                  return Column(children: [
                    const FlashAvailabilityCard(),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: TtSpace.s8),
                        child: TratraEmptyState(icon: Icons.bolt_rounded, title: 'Aucune proposition pour le moment',
                            description: 'Restez « Disponible » : les nouvelles missions de votre métier et de votre zone arrivent ici.'),
                      ),
                  ]);
                }
                final o = items[index - 1];
                final (label, tone) = _labels[o.status] ?? (o.status, TratraTone.gray);
                return TratraCard(
                  padding: TratraCard.compact,
                  onTap: () => _open(o),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(o.category, style: TratraTheme.style(TtType.title))),
                      Text(o.quoteMode ? 'Sur devis' : o.amountLabel, style: TratraTheme.style(TtType.title, color: TtColors.primary)),
                    ]),
                    Text('${o.zone} · ${o.whenLabel}', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                    const SizedBox(height: TtSpace.s2),
                    TratraBadge(label, tone: tone),
                  ]),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
