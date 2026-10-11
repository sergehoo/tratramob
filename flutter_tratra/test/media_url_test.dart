import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/screens/home/home_models.dart';

void main() {
  test("l'API et les médias pointent par défaut vers les sous-domaines de production", () {
    expect(AppConstants.baseUrl, 'https://api.tratra.net/handy');
    expect(AppConstants.mediaBase, 'https://minioapi.tratra.net');
  });

  test('un chemin relatif ou une adresse interne de MinIO est réécrit vers l\'hôte public des médias', () {
    expect(homeFixMediaUrl('/media/a.jpg'), 'https://minioapi.tratra.net/media/a.jpg');
    expect(homeFixMediaUrl('http://minio:9000/tratra/a.jpg'), 'https://minioapi.tratra.net/tratra/a.jpg');
  });

  test('les anciennes URL de médias du site ou de l\'API sont réécrites, une URL signée de MinIO reste intacte', () {
    expect(homeFixMediaUrl('https://tratra.net/media/a.jpg'), 'https://minioapi.tratra.net/media/a.jpg');
    expect(homeFixMediaUrl('http://api.tratra.net/media/a.jpg'), 'https://minioapi.tratra.net/media/a.jpg');
    const signed = 'https://minioapi.tratra.net/tratra/a.jpg?X-Amz-Signature=abc';
    expect(homeFixMediaUrl(signed), signed);
  });

  test('le HTTP clair est forcé en HTTPS ; vide reste vide', () {
    expect(homeFixMediaUrl('http://cdn.example.org/a.jpg'), 'https://cdn.example.org/a.jpg');
    expect(homeFixMediaUrl(null), '');
    expect(homeFixMediaUrl(''), '');
  });
}
