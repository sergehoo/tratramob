import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tratra/core/upload_file.dart';

void main() {
  test('le type vient du contenu : JPEG, PNG, PDF, WebP ; inconnu = null', () {
    expect(sniffUpload([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10])!.mime, 'image/jpeg');
    expect(sniffUpload([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0])!.ext, '.png');
    expect(sniffUpload('%PDF-1.4'.codeUnits)!.mime, 'application/pdf');
    expect(sniffUpload([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])!.mime, 'image/webp');
    expect(sniffUpload('MZ not a document'.codeUnits), isNull);
    expect(sniffUpload(const []), isNull);
  });

  test('un JPEG nommé .webp ou sans extension part avec le nom et le type du contenu réel', () async {
    final dir = await Directory.systemTemp.createTemp('upload_test');
    addTearDown(() => dir.delete(recursive: true));
    final jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1];
    for (final name in ['scaled_1234', 'photo.webp', 'IMG.HEIC']) {
      final f = File('${dir.path}/$name')..writeAsBytesSync(jpeg);
      final part = await multipartFromPath('file', f.path);
      expect(part.filename, 'document.jpg', reason: name);
      expect(part.contentType.mimeType, 'image/jpeg', reason: name);
    }
    final unknown = File('${dir.path}/notes.txt')..writeAsStringSync('hello');
    final part = await multipartFromPath('file', unknown.path);
    expect(part.filename, 'notes.txt');                                 // contenu inconnu : comportement historique (le serveur tranche)
  });
}
