import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// Photo réelle sinon initiales sur dégradé de marque (jamais de photo de stock),
/// y compris si la photo ne charge pas (miroir de `Avatar` côté web).
class TratraAvatar extends StatelessWidget {
  const TratraAvatar({super.key, required this.name, this.photoUrl, this.size = 48, this.online = false});

  final String name;
  final String? photoUrl;
  final double size;
  final bool online;

  static String initials(String name) {
    final parts = name.replaceAll('.', '').split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final first = parts.isNotEmpty ? parts[0][0] : 'T';
    final second = parts.length > 1 ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: TtGradients.brand, shape: BoxShape.circle),
      child: Center(
        child: Text(
          initials(name),
          style: TratraTheme.style(TtType.h3, color: Colors.white)
              .copyWith(fontSize: (size / 2.8).clamp(12, 28).toDouble(), height: 1),
        ),
      ),
    );
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return Semantics(
      label: online ? 'Photo de $name, en ligne' : 'Photo de $name',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: ClipOval(
                  child: hasPhoto
                      ? CachedNetworkImage(
                          imageUrl: photoUrl!,
                          fit: BoxFit.cover,
                          fadeInDuration: TtMotion.base,
                          placeholder: (_, __) => fallback,
                          errorWidget: (_, __, ___) => fallback,
                        )
                      : fallback,
                ),
              ),
            ),
            if (online)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: size * 0.26,
                  height: size * 0.26,
                  decoration: BoxDecoration(
                    color: TtColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
