// lib/flash/flash_deadline.dart
//
// Délais Tratra Flash : barre qui se décharge jusqu'à l'échéance (délai de réponse à une mission, contre-offre, validité d'une
// proposition).
//
//  * L'échéance vient TOUJOURS du serveur (`expires_at`) et le temps restant est calé sur SON heure (`server_now`, à défaut
//    `seconds_left`) : l'horloge du téléphone, même fausse de plusieurs heures, ne déplace jamais la barre. Sans l'un ni l'autre,
//    aucune barre n'est affichée — jamais de compteur local inventé.
//  * Rien n'est décompté : chaque image relit l'horloge et l'échéance. Fermer puis rouvrir l'écran, revenir de l'arrière-plan
//    ou recevoir un nouvel état reprend donc exactement au bon endroit.
//  * Une seule pulsation (`FlashPulse`) anime toutes les barres de l'application ; elle s'arrête dès qu'aucune barre n'attend.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_tratra/design/design.dart';

/// Une échéance du serveur, ramenée sur l'horloge du téléphone au moment où la réponse a été reçue.
@immutable
class FlashDeadline {
  const FlashDeadline._(this.endsAt, this.total);

  /// Fin du délai, sur l'horloge du téléphone.
  final DateTime endsAt;

  /// Durée complète du délai (barre pleine). Jamais inférieure au temps restant à la réception.
  final Duration total;

  /// `expiresAt` / `startedAt` / `serverNow` : dates ISO du serveur ; `secondsLeft` : repli des serveurs qui n'envoient pas leur
  /// heure ; `receivedAt` : instant (téléphone) où ces données ont été reçues. Nul s'il n'y a pas de quoi situer l'échéance.
  static FlashDeadline? from({Object? expiresAt, Object? startedAt, Object? serverNow, Object? secondsLeft, required DateTime receivedAt}) {
    final expires = _date(expiresAt), now = _date(serverNow), started = _date(startedAt);
    Duration? left;
    if (expires != null && now != null) {
      left = expires.difference(now);
    } else {
      final s = num.tryParse('${secondsLeft ?? ''}');
      if (s != null) left = Duration(milliseconds: (s * 1000).round());
    }
    if (left == null) return null;
    if (left.isNegative) left = Duration.zero;
    var total = expires != null && started != null ? expires.difference(started) : left;
    if (total < left) total = left;
    return FlashDeadline._(receivedAt.add(left), total);
  }

  static DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');

  /// Temps restant (jamais négatif).
  Duration left([DateTime? now]) {
    final d = endsAt.difference(now ?? clock.now());
    return d.isNegative ? Duration.zero : d;
  }

  bool over([DateTime? now]) => left(now) <= Duration.zero;

  /// Part du délai encore disponible : 1 au départ, 0 à l'échéance.
  double fraction([DateTime? now]) {
    if (total <= Duration.zero) return 0;
    return (left(now).inMicroseconds / total.inMicroseconds).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) => other is FlashDeadline && other.endsAt == endsAt && other.total == total;

  @override
  int get hashCode => Object.hash(endsAt, total);
}

/// `01:30 → 00:00` (secondes arrondies vers le haut : « 00:00 » n'apparaît qu'à l'échéance) ; `1:02:05` au-delà d'une heure.
String flashCountdownText(Duration left) {
  final s = left <= Duration.zero ? 0 : (left.inMilliseconds / 1000).ceil();
  String two(int v) => v.toString().padLeft(2, '0');
  final h = s ~/ 3600, m = (s % 3600) ~/ 60;
  return h > 0 ? '$h:${two(m)}:${two(s % 60)}' : '${two(m)}:${two(s % 60)}';
}

/// Vert, puis orange, puis rouge selon la part de temps restante — avec un fondu entre deux couleurs, sans saut.
Color flashCountdownColor(double fraction) {
  const green = TtColors.primary, orange = TtColors.warning, red = TtColors.danger;
  if (fraction >= 0.55) return green;
  if (fraction >= 0.45) return Color.lerp(orange, green, (fraction - 0.45) / 0.10)!;
  if (fraction >= 0.25) return orange;
  if (fraction >= 0.15) return Color.lerp(red, orange, (fraction - 0.15) / 0.10)!;
  return red;
}

/// 0 = vert, 1 = orange, 2 = rouge (couleur du temps affiché en chiffres).
int flashCountdownTone(double fraction) => fraction >= 0.5 ? 0 : (fraction >= 0.2 ? 1 : 2);

/// Pulsation unique des barres de délai : un seul `Ticker` pour toute l'application, démarré à la première barre qui attend et
/// arrêté à la dernière — aucune minuterie par barre, rien qui tourne quand aucune échéance n'est affichée.
class FlashPulse extends ChangeNotifier {
  FlashPulse._();
  static final FlashPulse instance = FlashPulse._();

  Ticker? _ticker;

  /// Vrai tant qu'au moins une barre attend son échéance.
  bool get running => _ticker != null;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _ticker ??= Ticker((_) => notifyListeners(), debugLabel: 'FlashPulse')..start();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _ticker?.dispose();
      _ticker = null;
    }
  }
}

/// Barre de délai : pleine au départ, vide à l'échéance, avec le temps restant en chiffres.
///
/// `onExpired` est appelé UNE fois, au moment où l'échéance passe pendant que la barre est affichée (y compris application en
/// arrière-plan : une minuterie unique prend le relais des images). Une barre construite sur une échéance déjà passée reste
/// vide à « 00:00 » sans rien déclencher : l'appelant ne peut pas boucler sur un état que le serveur n'a pas encore clos.
class FlashCountdownBar extends StatefulWidget {
  const FlashCountdownBar({super.key, required this.deadline, this.onExpired, this.label, this.compact = false});

  final FlashDeadline deadline;
  final VoidCallback? onExpired;
  final String? label;
  final bool compact;

  @override
  State<FlashCountdownBar> createState() => _FlashCountdownBarState();
}

class _FlashCountdownBarState extends State<FlashCountdownBar> {
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  Timer? _end;
  bool _over = false;
  bool _enabled = true;
  bool _listening = false;
  double _width = 0;
  double _dpr = 1;
  String _text = '';
  int _tone = 0;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = TickerMode.of(context);   // écran recouvert par un autre : la barre ne demande plus d'images
    _dpr = MediaQuery.devicePixelRatioOf(context);
    _listen();
    _read();
  }

  @override
  void didUpdateWidget(FlashCountdownBar old) {
    super.didUpdateWidget(old);
    if (old.deadline != widget.deadline) {   // nouvel état du serveur : la barre se recale dessus
      _arm();
      _listen();
      _repaint.value++;
    }
  }

  @override
  void dispose() {
    _end?.cancel();
    if (_listening) FlashPulse.instance.removeListener(_onPulse);
    _repaint.dispose();
    super.dispose();
  }

  void _arm() {
    _end?.cancel();
    _end = null;
    final left = widget.deadline.left();
    _over = left <= Duration.zero;
    _read();
    if (!_over) _end = Timer(left, _onTimer);
  }

  void _listen() {
    final want = !_over && _enabled;
    if (want == _listening) return;
    _listening = want;
    if (want) {
      FlashPulse.instance.addListener(_onPulse);
    } else {
      FlashPulse.instance.removeListener(_onPulse);
    }
  }

  /// Chiffres et couleur du texte : relus à chaque image, reconstruits seulement quand ils changent (une fois par seconde).
  bool _read() {
    final left = _over ? Duration.zero : widget.deadline.left();
    final text = flashCountdownText(left);
    final tone = _over ? 2 : flashCountdownTone(widget.deadline.fraction());
    if (text == _text && tone == _tone) return false;
    _text = text;
    _tone = tone;
    return true;
  }

  void _onPulse() {
    if (!mounted) return;
    if (widget.deadline.over()) {
      _expire();
      return;
    }
    // La barre n'est repeinte que si son remplissage a bougé d'au moins un demi-pixel : fluide sur 90 s, presque gratuit sur 30 min.
    final step = (widget.deadline.fraction() * _width * 2 * _dpr).floor();
    if (step != _repaint.value) _repaint.value = step;
    if (_read()) setState(() {});
  }

  void _onTimer() {
    if (!mounted || _over) return;
    final left = widget.deadline.left();
    if (left > Duration.zero) {          // minuterie partie un rien trop tôt : on attend le reste, sans jamais couper avant l'heure
      _end = Timer(left, _onTimer);
      return;
    }
    _expire();
  }

  void _expire() {
    if (_over) return;
    _end?.cancel();
    _end = null;
    setState(() {
      _over = true;
      _read();
    });
    _listen();
    widget.onExpired?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ink = switch (_tone) { 0 => TtColors.ink, 1 => TtColors.warningInk, _ => TtColors.dangerInk };
    final time = Text(
      _text,
      key: const ValueKey('flash-countdown-time'),
      style: TratraTheme.style(widget.compact ? TtType.caption : TtType.title, color: ink)
          .copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
    );
    final bar = RepaintBoundary(
      child: LayoutBuilder(builder: (context, box) {
        _width = box.maxWidth.isFinite ? box.maxWidth : 0;
        return CustomPaint(
          size: Size(_width, widget.compact ? 4 : 6),
          painter: _BarPainter(widget.deadline, over: _over, repaint: _repaint),
        );
      }),
    );
    final label = widget.label;
    final Widget child;
    if (label == null) {
      child = Row(children: [Expanded(child: bar), const SizedBox(width: TtSpace.s2), time]);
    } else {
      child = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (!widget.compact) ...[Icon(Icons.timer_outlined, size: 16, color: ink), const SizedBox(width: 6)],
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
          const SizedBox(width: TtSpace.s2),
          time,
        ]),
        SizedBox(height: widget.compact ? 4 : 6),
        bar,
      ]);
    }
    return Semantics(
      container: true,
      label: label ?? 'Temps restant',
      value: _over ? 'Délai écoulé' : _text,
      child: ExcludeSemantics(child: child),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.deadline, {required this.over, super.repaint});

  final FlashDeadline deadline;
  final bool over;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(track, Paint()..color = TtColors.line);
    final f = over ? 0.0 : deadline.fraction();
    if (f <= 0) return;
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width * f, size.height), radius), Paint()..color = flashCountdownColor(f));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.deadline != deadline || old.over != over;
}
