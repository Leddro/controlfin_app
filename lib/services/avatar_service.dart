import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// Foto de perfil em users/{uid}/settings/avatar, como JPEG pequeno.
///
/// Fica no Firestore (e não no Firebase Storage) porque o Storage exige o
/// plano pago em projetos novos. Uma foto de 256x256 tem uns 15 a 30 KB,
/// bem abaixo do limite de 1 MB por documento.
class AvatarService {
  static const size = 256;

  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore.instance
      .collection('users')
      .doc(FirebaseAuth.instance.currentUser!.uid)
      .collection('settings')
      .doc('avatar');

  /// Emite nulo quando o usuário não escolheu uma foto.
  Stream<Uint8List?> watch() => _doc.snapshots().map((s) {
        final raw = s.data()?['image'];
        return raw is Blob ? raw.bytes : null;
      });

  /// Prepara a imagem escolhida e salva.
  Future<void> save(Uint8List original) async {
    final jpg = await prepareAvatar(original);
    await _doc.set({
      'image': Blob(jpg),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> remove() => _doc.delete();
}

/// Recorta o centro em quadrado, reduz para [size]x[size] e gera um JPEG.
/// Lança uma exceção se os bytes não forem uma imagem que o aparelho lê.
Future<Uint8List> prepareAvatar(Uint8List bytes,
    {int size = AvatarService.size}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final source = frame.image;
  codec.dispose();

  final side = math.min(source.width, source.height).toDouble();
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    source,
    ui.Rect.fromLTWH(
        (source.width - side) / 2, (source.height - side) / 2, side, side),
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..filterQuality = FilterQuality.high,
  );
  final square = await recorder.endRecording().toImage(size, size);
  source.dispose();

  final rgba = await square.toByteData(format: ui.ImageByteFormat.rawRgba);
  square.dispose();

  final image = img.Image.fromBytes(
    width: size,
    height: size,
    bytes: rgba!.buffer,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: 82);
}
