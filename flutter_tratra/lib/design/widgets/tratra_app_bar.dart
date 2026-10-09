import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tokens.dart';

/// Pastille logo de la marque (asset du dépôt).
class TratraBrandMark extends StatelessWidget {
  const TratraBrandMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(TtRadius.control),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: TtShadows.hair,
      ),
      child: Image.asset('assets/images/tratra_logo.webp', fit: BoxFit.contain, semanticLabel: 'Tratra'),
    );
  }
}

/// Barre d'application de la marque (miroir de la barre supérieure web) : blanche,
/// filet bas discret, titre Montserrat. `onNight` : barre sombre (écrans immersifs).
class TratraAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TratraAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.leading,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.onNight = false,
    this.transparent = false,
  });

  final String? title;

  /// Remplace `title` (ex. logo + nom).
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final bool onNight;
  final bool transparent;

  @override
  Size get preferredSize =>
      Size.fromHeight(TtLayout.topbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final fg = onNight ? Colors.white : TtColors.ink;
    final bg = transparent ? Colors.transparent : (onNight ? TtColors.night : TtColors.surface);

    final titleChild = titleWidget ??
        (title == null
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.h3, color: fg)),
                  if (subtitle != null)
                    Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TratraTheme.style(TtType.caption, color: onNight ? Colors.white70 : TtColors.ash)),
                ],
              ));

    return AppBar(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      toolbarHeight: TtLayout.topbarHeight,
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      iconTheme: IconThemeData(color: fg),
      actionsIconTheme: IconThemeData(color: fg),
      systemOverlayStyle: onNight ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      title: titleChild,
      actions: [...?actions, const SizedBox(width: 4)],
      bottom: bottom,
      shape: transparent
          ? null
          : Border(bottom: BorderSide(color: onNight ? Colors.white12 : TtColors.lineSoft)),
    );
  }
}
