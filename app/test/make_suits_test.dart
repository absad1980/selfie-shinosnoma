import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Build tool — runs only when asked, so a normal `flutter test` never overwrites the cleaned suits:
///   MAKE_SUITS=1 flutter test test/make_suits_test.dart   then   python ../tools/clean_women_suits.py
///
/// cuts the clothing out of each AI suit photo into a transparent layer and
/// records where the neck and chin are, so the app can fit it onto any photo.
///
/// Steps per photo: flood-fill the plain background from the edges → find skin
/// (YCbCr) → chin = where the skin narrows from face to neck → keep non-skin,
/// non-background pixels below the chin.
bool _isSkin(num r, num g, num b) {
  final cb = 128 - .168736 * r - .331264 * g + .5 * b;
  final cr = 128 + .5 * r - .418688 * g - .081312 * b;
  final lum = .299 * r + .587 * g + .114 * b;
  // strict: excludes cream fabric (r≈g) and dark burgundy (low brightness)
  return cb > 80 && cb < 125 && cr > 138 && cr < 172 && lum > 80 && r - g > 14 && g >= b;
}

/// Chin lines read by eye from a gridded contact sheet (pixels in the 350×450 photos).
const _chin = {
  'm01': 238, 'm02': 236, 'm03': 258, 'm04': 250, 'm05': 272, 'm06': 270, 'm07': 262, 'm08': 256, 'm09': 250, 'm10': 196,
  'w01': 222, 'w02': 222, 'w03': 222, 'w04': 232, 'w05': 236, 'w06': 234, 'w07': 222, 'w08': 222, 'w09': 222,
};

void main() {
  test('make suit layers', () {
    final out = Directory('assets/suits')..createSync(recursive: true);
    final anchors = <String, Map<String, num>>{};
    final names = [for (var i = 1; i <= 10; i++) 'm${i.toString().padLeft(2, '0')}', for (var i = 1; i <= 9; i++) 'w${i.toString().padLeft(2, '0')}'];
    for (final name in names) {
      final src = img.decodeJpg(File('assets/samples/$name.jpg').readAsBytesSync())!;
      final w = src.width, h = src.height;

      // 1) background: flood fill from the borders over near-white, low-saturation pixels
      final bgMask = List<bool>.filled(w * h, false);
      // the backdrop colour, sampled from the top corners
      double br = 0, bgc = 0, bb = 0;
      for (final c in [src.getPixel(3, 3), src.getPixel(w - 4, 3), src.getPixel(3, 40), src.getPixel(w - 4, 40)]) {
        br += c.r / 4;
        bgc += c.g / 4;
        bb += c.b / 4;
      }
      bool nearBg(int x, int y) {
        final p = src.getPixel(x, y);
        return (p.r - br).abs() < 14 && (p.g - bgc).abs() < 14 && (p.b - bb).abs() < 14;
      }

      final stack = <int>[];
      for (var x = 0; x < w; x++) {
        stack.add(x); // top row
      }
      for (var y = 0; y < h * .6; y++) {
        stack
          ..add(y * w)
          ..add(y * w + w - 1);
      }
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        if (bgMask[i]) continue;
        final x = i % w, y = i ~/ w;
        if (!nearBg(x, y)) continue;
        bgMask[i] = true;
        if (x > 0) stack.add(i - 1);
        if (x < w - 1) stack.add(i + 1);
        if (y > 0) stack.add(i - w);
        if (y < h - 1) stack.add(i + w);
      }

      // 2) skin width per row, inside the central band
      final skinW = List<int>.filled(h, 0);
      final skinMid = List<double>.filled(h, w / 2);
      for (var y = 0; y < h; y++) {
        var first = -1, last = -1;
        for (var x = (w * .22).round(); x < (w * .78).round(); x++) {
          final p = src.getPixel(x, y);
          if (!bgMask[y * w + x] && _isSkin(p.r, p.g, p.b)) {
            if (first < 0) first = x;
            last = x;
          }
        }
        if (first >= 0) {
          skinW[y] = last - first;
          skinMid[y] = (first + last) / 2;
        }
      }
      // face rows: the widest skin rows in the upper 70%
      var faceW = 0;
      for (var y = (h * .15).round(); y < (h * .7).round(); y++) {
        if (skinW[y] > faceW) {
          faceW = skinW[y];
        }
      }
      final chin = _chin[name]!;
      final neckX = skinMid[math.min(h - 1, chin + 18)];
      // shoulder line: first row below the chin where clothing reaches the photo edges
      var shoulder = h - 1;
      for (var y = chin; y < h; y++) {
        if (!bgMask[y * w + 2] || !bgMask[y * w + w - 3]) {
          shoulder = y;
          break;
        }
      }

      // 3) clothing layer: below the shoulder line everywhere, and from the chin down only in the
      //    collar zone around the neck (drops hair beside the neck); skin removed only near the neck
      final layer = img.Image(width: w, height: h, numChannels: 4);
      final collarHalf = faceW * .48, skinHalf = faceW * .4;
      var top = h;
      for (var y = chin; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = src.getPixel(x, y);
          final i = y * w + x;
          final dx = (x - neckX).abs();
          if (bgMask[i]) continue;
          if (y < chin + 16) continue; // jaw-edge shadows
          if (name.startsWith('w') && y < shoulder - faceW * .05) {
            // hair tips beside the collar: dark and grey-ish
            final q = .299 * p.r + .587 * p.g + .114 * p.b;
            final hi = math.max(p.r, math.max(p.g, p.b)).toDouble(), lo = math.min(p.r, math.min(p.g, p.b)).toDouble();
            if (q < 75 && (hi == 0 ? 0 : (hi - lo) / hi) < .4) continue;
          }
          // women: hair hangs beside the neck, so above the shoulders keep only the collar zone
          if (name.startsWith('w') && y < shoulder - faceW * .25 && dx > collarHalf) continue;
          final mx = math.max(p.r, math.max(p.g, p.b)).toDouble(), mn = math.min(p.r, math.min(p.g, p.b)).toDouble();
          final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
          // leftover backdrop specks on men's shoulders
          if (name.startsWith('m') && dx > collarHalf && mx > 215 && sat < .07 && y < shoulder + faceW * .3) continue;
          // neck zone: drop skin and skin-shadow tones (warm, not bright, not strongly saturated);
          // white shirts, cream tops, blue shirts, burgundy and gold ties all fail this test and stay
          final lum = .299 * p.r + .587 * p.g + .114 * p.b;
          final warm = p.r - p.g > 22 && p.g >= p.b; // skin and its shadows; beige fabric is flatter
          if (dx < skinHalf && ((y < shoulder && warm && lum < 205 && sat < .6) || (y < shoulder + faceW * .35 && _isSkin(p.r, p.g, p.b)))) continue;
          layer.setPixelRgba(x, y, p.r, p.g, p.b, 255);
          if (y < top) top = y;
        }
      }
      // drop small loose islands (backdrop specks, hair tips, neck shadows)
      final seen = List<bool>.filled(w * h, false);
      for (var i0 = 0; i0 < w * h; i0++) {
        if (seen[i0] || layer.getPixel(i0 % w, i0 ~/ w).a == 0) continue;
        final comp = <int>[], st = <int>[i0];
        seen[i0] = true;
        while (st.isNotEmpty) {
          final i = st.removeLast();
          comp.add(i);
          final x = i % w, y = i ~/ w;
          for (final nb in [if (x > 0) i - 1, if (x < w - 1) i + 1, if (y > 0) i - w, if (y < h - 1) i + w]) {
            if (!seen[nb] && layer.getPixel(nb % w, nb ~/ w).a > 0) {
              seen[nb] = true;
              st.add(nb);
            }
          }
        }
        if (comp.length < 400) {
          for (final i in comp) {
            layer.setPixelRgba(i % w, i ~/ w, 0, 0, 0, 0);
          }
        }
      }
      // thin slivers: keep a pixel only if most of its 5×5 neighbourhood is clothing too
      final thin = <int>[];
      for (var y = chin; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (layer.getPixel(x, y).a == 0) continue;
          var c = 0;
          for (var dy = -2; dy <= 2; dy++) {
            for (var dx = -2; dx <= 2; dx++) {
              final xx = x + dx, yy = y + dy;
              if (xx >= 0 && yy >= 0 && xx < w && yy < h && layer.getPixel(xx, yy).a > 0) c++;
            }
          }
          if (c < 11) thin.add(y * w + x);
        }
      }
      for (final i in thin) {
        layer.setPixelRgba(i % w, i ~/ w, 0, 0, 0, 0);
      }
      top = h;
      for (var y = chin; y < h && top == h; y++) {
        for (var x = 0; x < w; x++) {
          if (layer.getPixel(x, y).a > 0) {
            top = y;
            break;
          }
        }
      }
      // suit shoulder line: first row with clothing at both neck ± 0.8 face-box widths (box ≈ 0.9 × skin width)
      final probe = .8 * .9 * faceW;
      var suitShoulder = h - 1;
      for (var y = chin; y < h; y++) {
        final xl = (neckX - probe).round().clamp(0, w - 1), xr = (neckX + probe).round().clamp(0, w - 1);
        if (layer.getPixel(xl, y).a > 0 && layer.getPixel(xr, y).a > 0) {
          suitShoulder = y;
          break;
        }
      }
      // soften the outline by one pixel
      final soft = img.gaussianBlur(img.Image.from(layer), radius: 1);
      for (final p in layer) {
        if (p.a > 0) p.a = math.max(p.a.toInt(), soft.getPixel(p.x, p.y).a.toInt());
      }
      File('${out.path}/$name.png').writeAsBytesSync(img.encodePng(layer, level: 9));
      anchors[name] = {'w': w, 'h': h, 'faceW': faceW, 'chinY': chin, 'neckX': neckX, 'top': top, 'shoulder': suitShoulder};
    }
    File('${out.path}/anchors.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(anchors));
    expect(anchors.length, 19);
  }, skip: Platform.environment['MAKE_SUITS'] == null ? 'suit generator: set MAKE_SUITS=1 to regenerate' : null);
}
