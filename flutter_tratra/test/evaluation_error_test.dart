import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/screens/dashboard/mutual_evaluations.dart';

void main() {
  test('le message d’une évaluation refusée est celui du serveur (champ, puis détail), jamais le JSON brut', () {
    final field = ApiException(400, 'x', body: json.encode({'code': 'invalid', 'detail': 'Évaluation invalide.', 'fields': {'comment': 'Pas de lien dans un commentaire.'}}));
    expect(evaluationErrorMessage(field, 'défaut'), 'Pas de lien dans un commentaire.');
    final detail = ApiException(409, 'x', body: json.encode({'code': 'not_completed', 'detail': 'Une mission se note après avoir réellement été effectuée.'}));
    expect(evaluationErrorMessage(detail, 'défaut'), 'Une mission se note après avoir réellement été effectuée.');
    expect(evaluationErrorMessage(Exception('boom'), 'défaut'), 'défaut');
  });
}
