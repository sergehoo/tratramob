// lib/engagements/labels.dart
//
// Libellés français, formats et états visuels des engagements — affichage uniquement, aucune règle métier. Fonctions pures
// (testées sans réseau). Les dates « AAAA-MM-JJ » sont sans fuseau : jamais de décalage d'un jour.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_tratra/design/design.dart';

typedef Json = Map<String, dynamic>;

extension JsonX on Map<String, dynamic> {
  String s(String k, [String fallback = '']) {
    final v = this[k];
    return v == null ? fallback : '$v';
  }

  String? sn(String k) {
    final v = this[k];
    return (v == null || '$v'.isEmpty) ? null : '$v';
  }

  int i(String k) => this[k] is num ? (this[k] as num).toInt() : int.tryParse('${this[k] ?? ''}') ?? 0;
  bool b(String k) => this[k] == true;
  Json m(String k) => this[k] is Map ? (this[k] as Map).cast<String, dynamic>() : <String, dynamic>{};
  List<Json> l(String k) => this[k] is List ? (this[k] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : <Json>[];
  List<String> strs(String k) => this[k] is List ? (this[k] as List).map((e) => '$e').toList() : <String>[];
}

// ── Argent ──────────────────────────────────────────────────────────────────────────────────────────────────────────

/// « 150000.00 » → « 150 000 FCFA » ; valeur absente → « — » (jamais de montant inventé).
String fcfa(Object? value, [String currency = 'XOF']) {
  if (value == null || '$value'.isEmpty) return '—';
  final n = num.tryParse('$value');
  if (n == null) return '—';
  final neg = n < 0;
  final digits = n.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return '${neg ? '-' : ''}$buf ${currency == 'XOF' ? 'FCFA' : currency}';
}

// ── Dates ───────────────────────────────────────────────────────────────────────────────────────────────────────────

const _months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
const _monthsShort = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const _weekdaysShort = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const weekdays = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

DateTime? parseDay(String? iso) {
  if (iso == null || iso.length < 10) return null;
  final p = iso.substring(0, 10).split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  if (y == null || m == null || d == null || m < 1 || m > 12) return null;
  return DateTime(y, m, d);
}

String isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// « 4 janvier 2027 ».
String dateFr(String? iso) {
  final d = parseDay(iso);
  return d == null ? '—' : '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// « lun. 4 janv. ».
String dateShortFr(String? iso) {
  final d = parseDay(iso);
  return d == null ? '—' : '${_weekdaysShort[d.weekday - 1]} ${d.day} ${_monthsShort[d.month - 1]}';
}

/// « 08:00:00 » → « 08 h 00 ».
String timeFr(String? t) => (t == null || t.length < 5) ? '' : '${t.substring(0, 2)} h ${t.substring(3, 5)}';

/// Horodatage ISO → « 4 janvier 2027 à 10:30 » (heure de l'appareil).
String dateTimeFr(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '—';
  return '${d.day} ${_months[d.month - 1]} ${d.year} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// « 12 mois », « Durée indéterminée ».
String durationLabel(Json c) {
  final end = c.sn('end_date');
  if (c.b('is_indefinite') || end == null) return 'Durée indéterminée';
  final a = parseDay(c.sn('start_date')), b = parseDay(end);
  if (a == null || b == null) return '—';
  final days = b.difference(a).inDays + 1;
  final months = (days / 30.4375).round();
  return months >= 2 ? '$months mois' : '$days jours';
}

/// « lun., mar. · 08 h 00 – 12 h 00 ».
String scheduleLabel(List<Json> schedule) {
  if (schedule.isEmpty) return 'Aucun planning fixe';
  final groups = <String, List<int>>{};
  for (final s in schedule) {
    groups.putIfAbsent('${s['start']}-${s['end']}', () => []).add(s.i('weekday'));
  }
  return groups.entries.map((e) {
    final days = (e.value..sort()).map((d) => weekdays[d].substring(0, 3).toLowerCase()).join(', ');
    final hours = e.key.split('-');
    return '$days · ${timeFr(hours[0])} – ${timeFr(hours[1])}';
  }).join(' ; ');
}

// ── Libellés ────────────────────────────────────────────────────────────────────────────────────────────────────────

const missionTypeFr = {'recurring': 'Prestation récurrente', 'long_term': 'Engagement de longue durée'};
const relationshipFr = {'independent': 'Prestation indépendante', 'employment': 'Emploi salarié'};
const periodFr = {'monthly': 'par mois', 'hourly': 'par heure', 'per_visit': 'par intervention'};
const periodLabel = {'monthly': 'Montant mensuel fixe', 'hourly': 'Taux horaire', 'per_visit': 'Prix par intervention'};
const eventKindFr = {'shift': 'Intervention', 'absence': 'Absence', 'leave': 'Congé', 'rest': 'Repos', 'overtime': 'Heures supplémentaires', 'replacement': 'Remplacement'};
const eventStatusFr = {'planned': 'Prévue', 'requested': 'À valider', 'approved': 'Validée', 'rejected': 'Refusée', 'cancelled': 'Annulée', 'replaced': 'Remplacée'};
const attendanceFr = {'none': 'À venir', 'declared': 'Présence déclarée', 'confirmed': 'Présence confirmée', 'disputed': 'Présence contestée'};
const lineKindFr = {'bonus': 'Prime', 'expense': 'Remboursement de frais', 'deduction': 'Retenue convenue', 'overtime': 'Heures supplémentaires', 'correction': 'Correction'};
const paymentMethodFr = {'cash': 'Espèces', 'bank_transfer': 'Virement', 'mobile_money': 'Mobile Money', 'other': 'Autre'};
const amendmentKindFr = {'change': 'Modification des conditions', 'suspend': 'Suspension', 'end': 'Fin d’un commun accord', 'cancel_notice': 'Annulation du préavis', 'renewal': 'Renouvellement'};
const disputeKindFr = {'payment': 'Paiement', 'conditions': 'Conditions du contrat', 'conduct': 'Comportement', 'planning': 'Planning et présences', 'other': 'Autre'};
const interviewModeFr = {'phone': 'Par téléphone', 'video': 'En visioconférence', 'in_person': 'En personne'};
const roleFr = {'principal': 'Donneur d’ordre', 'worker': 'Prestataire'};

const contractEventFr = {
  'created': 'Brouillon créé', 'proposed': 'Contrat proposé', 'accepted': 'Accepté', 'activated': 'Contrat démarré', 'sent_back': 'Modification demandée', 'cancelled': 'Contrat annulé',
  'amendment_proposed': 'Avenant proposé', 'amendment_accepted': 'Avenant accepté', 'amendment_rejected': 'Avenant refusé', 'amendment_withdrawn': 'Avenant retiré',
  'amendment_applied': 'Avenant en vigueur', 'suspended': 'Contrat suspendu', 'resumed': 'Contrat repris', 'resume_requested': 'Reprise demandée', 'notice_given': 'Préavis donné',
  'non_renewal': 'Non-renouvellement', 'renewed': 'Contrat renouvelé', 'ended': 'Contrat terminé', 'closed': 'Contrat clôturé', 'admin_suspended': 'Suspendu par Tratra',
  'admin_resumed': 'Repris par Tratra', 'admin_terminated': 'Résilié par Tratra', 'payment_declared': 'Paiement déclaré', 'payment_confirmed': 'Paiement confirmé',
  'payment_contested': 'Paiement contesté', 'adjustment_proposed': 'Ajustement proposé', 'adjustment_accepted': 'Ajustement accepté', 'adjustment_rejected': 'Ajustement refusé',
  'installment_waived': 'Solde abandonné', 'schedule_requested': 'Demande de planning', 'schedule_approved': 'Planning validé', 'schedule_rejected': 'Planning refusé',
  'schedule_cancelled': 'Demande annulée', 'attendance_declared': 'Présence déclarée', 'attendance_confirmed': 'Présence confirmée', 'attendance_disputed': 'Présence contestée',
  'replacement_proposed': 'Remplacement proposé', 'replacement_accepted': 'Remplacement accepté', 'replacement_declined': 'Remplacement refusé', 'evaluation_created': 'Évaluation publiée',
  'dispute_opened': 'Litige ouvert', 'dispute_review': 'Litige pris en charge', 'dispute_resolved': 'Litige traité',
};

/// Libellé + ton d'un statut (contrat, échéance, besoin, candidature).
typedef StatusView = (String, TratraTone);

StatusView contractStatus(String s) => switch (s) {
      'draft' => ('Brouillon', TratraTone.gray),
      'pending_acceptance' => ('À accepter', TratraTone.accent),
      'accepted' => ('Accepté · début à venir', TratraTone.info),
      'active' => ('En cours', TratraTone.success),
      'suspended' => ('Suspendu', TratraTone.warning),
      'notice' => ('Préavis en cours', TratraTone.warning),
      'terminated' => ('Résilié', TratraTone.gray),
      'completed' => ('Terminé', TratraTone.primary),
      'cancelled' => ('Annulé', TratraTone.gray),
      _ => (s.isEmpty ? '—' : s, TratraTone.gray),
    };

StatusView installmentStatus(String s) => switch (s) {
      'scheduled' => ('Planifiée', TratraTone.gray),
      'due' => ('À régler', TratraTone.accent),
      'partial' => ('Partiellement réglée', TratraTone.info),
      'paid' => ('Réglée', TratraTone.success),
      'overdue' => ('En retard', TratraTone.danger),
      'on_hold' => ('Suspendue', TratraTone.warning),
      'waived' => ('Solde abandonné', TratraTone.gray),
      'cancelled' => ('Annulée', TratraTone.gray),
      _ => (s.isEmpty ? '—' : s, TratraTone.gray),
    };

StatusView postingStatus(String s) => switch (s) {
      'draft' => ('Brouillon', TratraTone.gray),
      'open' => ('Ouvert aux candidatures', TratraTone.success),
      'closed' => ('Clos', TratraTone.gray),
      'filled' => ('Pourvu', TratraTone.primary),
      'cancelled' => ('Annulé', TratraTone.gray),
      'expired' => ('Expiré', TratraTone.gray),
      _ => (s.isEmpty ? '—' : s, TratraTone.gray),
    };

StatusView applicationStatus(String s) => switch (s) {
      'submitted' => ('Reçue', TratraTone.accent),
      'shortlisted' => ('Présélectionnée', TratraTone.info),
      'interview' => ('Entretien', TratraTone.info),
      'selected' => ('Retenue', TratraTone.success),
      'rejected' => ('Non retenue', TratraTone.gray),
      'withdrawn' => ('Retirée', TratraTone.gray),
      _ => (s.isEmpty ? '—' : s, TratraTone.gray),
    };

/// Page de l'application d'une tâche « à faire » (mêmes cibles que le web).
enum TodoTarget { contract, contractPay, contractPlanning, posting, replacements }

(TodoTarget, int?) todoTarget(Json t) {
  final contract = t['contract_id'] is num ? (t['contract_id'] as num).toInt() : null;
  final posting = t['posting_id'] is num ? (t['posting_id'] as num).toInt() : null;
  return switch (t.s('kind')) {
    'confirm_payment' || 'answer_adjustment' || 'pay_installment' || 'late_installment' => (TodoTarget.contractPay, contract),
    'validate_event' || 'confirm_attendance' => (TodoTarget.contractPlanning, contract),
    'answer_replacement' => (TodoTarget.replacements, null),
    'review_applications' || 'answer_interview' => posting != null ? (TodoTarget.posting, posting) : (TodoTarget.contract, null),
    _ => (TodoTarget.contract, contract),
  };
}

// ── Intentions idempotentes ─────────────────────────────────────────────────────────────────────────────────────────

final _rng = Random.secure();

String randomHex([int bytes = 6]) => List.generate(bytes, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// Empreinte stable (FNV-1a 32 bits) : identique d'un appel à l'autre pour un même contenu.
String fingerprint(String input) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(input)) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// Clé d'idempotence liée au CONTENU : un renvoi identique rejoue l'action ; modifier un champ crée une nouvelle intention.
/// Format accepté par le serveur : [A-Za-z0-9_\-:.]{8,80}.
String intentKey(String scope, String base, Object payload) {
  final key = '$scope-$base-${fingerprint('$payload')}';
  return key.length > 80 ? key.substring(0, 80) : key;
}
