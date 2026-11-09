import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:selfie_shinosnoma/processing.dart';

/// Takes a clean sample, spoils it like a bad selfie (dark, warm cast, side shadow),
/// runs the pixel engine and checks the result is brighter, more neutral, evener and framed to 35:45.
void main() {
  test('rework fixes light, cast and shadow, and frames to 35:45', () {
    final src = img.decodeJpg(File('assets/samples/m03.jpg').readAsBytesSync())!;
    final bad = img.Image.from(src);
    for (final p in bad) {
      final t = p.x / bad.width; // shadow on the left
      final shade = .55 + .45 * t;
      p
        ..r = (p.r * .62 * shade * 1.12).clamp(0, 255)
        ..g = (p.g * .62 * shade * .98).clamp(0, 255)
        ..b = (p.b * .62 * shade * .78).clamp(0, 255);
    }
    final face = [95.0, 95.0, 255.0, 300.0]; // given by hand here; ML Kit provides it on the phone
    final rgba = bad.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
    final out = img.decodeJpg(processPixelsForTest(rgba, bad.width, bad.height, face))!;
    Directory('build/test_out').createSync(recursive: true);
    File('build/test_out/before.jpg').writeAsBytesSync(img.encodeJpg(bad));
    File('build/test_out/after.jpg').writeAsBytesSync(img.encodeJpg(out));

    // framing
    expect((out.width / out.height - 35 / 45).abs() < .01, isTrue);

    // measure the face area in both
    ({double l, double cast, double sides}) stats(img.Image im, List<double> f) {
      double sr = 0, sb = 0, sl = 0, n = 0, left = 0, nl = 0, right = 0, nr = 0;
      final cx = (f[0] + f[2]) / 2;
      for (var y = f[1].round(); y < f[3].round(); y += 2) {
        for (var x = f[0].round(); x < f[2].round(); x += 2) {
          final p = im.getPixel(x, y);
          final l = .299 * p.r + .587 * p.g + .114 * p.b;
          sr += p.r;
          sb += p.b;
          sl += l;
          n++;
          if (x < cx) {
            left += l;
            nl++;
          } else {
            right += l;
            nr++;
          }
        }
      }
      return (l: sl / n, cast: (sr - sb) / n, sides: math.max(left / nl, right / nr) / math.min(left / nl, right / nr));
    }

    // central cheeks/nose area of the face in each image
    List<double> inner(List<double> f) {
      final w = f[2] - f[0], h = f[3] - f[1];
      return [f[0] + w * .2, f[1] + h * .3, f[2] - w * .2, f[3] - h * .25];
    }

    final clean = stats(src, inner(face));
    final b = stats(bad, inner(face));
    // in the output the face is centred horizontally; locate it by the same proportions
    final fwOut = out.width * .58, fhOut = out.height * .52;
    final outFace = [(out.width - fwOut) / 2, out.height * .3, (out.width + fwOut) / 2, out.height * .3 + fhOut];
    final a = stats(out, inner(outFace));
    // ignore: avoid_print
    print('clean: lum ${clean.l.toStringAsFixed(0)} cast ${clean.cast.toStringAsFixed(0)} | before: lum ${b.l.toStringAsFixed(0)} cast ${b.cast.toStringAsFixed(0)} sides ${b.sides.toStringAsFixed(2)} | after: lum ${a.l.toStringAsFixed(0)} cast ${a.cast.toStringAsFixed(0)} sides ${a.sides.toStringAsFixed(2)} | out ${out.width}x${out.height}');
    expect(a.l, greaterThan(b.l + 25)); // brighter
    expect((a.cast - clean.cast).abs(), lessThan((b.cast - clean.cast).abs() + 6)); // colour back near natural
    expect(a.sides, lessThan(b.sides)); // left/right more even
  });
}
