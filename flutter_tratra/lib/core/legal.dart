// core/legal.dart
//
// Pages juridiques publiques du site (Conditions d'utilisation, confidentialité, suppression de compte) et version des
// Conditions d'utilisation. L'inscription annonce `termsVersion` (version de ce build) ; si les conditions ont changé depuis, le
// serveur refuse (`terms_outdated`, avec la version en vigueur) : la case est décochée et la personne la recoche après avoir relu
// les nouvelles conditions. Jamais d'acceptation supposée.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/design/design.dart';

class LegalLinks {
  LegalLinks._();

  static const String siteBase = 'https://tratra.net';
  static final Uri terms = Uri.parse('$siteBase/conditions-utilisation');
  static final Uri privacy = Uri.parse('$siteBase/confidentialite');
  static final Uri accountDeletion = Uri.parse('$siteBase/suppression-compte');

  /// Doit concorder avec `handy/legal.py` (`TERMS_VERSION`) à la date du build ; en cas d'écart, la version du serveur prime.
  static const String termsVersion = '2026-11-12';
}

/// Refus `terms_outdated` du serveur : version en vigueur (`current_version`), sinon `null`.
String? outdatedTermsVersion(Object error) {
  if (error is! ApiException) return null;
  try {
    final d = json.decode(error.body);
    if (d is Map && d['code'] == 'terms_outdated') {
      final v = d['current_version'];
      return v is String && v.isNotEmpty ? v : LegalLinks.termsVersion;
    }
  } catch (_) {}
  return null;
}

/// Ouvre une page juridique dans le navigateur intégré (repli : navigateur du téléphone). Message si rien ne peut l'ouvrir.
Future<void> openLegalPage(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  } catch (_) {}
  if (!opened) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
  if (!opened) {
    messenger?.showSnackBar(SnackBar(content: Text('Impossible d’ouvrir la page. Adresse : $uri')));
  }
}

typedef LegalOpener = Future<void> Function(BuildContext context, Uri uri);

/// Case « J'accepte les Conditions d'utilisation » (jamais précochée) et liens ouvrables vers les pages juridiques.
class TermsConsent extends StatelessWidget {
  const TermsConsent({super.key, required this.value, required this.onChanged, this.enabled = true, this.opener});

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  /// Ouverture d'une page (tests) ; par défaut le navigateur intégré.
  final LegalOpener? opener;

  @override
  Widget build(BuildContext context) {
    final open = opener ?? openLegalPage;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CheckboxListTile(
        key: const ValueKey('terms-accept'),
        value: value,
        onChanged: enabled ? (v) => onChanged(v ?? false) : null,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: TtRadius.controlAll),
        title: Text('J’accepte les Conditions d’utilisation et la politique de confidentialité.',
            style: TratraTheme.style(TtType.bodySm, color: TtColors.ink)),
      ),
      Wrap(spacing: TtSpace.s2, children: [
        TextButton.icon(
          key: const ValueKey('terms-open'),
          onPressed: () => open(context, LegalLinks.terms),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('Lire les Conditions d’utilisation'),
        ),
        TextButton.icon(
          key: const ValueKey('privacy-open'),
          onPressed: () => open(context, LegalLinks.privacy),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('Politique de confidentialité'),
        ),
      ]),
    ]);
  }
}
