// widgets/custom_app_bar.dart
// Adaptateur : préférer TratraAppBar (lib/design) pour tout nouveau code.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// Barre d'application historique, désormais portée par TratraAppBar.
///
/// - `title` : titre de l'écran.
/// - `showBackButton` : affiche le bouton retour automatique quand la route peut être quittée.
/// - `leading` : un bouton (IconButton / BackButton) remplace le bouton retour, comme dans
///   AppBar ; tout autre widget (ex. avatar) est affiché devant le titre et le bouton retour
///   reste disponible.
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomAppBar({
    super.key,
    required this.title,
    required this.showBackButton,
    required this.leading,
  });

  final String title;
  final bool showBackButton;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(TtLayout.topbarHeight);

  @override
  Widget build(BuildContext context) {
    final lead = leading;
    final replacesBackButton = lead is IconButton || lead is BackButton;
    final inlineLead = lead != null && !replacesBackButton ? lead : null;

    return TratraAppBar(
      title: inlineLead == null ? title : null,
      titleWidget: inlineLead == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                inlineLead,
                const SizedBox(width: TtSpace.s3),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TratraTheme.style(TtType.h3),
                  ),
                ),
              ],
            ),
      leading: replacesBackButton ? lead : null,
      automaticallyImplyLeading: showBackButton,
    );
  }
}
