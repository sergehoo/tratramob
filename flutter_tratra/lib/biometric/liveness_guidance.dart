// lib/biometric/liveness_guidance.dart
//
// Guidage de la capture : traduit les mesures du détecteur de visage (ML Kit) en consigne pour l'étape demandée. C'est un GUIDAGE (cadrage,
// rotation, sourire), pas une preuve de présence réelle : des mouvements ne prouvent rien à eux seuls. La décision de liveness vient du serveur,
// à partir du fournisseur spécialisé, et la qualité de l'image (éclairage, netteté) est contrôlée côté serveur.
class FaceMetrics {
  const FaceMetrics({required this.faces, this.yaw = 0, this.pitch = 0, this.smile, this.leftEyeOpen, this.rightEyeOpen, this.widthRatio = 0, this.centerX = 0.5});

  /// Nombre de visages détectés.
  final int faces;

  /// Rotation horizontale (degrés, convention ML Kit) et inclinaison verticale (positif = tête vers le haut).
  final double yaw;
  final double pitch;
  final double? smile;
  final double? leftEyeOpen;
  final double? rightEyeOpen;

  /// Largeur du visage / petit côté de l'image (0-1) et position horizontale du centre du visage (0-1).
  final double widthRatio;
  final double centerX;
}

class Guidance {
  const Guidance(this.ok, this.hint);
  final bool ok;
  final String hint;
}

/// Signe de `yaw` quand la personne tourne la tête vers SA gauche (calibré sur la caméra avant : valeur confirmée sur appareil).
const double kLeftYawSign = 1;

const double minFaceWidth = 0.30;
const double maxFaceWidth = 0.85;
const double centerTolerance = 0.22;
const double turnDegrees = 18;
const double tiltDegrees = 12;
const double straightDegrees = 12;
const double smileProbability = 0.70;

/// Consigne pour l'étape `kind` (front | left | right | up | down | smile) ; `ok` = l'étape peut être capturée.
Guidance evaluate(String kind, FaceMetrics? m) {
  if (m == null || m.faces == 0) return const Guidance(false, 'Placez votre visage dans l’ovale');
  if (m.faces > 1) return const Guidance(false, 'Une seule personne dans le cadre');
  if (m.widthRatio < minFaceWidth) return const Guidance(false, 'Rapprochez-vous');
  if (m.widthRatio > maxFaceWidth) return const Guidance(false, 'Éloignez-vous un peu');
  if ((m.centerX - 0.5).abs() > centerTolerance) return const Guidance(false, 'Centrez votre visage');
  switch (kind) {
    case 'front':
      if (m.yaw.abs() > straightDegrees || m.pitch.abs() > straightDegrees) return const Guidance(false, 'Regardez droit devant vous');
      final eyes = [m.leftEyeOpen, m.rightEyeOpen].whereType<double>();
      if (eyes.isNotEmpty && eyes.any((e) => e < 0.4)) return const Guidance(false, 'Gardez les yeux ouverts');
      return const Guidance(true, 'Parfait, ne bougez plus');
    case 'left':
      return (m.yaw * kLeftYawSign >= turnDegrees) ? const Guidance(true, 'Parfait, ne bougez plus') : const Guidance(false, 'Tournez lentement la tête vers la gauche');
    case 'right':
      return (m.yaw * kLeftYawSign <= -turnDegrees) ? const Guidance(true, 'Parfait, ne bougez plus') : const Guidance(false, 'Tournez lentement la tête vers la droite');
    case 'up':
      return m.pitch >= tiltDegrees ? const Guidance(true, 'Parfait, ne bougez plus') : const Guidance(false, 'Inclinez la tête vers le haut');
    case 'down':
      return m.pitch <= -tiltDegrees ? const Guidance(true, 'Parfait, ne bougez plus') : const Guidance(false, 'Inclinez la tête vers le bas');
    case 'smile':
      if (m.yaw.abs() > 20) return const Guidance(false, 'Regardez l’écran et souriez');
      return (m.smile ?? 0) >= smileProbability ? const Guidance(true, 'Parfait, ne bougez plus') : const Guidance(false, 'Souriez');
  }
  return const Guidance(false, 'Suivez la consigne');
}

/// Nombre de mesures consécutives conformes avant de garder la capture (évite de figer une image prise en plein mouvement).
const int stableSamples = 2;
