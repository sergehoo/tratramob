// lib/screens/worker/kyc_screen.dart
//
// Vérification KYC artisan : liste des documents + téléversement (galerie/caméra).
// Aucune règle métier ici : mêmes appels HandymanService, mêmes types de documents,
// même sélection image (qualité 80). Le statut affiché est celui renvoyé par l'API.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/services/handyman_service.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  late Future<List<Map<String, dynamic>>> _docs;
  bool _uploading = false;

  static const _types = <String, String>{
    'id_card': 'Carte d\'identité',
    'license': 'Permis de conduire',
    'casier': 'Casier judiciaire',
    'insurance': 'Assurance',
    'certification': 'Certificats / diplômes',
    'other': 'Autre',
  };

  /// Icône d'illustration par type (affichage seulement).
  static const _typeIcons = <String, IconData>{
    'id_card': Icons.badge_outlined,
    'license': Icons.drive_eta_outlined,
    'casier': Icons.gavel_rounded,
    'insurance': Icons.health_and_safety_outlined,
    'certification': Icons.workspace_premium_outlined,
    'other': Icons.description_outlined,
  };

  @override
  void initState() {
    super.initState();
    _docs = context.read<HandymanService>().listDocuments();
  }

  /// Recharge la liste. Une erreur de chargement n'est pas relancée ici : elle est
  /// affichée (avec « Réessayer ») par le FutureBuilder, et ne fait jamais passer
  /// un envoi réussi pour un échec.
  Future<void> _reload() async {
    setState(() {
      _docs = context.read<HandymanService>().listDocuments();
    });
    try {
      await _docs;
    } catch (_) {
      // Rendu par l'état d'erreur de la liste.
    }
  }

  Future<String?> _chooseType() {
    return showTratraSheet<String>(
      context,
      title: 'Type de document',
      description: 'Quelle pièce souhaitez-vous envoyer ?',
      child: Builder(
        builder: (sheetContext) => Column(
          children: [
            for (final e in _types.entries)
              _ChoiceTile(
                icon: _typeIcons[e.key] ?? Icons.description_outlined,
                label: e.value,
                onTap: () => Navigator.of(sheetContext).pop(e.key),
              ),
          ],
        ),
      ),
    );
  }

  Future<ImageSource?> _chooseSource() {
    return showTratraSheet<ImageSource>(
      context,
      title: 'Ajouter une photo',
      description:
          'Cadrez la pièce en entier, bien éclairée, avec un texte lisible.',
      child: Builder(
        builder: (sheetContext) => Column(
          children: [
            _ChoiceTile(
              icon: Icons.photo_library_outlined,
              label: 'Choisir dans la galerie',
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            _ChoiceTile(
              icon: Icons.camera_alt_outlined,
              label: 'Prendre une photo',
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            const SizedBox(height: TtSpace.s2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.lock_outline_rounded,
                      size: 16, color: TtColors.ash),
                ),
                const SizedBox(width: TtSpace.s2),
                Expanded(
                  child: Text(
                    'Vos pièces sont stockées en privé : seuls vous et l’équipe Tratra pouvez les consulter.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startUpload() async {
    final type = await _chooseType();
    if (type == null || !mounted) return;

    final source = await _chooseSource();
    if (source == null || !mounted) return;

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source, imageQuality: 80);
    } catch (_) {
      if (!mounted) return;
      _toast(
        'Impossible d’ouvrir la caméra ou la galerie. Vérifiez les autorisations de l’application dans les réglages de votre téléphone.',
        error: true,
      );
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      await context.read<HandymanService>().uploadDocument(
            documentType: type,
            filePath: picked.path,
          );
      if (!mounted) return;
      _toast('Document envoyé. En attente de revue.');
      await _reload();
    } catch (e) {
      if (!mounted) return;
      _toast('Échec du téléversement : ${_readableError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: error ? TtColors.dangerInk : TtColors.primaryDark,
        duration: Duration(seconds: error ? 6 : 4),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_outline,
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: TtSpace.s3),
            Expanded(child: Text(message)),
          ],
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: const TratraAppBar(
        title: 'Vérification (KYC)',
        subtitle: 'Pièces d’identité et justificatifs',
      ),
      bottomNavigationBar: _UploadBar(
        uploading: _uploading,
        onPressed: _startUpload,
      ),
      body: RefreshIndicator(
        color: TtColors.primaryDark,
        onRefresh: _reload,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _docs,
          builder: (context, snap) {
            final waiting = snap.connectionState == ConnectionState.waiting;
            final docs = snap.data ?? const <Map<String, dynamic>>[];
            final failed = !waiting && snap.hasError;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(TtLayout.gutterMobile,
                  TtSpace.s4, TtLayout.gutterMobile, TtSpace.s6),
              children: [
                const TratraAlert(
                  tone: TratraAlertTone.brand,
                  icon: Icons.verified_user_outlined,
                  title: 'Pourquoi cette vérification ?',
                  message:
                      'Vos documents sont examinés par l’équipe Tratra avant que vous puissiez passer en ligne et recevoir des missions. Le badge « Vérifié » n’apparaît qu’une fois vos pièces réellement validées.',
                ),
                TratraSectionHeader(
                  title: 'Mes documents',
                  subtitle: (!waiting && !failed && docs.isNotEmpty)
                      ? (docs.length == 1
                          ? '1 document envoyé'
                          : '${docs.length} documents envoyés')
                      : null,
                  padding:
                      const EdgeInsets.fromLTRB(0, TtSpace.s6, 0, TtSpace.s3),
                ),
                if (waiting)
                  const TratraSkeletonList(count: 3, padding: EdgeInsets.zero)
                else if (failed)
                  TratraAlert(
                    tone: TratraAlertTone.danger,
                    title: 'Documents indisponibles',
                    message: _readableError(snap.error!),
                    action: Align(
                      alignment: Alignment.centerLeft,
                      child: TratraButton(
                        label: 'Réessayer',
                        size: TratraButtonSize.sm,
                        variant: TratraButtonVariant.outline,
                        leading: const Icon(Icons.refresh_rounded),
                        onPressed: _reload,
                      ),
                    ),
                  )
                else if (docs.isEmpty)
                  const TratraEmptyState(
                    icon: Icons.folder_open_rounded,
                    title: 'Aucun document envoyé',
                    description:
                        'Vos pièces apparaîtront ici avec leur statut réel. Touchez « Téléverser un document » pour envoyer la première.',
                  )
                else
                  for (var i = 0; i < docs.length; i++)
                    _Reveal(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: TtSpace.s3),
                        child: _DocumentCard(
                          typeLabel: _types[(docs[i]['document_type'] ?? '')
                                  .toString()] ??
                              (docs[i]['document_type'] ?? '').toString(),
                          icon: _typeIcons[(docs[i]['document_type'] ?? '')
                                  .toString()] ??
                              Icons.description_outlined,
                          status: _normalizedStatus(docs[i]['status']),
                          sentOn: _formatSentDate(docs[i]['uploaded_at']),
                          rejectionReason:
                              (docs[i]['rejection_reason'] ?? '').toString(),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aides d'affichage (aucune règle métier)
// ---------------------------------------------------------------------------

/// Statut inconnu ou absent = « pending », comme avant la refonte.
String _normalizedStatus(Object? raw) {
  final s = (raw ?? 'pending').toString();
  return (s == 'approved' || s == 'rejected') ? s : 'pending';
}

const _months = <String>[
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

/// « 8 octobre 2026 » ; null si la date est absente ou invalide.
String? _formatSentDate(Object? iso) {
  final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (d == null) return null;
  return '${d.day == 1 ? '1er' : d.day} ${_months[d.month - 1]} ${d.year}';
}

/// Message d'erreur lisible : texte serveur (JSON DRF) quand il existe, sinon formulation
/// neutre. Jamais de corps HTML ni de trace technique brute.
String _readableError(Object error) {
  final raw =
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();

  final api = RegExp(r'^Erreur \d+:\s*(.*)$', dotAll: true).firstMatch(raw);
  if (api != null) {
    try {
      final messages = _flattenMessages(json.decode(api.group(1)!.trim()));
      if (messages.isNotEmpty) return messages.join(' ');
    } catch (_) {
      // Corps non JSON (page HTML d'un proxy, par exemple).
    }
    return 'Le serveur a refusé la demande.';
  }

  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Failed host lookup')) {
    return 'Connexion impossible. Vérifiez votre réseau puis réessayez.';
  }
  return raw.isEmpty ? 'Une erreur est survenue.' : raw;
}

List<String> _flattenMessages(Object? node) {
  if (node is String) return node.trim().isEmpty ? const [] : [node.trim()];
  if (node is List) return node.expand(_flattenMessages).toList();
  if (node is Map) return node.values.expand(_flattenMessages).toList();
  return const [];
}

// ---------------------------------------------------------------------------
// Sous-widgets
// ---------------------------------------------------------------------------

/// Barre d'action fixe : le bouton « Téléverser » reste atteignable au pouce.
class _UploadBar extends StatelessWidget {
  const _UploadBar({required this.uploading, required this.onPressed});

  final bool uploading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: TtColors.surface,
        border: Border(top: BorderSide(color: TtColors.lineSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(TtLayout.gutterMobile, TtSpace.s3,
              TtLayout.gutterMobile, TtSpace.s3),
          child: TratraButton(
            label: uploading ? 'Envoi en cours…' : 'Téléverser un document',
            size: TratraButtonSize.lg,
            block: true,
            loading: uploading,
            leading: const Icon(Icons.upload_file_rounded),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

/// Ligne de choix d'une feuille basse (type de document, source de l'image).
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: TratraCard(
        variant: TratraCardVariant.flat,
        radius: TtRadius.panel,
        margin: const EdgeInsets.only(bottom: TtSpace.s2),
        padding: const EdgeInsets.symmetric(
            horizontal: TtSpace.s3, vertical: TtSpace.s2),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: TtColors.primarySoft,
                borderRadius: TtRadius.controlAll,
              ),
              child: Icon(icon, size: 20, color: TtColors.primaryDark),
            ),
            const SizedBox(width: TtSpace.s3),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
          ],
        ),
      ),
    );
  }
}

/// Carte d'un document : type, date d'envoi réelle, statut renvoyé par l'API et,
/// pour un refus, le motif saisi par l'équipe (jamais un texte inventé).
class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.typeLabel,
    required this.icon,
    required this.status,
    required this.sentOn,
    required this.rejectionReason,
  });

  final String typeLabel;
  final IconData icon;
  final String status;
  final String? sentOn;
  final String rejectionReason;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final view = TratraStatus.of(TratraStatus.document, status);
    final tone = tratraToneColors(view.tone);
    final note = switch (status) {
      'approved' => 'Cette pièce a été validée par l’équipe Tratra.',
      'pending' =>
        'L’équipe Tratra examine cette pièce. Son statut sera mis à jour ici dès la fin de l’examen.',
      _ => null,
    };

    return TratraCard(
      padding: TratraCard.compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tone.bg,
                  borderRadius: TtRadius.panelAll,
                ),
                child: Icon(icon, size: 22, color: tone.fg),
              ),
              const SizedBox(width: TtSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      typeLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    if (sentOn != null) ...[
                      const SizedBox(height: 2),
                      Text('Envoyé le $sentOn', style: text.bodySmall),
                    ],
                    const SizedBox(height: TtSpace.s2),
                    TratraStatusBadge(TratraStatus.document, status),
                  ],
                ),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: TtSpace.s3),
            Text(note, style: text.bodySmall),
          ],
          if (status == 'rejected' && rejectionReason.isNotEmpty) ...[
            const SizedBox(height: TtSpace.s3),
            TratraAlert(
              tone: TratraAlertTone.danger,
              title: 'Motif du refus',
              message: rejectionReason,
            ),
          ],
        ],
      ),
    );
  }
}

/// Apparition discrète (fondu + léger glissement, ≤ 420 ms), échelonnée sur les
/// premiers éléments. Neutralisée si l'utilisateur réduit les animations.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final step = index < 5 ? index : 5;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration:
          Duration(milliseconds: TtMotion.base.inMilliseconds + step * 40),
      curve: TtMotion.emphasized,
      child: child,
      builder: (context, t, child) {
        final v = t.clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * TtSpace.s3),
            child: child,
          ),
        );
      },
    );
  }
}
