// lib/biometric/biometric_flow_screen.dart
//
// Mon espace > Vérification d'identité > Vérification faciale : conditions et consentement explicite, présence d'une pièce d'identité, capture
// guidée, résultat. Alternatives toujours proposées : vérification par l'équipe Tratra (sans biométrie) et retrait du consentement (suppression
// immédiate des captures). Rien n'est validé par l'application : elle affiche l'état renvoyé par le serveur.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/biometric/biometric_api.dart';
import 'package:flutter_tratra/biometric/biometric_capture_screen.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart' show showMessage;
import 'package:flutter_tratra/screens/worker/kyc_screen.dart';

class BiometricFlowScreen extends StatefulWidget {
  const BiometricFlowScreen({super.key});
  @override
  State<BiometricFlowScreen> createState() => _BiometricFlowScreenState();
}

class _BiometricFlowScreenState extends State<BiometricFlowScreen> {
  late final BiometricApi _api = BiometricApi(context.read<BaseApi>());
  BiometricState? _state;
  String? _error;
  bool _busy = false;
  bool _accepted = false;
  String? _outcome;          // résultat qui vient d'être soumis
  String? _banner;           // message d'information après un retour de capture

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await _api.state();
      if (mounted) setState(() => _state = s);
    } on BiometricApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } catch (_) {
      if (mounted) setState(() => _error = 'Impossible de charger votre vérification. Vérifiez votre connexion.');
    }
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    setState(() => _busy = true);
    try {
      return await action();
    } on BiometricApiException catch (e) {
      if (mounted) showMessage(context, e.detail, error: true);
    } catch (_) {
      if (mounted) showMessage(context, 'Connexion indisponible. Réessayez.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  Future<void> _consent(BiometricState s) async {
    final ok = await _run(() async {
      await _api.grantConsent(s.consentVersion);
      return true;
    });
    if (ok == true) await _load();
  }

  Future<void> _humanReview(String reason) async {
    final ok = await _run(() async {
      await _api.requestHumanReview(reason);
      return true;
    });
    if (ok == true) {
      await _load();
      if (mounted) setState(() => _banner = 'Demande envoyée : l’équipe Tratra examinera votre dossier.');
    }
  }

  Future<void> _withdraw() async {
    final sure = await showTratraConfirm(context,
        title: 'Retirer mon consentement ?', message: 'Vos captures faciales sont supprimées immédiatement. Votre vérification faciale devra être refaite ou remplacée par une vérification de l’équipe.',
        confirmLabel: 'Retirer et supprimer', danger: true);
    if (!sure) return;
    final n = await _run(() => _api.withdrawConsent());
    if (n != null) {
      await _load();
      if (mounted) setState(() => _banner = 'Consentement retiré : captures supprimées.');
    }
  }

  Future<void> _capture() async {
    final session = await _run(() => _api.startSession());
    if (session == null || !mounted) return;
    final r = await Navigator.of(context).push<CaptureResult>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => BiometricCaptureScreen(api: _api, session: session)));
    if (!mounted) return;
    switch (r) {
      case CaptureResult.done:
        final out = await _run(() => _api.submit(session));
        if (out != null && mounted) setState(() => _outcome = '${out['outcome']}');
        await _load();
      case CaptureResult.denied:
        setState(() => _banner = 'L’accès à la caméra est refusé. Autorisez-le dans les réglages du téléphone, ou demandez une vérification par l’équipe.');
      case CaptureResult.camera:
        setState(() => _banner = 'La caméra n’est pas disponible sur cet appareil : demandez une vérification par l’équipe.');
      case CaptureResult.session:
        setState(() => _banner = 'La session a expiré. Reprenez la vérification : les étapes déjà envoyées sont conservées si elle est encore valide.');
      case CaptureResult.cancelled || null:
        await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: const TratraAppBar(title: 'Vérification faciale'),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(TtSpace.s5), child: Column(mainAxisSize: MainAxisSize.min, children: [
              TratraAlert(tone: TratraAlertTone.danger, message: _error!),
              const SizedBox(height: TtSpace.s3),
              TratraButton(label: 'Réessayer', onPressed: _load),
            ])))
          : _state == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _load, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8), children: _content(_state!))),
    );
  }

  List<Widget> _content(BiometricState s) {
    final w = <Widget>[];
    if (_banner != null) w.add(Padding(padding: const EdgeInsets.only(bottom: TtSpace.s3), child: TratraAlert(tone: TratraAlertTone.info, message: _banner!)));
    if (_outcome != null) w.add(Padding(padding: const EdgeInsets.only(bottom: TtSpace.s3), child: _resultCard(_outcome!)));

    // États terminaux ou en attente
    if (s.satisfied) {
      w.add(TratraAlert(tone: TratraAlertTone.success, title: 'Vérification faciale satisfaisante', message: 'Merci. L’équipe Tratra finalise la validation de votre dossier : aucun badge n’est accordé automatiquement.'));
      w.add(const SizedBox(height: TtSpace.s4));
      w.add(_withdrawLink(s));
      return w;
    }
    if (s.status == 'rejected') {
      w.add(TratraAlert(tone: TratraAlertTone.danger, title: 'Vérification refusée', message: '${s.decisionReason.isEmpty ? 'Votre vérification n’a pas pu être validée.' : s.decisionReason}\nVous pouvez contacter le support pour un recours.'));
      return w;
    }
    if (s.status == 'pending_review' && _outcome == null) {
      w.add(TratraAlert(tone: TratraAlertTone.info, title: 'En attente de vérification par l’équipe', message: 'Votre dossier sera examiné par un membre de l’équipe Tratra. Vous serez notifié de la décision.'));
      w.add(const SizedBox(height: TtSpace.s4));
    }
    if (s.status == 'recapture_requested') {
      w.add(TratraAlert(tone: TratraAlertTone.warning, title: 'Nouvelle capture demandée', message: s.decisionReason.isEmpty ? 'Merci de refaire la vérification faciale.' : s.decisionReason));
      w.add(const SizedBox(height: TtSpace.s4));
    }
    if (s.status == 'documents_requested') {
      w.add(TratraAlert(tone: TratraAlertTone.warning, title: 'Pièces complémentaires demandées', message: s.decisionReason.isEmpty ? 'Merci d’envoyer les pièces demandées.' : s.decisionReason));
      w.add(const SizedBox(height: TtSpace.s4));
    }

    // Prérequis
    if (!s.documentPresent) {
      w.add(TratraCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Une pièce d’identité est nécessaire', style: TratraTheme.style(TtType.h3)),
        const SizedBox(height: TtSpace.s2),
        Text('Déposez d’abord votre carte d’identité ou votre passeport : le visage est comparé à la photo de la pièce.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        const SizedBox(height: TtSpace.s3),
        TratraButton(label: 'Déposer une pièce d’identité', block: true, onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KycScreen()));
          if (mounted) _load();
        }),
      ])));
      w.add(const SizedBox(height: TtSpace.s4));
      w.add(_alternativeCard(s));
      return w;
    }

    if (!s.enabled) {
      w.add(TratraAlert(tone: TratraAlertTone.info, title: 'Vérification automatique indisponible', message: 'La vérification faciale automatique n’est pas activée pour le moment. L’équipe Tratra peut vérifier votre identité directement.'));
      w.add(const SizedBox(height: TtSpace.s4));
      w.add(_alternativeCard(s));
      return w;
    }

    // Conditions et consentement
    if (!s.consentGranted) {
      w.add(TratraCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Conditions et consentement', style: TratraTheme.style(TtType.h3)),
        const SizedBox(height: TtSpace.s2),
        Text(s.consentText, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        const SizedBox(height: TtSpace.s3),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _accepted,
          onChanged: (v) => setState(() => _accepted = v ?? false),
          title: const Text('J’ai lu ces conditions et je consens explicitement au traitement de mes données biométriques pour cette vérification.'),
        ),
        const SizedBox(height: TtSpace.s2),
        TratraButton(label: 'J’accepte et je continue', block: true, loading: _busy, onPressed: _accepted ? () => _consent(s) : null),
      ])));
      w.add(const SizedBox(height: TtSpace.s4));
      w.add(_alternativeCard(s, refuse: true));
      return w;
    }

    // Prêt à capturer
    w.add(TratraCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Avant de commencer', style: TratraTheme.style(TtType.h3)),
      const SizedBox(height: TtSpace.s2),
      for (final tip in const [
        'Placez-vous face à une source de lumière, sans contre-jour.',
        'Retirez lunettes de soleil, casquette ou masque.',
        'Tenez le téléphone à hauteur du visage, immobile.',
        'Suivez les consignes : face, gauche, droite, haut, bas puis un sourire — l’ordre change à chaque fois.',
      ])
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.check_circle_outline, size: 18, color: TtColors.primary), const SizedBox(width: 8), Expanded(child: Text(tip, style: TratraTheme.style(TtType.bodySm)))])),
      const SizedBox(height: TtSpace.s3),
      TratraButton(label: s.hasActiveSession ? 'Reprendre la vérification' : 'Commencer la vérification', block: true, loading: _busy, leading: const Icon(Icons.face_retouching_natural_rounded), onPressed: _capture),
      if (s.attemptsDay > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Tentatives aujourd’hui : ${s.attemptsDay} / ${s.maxDay}', style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
    ])));
    w.add(const SizedBox(height: TtSpace.s4));
    w.add(_alternativeCard(s));
    w.add(const SizedBox(height: TtSpace.s3));
    w.add(_withdrawLink(s));
    return w;
  }

  Widget _alternativeCard(BiometricState s, {bool refuse = false}) {
    if (s.humanReviewRequested && s.status == 'pending_review') return const SizedBox.shrink();
    return TratraCard(variant: TratraCardVariant.soft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(refuse ? 'Vous préférez ne pas utiliser la biométrie ?' : 'Une autre solution', style: TratraTheme.style(TtType.h3)),
      const SizedBox(height: TtSpace.s2),
      Text('L’équipe Tratra peut vérifier votre identité directement, sans capture de votre visage (caméra indisponible, handicap, préférence). Aucune pénalité.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
      const SizedBox(height: TtSpace.s3),
      TratraButton(label: 'Demander une vérification par l’équipe', variant: TratraButtonVariant.outline, block: true, loading: _busy, onPressed: () => _humanReview(refuse ? 'other' : 'accessibility')),
    ]));
  }

  Widget _withdrawLink(BiometricState s) => s.consentGranted
      ? Center(child: TextButton(onPressed: _busy ? null : _withdraw, child: const Text('Retirer mon consentement et supprimer mes captures')))
      : const SizedBox.shrink();

  Widget _resultCard(String outcome) {
    switch (outcome) {
      case 'passed':
        return const TratraAlert(tone: TratraAlertTone.success, title: 'Vérification satisfaisante', message: 'Merci. L’équipe Tratra finalise la validation de votre dossier.');
      case 'failed':
      case 'inconclusive':
        return const TratraAlert(tone: TratraAlertTone.warning, title: 'La vérification n’a pas abouti', message: 'Nous n’avons pas pu confirmer votre identité. Vous pouvez réessayer dans de meilleures conditions de lumière, ou demander une vérification par l’équipe.');
      default:
        return const TratraAlert(tone: TratraAlertTone.info, title: 'Dossier en attente de l’équipe', message: 'Vos captures ont bien été envoyées. Un membre de l’équipe Tratra les examinera : aucune validation automatique n’a été faite.');
    }
  }
}
