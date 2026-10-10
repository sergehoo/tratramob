// lib/engagements/evidence_viewer.dart
//
// Ouverture SÛRE des pièces justificatives PDF (reçus, contrats) : le document est téléchargé avec la session, vérifié (signature
// « %PDF- », taille), puis affiché DANS l'application par le moteur du système (Android PdfRenderer, iOS PDFKit) — aucune
// application tierce, aucun partage, aucune URL externe, pas de JavaScript. Le moteur écrit une copie temporaire dans le cache
// privé de l'application (Android) ; elle est SUPPRIMÉE à la fermeture du lecteur et au démarrage suivant (si l'application a été
// tuée pendant la lecture) : `EvidenceFiles.purge`.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import 'package:flutter_tratra/design/design.dart';

/// Source d'un document privé téléchargé avec la session (justificatifs d'engagement, reçus d'espèces).
abstract interface class PrivateDownloader {
  Future<Uint8List> download(String url);
}

/// Contrôles et nettoyage des pièces ouvertes dans l'application.
class EvidenceFiles {
  const EvidenceFiles._();

  /// Plafond serveur des justificatifs : 5 Mo (marge pour l'enveloppe HTTP).
  static const maxBytes = 6 * 1024 * 1024;

  /// Nom des copies temporaires du moteur PDF : 32 caractères hexadécimaux + extension.
  static final _stray = RegExp(r'^[0-9a-f]{32}\.(pdf|jpg|png|webp)$');
  static const _renderCache = 'pdf_renderer_cache';

  /// Un vrai PDF commence par « %PDF- » (dans ses premiers 1024 octets, selon la spécification).
  static bool looksLikePdf(Uint8List bytes) {
    final head = bytes.length > 1024 ? bytes.sublist(0, 1024) : bytes;
    const sig = [0x25, 0x50, 0x44, 0x46, 0x2d];
    for (var i = 0; i + sig.length <= head.length; i++) {
      var match = true;
      for (var j = 0; j < sig.length; j++) {
        if (head[i + j] != sig[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  /// Refus lisible d'une pièce inexploitable (null = acceptable).
  static String? refusal(Uint8List bytes) {
    if (bytes.isEmpty) return 'Le document est vide.';
    if (bytes.length > maxBytes) return 'Le document est trop volumineux pour être ouvert ici.';
    return null;
  }

  /// Supprime les copies temporaires laissées par le moteur PDF (cache et, sous iOS, dossier du moteur dans Documents).
  /// Ne touche à AUCUN autre fichier. Renvoie le nombre d'éléments supprimés ; ne lève jamais d'exception.
  static Future<int> purge({Directory? temp, Directory? documents}) async {
    var removed = 0;
    try {
      final dirs = <Directory>[temp ?? await getTemporaryDirectory(), documents ?? await getApplicationDocumentsDirectory()];
      for (final dir in dirs) {
        if (!await dir.exists()) continue;
        final cache = Directory('${dir.path}${Platform.pathSeparator}$_renderCache');
        if (await cache.exists()) {
          await cache.delete(recursive: true);
          removed++;
        }
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File && _stray.hasMatch(entity.uri.pathSegments.last)) {
            await entity.delete();
            removed++;
          }
        }
      }
    } catch (_) {
      // Nettoyage au mieux : un échec ne doit jamais gêner l'application.
    }
    return removed;
  }
}

/// Fabrique du visualiseur (remplaçable dans les tests : le moteur natif n'existe pas hors appareil).
typedef PdfBodyBuilder = Widget Function(BuildContext context, Uint8List bytes);

/// Lecteur PDF plein écran d'une pièce justificative PRIVÉE.
class EvidencePdfPage extends StatefulWidget {
  const EvidencePdfPage({super.key, required this.bytes, this.title = 'Pièce jointe', this.bodyBuilder, this.purgeOnClose = true});
  final Uint8List bytes;
  final String title;
  final PdfBodyBuilder? bodyBuilder;

  /// Désactivé uniquement par les tests (pas de plugin de chemins hors appareil).
  final bool purgeOnClose;

  @override
  State<EvidencePdfPage> createState() => _EvidencePdfPageState();
}

class _EvidencePdfPageState extends State<EvidencePdfPage> {
  PdfControllerPinch? _controller;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _problem = EvidenceFiles.refusal(widget.bytes) ?? (EvidenceFiles.looksLikePdf(widget.bytes) ? null : 'Ce fichier n’est pas un PDF valide.');
    if (_problem == null && widget.bodyBuilder == null) {
      _controller = PdfControllerPinch(document: PdfDocument.openData(widget.bytes));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    if (widget.purgeOnClose) EvidenceFiles.purge();
    super.dispose();
  }

  Widget _body(BuildContext context) {
    if (_problem != null) return _Message(_problem!);
    if (widget.bodyBuilder != null) return widget.bodyBuilder!(context, widget.bytes);
    return PdfViewPinch(
      controller: _controller!,
      builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
        pageLoaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, __) => const _Message('Ce PDF n’a pas pu être ouvert.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: TtColors.canvas,
        appBar: AppBar(
          title: Text(widget.title, style: TratraTheme.style(TtType.body).copyWith(fontWeight: FontWeight.w700)),
          backgroundColor: TtColors.canvas,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(24),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Privée : visible des deux parties seulement · ${(widget.bytes.length / 1024).round()} Ko', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            ),
          ),
        ),
        body: SafeArea(child: _body(context)),
      );
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center, style: TratraTheme.style(TtType.body, color: TtColors.dangerInk))),
      );
}
