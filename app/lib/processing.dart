import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'nn/runner.dart';
import 'nn/vision.dart';

/// Background colours offered for documents.
const bgColors = {'white': [255, 255, 255], 'grey': [232, 233, 236], 'blue': [220, 235, 247]};

/// Head (crown → chin) as a share of photo height, per document size.
/// (35×45 rule: 32–36 mm of 45 = 0.71–0.80; .72 leaves room for the shoulders)
const headShare = {'tj': .72, 's3545': .72, 's34': .70, 's46': .62};

/// What the ICAO check found; empty [problems] means the photo is suitable.
class ProcessResult {
  final File? file;
  final List<String> problems; // l10n keys
  ProcessResult(this.file, this.problems);
}

/// Everything runs on the phone with our own code and bundled models (no Google services, no internet):
/// find the face and its landmarks, check the pose, separate the person from the background,
/// then fix light, shadows and red eye, swap the background and crop to the document framing.
class PhotoProcessor {
  static List<Uint8List>? _models;

  static Future<List<Uint8List>> _loadModels() async => _models ??= [
        for (final n in ['face_detect', 'face_mesh', 'person_mask']) (await rootBundle.load('assets/models/$n.nnm')).buffer.asUint8List(),
      ];

  /// Quick check right after a selfie is taken: returns the problems (l10n keys), empty if the photo is usable.
  static Future<List<String>> check(File raw) async {
    final models = await _loadModels();
    Uint8List? small;
    try {
      // the phone shrinks the photo natively (fast), keeping it upright
      small = await FlutterImageCompress.compressWithFile(raw.path, minWidth: 640, minHeight: 640, quality: 90);
    } catch (_) {}
    small ??= await raw.readAsBytes();
    return compute(_checkOnly, (small, models));
  }

  static Future<ProcessResult> run(File raw, {required String presetId, required double ratio, required String bg, SuitLayer? suit}) async {
    final models = await _loadModels();
    final r = await compute(_analyzeAndProcess, _Request(await raw.readAsBytes(), models, bgColors[bg] ?? bgColors['white']!, ratio, headShare[presetId] ?? .74, suit));
    if (r.jpg == null) return ProcessResult(null, r.problems);
    final docs = await getApplicationDocumentsDirectory();
    final out = File('${docs.path}/done_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await out.writeAsBytes(r.jpg!, flush: true);
    return ProcessResult(out, r.problems);
  }
}

class _Request {
  final Uint8List photo;
  final List<Uint8List> models;
  final List<int> bg;
  final double ratio, head;
  final SuitLayer? suit;
  _Request(this.photo, this.models, this.bg, this.ratio, this.head, this.suit);
}

/// Face analysis of a photo: the face box used for framing (cheek to cheek, forehead to chin),
/// eye centres for red-eye, the person mask, and any pose problems (l10n keys).
class FaceAnalysis {
  final List<double> face;
  final Point leftEye, rightEye;
  final Float32List? mask;
  final int mw, mh;
  final List<String> problems;
  /// face outline (forehead, cheeks, jaw, chin) and the level of the ear lobes, for the suit step
  final List<Point> outline;
  final double cutY;
  FaceAnalysis(this.face, this.leftEye, this.rightEye, this.mask, this.mw, this.mh, this.problems, this.outline, this.cutY);
}

/// Face Mesh points that trace the face outline, in order around the face.
const faceOvalIdx = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109];

/// Runs our models on an RGBA photo (the person mask only if [withMask]). Returns null when no face is found.
FaceAnalysis? analyzeFace(Uint8List rgba, int w, int h, List<Uint8List> models, {bool withMask = true}) {
  // the models use small inputs: analyse a ~640 px copy, then scale the results back up
  final s = math.min(1.0, 640 / math.max(w, h));
  var small = rgba, sw = w, sh = h;
  if (s < 1) {
    final im = img.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
    final r = img.copyResize(im, width: (w * s).round(), height: (h * s).round(), interpolation: img.Interpolation.average);
    small = r.getBytes(order: img.ChannelOrder.rgba);
    sw = r.width;
    sh = r.height;
  }
  final faces = FaceDetector(NnModel.load(models[0])).detect(small, sw, sh);
  if (faces.isEmpty) return null;
  final f = faces.first;
  final lm = FaceMesh(NnModel.load(models[1])).landmarks(small, sw, sh, f);
  if (lm == null) return null;
  final p = lm.points;
  final problems = <String>[];
  if (faces.length > 1 && faces[1].width > f.width * .6) problems.add('ck_onlyone');
  // eye openness: lid gap ÷ eye width (open ≈ 0.32–0.39, closed ≈ 0.21 — the model never reaches 0 for shut eyes)
  final earR = p[159].dist(p[145]) / p[33].dist(p[133]), earL = p[386].dist(p[374]) / p[362].dist(p[263]);
  if (earR < .255 || earL < .255) problems.add('ck_eyes');
  // head turned (nose off the cheek midline) or tilted (eye line not level)
  final yaw = (p[1].x - p[234].x) / math.max(1, p[454].x - p[234].x) - .5;
  final roll = math.atan2(p[263].y - p[33].y, p[263].x - p[33].x) * 180 / math.pi;
  if (yaw.abs() > .08 || roll.abs() > 8) problems.add('ck_straight');
  // neutral face: mouth closed and not widened by a smile (neutral ≈ 0.34 of face width)
  final mouthOpen = p[13].dist(p[14]) / p[61].dist(p[291]), mouthW = p[61].dist(p[291]) / p[234].dist(p[454]);
  if (mouthOpen > .12 || mouthW > .44) problems.add('ck_neutral');
  final m = withMask ? PersonMask(NnModel.load(models[2])).run(small, sw, sh) : null;
  final k = w / sw;
  Point mid(int a, int b) => Point((p[a].x + p[b].x) / 2 * k, (p[a].y + p[b].y) / 2 * k);
  return FaceAnalysis([p[234].x * k, p[10].y * k, p[454].x * k, p[152].y * k], mid(362, 263), mid(33, 133), m?.mask, m?.w ?? 0, m?.h ?? 0, problems,
      [for (final i in faceOvalIdx) Point(p[i].x * k, p[i].y * k)], math.max(p[132].y, p[361].y) * k);
}

List<String> _checkOnly((Uint8List, List<Uint8List>) q) {
  final im = img.decodeImage(q.$1);
  if (im == null) return [];
  final up = img.bakeOrientation(im);
  final a = analyzeFace(up.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba), up.width, up.height, q.$2, withMask: false);
  return a == null ? ['ck_noface'] : a.problems;
}

({Uint8List? jpg, List<String> problems}) _analyzeAndProcess(_Request q) {
  final work = _prepare(q.photo);
  if (work == null) return (jpg: null, problems: ['ck_noface']);
  final a = analyzeFace(work.rgba, work.w, work.h, q.models);
  if (a == null) return (jpg: null, problems: ['ck_noface']);
  // eyes closed, head turned, smiling…: no document photo is made from it
  if (a.problems.isNotEmpty) return (jpg: null, problems: a.problems);
  final jpg = _process(_Job(rgba: work.rgba, w: work.w, h: work.h, face: a.face, leftEye: a.leftEye, rightEye: a.rightEye, mask: a.mask, mw: a.mw, mh: a.mh, bg: q.bg, ratio: q.ratio, head: q.head, suit: q.suit, outline: a.outline, cutY: a.cutY));
  // own clothes kept: warn when they are about the colour of the new background (e.g. white t-shirt on white)
  final tips = q.suit == null && clothesLikeBackground(work.rgba, work.w, work.h, a.face, a.mask, a.mw, a.mh, q.bg) ? ['ck_clothes'] : <String>[];
  return (jpg: jpg, problems: tips);
}

class Point {
  final double x, y;
  const Point(this.x, this.y);
}

/// Runs only the pixel step with a given face box and optional mask (used by tests on a computer).
@visibleForTesting
Uint8List processPixelsForTest(Uint8List rgba, int w, int h, List<double> face, {double ratio = 35 / 45, String bg = 'white', double head = .74, SuitLayer? suit, Float32List? mask, int? mw, int? mh, List<Point>? outline, double? cutY}) =>
    _process(_Job(rgba: rgba, w: w, h: h, face: face, mask: mask, mw: mask == null ? 0 : mw ?? w, mh: mask == null ? 0 : mh ?? h, bg: bgColors[bg]!, ratio: ratio, head: head, suit: suit, outline: outline, cutY: cutY));

class _Work {
  final Uint8List rgba;
  final int w, h;
  _Work(this.rgba, this.w, this.h);
}

/// A suit layer (transparent PNG) and where its neck/chin are.
class SuitLayer {
  final Uint8List png;
  /// [throat]: bottom of the suit's collar opening, where it meets the neck (set by tools/fix_men_suits.py)
  /// [openW]: width of its collar opening at the collar tips (sized to the customer's neck)
  final double faceW, chinY, neckX, shoulder, throat, openW;
  const SuitLayer(this.png, this.faceW, this.chinY, this.neckX, this.shoulder, this.throat, this.openW);

  static SuitLayer fromJson(Uint8List png, Map<String, dynamic> a) => SuitLayer(png, (a['faceW'] as num).toDouble(), (a['chinY'] as num).toDouble(), (a['neckX'] as num).toDouble(), (a['shoulder'] as num).toDouble(),
      ((a['throat'] ?? ((a['chinY'] as num) + (a['faceW'] as num) * .2)) as num).toDouble(), ((a['openW'] ?? (a['faceW'] as num) * .55) as num).toDouble());

  static Map<String, dynamic>? _anchors;

  /// Loads e.g. 'm01' from assets/suits (made by test/make_suits_test.dart).
  static Future<SuitLayer> load(String name) async {
    _anchors ??= jsonDecode(await rootBundle.loadString('assets/suits/anchors.json')) as Map<String, dynamic>;
    final a = _anchors![name] as Map<String, dynamic>;
    final png = (await rootBundle.load('assets/suits/$name.png')).buffer.asUint8List();
    return SuitLayer.fromJson(png, a);
  }
}

/// Suit file for a shot's suit choice. Captured photos ('u') list men's suits then women's.
String? suitFile(String gender, int suit) {
  if (suit < 0) return null;
  if (gender == 'm') return 'm${(suit + 1).toString().padLeft(2, '0')}';
  if (gender == 'f') return 'w${(suit + 1).toString().padLeft(2, '0')}';
  return suit < 10 ? 'm${(suit + 1).toString().padLeft(2, '0')}' : 'w${(suit - 9).toString().padLeft(2, '0')}';
}

/// Average colour of the clothing on the chest (person pixels below the chin) compared with the background
/// colour: true when they are so close that the shoulders would blend into the background.
bool clothesLikeBackground(Uint8List rgba, int w, int h, List<double> face, Float32List? mask, int mw, int mh, List<int> bg) {
  final fl = face[0], ft = face[1], fr = face[2], fb = face[3];
  final fw = fr - fl, fh = fb - ft, cx = (fl + fr) / 2;
  double r = 0, g = 0, b = 0;
  var n = 0;
  for (var y = (fb + fh * .45).round(); y < math.min(h, (fb + fh * 1.0).round()); y += 2) {
    for (var x = (cx - fw * .9).round(); x <= (cx + fw * .9).round(); x += 2) {
      if (x < 0 || x >= w || y < 0) continue;
      if (mask != null && mw > 0) {
        final mx = (x * (mw - 1) / math.max(1, w - 1)).round(), my = (y * (mh - 1) / math.max(1, h - 1)).round();
        if (mask[my * mw + mx] < .6) continue;
      }
      final i = (y * w + x) * 4;
      r += rgba[i];
      g += rgba[i + 1];
      b += rgba[i + 2];
      n++;
    }
  }
  if (n < 200) return false; // shoulders not in the photo
  r /= n;
  g /= n;
  b /= n;
  final dr = r - bg[0], dg = g - bg[1], db = b - bg[2];
  final lum = .299 * r + .587 * g + .114 * b, lumBg = .299 * bg[0] + .587 * bg[1] + .114 * bg[2];
  return math.sqrt(dr * dr + dg * dg + db * db) < 70 && (lum - lumBg).abs() < 45;
}

class _Job {
  final Uint8List rgba;
  final int w, h, mw, mh;
  final List<double> face;
  final Point? leftEye, rightEye;
  final Float32List? mask;
  final List<int> bg;
  final double ratio, head;
  final SuitLayer? suit;
  final List<Point>? outline;
  final double? cutY;
  _Job({required this.rgba, required this.w, required this.h, required this.face, this.leftEye, this.rightEye, this.mask, required this.mw, required this.mh, required this.bg, required this.ratio, required this.head, this.suit, this.outline, this.cutY});
}

_Work? _prepare(Uint8List bytes) {
  var im = img.decodeImage(bytes);
  if (im == null) return null;
  im = img.bakeOrientation(im);
  const maxSide = 1600;
  if (math.max(im.width, im.height) > maxSide) {
    im = im.width > im.height ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average) : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
  }
  return _Work(im.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba), im.width, im.height);
}

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

Uint8List _process(_Job j) {
  final w = j.w, h = j.h, px = j.rgba;
  final fl = j.face[0], ft = j.face[1], fr = j.face[2], fb = j.face[3];
  final fw = fr - fl, fh = fb - ft;

  // person mask sampled at image resolution (bilinear), softened at the edges
  double maskAt(int x, int y) {
    final m = j.mask;
    if (m == null || j.mw == 0) return 1;
    final mx = x * (j.mw - 1) / math.max(1, w - 1), my = y * (j.mh - 1) / math.max(1, h - 1);
    final x0 = mx.floor(), y0 = my.floor(), x1 = math.min(x0 + 1, j.mw - 1), y1 = math.min(y0 + 1, j.mh - 1);
    final dx = mx - x0, dy = my - y0;
    final v = m[y0 * j.mw + x0] * (1 - dx) * (1 - dy) + m[y0 * j.mw + x1] * dx * (1 - dy) + m[y1 * j.mw + x0] * (1 - dx) * dy + m[y1 * j.mw + x1] * dx * dy;
    return _smooth(.35, .8, v);
  }

  // --- measure the face: colour cast, brightness, left/right shadow ---
  double sr = 0, sg = 0, sb = 0, n = 0, lumL = 0, nL = 0, lumR = 0, nR = 0;
  final cx = (fl + fr) / 2;
  for (var y = (ft + fh * .2).round(); y < (fb - fh * .15).round(); y += 2) {
    for (var x = (fl + fw * .15).round(); x < (fr - fw * .15).round(); x += 2) {
      if (x < 0 || y < 0 || x >= w || y >= h) continue;
      final i = (y * w + x) * 4;
      final r = px[i].toDouble(), g = px[i + 1].toDouble(), b = px[i + 2].toDouble();
      sr += r;
      sg += g;
      sb += b;
      n++;
      final l = .299 * r + .587 * g + .114 * b;
      if (x < cx) {
        lumL += l;
        nL++;
      } else {
        lumR += l;
        nR++;
      }
    }
  }
  if (n == 0) n = 1;
  final ar = sr / n, ag = sg / n, ab = sb / n;
  // white balance: pull the face toward a natural skin balance (gentle, never a "beauty" filter)
  final avg = (ar + ag + ab) / 3;
  final kr = (1 + (avg * 1.08 / math.max(1, ar) - 1) * .5).clamp(.85, 1.2);
  final kg = (1 + (avg / math.max(1, ag) - 1) * .5).clamp(.85, 1.2);
  final kb = (1 + (avg * .9 / math.max(1, ab) - 1) * .5).clamp(.85, 1.25);
  // exposure: bring the face to a well-lit level
  final faceLum = .299 * ar * kr + .587 * ag * kg + .114 * ab * kb;
  final gain = (165 / math.max(30, faceLum)).clamp(.8, 2.2);
  // shadow balance: brighten the darker side of the face toward the lighter side
  final mL = nL > 0 ? lumL / nL : 1, mR = nR > 0 ? lumR / nR : 1;
  final darkLeft = mL < mR;
  final shadowGain = ((math.max(mL, mR) / math.max(20, math.min(mL, mR))) - 1).clamp(0.0, .8) * .7;

  // red-eye zones
  final eyes = [j.leftEye, j.rightEye].whereType<Point>().toList();
  final eyeR = fw * .075;

  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      var r = px[i] * kr, g = px[i + 1] * kg, b = px[i + 2] * kb;
      // horizontal lift on the shadowed side, fading across the face
      if (shadowGain > 0) {
        final t = ((x - (fl - fw * .3)) / (fw * 1.6)).clamp(0.0, 1.0);
        final side = darkLeft ? 1 - t : t;
        final k = 1 + shadowGain * side;
        r *= k;
        g *= k;
        b *= k;
      }
      // exposure with a soft shoulder so highlights don't burn
      double tone(double v) {
        final u = v * gain / 255;
        return 255 * (u < .8 ? u : .8 + .2 * (1 - math.exp(-(u - .8) * 5)));
      }

      r = tone(r);
      g = tone(g);
      b = tone(b);
      // red eye: pupils only
      for (final e in eyes) {
        final dx = x - e.x, dy = y - e.y;
        if (dx * dx + dy * dy < eyeR * eyeR && r > 90 && r > 1.5 * math.max(g, b)) r = (g + b) / 2;
      }
      // background replacement
      final m = maskAt(x, y);
      out[i] = (r * m + j.bg[0] * (1 - m)).round().clamp(0, 255);
      out[i + 1] = (g * m + j.bg[1] * (1 - m)).round().clamp(0, 255);
      out[i + 2] = (b * m + j.bg[2] * (1 - m)).round().clamp(0, 255);
      out[i + 3] = 255;
    }
  }

  // --- document framing: head (crown → chin) fills the required share of the height ---
  var crown = ft - fh * .4; // fallback if no mask (top = forehead landmark)
  if (j.mask != null) {
    final x0 = (fl + fw * .2).round(), x1 = (fr - fw * .2).round();
    outer:
    for (var y = 0; y < ft; y++) {
      for (var x = math.max(0, x0); x < math.min(w, x1); x += 2) {
        if (maskAt(x, y) > .5) {
          crown = y.toDouble();
          break outer;
        }
      }
    }
  }
  final chin = fb + fh * .01; // bottom = chin landmark
  final headH = math.max(10.0, chin - crown);
  final H = headH / j.head;
  final W = H * j.ratio;
  final top = crown - H * ((1 - j.head) * .45);
  final left = cx - W / 2;

  final full = img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
  final outH = math.min(1400, H.round()), outW = (outH * j.ratio).round();
  final res = img.Image(width: outW, height: outH, numChannels: 3);
  img.fill(res, color: img.ColorRgb8(j.bg[0], j.bg[1], j.bg[2]));
  final sx = W / outW, sy = H / outH;
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      final srcX = left + (x + .5) * sx, srcY = top + (y + .5) * sy;
      if (srcX < 0 || srcY < 0 || srcX >= w - 1 || srcY >= h - 1) continue;
      final p = full.getPixelInterpolate(srcX, srcY, interpolation: img.Interpolation.linear);
      res.setPixelRgb(x, y, p.r, p.g, p.b);
    }
  }

  // --- suit: the person's face, hair and neck stay exactly as photographed; only clothing is removed ---
  // 1) find where the person's clothing starts at the neck (first row down the neck that isn't their skin)
  // 2) remove clothing only: everything below that line, and beside the neck/jaw (never the face or the neck itself)
  // 3) lay the suit over it: its collar opening sized to the neck, its throat point on that line
  final s = j.suit;
  if (s != null) {
    final layer0 = img.decodePng(s.png);
    if (layer0 != null) {
      final faceWOut = fw / sx, chinOut = (fb - top) / sy, neckOut = (cx - left) / sx;
      // neck width from the lower jaw (face points 136–365); measuring from the mask fails because collars count as neck
      final o = j.outline;
      final neckWOut = ((o != null && o.length == 36 ? (o[13].x - o[23].x).abs() : fw * .7).clamp(fw * .5, fw * .9)) / sx;
      final throatL = s.throat;
      // size: the collar opening fits the neck, kept within reason of the face size
      // (landmark cheek-to-cheek width is ~0.85 of the suit photos' widest skin row incl. ears)
      final kFace = faceWOut / (s.faceW * .85) * 1.04;
      // the collar wraps around the neck: its opening at the tips is a little wider than the neck
      // (first estimate from the jaw; replaced by the measured neck once the photo is analysed below)
      var k = (neckWOut * 1.12 / s.openW).clamp(kFace * .85, kFace * 1.2);
      final layer = layer0;
      if (k > 1.5) {
        // the layer is enlarged several times: soften its outline so edges don't show steps
        final soft = img.gaussianBlur(img.Image.from(layer0), radius: k > 3 ? 2 : 1);
        for (final p in layer) {
          p.a = soft.getPixel(p.x, p.y).a;
        }
      }

      // 1) where the clothing starts: going down the neck centre, the first row that no longer matches
      //    the skin just under the chin
      double ycc(img.Pixel p, int c) => c == 0 ? .299 * p.r + .587 * p.g + .114 * p.b : (c == 1 ? 128 - .168736 * p.r - .331264 * p.g + .5 * p.b : 128 + .5 * p.r - .418688 * p.g - .081312 * p.b);
      final band = neckWOut * .3;
      double rY = 0, rCb = 0, rCr = 0;
      var rn = 0;
      for (var y = (chinOut + faceWOut * .03).round(); y <= (chinOut + faceWOut * .07).round() && y < outH; y++) {
        for (var x = (neckOut - band).round(); x <= (neckOut + band).round(); x += 2) {
          if (x < 0 || x >= outW || y < 0) continue;
          final p = res.getPixel(x, y);
          rY += ycc(p, 0);
          rCb += ycc(p, 1);
          rCr += ycc(p, 2);
          rn++;
        }
      }
      var clothStart = chinOut + faceWOut * .22;
      if (rn > 0) {
        rY /= rn;
        rCb /= rn;
        rCr /= rn;
        for (var y = (chinOut + faceWOut * .07).round(); y < chinOut + faceWOut * .4 && y < outH; y++) {
          var ok = 0, n = 0;
          for (var x = (neckOut - band).round(); x <= (neckOut + band).round(); x += 2) {
            if (x < 0 || x >= outW) continue;
            final p = res.getPixel(x, y);
            final dy = ycc(p, 0), db = ycc(p, 1) - rCb, dr = ycc(p, 2) - rCr;
            if (db * db + dr * dr < 11 * 11 && dy > rY * .55 && dy < rY * 1.35 + 10) ok++;
            n++;
          }
          if (n > 0 && ok < n * .6) {
            clothStart = y.toDouble();
            break;
          }
        }
      }
      clothStart = clothStart.clamp(chinOut + faceWOut * .08, chinOut + faceWOut * .4);

      // Measure the person the way an operator looks before placing the suit:
      // (a) the real neck: its edges just above the clothing line, where it is still skin
      bool skinAt(int x, int y) {
        if (x < 0 || x >= outW || y < 0 || y >= outH) return false;
        final p = res.getPixel(x, y);
        final dy = ycc(p, 0), db = ycc(p, 1) - rCb, dr = ycc(p, 2) - rCr;
        return db * db + dr * dr < 13 * 13 && dy > rY * .5 && dy < rY * 1.4 + 12;
      }
      double personAt(int x, int y) => maskAt((left + (x + .5) * sx).round().clamp(0, w - 1), (top + (y + .5) * sy).round().clamp(0, h - 1));
      var neckW = neckWOut, neckC = neckOut;
      if (rn > 0) {
        final ws = <double>[], cs = <double>[];
        for (var y = (clothStart - faceWOut * .08).round(); y <= (clothStart - faceWOut * .02).round(); y++) {
          if (y < 0 || y >= outH) continue;
          var l = neckOut.round(), r = neckOut.round();
          if (!skinAt(l, y)) continue;
          while (l > 0 && skinAt(l - 1, y) && personAt(l - 1, y) > .5 && neckOut - l < faceWOut * .6) {
            l--;
          }
          while (r < outW - 1 && skinAt(r + 1, y) && personAt(r + 1, y) > .5 && r - neckOut < faceWOut * .6) {
            r++;
          }
          ws.add((r - l).toDouble());
          cs.add((l + r) / 2);
        }
        if (ws.length >= 3) {
          ws.sort();
          cs.sort();
          final mw = ws[ws.length ~/ 2];
          // trusted only when it agrees with the jaw estimate (shadows or hair can stop the skin scan early or late)
          if ((mw - neckWOut).abs() < neckWOut * .2) {
            neckW = mw;
            neckC = cs[cs.length ~/ 2];
          }
        }
      }
      // (b) the body outline: how far the person reaches left and right on a row (and whether it runs off the photo)
      ({double l, double r, bool edge}) reach(int y) {
        var l = neckC.round(), r = neckC.round();
        while (l > 0 && personAt(l - 1, y) > .5) {
          l--;
        }
        while (r < outW - 1 && personAt(r + 1, y) > .5) {
          r++;
        }
        return (l: neckC - l, r: r - neckC, edge: l <= 0 || r >= outW - 1);
      }

      // 2) remove clothing only. Protected: the face (its landmark outline, generously enlarged) and the neck
      //    (its full width plus a margin) above the clothing line. Everything else from the ear lobes down
      //    becomes background: collars and jackets beside the jaw and neck, and all clothing below the line.
      final src = j.outline ??
          [
            for (var i = 0; i < 36; i++)
              Point(cx + fw / 2 * math.cos(i * math.pi / 18), (ft + fb) / 2 + fh / 2 * math.sin(i * math.pi / 18)),
          ];
      double mx = 0, my = 0;
      for (final q in src) {
        mx += q.x;
        my += q.y;
      }
      mx /= src.length;
      my /= src.length;
      final poly = [for (final q in src) Point(((mx + (q.x - mx) * 1.1) - left) / sx, ((my + (q.y - my) * 1.04) - top) / sy)];
      final faceL = List<double>.filled(outH, double.infinity), faceR = List<double>.filled(outH, double.negativeInfinity);
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i], b = poly[(i + 1) % poly.length];
        final y0 = math.min(a.y, b.y), y1 = math.max(a.y, b.y);
        for (var y = math.max(0, y0.ceil()); y <= math.min(outH - 1, y1.floor()); y++) {
          final t = y1 == y0 ? 0.0 : (y - a.y) / (b.y - a.y);
          final x = a.x + (b.x - a.x) * t;
          if (x < faceL[y]) faceL[y] = x;
          if (x > faceR[y]) faceR[y] = x;
        }
      }
      final cutOut = ((j.cutY ?? (ft + fh * .75)) - top) / sy;
      // collar sized to the measured neck
      k = (neckW * 1.12 / s.openW).clamp(kFace * .8, kFace * 1.25);
      // (c) the shoulders: the row where the body reaches the suit's own shoulder width, and how wide the body is below it
      final suitShoulderHalfOut = s.faceW * .72 * k;
      double? shoulderY, bodyHalf;
      for (var y = clothStart.round(); y < outH; y++) {
        final rr = reach(y);
        if (math.min(rr.l, rr.r) >= suitShoulderHalfOut) {
          shoulderY = y.toDouble();
          final yb = (y + faceWOut * .3).round();
          if (yb < outH) {
            final rb = reach(yb);
            if (!rb.edge) bodyHalf = (rb.l + rb.r) / 2;
          }
          break;
        }
      }
      final edge = math.max(3.0, faceWOut * .012), neckHalf = neckW * .62;
      for (var y = math.max(0, cutOut.floor()); y < outH; y++) {
        // below the clothing line nothing of the person remains (a soft few-pixel fade at the line)
        final belowLine = _smooth(clothStart - edge, clothStart + edge, y.toDouble());
        for (var x = 0; x < outW; x++) {
          final dFace = faceL[y].isFinite ? math.max(0.0, math.max(faceL[y] - x, x - faceR[y])) : 1e9;
          var keep = 1 - _smooth(0, edge, dFace);
          if (y > chinOut - faceWOut * .25) {
            final kn = 1 - _smooth(0, edge * 2, (x - neckC).abs() - neckHalf);
            if (kn > keep) keep = kn;
          }
          keep *= 1 - belowLine;
          if (keep >= 1) continue;
          final d = res.getPixel(x, y);
          res.setPixelRgb(x, y, (d.r * keep + j.bg[0] * (1 - keep)).round(), (d.g * keep + j.bg[1] * (1 - keep)).round(), (d.b * keep + j.bg[2] * (1 - keep)).round());
        }
      }

      // 3) the suit. Its throat point sits on the clothing line; the collar keeps its size, and the long stretch
      //    from collar to shoulder line in the suit photos is shortened so the shoulders sit at a natural height.
      final throatOut = clothStart;
      // vertical: collar → shoulder line stretched or squeezed so the suit's shoulders land on the person's
      final span = math.max(1.0, s.shoulder - throatL);
      final kk = shoulderY != null
          ? ((shoulderY - throatOut) / span).clamp(k * .5, k * 1.3)
          : math.min(k, (math.max(throatOut + faceWOut * .12, chinOut + faceWOut * .32) - throatOut) / span);
      final shoulderAt = throatOut + span * kk;
      double layerY(int y) => y < throatOut ? throatL + (y - throatOut) / k : (y < shoulderAt ? throatL + (y - throatOut) / kk : s.shoulder + (y - shoulderAt) / k);
      final lw = layer.width, lh = layer.height;
      // horizontal: the collar part keeps the neck fit; the jacket beyond it is stretched to the person's shoulder width
      double suitHalfAt(double ly) {
        final yy = ly.round().clamp(0, lh - 1), cxl = s.neckX.round();
        var l = cxl, r = cxl;
        for (var x = cxl; x >= 0; x--) {
          if (layer.getPixel(x, yy).a > 128) l = x;
        }
        for (var x = cxl; x < lw; x++) {
          if (layer.getPixel(x, yy).a > 128) r = x;
        }
        return (r - l) / 2;
      }
      final collarHalfL = s.openW / 2 + s.faceW * .12;
      final suitBodyHalf = suitHalfAt(s.shoulder + s.faceW * .3);
      final kOut = bodyHalf != null && suitBodyHalf > collarHalfL + 5
          ? ((bodyHalf - collarHalfL * k) / (suitBodyHalf - collarHalfL)).clamp(k * .7, k * 1.6)
          : k;
      double layerX(int x) {
        final dx = x - neckC, ad = dx.abs(), c = collarHalfL * k;
        final l = ad <= c ? ad / k : collarHalfL + (ad - c) / kOut;
        return s.neckX + (dx < 0 ? -l : l);
      }
      for (var y = math.max(0, (throatOut - (throatL - s.chinY) * k).floor()); y < outH; y++) {
        var ly = layerY(y);
        if (ly < 0) continue;
        final body = ly > s.shoulder; // below the shoulder line the jacket may be extended sideways
        if (ly > lh - 2) ly = lh - 2.0;
        for (var x = 0; x < outW; x++) {
          var lx = layerX(x);
          if (lx < 0 || lx > lw - 2) {
            if (!body) continue;
            lx = lx.clamp(0.0, lw - 2.0);
          }
          final q = layer.getPixelInterpolate(lx, ly, interpolation: img.Interpolation.linear);
          final a = q.a / 255;
          if (a <= 0) continue;
          final d = res.getPixel(x, y);
          res.setPixelRgb(x, y, (q.r * a + d.r * (1 - a)).round(), (q.g * a + d.g * (1 - a)).round(), (q.b * a + d.b * (1 - a)).round());
        }
      }
    }
  }
  return img.encodeJpg(res, quality: 95);
}
