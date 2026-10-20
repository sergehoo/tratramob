// lib/core/phone/phone_value.dart
//
// Téléphone : [drapeau ▼] + numéro NATIONAL. L'utilisateur ne saisit jamais l'indicatif ; le numéro est normalisé en E.164 avec
// libphonenumber (phone_numbers_parser), comme le site (libphonenumber-js) et Django (`handy/phone.py`, qui revalide toujours).
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:phone_numbers_parser/metadata.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tratra/core/phone/country_names_fr.dart';

/// Pays de repli (Côte d'Ivoire).
const IsoCode defaultPhoneCountry = IsoCode.CI;

class PhoneCountry {
  const PhoneCountry(this.iso, this.name, this.dial);
  final IsoCode iso;
  final String name;
  final String dial;
  String get code => iso.name;
  String get flag => flagOf(iso.name);
}

/// Drapeau emoji d'un code pays (indicateurs régionaux Unicode).
String flagOf(String code) => String.fromCharCodes(code.toUpperCase().codeUnits.map((c) => 127397 + c));

String countryNameFr(IsoCode iso) => countryNamesFr[iso.name] ?? iso.name;

String dialOf(IsoCode iso) => metadataByIsoCode[iso]?.countryCode ?? '';

IsoCode? isoFrom(String? code) {
  final c = (code ?? '').trim().toUpperCase();
  for (final iso in IsoCode.values) {
    if (iso.name == c) return iso;
  }
  return null;
}

String _fold(String s) {
  const from = 'àâäáãçéèêëîïíìôöóòõùûüúÿñ';
  const to = 'aaaaaceeeeiiiiooooouuuuyn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().replaceAll('œ', 'oe').replaceAll(RegExp(r'[^a-z0-9+ ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<PhoneCountry>? _all;

/// Tous les pays (noms français, ordre alphabétique) avec indicatif.
List<PhoneCountry> allPhoneCountries() => _all ??= ([
      for (final iso in IsoCode.values)
        if (dialOf(iso).isNotEmpty) PhoneCountry(iso, countryNameFr(iso), dialOf(iso)),
    ]..sort((a, b) => _fold(a.name).compareTo(_fold(b.name))));

/// Recherche par nom (sans accents), code ISO ou indicatif (« cote », « CI », « +225 », « 225 »).
List<PhoneCountry> searchPhoneCountries(String query) {
  final q = _fold(query);
  final all = allPhoneCountries();
  if (q.isEmpty) return all;
  final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
  final starts = <PhoneCountry>[], contains = <PhoneCountry>[];
  for (final c in all) {
    final name = _fold(c.name);
    if (digits.isNotEmpty && c.dial.startsWith(digits)) {
      starts.add(c);
    } else if (name.startsWith(q) || c.code.toLowerCase() == q || name.contains(' $q')) {
      starts.add(c);
    } else if (name.contains(q)) {
      contains.add(c);
    }
  }
  return [...starts, ...contains];
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// Mise en forme du numéro national pendant la saisie (« 0700000000 » → « 07 00 00 00 00 », « 0612345678 » → « 06 12 34 56 78 »).
String formatNational(String national, IsoCode iso) {
  final d = _digits(national);
  if (d.isEmpty) return '';
  if (iso == IsoCode.CI) {
    final ci = d.length > 10 ? d.substring(0, 10) : d;
    return ci.replaceAllMapped(RegExp(r'(\d{2})(?=\d)'), (m) => '${m[1]} ');      // écriture usuelle : 07 00 00 00 00
  }
  try {
    final formatted = PhoneNumber.parse(d, destinationCountry: iso).formatNsn();
    final prefix = metadataByIsoCode[iso]?.nationalPrefix;
    // Le 0 national tapé par l'utilisateur est conservé à l'affichage (« 06… » et non « 6… »).
    if (prefix != null && prefix.isNotEmpty && d.startsWith(prefix) && !_digits(formatted).startsWith(prefix)) return '$prefix$formatted';
    return formatted;
  } catch (_) {
    return d;
  }
}

/// Exemple de numéro national (indication du champ).
String exampleNational(IsoCode iso) {
  if (iso == IsoCode.CI) return '07 00 00 00 00';
  final ex = metadataExamplesByIsoCode[iso]?.mobile;
  return ex == null || ex.isEmpty ? '' : formatNational('${metadataByIsoCode[iso]?.nationalPrefix ?? ''}$ex', iso);
}

class PhoneValue {
  const PhoneValue(this.iso, this.national);
  final IsoCode iso;

  /// Numéro national tel que saisi (espaces de mise en forme compris).
  final String national;

  static const empty = PhoneValue(defaultPhoneCountry, '');

  bool get isEmpty => _digits(national).isEmpty;

  PhoneValue copyWith({IsoCode? iso, String? national}) => PhoneValue(iso ?? this.iso, national ?? this.national);

  PhoneNumber? get _parsed {
    try {
      return PhoneNumber.parse(national, destinationCountry: iso);
    } catch (_) {
      return null;
    }
  }

  /// E.164 d'un numéro VALIDE (« +2250700000000 »), sinon null.
  String? get e164 {
    final p = _parsed;
    return p != null && p.isValid() ? p.international : null;
  }

  /// Numéro à RECHERCHER (connexion, récupération) : E.164 valide, sinon « +indicatif + chiffres » pour qu'un compte enregistré
  /// avant libphonenumber soit quand même retrouvé par le serveur. null si presque rien n'a été saisi.
  String? get lookupE164 {
    final valid = e164;
    if (valid != null) return valid;
    final d = _digits(national);
    return d.length >= 6 ? '+${dialOf(iso)}$d' : null;
  }

  /// Message d'erreur clair (null si le numéro est valide).
  String? error({String empty = 'Saisissez votre numéro de téléphone.'}) {
    final d = _digits(national);
    if (d.isEmpty) return empty;
    if (e164 != null) return null;
    final ex = exampleNational(iso);
    final tip = ex.isEmpty ? '' : ' Exemple : $ex.';
    final p = _parsed;
    final country = countryNameFr(iso);
    if (p != null && !p.isValidLength()) {
      final lengths = metadataLenghtsByIsoCode[iso];
      final longest = [...?lengths?.mobile, ...?lengths?.fixedLine].fold<int>(0, (m, v) => v > m ? v : m);
      final nsnLength = _digits(p.nsn).length;
      if (longest > 0 && nsnLength > longest) return 'Numéro trop long pour $country.$tip';
      return 'Numéro trop court pour $country.$tip';
    }
    return 'Ce numéro n’est pas valide pour $country. Vérifiez le pays et les chiffres.$tip';
  }

  /// Valeur de départ d'un champ à partir d'un numéro enregistré (E.164).
  static PhoneValue fromE164(String? e164, {IsoCode fallback = defaultPhoneCountry}) => splitInternational(e164 ?? '') ?? PhoneValue(fallback, '');

  /// Numéro collé ou tapé avec son indicatif (« +33 6 12… », « 00225 07… ») : pays et numéro national, sinon null.
  static PhoneValue? splitInternational(String raw) {
    var v = raw.trim();
    if (v.startsWith('00')) v = '+${v.substring(2)}';
    if (!v.startsWith('+')) return null;
    try {
      final p = PhoneNumber.parse(v);
      if (_digits(p.nsn).length < 2) return null;
      final prefix = metadataByIsoCode[p.isoCode]?.nationalPrefix ?? '';
      final national = p.isoCode == IsoCode.CI ? p.nsn : '$prefix${p.nsn}';
      return PhoneValue(p.isoCode, formatNational(national, p.isoCode));
    } catch (_) {
      return null;
    }
  }
}

/// « +225 07 00 00 00 00 » pour l'affichage (le numéro brut sinon).
String displayPhone(String? e164) {
  if (e164 == null || e164.isEmpty) return '';
  try {
    final p = PhoneNumber.parse(e164);
    final nsn = p.isoCode == IsoCode.CI ? formatNational(p.nsn, IsoCode.CI) : p.formatNsn();
    return '+${p.countryCode} $nsn';
  } catch (_) {
    return e164;
  }
}

// ------------------------------------------------------------------ pays présélectionné

const _prefsKey = 'tratra.phone.country';
const _device = MethodChannel('tratra/device');

/// Pays présélectionné, dans cet ordre : préférence enregistrée → carte SIM (Android) → région de l'appareil → pays de l'adresse IP
/// SEULEMENT si le serveur le connaît déjà (`ipRegion`) → Côte d'Ivoire.
Future<IsoCode> resolveDefaultPhoneCountry({Future<String?> Function()? ipRegion, String? deviceRegion}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = isoFrom(prefs.getString(_prefsKey));
    if (saved != null) return saved;
  } catch (_) {}
  try {
    final sim = isoFrom(await _device.invokeMethod<String>('simCountry'));
    if (sim != null) return sim;
  } catch (_) {
    // iOS, web, tests : pas de canal — on passe à la suite
  }
  final region = isoFrom(deviceRegion ?? PlatformDispatcher.instance.locale.countryCode);
  if (region != null) return region;
  if (ipRegion != null) {
    try {
      final ip = isoFrom(await ipRegion());
      if (ip != null) return ip;
    } catch (_) {}
  }
  return defaultPhoneCountry;
}

Future<void> rememberPhoneCountry(IsoCode iso) async {
  try {
    (await SharedPreferences.getInstance()).setString(_prefsKey, iso.name);
  } catch (_) {}
}
