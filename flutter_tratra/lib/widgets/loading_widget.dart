// lib/widgets/loading_widget.dart
// Adaptateur : préférer TratraSkeleton* (lib/design) pour tout nouveau code.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// Indicateur de chargement centré, avec message optionnel (annoncé aux lecteurs d'écran).
class LoadingWidget extends StatelessWidget {
  final String? message;

  const LoadingWidget({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final text = message;
    return Semantics(
      liveRegion: true,
      container: true,
      label: text ?? 'Chargement en cours',
      child: ExcludeSemantics(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(TtSpace.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: TtColors.primary),
                if (text != null) ...[
                  const SizedBox(height: TtSpace.s4),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TratraTheme.style(TtType.body, color: TtColors.ash),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Squelette de liste de cartes (`itemCount` cartes), défilable comme l'ancienne ListView.
class ShimmerLoadingWidget extends StatelessWidget {
  final int itemCount;

  const ShimmerLoadingWidget({super.key, this.itemCount = 3});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: TratraSkeletonList(count: itemCount),
    );
  }
}
