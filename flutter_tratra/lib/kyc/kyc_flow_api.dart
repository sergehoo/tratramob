// lib/kyc/kyc_flow_api.dart
//
// Parcours « Vérifier mon identité » : client de l'API Django /me/kyc/ (handy/kyc_flow.py). La progression est enregistrée par le
// serveur — l'application la recharge à chaque ouverture et ne décide rien (ni qualité finale, ni validation).
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/upload_file.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

String? _s(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
Map<String, dynamic> _m(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> _l(dynamic v) => v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];

class KycStep {
  KycStep(Map<String, dynamic> j)
      : key = '${j['key'] ?? ''}',
        label = '${j['label'] ?? ''}',
        state = '${j['state'] ?? 'todo'}';
  final String key;
  final String label;

  /// done | current | todo | waiting | error | skipped
  final String state;
}

class KycProblem {
  KycProblem(Map<String, dynamic> j)
      : code = '${j['code'] ?? ''}',
        label = '${j['label'] ?? ''}',
        blocking = j['blocking'] == true;
  final String code;
  final String label;
  final bool blocking;
}

class KycCapture {
  KycCapture(Map<String, dynamic> j)
      : side = '${j['side'] ?? 'front'}',
        label = '${j['label'] ?? ''}',
        present = j['present'] == true,
        quality = _s(j['quality']),
        problems = _l(j['problems']).map(KycProblem.new).toList(),
        readingStatus = _s(_m(j['reading'])['status']),
        readingNotes = [for (final n in (_m(j['reading'])['notes'] as List? ?? const [])) '$n'];
  final String side;
  final String label;
  final bool present;

  /// ok | warn | fail (null tant que la photo n'a pas été prise).
  final String? quality;
  final List<KycProblem> problems;
  final String? readingStatus;
  final List<String> readingNotes;
}

class KycKind {
  KycKind(Map<String, dynamic> j)
      : value = '${j['value'] ?? ''}',
        label = '${j['label'] ?? ''}',
        sides = (j['sides'] as num?)?.toInt() ?? 1;
  final String value;
  final String label;
  final int sides;
}

class KycFlowState {
  KycFlowState(Map<String, dynamic> j)
      : status = '${j['status'] ?? 'draft'}',
        statusLabel = '${j['status_label'] ?? ''}',
        currentStep = '${j['current_step'] ?? 'personal'}',
        steps = _l(j['steps']).map(KycStep.new).toList(),
        firstName = '${_m(j['personal'])['first_name'] ?? ''}',
        lastName = '${_m(j['personal'])['last_name'] ?? ''}',
        birthDate = DateTime.tryParse('${_m(j['personal'])['birth_date'] ?? ''}'),
        personalComplete = _m(j['personal'])['complete'] == true,
        documentKind = _s(_m(j['document'])['kind']),
        kinds = _l(_m(j['document'])['kinds']).map(KycKind.new).toList(),
        captures = _l(_m(j['document'])['captures']).map(KycCapture.new).toList(),
        readyToSend = _m(j['document'])['ready_to_send'] == true,
        faceEnabled = _m(j['face'])['enabled'] == true,
        faceSatisfied = _m(j['face'])['satisfied'] == true,
        faceHumanReview = _m(j['face'])['human_review_requested'] == true,
        faceNote = '${_m(j['face'])['note'] ?? ''}',
        reviewState = '${_m(j['review'])['state'] ?? 'none'}',
        reviewReason = _s(_m(j['review'])['reason']),
        previousReason = _s(_m(j['review'])['previous_reason']),
        sentAt = DateTime.tryParse('${_m(j['review'])['sent_at'] ?? ''}'),
        attempts = (_m(j['review'])['attempts'] as num?)?.toInt() ?? 0,
        activation = j['activation'] is Map ? DashEligibility(_m(j['activation'])) : null,
        editable = j['editable'] != false,
        suggestions = {for (final e in _m(j['suggestions']).entries) if (e.value != null) e.key: '${e.value}'};

  /// draft | in_review | changes_requested | verified
  final String status;
  final String statusLabel;
  final String currentStep;
  final List<KycStep> steps;
  final String firstName;
  final String lastName;
  final DateTime? birthDate;
  final bool personalComplete;
  final String? documentKind;
  final List<KycKind> kinds;
  final List<KycCapture> captures;
  final bool readyToSend;
  final bool faceEnabled;
  final bool faceSatisfied;
  final bool faceHumanReview;
  final String faceNote;

  /// none | pending | rejected | approved
  final String reviewState;
  final String? reviewReason;
  final String? previousReason;
  final DateTime? sentAt;
  final int attempts;
  final DashEligibility? activation;
  final bool editable;

  /// Lu sur la pièce par la lecture automatique (réponse à une photo du recto) : PROPOSÉ à l'utilisateur, jamais enregistré tel quel.
  final Map<String, String> suggestions;

  KycStep? step(String key) {
    for (final s in steps) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// Rang (1 à 7) de l'étape à afficher, pour « Étape n sur 7 ».
  int indexOf(String key) => steps.indexWhere((s) => s.key == key) + 1;
}

class KycFlowApi {
  KycFlowApi(this._base) : _dash = DashboardApi(_base);
  final BaseApi _base;
  final DashboardApi _dash;

  Future<KycFlowState> load() async => KycFlowState(await _dash.getMap('/me/kyc/'));

  Future<KycFlowState> savePersonal({required String firstName, required String lastName, required DateTime birthDate}) async {
    final d = '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}';
    return KycFlowState(await _dash.patch('/me/kyc/', {
      'personal': {'first_name': firstName, 'last_name': lastName, 'birth_date': d},
    }));
  }

  Future<KycFlowState> chooseKind(String kind) async => KycFlowState(await _dash.patch('/me/kyc/', {'document_kind': kind}));

  Future<KycFlowState> setFaceChoice(String choice) async => KycFlowState(await _dash.patch('/me/kyc/', {'face_choice': choice}));

  /// Photo d'une face : renvoie l'état et le contrôle qualité / lecture de CETTE photo.
  Future<KycFlowState> capture(String side, String filePath, {void Function(double)? onProgress}) async {
    final r = await _base.uploadMultipart('/me/kyc/capture/',
        fields: {'side': side}, files: [() => multipartFromPath('file', filePath)], onProgress: onProgress, timeout: const Duration(minutes: 2));
    if (r.statusCode < 200 || r.statusCode >= 300) _base.handleError(r);
    final d = _base.decodeBody(r);
    return KycFlowState(d is Map ? d.cast<String, dynamic>() : <String, dynamic>{});
  }

  Future<KycFlowState> send() async => KycFlowState(await _dash.post('/me/kyc/send/'));

  Future<KycFlowState> restart() async => KycFlowState(await _dash.post('/me/kyc/restart/'));
}
