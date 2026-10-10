// lib/continuity/continuity_widgets.dart
//
// Bandeau « Activité en cours » de l'accueil : retrouver sa mission ou sa réservation en un geste après une fermeture,
// une coupure, un plantage ou un changement de téléphone. Les données viennent du serveur (dernier état connu affiché
// pendant le chargement, clairement signalé comme tel hors ligne). Rien n'est affiché sans activité.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/continuity/activities_controller.dart';
import 'package:flutter_tratra/continuity/activity.dart';
import 'package:flutter_tratra/core/deep_links.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';

String _hhmm(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}h${l.minute.toString().padLeft(2, '0')}';
}

class ActivityBanner extends StatelessWidget {
  const ActivityBanner({super.key});

  Future<void> _resume(BuildContext context, Activity a) => openDeepLink(context, parseDeepLink({'deeplink': a.deeplink}));

  void _showAll(BuildContext context, ActivitiesController c) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(TtSpace.s4, 0, TtSpace.s4, TtSpace.s4),
          children: [
            Text('Mes activités en cours', style: TratraTheme.style(TtType.h3)),
            const SizedBox(height: TtSpace.s2),
            for (final a in c.items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(a.isMission ? Icons.handyman_outlined : Icons.event_available_outlined, color: TtColors.primary),
                title: Text(a.title),
                subtitle: Text('${a.statusLabel}${a.counterpart.isEmpty ? '' : ' · ${a.counterpart}'}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _resume(context, a);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ActivitiesController>();
    final a = c.primary ?? (c.items.isEmpty ? null : c.items.first);
    if (a == null && c.notice == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: TtSpace.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (c.notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: TtSpace.s2),
            child: TratraAlert(message: c.notice!, onDismiss: c.clearNotice),
          ),
        if (a != null)
          TratraCard(
            variant: TratraCardVariant.soft,
            padding: TratraCard.compact,
            semanticLabel: 'Activité en cours : ${a.title}, ${a.statusLabel}',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.bolt_rounded, color: TtColors.primary, size: 20),
                const SizedBox(width: TtSpace.s2),
                Text('Activité en cours', style: TratraTheme.style(TtType.caption, color: TtColors.primaryDark).copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (a.kind == 'contract') TratraBadge(a.statusLabel, tone: TratraTone.primary, dot: true) else TratraStatusBadge(TratraStatus.booking, a.status),
              ]),
              const SizedBox(height: TtSpace.s2),
              Text(a.title, style: TratraTheme.style(TtType.h3)),
              Text(
                [if (a.counterpart.isNotEmpty) a.counterpart, if (a.city != null) a.city!].join(' · '),
                style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
              ),
              if (c.offline)
                Padding(
                  padding: const EdgeInsets.only(top: TtSpace.s1),
                  child: Text(
                    c.syncedAt == null
                        ? 'Hors ligne — état non vérifié.'
                        : 'Hors ligne — état connu à ${_hhmm(c.syncedAt!)}, non vérifié. Nouvelle tentative automatique.',
                    style: TratraTheme.style(TtType.caption, color: TtColors.warningInk),
                  ),
                ),
              const SizedBox(height: TtSpace.s3),
              Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s1, crossAxisAlignment: WrapCrossAlignment.center, children: [
                TratraButton(label: a.resumeLabel, size: TratraButtonSize.sm, onPressed: () => _resume(context, a)),
                if (c.items.length > 1)
                  TextButton(onPressed: () => _showAll(context, c), child: Text('Voir les ${c.items.length} activités')),
              ]),
            ]),
          ),
      ]),
    );
  }
}
