// lib/kyc/identity_flow_screen.dart
//
// « Vérifier mon identité » : UN parcours guidé (informations, choix de la pièce, photo, contrôle qualité et lecture, vérification
// faciale, revue humaine, activation des commandes). La progression est celle du SERVEUR (/me/kyc/) : l'artisan reprend où il s'était
// arrêté, même après avoir fermé l'application. Rien n'est validé ici : qualité, lecture, revue et éligibilité viennent du serveur.
// La vérification faciale réutilise l'écran du module biométrique (consentement explicite, alternative humaine). Elle n'apparaît que
// si le serveur l'a activée ; exigée (métier sensible) elle fait partie du parcours, sinon elle est PROPOSÉE après l'envoi de la
// pièce — elle donne le badge « Vérifié » et ne retarde jamais l'activation des commandes.
// L'écran se relit seul quand une décision arrive (notification) ou quand l'application revient au premier plan.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/biometric/biometric_api.dart';
import 'package:flutter_tratra/biometric/biometric_flow_screen.dart';
import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/kyc/kyc_flow_api.dart';
import 'package:flutter_tratra/notifications/notice_center.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart' show showMessage;
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/eligibility_panel.dart';

/// Sélection d'une photo : caméra par défaut ; remplaçable dans les tests.
typedef KycPhotoPicker = Future<String?> Function(ImageSource source);

Future<String?> _defaultPicker(ImageSource source) async {
  final f = await ImagePicker().pickImage(source: source, imageQuality: 90, maxWidth: 2400, preferredCameraDevice: CameraDevice.rear);
  return f?.path;
}

const _months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
String _date(DateTime d) => '${d.day == 1 ? '1er' : d.day} ${_months[d.month - 1]} ${d.year}';

class IdentityFlowScreen extends StatefulWidget {
  const IdentityFlowScreen({super.key, this.picker, this.api, this.simplified = false, this.initialStep});
  final KycPhotoPicker? picker;
  final KycFlowApi? api;

  /// Inscription accompagnée : la pièce d'abord (choix, photos), puis les informations PRÉREMPLIES par la lecture de la pièce et le
  /// nom du compte, à confirmer. Mêmes étapes côté serveur, même revue humaine ; la vérification faciale reste facultative.
  final bool simplified;

  /// Étape à ouvrir d'emblée : `face` (« Obtenir le badge Vérifié » depuis l'accueil), si elle est encore à faire.
  final String? initialStep;
  @override
  State<IdentityFlowScreen> createState() => _IdentityFlowScreenState();
}

class _IdentityFlowScreenState extends State<IdentityFlowScreen> with WidgetsBindingObserver {
  late final KycFlowApi _api = widget.api ?? KycFlowApi(context.read<BaseApi>());
  KycFlowState? _s;
  String? _loadError;
  String? _error;
  bool _busy = false;
  String? _view;                                  // étape rouverte par l'artisan (modifier ses informations, changer de pièce)
  String? _uploading;                             // face en cours d'envoi
  double _progress = 0;
  bool _cameraFailed = false;
  final _first = TextEditingController();
  final _last = TextEditingController();
  DateTime? _birth;
  Map<String, String> _fieldErrors = const {};
  String? _kind;
  final _local = <String, String>{};              // face → photo locale (aperçu de ce qui vient d'être pris)
  Map<String, String> _read = const {};           // lu sur la pièce (proposé, à confirmer)
  final _scroll = ScrollController();
  ValueNotifier<int>? _arrivals;
  bool _opened = false;                           // `initialStep` n'est appliqué qu'au premier chargement
  int _seq = 0;                                   // une relecture lancée avant une action ne doit pas écraser son résultat

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arrivals = context.read<NoticeCenter?>()?.arrivals?..addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _arrivals?.removeListener(_refresh);
    _scroll.dispose();
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  void _apply(KycFlowState s, {bool keepView = false}) {
    setState(() {
      _s = s;
      _loadError = null;
      if (!keepView) _view = null;
      if (!_opened) {
        _opened = true;
        if (widget.initialStep == 'face' && s.faceEnabled && !s.faceDone) _view = 'face';
      }
      if (_first.text.isEmpty) _first.text = s.firstName;
      if (_last.text.isEmpty) _last.text = s.lastName;
      _birth ??= s.birthDate;
      _kind ??= s.documentKind;
    });
  }

  Future<void> _load() async {
    final seq = _seq;
    try {
      final s = await _api.load();
      if (mounted && seq == _seq) _apply(s, keepView: true);
    } catch (e) {
      if (mounted && _s == null) setState(() => _loadError = friendlyError(e, 'Votre vérification n’a pas pu être chargée. Vérifiez votre connexion.'));
    }
  }

  /// Décision de l'équipe reçue (notification) ou retour au premier plan : l'état est relu sans geste de l'utilisateur.
  void _refresh() {
    if (mounted && _s != null && !_busy && _uploading == null) _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// Le message s'affiche EN HAUT de l'écran, et l'écran y revient : sous un long formulaire il resterait hors champ.
  void _fail(String message, {Map<String, String>? fields}) {
    if (!mounted) return;
    setState(() {
      _error = message;
      if (fields != null) _fieldErrors = fields;
    });
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  Future<void> _run(Future<KycFlowState> Function() action, {String? done, bool keepView = false}) async {
    _seq++;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await action();
      _seq++;
      if (!mounted) return;
      _apply(s, keepView: keepView);
      if (done != null) showMessage(context, done);
    } on ApiException catch (e) {
      _fail(e.message, fields: e.fieldErrors);
    } catch (e) {
      _fail(friendlyError(e, 'Connexion interrompue. Réessayez : rien n’a été perdu.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------ actions

  Future<void> _savePersonal() async {
    final errs = <String, String>{
      if (_first.text.trim().length < 2) 'first_name': 'Indiquez vos prénoms tels qu’ils figurent sur la pièce.',
      if (_last.text.trim().length < 2) 'last_name': 'Indiquez votre nom tel qu’il figure sur la pièce.',
      if (_birth == null) 'birth_date': 'Indiquez votre date de naissance.',
    };
    setState(() => _fieldErrors = errs);
    if (errs.isNotEmpty) return;
    await _run(() => _api.savePersonal(firstName: _first.text.trim(), lastName: _last.text.trim(), birthDate: _birth!));
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Date de naissance',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (d != null && mounted) setState(() => _birth = d);
  }

  Future<void> _chooseKind() async {
    final s = _s!;
    final kind = _kind;
    if (kind == null) return _fail('Choisissez le type de pièce.');
    if (s.documentKind != null && s.documentKind != kind && s.captures.any((c) => c.present)) {
      final ok = await showTratraConfirm(context,
          title: 'Changer de pièce ?', message: 'Les photos déjà prises de votre pièce actuelle ne seront pas envoyées.', confirmLabel: 'Changer');
      if (!ok) return;
      _local.clear();
    }
    await _run(() => _api.chooseKind(kind));
  }

  Future<void> _take(String side, {ImageSource source = ImageSource.camera}) async {
    setState(() => _error = null);
    String? path;
    try {
      path = await (widget.picker ?? _defaultPicker)(source);
    } catch (_) {
      if (mounted) setState(() => _cameraFailed = true);
      _fail('Impossible d’ouvrir la caméra. Autorisez-la dans les réglages du téléphone, ou importez une photo de la pièce.');
      return;
    }
    if (path == null || !mounted) return;
    setState(() {
      _uploading = side;
      _progress = 0;
    });
    final file = path;
    await _run(() async {
      final s = await _api.capture(side, file, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (s.suggestions.isNotEmpty && mounted) _prefill(s.suggestions);
      return s;
    });
    if (mounted) {
      setState(() {
        if (_error == null) _local[side] = file;
        _uploading = null;
      });
    }
  }

  /// Préremplit les informations avec ce qui a été lu sur la pièce ; l'utilisateur vérifie et corrige avant l'envoi.
  void _prefill(Map<String, String> read) {
    setState(() {
      _read = read;
      if ((read['first_name'] ?? '').isNotEmpty) _first.text = read['first_name']!;
      if ((read['last_name'] ?? '').isNotEmpty) _last.text = read['last_name']!;
      final birth = DateTime.tryParse(read['birth_date'] ?? '');
      if (birth != null) _birth = birth;
    });
  }

  /// Étape affichée. Mode simplifié : la pièce d'abord, puis les informations (préremplies) ; ensuite l'ordre du serveur.
  String _stepOf(KycFlowState s) {
    if (_view != null) return _view!;
    if (!widget.simplified || !s.editable || s.reviewState == 'rejected' && s.captures.any((c) => !c.present)) return s.currentStep;
    if (s.documentKind == null) return 'document';
    if (s.captures.any((c) => !c.present)) return 'capture';
    if (!s.personalComplete) return 'personal';
    return s.currentStep;
  }

  Future<void> _send() async {
    await _run(() => _api.send(), done: 'Pièce transmise à l’équipe Tratra.');
    if (mounted && _error == null) context.read<DashboardController>().load();
  }

  Future<void> _face({required bool human}) async {
    if (human) {
      setState(() => _busy = true);
      try {
        await BiometricApi(context.read<BaseApi>()).requestHumanReview('other');
      } on BiometricApiException catch (e) {
        if (e.code != 'already_verified') _fail(e.detail);
      } catch (_) {
        _fail('Connexion interrompue. Réessayez.');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (_error == null) await _run(() => _api.setFaceChoice('human'));
      return;
    }
    await _run(() => _api.setFaceChoice('biometric'), keepView: true);
    if (!mounted || _error != null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BiometricFlowScreen()));
    if (!mounted) return;
    await _load();
    if (mounted && (_s?.faceDone ?? false)) {
      setState(() => _view = null);
      context.read<DashboardController?>()?.load();
    }
  }

  // ------------------------------------------------------------------ affichage

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final step = s == null ? '' : _stepOf(s);
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: TratraAppBar(title: 'Vérifier mon identité', subtitle: s?.statusLabel),
      body: s == null
          ? (_loadError == null
              ? const TratraSkeletonList(count: 3)
              : TratraEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Vérification indisponible',
                  description: _loadError,
                  actions: [TratraButton(label: 'Réessayer', leading: const Icon(Icons.refresh_rounded), onPressed: _load)],
                ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(TtLayout.gutterMobile, TtSpace.s4, TtLayout.gutterMobile, TtSpace.s8 + MediaQuery.paddingOf(context).bottom),
                children: [
                  _Header(state: s, step: step),
                  if (_error != null) ...[
                    const SizedBox(height: TtSpace.s3),
                    TratraAlert(key: const ValueKey('kyc-error'), tone: TratraAlertTone.danger, message: _error!),
                  ],
                  const SizedBox(height: TtSpace.s3),
                  _StepsOverview(
                    state: s,
                    onOpen: s.editable && !_busy ? (k) => setState(() => _view = k) : null,
                    onFace: _faceOffered(s) && !_busy ? () => setState(() => _view = 'face') : null,
                  ),
                  const SizedBox(height: TtSpace.s4),
                  ..._content(s, step),
                ],
              ),
            ),
    );
  }

  List<Widget> _content(KycFlowState s, String step) => switch (step) {
        'personal' => _personal(s),
        'document' => _document(s),
        'capture' => _capture(s),
        'quality' => _quality(s),
        'face' => _faceStep(s),
        'review' => _review(s),
        _ => _activation(s),
      };

  List<Widget> _personal(KycFlowState s) => [
        if (_read.isNotEmpty) ...[
          const TratraAlert(
            key: ValueKey('kyc-read'),
            tone: TratraAlertTone.info,
            title: 'Lu sur votre pièce',
            message: 'Nous avons rempli ces informations à partir de votre pièce. Vérifiez-les et corrigez si besoin.',
          ),
          const SizedBox(height: TtSpace.s3),
        ],
        Text('Saisissez vos nom et prénoms exactement comme sur votre pièce d’identité.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        const SizedBox(height: TtSpace.s4),
        TratraInput(key: const ValueKey('kyc-first'), controller: _first, label: 'Prénoms', required: true, textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next, errorText: _fieldErrors['first_name']),
        const SizedBox(height: TtSpace.s3),
        TratraInput(key: const ValueKey('kyc-last'), controller: _last, label: 'Nom', required: true, textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done, errorText: _fieldErrors['last_name']),
        const SizedBox(height: TtSpace.s3),
        TratraInput(
          key: ValueKey('kyc-birth-${_birth?.toIso8601String()}'),
          initialValue: _birth == null ? '' : _date(_birth!),
          label: 'Date de naissance',
          hint: 'Choisir la date',
          required: true,
          readOnly: true,
          onTap: _pickBirth,
          suffix: const Icon(Icons.calendar_month_outlined, color: TtColors.ash),
          errorText: _fieldErrors['birth_date'],
        ),
        const SizedBox(height: TtSpace.s2),
        Text('Ces informations servent uniquement à comparer votre pièce : votre nom public reste celui de votre compte.',
            style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        const SizedBox(height: TtSpace.s5),
        TratraButton(key: const ValueKey('kyc-personal-save'), label: 'Continuer', block: true, loading: _busy, onPressed: _savePersonal),
      ];

  List<Widget> _document(KycFlowState s) => [
        Text('Quelle pièce allez-vous photographier ?', style: TratraTheme.style(TtType.h3)),
        const SizedBox(height: TtSpace.s3),
        for (final k in s.kinds)
          Padding(
            padding: const EdgeInsets.only(bottom: TtSpace.s2),
            child: Semantics(
              selected: _kind == k.value,
              button: true,
              child: TratraCard(
                key: ValueKey('kyc-kind-${k.value}'),
                padding: TratraCard.compact,
                onTap: _busy ? null : () => setState(() => _kind = k.value),
                child: Row(children: [
                  Icon(_kind == k.value ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                      color: _kind == k.value ? TtColors.primary : TtColors.fog),
                  const SizedBox(width: TtSpace.s3),
                  Icon(k.value == 'passport' ? Icons.menu_book_outlined : Icons.badge_outlined, color: TtColors.primaryDark),
                  const SizedBox(width: TtSpace.s3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k.label, style: TratraTheme.style(TtType.title)),
                      Text(k.sides > 1 ? 'Recto et verso — 2 photos' : 'Page avec votre photo — 1 photo',
                          style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        const SizedBox(height: TtSpace.s4),
        TratraButton(key: const ValueKey('kyc-kind-save'), label: 'Continuer', block: true, loading: _busy, onPressed: _kind == null ? null : _chooseKind),
      ];

  Widget _tips() => const TratraAlert(
        tone: TratraAlertTone.brand,
        icon: Icons.photo_camera_outlined,
        title: 'Pour une photo acceptée du premier coup',
        message: 'Posez la pièce à plat, bien éclairée, sans reflet ni flash. Les quatre coins doivent être visibles et le texte lisible.',
      );

  Widget? _rejection(KycFlowState s) {
    if (s.reviewState == 'rejected' && s.reviewReason != null) {
      return TratraAlert(key: const ValueKey('kyc-rejection'), tone: TratraAlertTone.danger, title: 'Nouvelle pièce demandée', message: s.reviewReason!);
    }
    if (s.previousReason == null) return null;
    return TratraAlert(key: const ValueKey('kyc-previous'), tone: TratraAlertTone.warning, title: 'Motif du refus précédent', message: s.previousReason!);
  }

  List<Widget> _capture(KycFlowState s) => [
        if (_rejection(s) != null) ...[_rejection(s)!, const SizedBox(height: TtSpace.s3)],
        _tips(),
        const SizedBox(height: TtSpace.s3),
        for (final c in s.captures) ...[_sideCard(c), const SizedBox(height: TtSpace.s2)],
        if (_cameraFailed)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _take(s.captures.firstWhere((c) => !c.present, orElse: () => s.captures.first).side, source: ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Importer une photo de la pièce'),
            ),
          ),
      ];

  Widget _sideCard(KycCapture c) {
    final local = _local[c.side];
    final uploading = _uploading == c.side;
    return TratraCard(
      key: ValueKey('kyc-side-${c.side}'),
      padding: TratraCard.compact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(TtRadius.control),
            child: SizedBox(
              width: 72,
              height: 48,
              child: local != null && File(local).existsSync()
                  ? Image.file(File(local), fit: BoxFit.cover)
                  : ColoredBox(color: TtColors.primarySoft, child: Icon(c.present ? Icons.check_rounded : Icons.badge_outlined, color: TtColors.primaryDark)),
            ),
          ),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.label, style: TratraTheme.style(TtType.title)),
              Text(
                uploading ? 'Envoi et contrôle de la photo…' : !c.present ? 'Photo à prendre' : switch (c.quality) {
                  'ok' => 'Photo nette et lisible',
                  'warn' => 'Photo exploitable — à reprendre si possible',
                  'fail' => 'Photo inexploitable : à reprendre',
                  _ => 'Photo prise',
                },
                style: TratraTheme.style(TtType.caption, color: c.quality == 'fail' ? TtColors.dangerInk : c.quality == 'warn' ? TtColors.warningInk : TtColors.ash),
              ),
            ]),
          ),
        ]),
        if (uploading) ...[
          const SizedBox(height: TtSpace.s2),
          LinearProgressIndicator(value: _progress == 0 || _progress >= 1 ? null : _progress, color: TtColors.primary, minHeight: 4),
        ],
        for (final p in c.problems)
          Padding(
            padding: const EdgeInsets.only(top: TtSpace.s2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(p.blocking ? Icons.error_outline_rounded : Icons.info_outline_rounded, size: 16, color: p.blocking ? TtColors.dangerInk : TtColors.warningInk),
              const SizedBox(width: TtSpace.s2),
              Expanded(child: Text(p.label, style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft))),
            ]),
          ),
        const SizedBox(height: TtSpace.s2),
        Align(
          alignment: Alignment.centerRight,
          child: TratraButton(
            key: ValueKey('kyc-take-${c.side}'),
            label: c.present ? 'Reprendre' : 'Prendre la photo',
            size: TratraButtonSize.sm,
            variant: c.present ? TratraButtonVariant.outline : TratraButtonVariant.primary,
            leading: const Icon(Icons.photo_camera_outlined, size: 18),
            loading: uploading,
            onPressed: _busy ? null : () => _take(c.side),
          ),
        ),
      ]),
    );
  }

  List<Widget> _quality(KycFlowState s) {
    final notes = [for (final c in s.captures) ...c.readingNotes];
    final reading = s.captures.map((c) => c.readingStatus).whereType<String>().toSet();
    return [
      if (_rejection(s) != null) ...[_rejection(s)!, const SizedBox(height: TtSpace.s3)],
      Text('Vérifiez vos photos avant de les envoyer.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
      const SizedBox(height: TtSpace.s3),
      for (final c in s.captures) ...[_sideCard(c), const SizedBox(height: TtSpace.s2)],
      if (reading.isNotEmpty)
        TratraAlert(
          key: const ValueKey('kyc-reading'),
          tone: notes.isEmpty ? TratraAlertTone.info : TratraAlertTone.warning,
          title: reading.contains('read') ? 'Lecture automatique' : 'Lecture automatique incomplète',
          message: notes.isNotEmpty
              ? notes.join('\n')
              : reading.contains('read')
                  ? 'Les informations lisibles ont été repérées. L’équipe Tratra vérifiera la pièce elle-même.'
                  : 'Le texte n’a pas pu être lu automatiquement : l’équipe Tratra vérifiera la pièce directement.',
        ),
      const SizedBox(height: TtSpace.s3),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.lock_outline_rounded, size: 16, color: TtColors.ash)),
        const SizedBox(width: TtSpace.s2),
        Expanded(
          child: Text('En envoyant, vous acceptez que l’équipe Tratra examine ces photos pour vérifier votre identité. Elles sont stockées en privé.',
              style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        ),
      ]),
      const SizedBox(height: TtSpace.s4),
      TratraButton(
        key: const ValueKey('kyc-send'),
        label: 'Envoyer à l’équipe Tratra',
        block: true,
        loading: _busy && _uploading == null,
        leading: const Icon(Icons.send_rounded, size: 18),
        onPressed: s.readyToSend && !_busy ? _send : null,
      ),
    ];
  }

  /// Vérification faciale FACULTATIVE encore à faire : proposée dès que la pièce est envoyée, jamais imposée.
  bool _faceOffered(KycFlowState s) =>
      s.faceEnabled && !s.faceRequired && !s.faceDone && (s.reviewState == 'pending' || s.reviewState == 'approved');

  List<Widget> _faceStep(KycFlowState s) => [
        TratraCard(
          key: const ValueKey('kyc-face'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Vérification faciale', style: TratraTheme.style(TtType.h3))),
              if (!s.faceRequired) const TratraBadge('Facultatif', tone: TratraTone.gray),
            ]),
            const SizedBox(height: TtSpace.s2),
            Text(s.faceNote, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
            const SizedBox(height: TtSpace.s2),
            Text('Elle ne démarre qu’après votre consentement explicite. Aucune décision n’est prise automatiquement : l’équipe Tratra valide.',
                style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            const SizedBox(height: TtSpace.s4),
            if (s.faceDone) ...[
              TratraAlert(
                key: const ValueKey('kyc-face-sent'),
                tone: s.faceSatisfied ? TratraAlertTone.success : TratraAlertTone.info,
                message: s.faceSatisfied
                    ? 'Votre vérification faciale est validée.'
                    : 'Votre vérification faciale est transmise : l’équipe Tratra la valide et vous prévient.',
              ),
              const SizedBox(height: TtSpace.s3),
              TratraButton(label: 'Continuer', block: true, onPressed: () => setState(() => _view = null)),
            ] else ...[
              TratraButton(label: 'Vérifier mon visage', block: true, loading: _busy, leading: const Icon(Icons.face_retouching_natural_rounded),
                  onPressed: () => _face(human: false)),
              const SizedBox(height: TtSpace.s2),
              TratraButton(key: const ValueKey('kyc-face-human'), label: 'Vérification par l’équipe', block: true,
                  variant: TratraButtonVariant.outline, onPressed: _busy ? null : () => _face(human: true)),
              if (!s.faceRequired) ...[
                const SizedBox(height: TtSpace.s2),
                TratraButton(key: const ValueKey('kyc-face-later'), label: 'Plus tard', block: true, variant: TratraButtonVariant.ghost,
                    onPressed: _busy ? null : () => setState(() => _view = null)),
              ],
            ],
          ]),
        ),
      ];

  /// « Obtenir le badge Vérifié » : la suite proposée une fois la pièce envoyée (revue en cours ou commandes activées).
  List<Widget> _faceOffer(KycFlowState s) => [
        if (_faceOffered(s)) ...[
          const SizedBox(height: TtSpace.s3),
          TratraCard(
            key: const ValueKey('kyc-face-offer'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.verified_outlined, color: TtColors.primaryDark),
                const SizedBox(width: TtSpace.s2),
                Expanded(child: Text('Obtenez le badge « Vérifié »', style: TratraTheme.style(TtType.title))),
                const TratraBadge('Facultatif', tone: TratraTone.gray),
              ]),
              const SizedBox(height: TtSpace.s2),
              Text(s.faceBenefit.isNotEmpty ? s.faceBenefit : 'Une vérification faciale confirme que la pièce d’identité est bien la vôtre.',
                  style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
              const SizedBox(height: TtSpace.s3),
              TratraButton(key: const ValueKey('kyc-face-open'), label: 'Obtenir le badge Vérifié', block: true, variant: TratraButtonVariant.outline,
                  leading: const Icon(Icons.face_retouching_natural_rounded, size: 18), onPressed: _busy ? null : () => setState(() => _view = 'face')),
            ]),
          ),
        ] else if (s.faceEnabled && s.faceDone && !s.faceSatisfied && s.reviewState != 'none') ...[
          const SizedBox(height: TtSpace.s3),
          const TratraAlert(
            key: ValueKey('kyc-face-pending'),
            tone: TratraAlertTone.info,
            title: 'Vérification faciale en cours de revue',
            message: 'Le badge « Vérifié » s’affichera après la décision de l’équipe Tratra.',
          ),
        ],
      ];

  List<Widget> _review(KycFlowState s) => [
        TratraCard(
          key: const ValueKey('kyc-review'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.hourglass_top_rounded, color: TtColors.accentDark),
              const SizedBox(width: TtSpace.s2),
              Expanded(child: Text('Votre pièce est en cours de revue', style: TratraTheme.style(TtType.h3))),
            ]),
            const SizedBox(height: TtSpace.s2),
            if (s.sentAt != null) Text('Transmise le ${_date(s.sentAt!.toLocal())}.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
            const SizedBox(height: TtSpace.s1),
            Text('Un membre de l’équipe Tratra l’examine. Vous serez prévenu(e) de la décision et cet écran se mettra à jour. Votre progression est '
                'enregistrée : vous pouvez continuer à utiliser l’application.',
                style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
            if (s.activation?.authorized ?? false) ...[
              const SizedBox(height: TtSpace.s2),
              Text('En attendant, votre service reste visible avec la mention « ${s.activation!.verificationLabel} ».',
                  style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
            ],
            const SizedBox(height: TtSpace.s4),
            TratraButton(key: const ValueKey('kyc-review-back'), label: 'Retour à mon espace', block: true, onPressed: () => Navigator.of(context).maybePop()),
            const SizedBox(height: TtSpace.s1),
            Center(
              child: TextButton.icon(
                onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Actualiser')),
            ),
          ]),
        ),
        ..._faceOffer(s),
      ];

  List<Widget> _activation(KycFlowState s) {
    final e = s.activation;
    return [
      if (e != null && e.verified)
        const TratraAlert(key: ValueKey('kyc-badge'), tone: TratraAlertTone.success, title: 'Profil vérifié',
            message: 'Votre pièce d’identité et votre visage sont vérifiés : le badge « Vérifié » est affiché sur votre profil et vos offres.')
      else if (e != null && e.ordersAuthorized)
        const TratraAlert(key: ValueKey('kyc-active'), tone: TratraAlertTone.success, title: 'Commandes activées',
            message: 'Votre identité est vérifiée : vous pouvez recevoir des réservations, des missions Tratra Flash et des contrats.')
      else if (s.status == 'verified')
        const TratraAlert(key: ValueKey('kyc-verified'), tone: TratraAlertTone.success, title: 'Identité vérifiée',
            message: 'Il reste ce qui est indiqué ci-dessous avant l’activation de vos commandes.'),
      ..._faceOffer(s),
      const SizedBox(height: TtSpace.s3),
      if (e != null) EligibilityPanel(eligibility: e, onChanged: _load),
      const SizedBox(height: TtSpace.s4),
      TratraButton(label: 'Gérer mes offres', block: true, variant: TratraButtonVariant.outline, onPressed: () => openProviderHub(context)),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.step});
  final KycFlowState state;
  final String step;

  @override
  Widget build(BuildContext context) {
    final shown = _shownSteps(state, step);
    final total = shown.isEmpty ? 1 : shown.length;
    final i = (shown.indexWhere((x) => x.key == step) + 1).clamp(1, total);
    final label = state.step(step)?.label ?? '';
    return Semantics(
      label: 'Étape $i sur $total : $label',
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Étape $i sur $total', style: TratraTheme.style(TtType.caption, color: TtColors.primaryDark).copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, key: const ValueKey('kyc-step-title'), style: TratraTheme.style(TtType.h2)),
          const SizedBox(height: TtSpace.s2),
          ClipRRect(
            borderRadius: BorderRadius.circular(TtRadius.pill),
            child: LinearProgressIndicator(value: i / total, minHeight: 6, backgroundColor: TtColors.lineSoft, color: TtColors.primary),
          ),
        ]),
      ),
    );
  }
}

/// Étapes comptées dans « Étape n sur N » : ni la vérification faciale désactivée, ni la facultative (sauf quand c'est elle qui est
/// affichée) — le compte annoncé est celui que l'artisan parcourt réellement.
List<KycStep> _shownSteps(KycFlowState s, String step) =>
    [for (final x in s.steps) if (x.state != 'skipped' && (x.state != 'optional' || x.key == step)) x];

/// « 2 sur 6 terminées » : une étape désactivée ou facultative n'est ni comptée ni présentée comme faite.
String _progressLabel(KycFlowState s) {
  final required = s.steps.where((x) => x.state != 'skipped' && x.state != 'optional').length;
  final done = s.steps.where((x) => x.state == 'done').length;
  return '$done sur $required terminée${done > 1 ? 's' : ''}';
}

/// Les étapes et leur état réel ; une étape déjà faite et encore modifiable peut être rouverte, la vérification faciale facultative
/// s'ouvre d'ici une fois la pièce envoyée.
class _StepsOverview extends StatelessWidget {
  const _StepsOverview({required this.state, this.onOpen, this.onFace});
  final KycFlowState state;
  final void Function(String key)? onOpen;
  final VoidCallback? onFace;

  @override
  Widget build(BuildContext context) {
    return TratraCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('kyc-steps'),
          tilePadding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
          childrenPadding: const EdgeInsets.fromLTRB(TtSpace.s4, 0, TtSpace.s4, TtSpace.s3),
          title: Text('Les ${state.steps.where((x) => x.state != 'skipped' && x.state != 'optional').length} étapes', style: TratraTheme.style(TtType.title)),
          subtitle: Text(_progressLabel(state), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          children: [
            for (final s in state.steps.where((x) => x.state != 'skipped'))
              InkWell(
                onTap: s.state == 'optional'
                    ? onFace
                    : onOpen != null && s.state == 'done' && (s.key == 'personal' || s.key == 'document') ? () => onOpen!(s.key) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(switch (s.state) {
                      'done' => Icons.check_circle_rounded,
                      'current' => Icons.radio_button_checked_rounded,
                      'waiting' => Icons.hourglass_top_rounded,
                      'error' => Icons.error_rounded,
                      'optional' => Icons.add_circle_outline_rounded,
                      _ => Icons.radio_button_unchecked_rounded,
                    }, size: 18, color: switch (s.state) {
                      'done' => TtColors.success,
                      'current' => TtColors.primary,
                      'waiting' => TtColors.accentDark,
                      'error' => TtColors.dangerInk,
                      'optional' => TtColors.primary,
                      _ => TtColors.fog,
                    }),
                    const SizedBox(width: TtSpace.s2),
                    Expanded(child: Text(s.label, style: TratraTheme.style(TtType.bodySm, color: s.state == 'todo' ? TtColors.ash : TtColors.ink))),
                    Text(switch (s.state) {
                      'done' => (s.key == 'personal' || s.key == 'document') && onOpen != null ? 'Modifier' : 'Fait',
                      'current' => 'En cours',
                      'waiting' => 'En attente',
                      'error' => 'À refaire',
                      'optional' => 'Facultatif',
                      _ => '',
                    }, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
