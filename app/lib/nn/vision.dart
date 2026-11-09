import 'dart:math' as math;
import 'dart:typed_data';
import 'runner.dart';

/// A point in image pixels.
class P {
  final double x, y;
  const P(this.x, this.y);
  double dist(P o) => math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));
}

/// One face found by the detector (image pixels).
class FaceBox {
  final double left, top, right, bottom, score;
  final List<P> keypoints; // eye, eye, nose tip, mouth, ear, ear
  const FaceBox(this.left, this.top, this.right, this.bottom, this.score, this.keypoints);
  double get width => right - left;
  double get height => bottom - top;
}

/// Bilinear sample of an RGBA image; returns 0 outside.
double _sample(Uint8List rgba, int w, int h, double x, double y, int ch) {
  if (x < 0 || y < 0 || x > w - 1 || y > h - 1) return 0;
  final x0 = x.floor(), y0 = y.floor();
  final x1 = math.min(x0 + 1, w - 1), y1 = math.min(y0 + 1, h - 1);
  final dx = x - x0, dy = y - y0;
  final a = rgba[(y0 * w + x0) * 4 + ch], b = rgba[(y0 * w + x1) * 4 + ch];
  final c = rgba[(y1 * w + x0) * 4 + ch], d = rgba[(y1 * w + x1) * 4 + ch];
  return a * (1 - dx) * (1 - dy) + b * dx * (1 - dy) + c * (1 - dx) * dy + d * dx * dy;
}

/// Face detector (MediaPipe BlazeFace short range, 128×128).
class FaceDetector {
  final NnModel model;
  FaceDetector(this.model);

  static final List<P> _anchors = () {
    final a = <P>[];
    // strides 8 (16×16 cells, 2 anchors) and 16 (8×8 cells, 6 anchors)
    for (final (cells, per) in [(16, 2), (8, 6)]) {
      for (var y = 0; y < cells; y++) {
        for (var x = 0; x < cells; x++) {
          for (var k = 0; k < per; k++) {
            a.add(P((x + .5) / cells, (y + .5) / cells));
          }
        }
      }
    }
    return a;
  }();

  /// All faces, best first (after overlap removal).
  List<FaceBox> detect(Uint8List rgba, int w, int h, {double minScore = .5}) {
    const n = 128;
    final scale = n / math.max(w, h);
    final ox = (n - w * scale) / 2, oy = (n - h * scale) / 2;
    final input = Float32List(n * n * 3);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final sx = (x + .5 - ox) / scale - .5, sy = (y + .5 - oy) / scale - .5;
        for (var ch = 0; ch < 3; ch++) {
          final v = (sx < 0 || sy < 0 || sx > w - 1 || sy > h - 1) ? 0.0 : _sample(rgba, w, h, sx, sy, ch);
          input[(y * n + x) * 3 + ch] = v / 127.5 - 1;
        }
      }
    }
    final out = model.run(input);
    final reg = out[0], cls = out[1];
    final found = <FaceBox>[];
    P toImg(double u, double v) => P((u * n - ox) / scale, (v * n - oy) / scale);
    for (var i = 0; i < _anchors.length; i++) {
      final s = 1 / (1 + math.exp(-cls[i].clamp(-100.0, 100.0)));
      if (s < minScore) continue;
      final r = i * 16, an = _anchors[i];
      final cx = reg[r] / n + an.x, cy = reg[r + 1] / n + an.y, bw = reg[r + 2] / n, bh = reg[r + 3] / n;
      final tl = toImg(cx - bw / 2, cy - bh / 2), br = toImg(cx + bw / 2, cy + bh / 2);
      found.add(FaceBox(tl.x, tl.y, br.x, br.y, s, [for (var k = 0; k < 6; k++) toImg(reg[r + 4 + k * 2] / n + an.x, reg[r + 5 + k * 2] / n + an.y)]));
    }
    found.sort((a, b) => b.score.compareTo(a.score));
    // weighted overlap removal: average each cluster, weighted by score
    final result = <FaceBox>[];
    final used = List<bool>.filled(found.length, false);
    for (var i = 0; i < found.length; i++) {
      if (used[i]) continue;
      final c = <FaceBox>[];
      for (var j = i; j < found.length; j++) {
        if (!used[j] && _iou(found[i], found[j]) > .3) {
          used[j] = true;
          c.add(found[j]);
        }
      }
      final ws = c.fold<double>(0, (a, f) => a + f.score);
      double avg(double Function(FaceBox) g) => c.fold<double>(0, (a, f) => a + g(f) * f.score) / ws;
      result.add(FaceBox(avg((f) => f.left), avg((f) => f.top), avg((f) => f.right), avg((f) => f.bottom), found[i].score,
          [for (var k = 0; k < 6; k++) P(avg((f) => f.keypoints[k].x), avg((f) => f.keypoints[k].y))]));
    }
    return result;
  }

  static double _iou(FaceBox a, FaceBox b) {
    final ix = math.max(0.0, math.min(a.right, b.right) - math.max(a.left, b.left));
    final iy = math.max(0.0, math.min(a.bottom, b.bottom) - math.max(a.top, b.top));
    final inter = ix * iy, uni = a.width * a.height + b.width * b.height - inter;
    return uni <= 0 ? 0 : inter / uni;
  }
}

/// 468 face landmarks (MediaPipe Face Mesh, 192×192) in image pixels.
class FaceMesh {
  final NnModel model;
  FaceMesh(this.model);

  /// Returns null if the crop doesn't contain a face.
  ({List<P> points, double presence})? landmarks(Uint8List rgba, int w, int h, FaceBox f) {
    const n = 192;
    // eye line sets the rotation; crop is a square 1.5× the face box around its centre
    var e1 = f.keypoints[0], e2 = f.keypoints[1];
    if (e2.x < e1.x) (e1, e2) = (e2, e1);
    final th = math.atan2(e2.y - e1.y, e2.x - e1.x);
    final cs = math.cos(th), sn = math.sin(th);
    final cx = (f.left + f.right) / 2, cy = (f.top + f.bottom) / 2;
    final size = math.max(f.width, f.height) * 1.5;
    P toImg(double u, double v) {
      final lx = (u / n - .5) * size, ly = (v / n - .5) * size;
      return P(cx + lx * cs - ly * sn, cy + lx * sn + ly * cs);
    }

    final input = Float32List(n * n * 3);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final p = toImg(x + .5, y + .5);
        for (var ch = 0; ch < 3; ch++) {
          input[(y * n + x) * 3 + ch] = _sample(rgba, w, h, p.x - .5, p.y - .5, ch) / 255;
        }
      }
    }
    final out = model.run(input);
    final presence = 1 / (1 + math.exp(-out[1][0]));
    if (presence < .5) return null;
    final lm = out[0];
    return (points: [for (var i = 0; i < 468; i++) toImg(lm[i * 3], lm[i * 3 + 1])], presence: presence);
  }
}

/// Person-vs-background mask (MediaPipe selfie segmentation, 256×256): 0 background … 1 person.
class PersonMask {
  final NnModel model;
  PersonMask(this.model);

  ({Float32List mask, int w, int h}) run(Uint8List rgba, int w, int h) {
    const n = 256;
    final input = Float32List(n * n * 3);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final sx = (x + .5) * w / n - .5, sy = (y + .5) * h / n - .5;
        for (var ch = 0; ch < 3; ch++) {
          input[(y * n + x) * 3 + ch] = _sample(rgba, w, h, sx.clamp(0, w - 1), sy.clamp(0, h - 1), ch) / 255;
        }
      }
    }
    return (mask: model.run(input).first, w: n, h: n);
  }
}
