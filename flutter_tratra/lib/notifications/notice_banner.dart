// lib/notifications/notice_banner.dart
//
// Ruban de notification flottant en haut de l'écran, application ouverte : icône, catégorie, heure, titre, message, bouton fermer.
// Un toucher ouvre l'objet concerné ; un glissement vers le haut le ferme ; il disparaît seul après 5 secondes (NoticeCenter).
// Tratra Flash : ruban sombre, éclair jaune. Placé au-dessus du navigateur (MaterialApp.builder) : visible sur tous les écrans,
// y compris les feuilles et les dialogues ; aucun composant qui exige un Overlay ici.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/notifications/notice_center.dart';

/// Libellé et icône d'une catégorie de notification (mêmes catégories que le centre de notifications).
const Map<String, (String, IconData)> _categories = {
  'booking': ('Réservation', Icons.event_available_outlined),
  'message': ('Message', Icons.chat_bubble_outline_rounded),
  'payment': ('Paiement', Icons.payments_outlined),
  'live': ('Suivi', Icons.my_location_rounded),
  'review': ('Avis', Icons.star_outline_rounded),
  'account': ('Compte', Icons.verified_user_outlined),
  'business': ('Entreprise', Icons.business_center_outlined),
  'engagement': ('Contrat', Icons.description_outlined),
  'flash': ('Tratra Flash', Icons.bolt_rounded),
  'announcement': ('Annonce', Icons.campaign_outlined),
  'tips': ('Conseil', Icons.tips_and_updates_outlined),
  'system': ('Tratra', Icons.notifications_none_rounded),
};

String noticeLabel(AppNotice n) => n.priority ? 'Tratra Flash' : (_categories[n.category] ?? _categories['system']!).$1;

IconData noticeIcon(AppNotice n) => n.priority ? Icons.bolt_rounded : (_categories[n.category] ?? _categories['system']!).$2;

String noticeTime(DateTime at) {
  final d = at.toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Zone d'affichage des rubans, au-dessus de toute l'application.
class NoticeHost extends StatefulWidget {
  const NoticeHost({super.key, required this.child});
  final Widget child;

  @override
  State<NoticeHost> createState() => _NoticeHostState();
}

class _NoticeHostState extends State<NoticeHost> {
  late final NoticeCenter _center = context.read<NoticeCenter>();

  @override
  void initState() {
    super.initState();
    _center.attach();
  }

  @override
  void dispose() {
    _center.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = context.watch<NoticeCenter>().current;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(TtSpace.s3, TtSpace.s2, TtSpace.s3, 0),
                  child: AnimatedSwitcher(
                    duration: still ? Duration.zero : const Duration(milliseconds: 280),
                    reverseDuration: still ? Duration.zero : const Duration(milliseconds: 200),
                    switchInCurve: TtMotion.emphasized,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, -1.25), end: Offset.zero).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    layoutBuilder: (current, previous) =>
                        Stack(alignment: Alignment.topCenter, children: [...previous, if (current != null) current]),
                    child: notice == null
                        ? const SizedBox.shrink(key: ValueKey('notice-none'))
                        : NoticeBanner(key: ObjectKey(notice), notice: notice, onOpen: _center.open, onClose: _center.dismiss),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class NoticeBanner extends StatefulWidget {
  const NoticeBanner({super.key, required this.notice, required this.onOpen, required this.onClose});
  final AppNotice notice;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  State<NoticeBanner> createState() => _NoticeBannerState();
}

class _NoticeBannerState extends State<NoticeBanner> {
  double _dy = 0;

  void _dragEnd(DragEndDetails d) {
    if (_dy < -28 || (d.primaryVelocity ?? 0) < -300) {
      widget.onClose();
    } else {
      setState(() => _dy = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notice;
    final flash = n.priority;
    final onDark = flash;
    final titleColor = onDark ? Colors.white : TtColors.ink;
    final textColor = onDark ? Colors.white.withValues(alpha: 0.82) : TtColors.inkSoft;
    final metaColor = onDark ? Colors.white.withValues(alpha: 0.64) : TtColors.ash;
    final labelColor = onDark ? TtColors.accentBright : TtColors.primaryDark;
    final time = noticeTime(n.at);

    return Semantics(
      container: true,
      liveRegion: true,
      child: Transform.translate(
        offset: Offset(0, _dy),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen,
          onVerticalDragUpdate: (d) => setState(() => _dy = (_dy + d.delta.dy).clamp(-240.0, 10.0)),
          onVerticalDragEnd: _dragEnd,
          onVerticalDragCancel: () => setState(() => _dy = 0),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              decoration: BoxDecoration(
                color: onDark ? null : TtColors.surface,
                gradient: onDark ? TtGradients.night : null,
                borderRadius: BorderRadius.circular(TtRadius.panel + 2),
                border: Border.all(color: onDark ? Colors.white.withValues(alpha: 0.10) : TtColors.line),
                boxShadow: TtShadows.strong,
              ),
              padding: const EdgeInsets.fromLTRB(TtSpace.s3, TtSpace.s3, 0, TtSpace.s3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: flash ? TtColors.accent : TtColors.primarySoft,
                      borderRadius: BorderRadius.circular(TtRadius.control),
                    ),
                    child: Icon(noticeIcon(n), size: 22, color: flash ? TtColors.night : TtColors.primary),
                  ),
                  const SizedBox(width: TtSpace.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                noticeLabel(n).toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TratraTheme.style(TtType.eyebrow, color: labelColor),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text('·', style: TratraTheme.style(TtType.eyebrow, color: metaColor)),
                            ),
                            Text(time, style: TratraTheme.style(TtType.caption, color: metaColor)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TratraTheme.style(TtType.title, color: titleColor).copyWith(fontSize: 15, height: 1.3),
                        ),
                        if (n.body.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              n.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TratraTheme.style(TtType.bodySm, color: textColor).copyWith(height: 1.4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Fermer la notification',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onClose,
                      child: SizedBox(
                        width: TtLayout.touchTarget,
                        height: TtLayout.touchTarget,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: onDark ? Colors.white.withValues(alpha: 0.12) : TtColors.lineSoft,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close_rounded, size: 16, color: onDark ? Colors.white : TtColors.inkSoft),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
