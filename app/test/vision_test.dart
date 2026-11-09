import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:selfie_shinosnoma/nn/runner.dart';
import 'package:selfie_shinosnoma/nn/vision.dart';

/// Runs our own face detector, face mesh and person mask on sample photos and draws what they found.
void main() {
  NnModel load(String n) => NnModel.load(File('assets/models/$n.nnm').readAsBytesSync());

  test('face, landmarks and mask on samples', () {
    final det = FaceDetector(load('face_detect')), mesh = FaceMesh(load('face_mesh')), seg = PersonMask(load('person_mask'));
    Directory('build/test_out').createSync(recursive: true);
    for (final name in ['man', 'woman', 'm03', 'w05']) {
      final src = img.decodeJpg(File('assets/samples/$name.jpg').readAsBytesSync())!;
      final rgba = src.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
      final sw = Stopwatch()..start();
      final faces = det.detect(rgba, src.width, src.height);
      final tDet = sw.elapsedMilliseconds;
      expect(faces, isNotEmpty, reason: name);
      final f = faces.first;
      final lm = mesh.landmarks(rgba, src.width, src.height, f);
      final tMesh = sw.elapsedMilliseconds - tDet;
      final m = seg.run(rgba, src.width, src.height);
      final tSeg = sw.elapsedMilliseconds - tDet - tMesh;
      final p = lm!.points;
      // ignore: avoid_print
      print('$name faces=${faces.length} score=${f.score.toStringAsFixed(2)} box=[${f.left.round()},${f.top.round()},${f.right.round()},${f.bottom.round()}] '
          'mesh=${lm.presence.toStringAsFixed(2)} cheeks=${p[234].x.round()}..${p[454].x.round()} top10=${p[10].y.round()} chin152=${p[152].y.round()} '
          'mask[min,max]=${m.mask.reduce((a, b) => a < b ? a : b).toStringAsFixed(2)},${m.mask.reduce((a, b) => a > b ? a : b).toStringAsFixed(2)} '
          'ms det=$tDet mesh=$tMesh seg=$tSeg');
      // draw: mask tint, box, keypoints, landmarks
      final out = img.Image.from(src);
      for (final px in out) {
        final mv = m.mask[(px.y * m.h ~/ src.height) * m.w + (px.x * m.w ~/ src.width)];
        px.r = (px.r * (.4 + .6 * mv) + 255 * (1 - mv) * .6).round();
        px.b = (px.b * (.4 + .6 * mv)).round();
      }
      img.drawRect(out, x1: f.left.round(), y1: f.top.round(), x2: f.right.round(), y2: f.bottom.round(), color: img.ColorRgb8(0, 200, 0));
      for (final k in f.keypoints) {
        img.fillCircle(out, x: k.x.round(), y: k.y.round(), radius: 3, color: img.ColorRgb8(255, 0, 0));
      }
      for (final q in p) {
        out.setPixelRgb(q.x.round().clamp(0, src.width - 1), q.y.round().clamp(0, src.height - 1), 0, 255, 255);
      }
      File('build/test_out/vision_$name.png').writeAsBytesSync(img.encodePng(out));
    }
  });
}
