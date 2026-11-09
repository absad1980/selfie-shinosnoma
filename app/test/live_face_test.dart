import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:selfie_shinosnoma/live_face.dart';

/// The live guide on a simulated camera frame: a sideways grey "sensor" image of a sample photo.
void main() {
  final model = File('assets/models/face_detect.nnm').readAsBytesSync();
  final src = img.decodeJpg(File('assets/samples/man.jpg').readAsBytesSync())!;
  // the sensor delivers the picture turned 90° anticlockwise (so it needs 90° clockwise to stand up)
  final sensor = img.copyRotate(src, angle: -90);
  final y = Uint8List(sensor.width * sensor.height);
  for (final p in sensor) {
    y[p.y * sensor.width + p.x] = (.299 * p.r + .587 * p.g + .114 * p.b).round();
  }

  test('the upright turn is found', () {
    const turns = [0, 90, 180, 270];
    final i = bestTurn(([for (final t in turns) smallGreyFromPlane(y, sensor.width, 1, sensor.width, sensor.height, t, false)], model));
    expect(i == null ? null : turns[i], 90);
    // and with no face there is no answer
    final blank = Uint8List(sensor.width * sensor.height)..fillRange(0, sensor.width * sensor.height, 200);
    expect(bestTurn(([for (final t in turns) smallGreyFromPlane(blank, sensor.width, 1, sensor.width, sensor.height, t, false)], model)), isNull);
  });

  test('fit judgement', () {
    final f = smallGreyFromPlane(y, sensor.width, 1, sensor.width, sensor.height, 90, false);
    final faces = detectLive((f, model));
    final aspect = f.w / f.h;
    expect(faces, hasLength(1));
    expect(judge(faces, const Size(380, 640), aspect, true), isNot(FaceFit.none));
    expect(judge(const [], const Size(400, 800), aspect, true), FaceFit.none);
    expect(judge(const [LiveFace(.5, .43, .4)], const Size(400, 800), 400 / 800, true), FaceFit.good);
    expect(judge(const [LiveFace(.5, .43, .15)], const Size(400, 800), 400 / 800, true), FaceFit.closer);
    expect(judge(const [LiveFace(.5, .43, .65)], const Size(400, 800), 400 / 800, true), FaceFit.farther);
    expect(judge(const [LiveFace(.5, .75, .4)], const Size(400, 800), 400 / 800, true), FaceFit.center);
    expect(judge(const [LiveFace(.5, .43, .4), LiveFace(.8, .4, .35)], const Size(400, 800), 400 / 800, true), FaceFit.many);
  });
}
