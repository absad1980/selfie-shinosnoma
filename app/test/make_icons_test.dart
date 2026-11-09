import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfie_shinosnoma/widgets/painters.dart';

/// Build tool (run with `flutter test test/make_icons_test.dart`): draws the app logo into
/// the Android launcher icons (classic + adaptive) and the iPhone app icons.
const bgTop = Color(0xFFFFFFFF), bgBottom = Color(0xFFE3E8F1);

Future<void> _png(String path, int px, {required bool background, required double logoShare, double lift = 0}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final s = px.toDouble();
  if (background) {
    c.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bgTop, bgBottom]).createShader(Rect.fromLTWH(0, 0, s, s)));
  }
  final l = s * logoShare;
  c.save();
  c.translate((s - l) / 2, (s - l) / 2 - s * lift);
  LogoPainter().paint(c, Size(l, l));
  c.restore();
  final im = await rec.endRecording().toImage(px, px);
  final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('make app icons', (tester) async {
    await tester.runAsync(() async {
      const res = 'android/app/src/main/res';
      // classic icons (older Android): full square with background, logo large
      for (final (d, px) in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]) {
        await _png('$res/mipmap-$d/ic_launcher.png', px, background: true, logoShare: .8);
      }
      // adaptive icon foreground (Android 8+): 108 dp canvas, logo inside the 66 dp safe zone
      for (final (d, px) in [('mdpi', 108), ('hdpi', 162), ('xhdpi', 216), ('xxhdpi', 324), ('xxxhdpi', 432)]) {
        await _png('$res/mipmap-$d/ic_launcher_foreground.png', px, background: false, logoShare: .6);
      }
      // iPhone: opaque squares, every size listed in the asset catalog
      const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final names = Directory(ios).listSync().whereType<File>().map((f) => f.uri.pathSegments.last).where((n) => n.endsWith('.png'));
      for (final n in names) {
        final m = RegExp(r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png').firstMatch(n)!;
        final px = (double.parse(m[1]!) * int.parse(m[2]!)).round();
        await _png('$ios/$n', px, background: true, logoShare: .78);
      }
      // a large preview for the store listing / checking by eye
      await _png('build/icon_preview.png', 512, background: true, logoShare: .8);
    });
  });
}
