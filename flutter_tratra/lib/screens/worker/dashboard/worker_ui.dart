// lib/screens/worker/dashboard/worker_ui.dart
//
// Briques d'affichage de l'espace artisan (accueil + détail de mission), composées avec
// les jetons du Design System. Aucune règle métier ici : formatage et présentation.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';

// ============================ FORMATAGE (affichage uniquement) ============================

/// Montant lisible : « 12 500 » (espace insécable entre les milliers).
String formatAmount(num amount) {
  final digits = amount.abs().toStringAsFixed(0);
  final buffer = StringBuffer(amount < 0 ? '−' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// « 12 500 FCFA » (espaces insécables : le montant ne se coupe jamais en fin de ligne).
String formatFcfa(num amount) => '${formatAmount(amount)} FCFA';

const _monthsLong = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

const _monthsShort = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

/// Date et heure locales : « 8 oct. 2026 · 14:30 » (ou mois en toutes lettres si [long]).
String formatWhen(DateTime when, {bool long = false}) {
  final d = when.toLocal();
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  final month = (long ? _monthsLong : _monthsShort)[d.month - 1];
  return '${d.day} $month ${d.year} · $hh:$mm';
}

/// Durée neutralisée quand l'utilisateur réduit les animations.
Duration workerMotion(BuildContext context, Duration duration) =>
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
        ? Duration.zero
        : duration;

// ============================ RETOURS UTILISATEUR ============================

enum WorkerToastTone { neutral, success, danger }

/// Message éphémère de la marque : sombre par défaut, vert/rouge profonds pour succès/échec.
void showWorkerToast(
  BuildContext context,
  String message, {
  WorkerToastTone tone = WorkerToastTone.neutral,
}) {
  final (Color? background, IconData? icon) = switch (tone) {
    WorkerToastTone.success => (
        TtColors.successInk,
        Icons.check_circle_outline
      ),
    WorkerToastTone.danger => (TtColors.dangerInk, Icons.error_outline),
    WorkerToastTone.neutral => (null, null),
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: background,
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: TtSpace.s3),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

// ============================ PETITS WIDGETS ============================

/// Entrée discrète (fondu + léger glissement, <= 420 ms, courbe « emphasized »).
/// [index] décale légèrement les éléments d'une liste ; sans effet si animations réduites.
class WorkerReveal extends StatelessWidget {
  const WorkerReveal({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final duration =
        TtMotion.base + Duration(milliseconds: 40 * math.min(index, 5));
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: TtMotion.emphasized,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
            offset: Offset(0, (1 - t) * TtSpace.s2), child: child),
      ),
    );
  }
}

/// Sur-titre en pastille : majuscules 11 px, fort interlettrage, point jaune.
class WorkerEyebrow extends StatelessWidget {
  const WorkerEyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const ShapeDecoration(
          color: TtColors.primarySoft, shape: StadiumBorder()),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: TtSpace.s3, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DecoratedBox(
              decoration:
                  BoxDecoration(color: TtColors.accent, shape: BoxShape.circle),
              child: SizedBox(width: 6, height: 6),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TratraTheme.style(TtType.eyebrow,
                    color: TtColors.primaryDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// En-tête d'écran : sur-titre, titre Montserrat serré, soulignement jaune, sous-titre.
class WorkerPageHeader extends StatelessWidget {
  const WorkerPageHeader(
      {super.key, required this.eyebrow, required this.title, this.subtitle});

  final String eyebrow;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(alignment: Alignment.centerLeft, child: WorkerEyebrow(eyebrow)),
        const SizedBox(height: TtSpace.s3),
        Semantics(
            header: true,
            child: Text(title, style: TratraTheme.style(TtType.h1))),
        const SizedBox(height: TtSpace.s2),
        const DecoratedBox(
          decoration: BoxDecoration(
            color: TtColors.accent,
            borderRadius: BorderRadius.all(Radius.circular(TtRadius.pill)),
          ),
          child: SizedBox(width: 40, height: 4),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: TtSpace.s3),
          Text(subtitle!,
              style: TratraTheme.style(TtType.body, color: TtColors.inkSoft)
                  .copyWith(fontSize: 14)),
        ],
      ],
    );
  }
}

/// Pastille d'icône verte douce (décorative).
class WorkerIconTile extends StatelessWidget {
  const WorkerIconTile(this.icon, {super.key, this.size = 44});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
            color: TtColors.primarySoft,
            borderRadius: BorderRadius.all(Radius.circular(TtRadius.panel))),
        child: Icon(icon, size: size * 0.5, color: TtColors.primaryDark),
      ),
    );
  }
}

/// Ligne d'information compacte : icône + texte (ellipsis).
class WorkerMetaLine extends StatelessWidget {
  const WorkerMetaLine(
      {super.key, required this.icon, required this.text, this.maxLines = 1});

  final IconData icon;
  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: TtColors.ash),
        ),
        const SizedBox(width: TtSpace.s2),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
          ),
        ),
      ],
    );
  }
}
