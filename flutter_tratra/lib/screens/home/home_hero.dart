// lib/screens/home/home_hero.dart
//
// En-tête immersif « night » de l'accueil (miroir du hero de la landing) : halos vert et
// jaune, barre de marque, sur-titre, titre, recherche et accès rapides.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tratra/design/design.dart';

import 'home_motion.dart';

/// Accès rapide affiché sous la recherche (chaque entrée ouvre une destination réelle).
class HomeHeroAction {
  const HomeHeroAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Mise en avant jaune (action prioritaire).
  final bool accent;
}

class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.locationLabel,
    required this.locationActive,
    required this.onLocationTap,
    required this.onProfileTap,
    required this.searchController,
    required this.onSearchChanged,
    required this.actions,
    this.greetingName,
  });

  final String locationLabel;
  final bool locationActive;
  final VoidCallback onLocationTap;
  final VoidCallback onProfileTap;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final List<HomeHeroAction> actions;

  /// Prénom de la personne connectée (jamais inventé : absent => pas de salutation).
  final String? greetingName;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final name = (greetingName ?? '').trim();
    final lead = name.isEmpty
        ? 'Décrivez votre besoin ou choisissez un métier.'
        : 'Bonjour $name, décrivez votre besoin ou choisissez un métier.';

    const bottomRadius = BorderRadius.vertical(bottom: Radius.circular(TtRadius.sheet));
    final h1 = TratraTheme.style(TtType.displayLg, color: Colors.white);

    return DecoratedBox(
      decoration: const BoxDecoration(color: TtColors.night, borderRadius: bottomRadius),
      child: ClipRRect(
        borderRadius: bottomRadius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            const Positioned.fill(child: IgnorePointer(child: _Halos())),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: topInset + TtLayout.topbarHeight,
                  child: TratraAppBar(
                    transparent: true,
                    onNight: true,
                    automaticallyImplyLeading: false,
                    titleWidget: Row(
                      children: [
                        const TratraBrandMark(size: 40),
                        const SizedBox(width: TtSpace.s3),
                        const Flexible(child: TratraWordmark(size: 32, onNight: true)),
                      ],
                    ),
                    actions: [
                      _GlassIconButton(
                        icon: locationActive ? Icons.near_me_rounded : Icons.location_off_outlined,
                        iconColor: locationActive ? TtColors.accent : Colors.white,
                        tooltip: '$locationLabel. Options de localisation',
                        onPressed: onLocationTap,
                      ),
                      const SizedBox(width: TtSpace.s2),
                      _GlassIconButton(
                        icon: Icons.person_outline_rounded,
                        tooltip: 'Mon compte',
                        onPressed: onProfileTap,
                      ),
                      const SizedBox(width: TtSpace.s2),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, 0),
                  child: HomeReveal(
                    child: _Eyebrow(label: 'Dépannage · travaux · entretien'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, 0),
                  child: HomeReveal(
                    delay: const Duration(milliseconds: 60),
                    child: Semantics(
                      header: true,
                      child: Text.rich(
                        TextSpan(
                          style: h1,
                          children: [
                            const TextSpan(text: 'L’artisan qu’il vous faut, '),
                            TextSpan(
                              text: 'près de chez vous',
                              style: h1.copyWith(
                                color: TtColors.accent,
                                decoration: TextDecoration.underline,
                                decorationColor: TtColors.accent,
                                decorationThickness: 2.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, 0),
                  child: HomeReveal(
                    delay: const Duration(milliseconds: 100),
                    child: Text(
                      lead,
                      style: TratraTheme.style(TtType.body, color: Colors.white.withValues(alpha: 0.78)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s5, TtSpace.s4, 0),
                  child: HomeReveal(
                    delay: const Duration(milliseconds: 140),
                    child: SearchBarPremium(
                      controller: searchController,
                      onChanged: onSearchChanged,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: TtSpace.s4, bottom: TtSpace.s6),
                  child: HomeReveal(
                    delay: const Duration(milliseconds: 180),
                    child: SizedBox(
                      height: TtLayout.touchTarget,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
                        itemCount: actions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: TtSpace.s2),
                        itemBuilder: (_, i) => _HeroActionChip(action: actions[i]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Barre de recherche de l'accueil. Classe publique conservée (même nom, même constructeur) :
/// le texte saisi est transmis tel quel à [onChanged] (la recherche est déclenchée par l'écran).
class SearchBarPremium extends StatelessWidget {
  const SearchBarPremium({
    super.key,
    required this.controller,
    required this.onChanged,
    this.accent = TtColors.primaryDark,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// Conservé pour compatibilité des appels existants : la couleur du curseur et du focus
  /// est désormais imposée par le Design System (vert profond).
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: TtRadius.controlAll, boxShadow: TtShadows.strong),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TratraInput(
          controller: controller,
          onChanged: onChanged,
          hint: 'Plombier, électricien, peinture…',
          leadingIcon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          suffix: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer la recherche',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                    HapticFeedback.selectionClick();
                  },
                ),
        ),
      ),
    );
  }
}

class _Halos extends StatelessWidget {
  const _Halos();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.9, -1),
              radius: 1.15,
              colors: [TtColors.primary.withValues(alpha: 0.5), Colors.transparent],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1, 1),
              radius: 1.0,
              colors: [TtColors.primaryDark.withValues(alpha: 0.6), Colors.transparent],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1.05, -0.75),
              radius: 0.55,
              colors: [TtColors.accent.withValues(alpha: 0.2), Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: TtColors.accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: TtSpace.s2),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.eyebrow, color: Colors.white.withValues(alpha: 0.9)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton-icône translucide de l'en-tête (cible tactile 44 dp, infobulle lue par les lecteurs d'écran).
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        HapticFeedback.selectionClick();
        onPressed();
      },
      tooltip: tooltip,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: iconColor,
        backgroundColor: Colors.white.withValues(alpha: 0.10),
        minimumSize: const Size(TtLayout.touchTarget, TtLayout.touchTarget),
      ),
    );
  }
}

class _HeroActionChip extends StatelessWidget {
  const _HeroActionChip({required this.action});
  final HomeHeroAction action;

  @override
  Widget build(BuildContext context) {
    final fg = action.accent ? TtColors.ink : Colors.white;
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: Material(
        color: action.accent ? TtColors.accent : Colors.white.withValues(alpha: 0.08),
        shape: StadiumBorder(
          side: action.accent ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            action.onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: TtLayout.touchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(action.icon, size: 18, color: fg),
                  const SizedBox(width: TtSpace.s2),
                  Text(
                    action.label,
                    style: TratraTheme.style(TtType.button, color: fg).copyWith(fontSize: 14),
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
