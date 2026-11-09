import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:selfie_shinosnoma/processing.dart';

/// The phone's real path, on a computer: our models analyse the photo, then the pixel step and suit fitting run.
void main() {
  final models = [for (final n in ['face_detect', 'face_mesh', 'person_mask']) File('assets/models/$n.nnm').readAsBytesSync()];
  final anchors = jsonDecode(File('assets/suits/anchors.json').readAsStringSync()) as Map<String, dynamic>;
  SuitLayer suit(String n) => SuitLayer.fromJson(File('assets/suits/$n.png').readAsBytesSync(), anchors[n] as Map<String, dynamic>);
  Uint8List rgbaOf(img.Image im) => im.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);

  test('analyse + process + suit on base photos', () {
    Directory('build/test_out').createSync(recursive: true);
    for (final (person, s) in [('man', 'm01'), ('man', 'm06'), ('woman', 'w09'), ('woman', 'w02')]) {
      final src = img.decodeJpg(File('assets/samples/$person.jpg').readAsBytesSync())!;
      // upscale like a phone photo so the 640 px analysis copy path is used too
      final big = img.copyResize(src, width: 1050, interpolation: img.Interpolation.cubic);
      final rgba = rgbaOf(big);
      final sw = Stopwatch()..start();
      final a = analyzeFace(rgba, big.width, big.height, models)!;
      final t = sw.elapsedMilliseconds;
      expect(a.problems, isEmpty, reason: '$person: ${a.problems}');
      final out = processPixelsForTest(rgba, big.width, big.height, a.face, suit: suit(s), mask: a.mask, mw: a.mw, mh: a.mh, outline: a.outline, cutY: a.cutY);
      File('build/test_out/pipe_${person}_$s.jpg').writeAsBytesSync(out);
      // ignore: avoid_print
      print('$person/$s face=${a.face.map((v) => v.round()).toList()} analysis=${t}ms total=${sw.elapsedMilliseconds}ms');
    }
  });

  test('tilted head is flagged, no face is rejected', () {
    final src = img.decodeJpg(File('assets/samples/man.jpg').readAsBytesSync())!;
    final tilted = img.copyRotate(src, angle: 14);
    final a = analyzeFace(rgbaOf(tilted), tilted.width, tilted.height, models)!;
    expect(a.problems, contains('ck_straight'));
    final blank = img.Image(width: 400, height: 500)..clear(img.ColorRgb8(230, 232, 236));
    expect(analyzeFace(rgbaOf(blank), 400, 500, models), isNull);
  });
}
