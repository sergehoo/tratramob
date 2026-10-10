// lib/screens/dashboard/dash_ui.dart
//
// Briques d'affichage partagées par les pages de l'espace unifié (Design System Tratra).
// Présentation uniquement : états chargement / erreur / vide honnêtes, aucune donnée fictive.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/worker/dashboard/worker_ui.dart' show formatFcfa, formatWhen;

export 'package:flutter_tratra/screens/worker/dashboard/worker_ui.dart' show formatAmount, formatFcfa, formatWhen;

/// Charge une ressource, affiche squelette → contenu / erreur (avec « Réessayer »),
/// et offre le tirer-pour-rafraîchir. Le `builder` doit renvoyer un défilant.
class ApiView<T> extends StatefulWidget {
  const ApiView({
    super.key,
    required this.load,
    required this.builder,
    this.errorTitle = 'Chargement impossible',
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final String errorTitle;

  @override
  State<ApiView<T>> createState() => _ApiViewState<T>();
}

class _ApiViewState<T> extends State<ApiView<T>> {
  T? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (_data == null) setState(() => _loading = true);
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
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
    if (_loading && _data == null) return const TratraSkeletonList(count: 4);
    final data = _data;
    if (data == null) {
      return TratraEmptyState(
        icon: Icons.cloud_off_rounded,
        title: widget.errorTitle,
        description: _error,
        actions: [
          TratraButton(
            label: 'Réessayer',
            variant: TratraButtonVariant.outline,
            onPressed: () {
              setState(() => _loading = true);
              _reload();
            },
          ),
        ],
      );
    }
    return RefreshIndicator(
      color: TtColors.primary,
      onRefresh: _reload,
      child: widget.builder(context, data, _reload),
    );
  }
}

/// Page secondaire (hors onglets) : fond canvas + barre de la marque.
class DashPage extends StatelessWidget {
  const DashPage({super.key, required this.title, required this.body, this.actions});
  final String title;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: TtColors.canvas,
        appBar: TratraAppBar(title: title, actions: actions),
        body: body,
      );
}

/// Carte-indicateur : valeur réelle issue de l'API.
class DashKpi extends StatelessWidget {
  const DashKpi({super.key, required this.icon, required this.label, required this.value, this.hint, this.tone = TratraTone.primary, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final TratraTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      TratraTone.accent => (TtColors.accentSoft, TtColors.accentDark),
      TratraTone.night => (TtColors.night, TtColors.accent),
      _ => (TtColors.primarySoft, TtColors.primary),
    };
    return TratraCard(
      padding: TratraCard.compact,
      onTap: onTap,
      semanticLabel: '$label : $value',
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(TtRadius.control)),
            child: Icon(icon, color: fg, size: 22),
          ),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TratraTheme.style(TtType.h1)),
                ),
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                if (hint != null)
                  Text(hint!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.caption, color: TtColors.fog)), // 2 lignes : « 0 créées ce mois-ci » ne doit pas être coupé en tuiles étroites
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ligne « réservation / mission » (accueil, listes).
class DashItemTile extends StatelessWidget {
  const DashItemTile({super.key, required this.item, this.onTap});
  final DashItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final when = item.bookingDate == null ? null : formatWhen(item.bookingDate!);
    final meta = [
      item.isMission ? 'Client : ${item.counterpart}' : 'Artisan : ${item.counterpart}',
      if (when != null) when,
      if (item.city != null) item.city!,
    ].join(' · ');
    return TratraCard(
      padding: TratraCard.compact,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item.isMission ? TtColors.accentSoft : TtColors.primarySoft,
              borderRadius: BorderRadius.circular(TtRadius.control),
            ),
            child: Icon(item.isMission ? Icons.handyman_outlined : Icons.calendar_today_outlined,
                size: 20, color: item.isMission ? TtColors.accentDark : TtColors.primary),
          ),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.title)),
                const SizedBox(height: 2),
                Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
              ],
            ),
          ),
          const SizedBox(width: TtSpace.s2),
          TratraStatusBadge(TratraStatus.booking, item.status),
        ],
      ),
    );
  }
}

/// Montant « 12 500 FCFA » ; « 0 FCFA » si nul.
String fcfaOrZero(num v) => v > 0 ? formatFcfa(v) : '0 FCFA';

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? TtColors.dangerInk : TtColors.night,
      behavior: SnackBarBehavior.floating,
    ));
}
