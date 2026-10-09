// Formatage d'affichage partagé par la réservation, le paiement et le suivi.
// Fonctions pures : aucune règle métier ici.

const List<String> _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const List<String> _months = [
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

const List<String> _weekdaysShort = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];

const List<String> _monthsShort = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

/// Montant en FCFA, arrondi à l'unité, milliers séparés par une espace insécable
/// (ex. « 15 000 FCFA »).
String formatFcfa(num amount) {
  final raw = amount.toStringAsFixed(0);
  final negative = raw.startsWith('-');
  final digits = negative ? raw.substring(1) : raw;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}$buffer FCFA';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// « 08/10/2026 ».
String formatDateNumeric(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// « 09:00 ».
String formatTime(int hour, int minute) => '${_two(hour)}:${_two(minute)}';

/// « jeudi 8 octobre 2026 » (« 1er » pour le premier du mois).
/// Les champs de la date sont utilisés tels quels (pas de conversion de fuseau) :
/// l'heure choisie à la réservation est celle d'Abidjan, stockée en UTC.
String formatDateLong(DateTime d, {bool capitalize = false}) {
  final day = d.day == 1 ? '1er' : '${d.day}';
  final text = '${_weekdays[d.weekday - 1]} $day ${_months[d.month - 1]} ${d.year}';
  if (!capitalize) return text;
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

/// « Jeudi 8 octobre 2026 · 09:00 ».
String formatDateTimeLong(DateTime d) =>
    '${formatDateLong(d, capitalize: true)} · ${formatTime(d.hour, d.minute)}';

/// « jeu. 8 oct. 2026 · 09:00 » : version compacte pour les lignes de liste.
String formatDateTimeShort(DateTime d) {
  final day = d.day == 1 ? '1er' : '${d.day}';
  return '${_weekdaysShort[d.weekday - 1]} $day ${_monthsShort[d.month - 1]} ${d.year} · ${formatTime(d.hour, d.minute)}';
}

/// Message d'erreur lisible : retire les préfixes techniques de Dart.
String cleanError(Object error) {
  return error
      .toString()
      .replaceAll('Exception: ', '')
      .replaceAll('Invalid argument(s): ', '')
      .trim();
}
