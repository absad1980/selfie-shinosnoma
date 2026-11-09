import 'dart:ui' show Offset, Rect, Size;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'nn/runner.dart';
import 'nn/vision.dart';

/// Live face guide for the camera screen: a few times a second a small grey copy of the preview frame
/// goes through our face detector, and the oval turns green only when one face sits well inside it.

/// What the guide tells the user.
enum FaceFit { none, many, closer, farther, center, good }

/// A detected face in upright frame coordinates (0…1) and the detector's confidence.
class LiveFace {
  final double cx, cy, w, score;
  const LiveFace(this.cx, this.cy, this.w, [this.score = 1]);
}

/// Small upright grey copy of a camera frame, as RGBA for the detector.
class SmallFrame {
  final Uint8List rgba;
  final int w, h;
  const SmallFrame(this.rgba, this.w, this.h);
}

/// Turns a camera frame (YUV on Android, BGRA on iPhone) into an upright ~200 px grey image.
/// [rot] is how far the sensor image must turn clockwise (0/90/180/270) to stand upright.
SmallFrame smallGreyFrame(CameraImage f, int rot) {
  final bgra = f.format.group == ImageFormatGroup.bgra8888;
  final p = f.planes.first;
  return smallGreyFromPlane(p.bytes, p.bytesPerRow, bgra ? 4 : (p.bytesPerPixel ?? 1), f.width, f.height, rot, bgra);
}

/// Same, from the raw first plane (Y for YUV, or BGRA pixels).
SmallFrame smallGreyFromPlane(Uint8List bytes, int stride, int pix, int ws, int hs, int rot, bool bgra) {
  final upW = rot % 180 == 0 ? ws : hs, upH = rot % 180 == 0 ? hs : ws;
  final step = (upW > upH ? upW : upH) / 200;
  final w = (upW / step).floor(), h = (upH / step).floor();
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = ((x + .5) * step).floor(), py = ((y + .5) * step).floor();
      int sx, sy;
      switch (rot) {
        case 90:
          sx = py;
          sy = hs - 1 - px;
        case 180:
          sx = ws - 1 - px;
          sy = hs - 1 - py;
        case 270:
          sx = ws - 1 - py;
          sy = px;
        default:
          sx = px;
          sy = py;
      }
      final i = sy * stride + sx * pix;
      int v;
      if (i < 0 || i + (bgra ? 2 : 0) >= bytes.length) {
        v = 0;
      } else if (bgra) {
        v = (bytes[i + 2] * 77 + bytes[i + 1] * 150 + bytes[i] * 29) >> 8;
      } else {
        v = bytes[i];
      }
      final o = (y * w + x) * 4;
      out[o] = v;
      out[o + 1] = v;
      out[o + 2] = v;
      out[o + 3] = 255;
    }
  }
  return SmallFrame(out, w, h);
}

/// Runs in a background isolate: all faces in the small frame (centre and width, 0…1), best first.
List<LiveFace> detectLive((SmallFrame, Uint8List) q) {
  final f = q.$1;
  final faces = FaceDetector(NnModel.load(q.$2)).detect(f.rgba, f.w, f.h, minScore: .6);
  return [for (final b in faces) LiveFace((b.left + b.right) / 2 / f.w, (b.top + b.bottom) / 2 / f.h, b.width / f.w, b.score)];
}

/// Which turn makes the camera frame upright: the detector also finds faces lying sideways or upside down,
/// but always with less confidence than the upright face (measured: 0.88–0.93 vs 0.57–0.81).
/// [frames] are the same frame turned 0/90/180/270. Returns the index of the clear winner, or null.
int? bestTurn((List<SmallFrame>, Uint8List) q) {
  final det = FaceDetector(NnModel.load(q.$2));
  final scores = [
    for (final f in q.$1)
      (() {
        final fs = det.detect(f.rgba, f.w, f.h, minScore: .3);
        return fs.isEmpty ? 0.0 : fs.first.score;
      })(),
  ];
  var best = 0;
  for (var i = 1; i < scores.length; i++) {
    if (scores[i] > scores[best]) best = i;
  }
  final second = [for (var i = 0; i < scores.length; i++) if (i != best) scores[i]].reduce((a, b) => a > b ? a : b);
  return scores[best] >= .8 && scores[best] - second >= .05 ? best : null;
}

/// The oval drawn on the camera screen (also used by its painter).
/// Centred a little above the middle of the screen, where the face is when the phone is held at eye level.
Rect ovalRect(Size s) => Rect.fromCenter(center: Offset(s.width / 2, s.height * .43), width: s.width * .5, height: s.width * .65);

/// Judges how the face sits in the oval. The preview fills the screen like BoxFit.cover;
/// [frameAspect] is the upright frame's width ÷ height; [mirror] for the front camera.
FaceFit judge(List<LiveFace> faces, Size screen, double frameAspect, bool mirror) {
  if (faces.isEmpty) return FaceFit.none;
  if (faces.length > 1 && faces[1].w > faces[0].w * .6) return FaceFit.many;
  final f = faces.first;
  // frame → screen (cover fit)
  final screenAspect = screen.width / screen.height;
  double dw, dh;
  if (frameAspect > screenAspect) {
    dh = screen.height;
    dw = dh * frameAspect;
  } else {
    dw = screen.width;
    dh = dw / frameAspect;
  }
  final ox = (screen.width - dw) / 2, oy = (screen.height - dh) / 2;
  final cx = ox + (mirror ? 1 - f.cx : f.cx) * dw, cy = oy + f.cy * dh, fw = f.w * dw;
  final o = ovalRect(screen);
  // the detector's box spans roughly cheek to cheek: a well-fitted face is ~0.6–1.0 of the oval's width
  if (fw < o.width * .55) return FaceFit.closer;
  if (fw > o.width * 1.1) return FaceFit.farther;
  if ((cx - o.center.dx).abs() > o.width * .2 || (cy - o.center.dy).abs() > o.height * .18) return FaceFit.center;
  return FaceFit.good;
}

/// Hint key for each state.
String fitKey(FaceFit f) => switch (f) {
      FaceFit.good => 'hold',
      FaceFit.closer => 'closer',
      FaceFit.farther => 'farther',
      FaceFit.center => 'centerFace',
      FaceFit.many => 'ck_onlyone',
      FaceFit.none => 'hint',
    };

/// Small helpers so the camera screen can run detection off the UI thread.
Future<List<LiveFace>> detectInBackground(SmallFrame f, Uint8List model) => compute(detectLive, (f, model));
Future<int?> bestTurnInBackground(List<SmallFrame> frames, Uint8List model) => compute(bestTurn, (frames, model));
