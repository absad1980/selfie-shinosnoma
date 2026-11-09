import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfie_shinosnoma/app_state.dart';
import 'package:selfie_shinosnoma/main.dart';
import 'package:selfie_shinosnoma/screens/camera.dart';

/// The camera screen's top bar must sit at the very top on every phone, with nothing overflowing:
/// small old phones to tablets, with or without a notch, any phone font size, every language.
/// (The test font is wider than the real one, so passing here leaves a safety margin.)
void main() {
  const screens = [Size(320, 568), Size(360, 640), Size(360, 780), Size(393, 851), Size(412, 915), Size(430, 932), Size(480, 854), Size(600, 960), Size(800, 1280)];
  const notches = [24.0, 40.0, 56.0];
  const fontScales = [1.0, 1.5, 2.0];

  for (final lang in ['tg', 'ru', 'en']) {
    testWidgets('camera top bar on every phone ($lang)', (tester) async {
      for (final s in screens) {
        for (final top in notches) {
          for (final fs in fontScales) {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = s;
            tester.view.padding = FakeViewPadding(top: top, bottom: 24);
            final st = AppState()..lang = lang;
            st.timer = 10; // the longest timer label
            await tester.pumpWidget(AppScope(
              notifier: st,
              child: MediaQuery(
                data: MediaQueryData(size: s, padding: EdgeInsets.only(top: top, bottom: 24), textScaler: TextScaler.linear(fs)),
                child: const MaterialApp(home: CameraScreen()),
              ),
            ));
            await tester.pump(const Duration(milliseconds: 300));
            final what = '$lang ${s.width.toInt()}×${s.height.toInt()} notch $top font ×$fs';
            expect(tester.takeException(), isNull, reason: 'overflow/error on $what');
            final close = tester.getRect(find.byIcon(Icons.close).first);
            expect(close.top, lessThan(top + 30), reason: 'top bar not at the top on $what');
            for (final icon in [Icons.close, Icons.nightlight_round, Icons.light_mode_outlined, Icons.timer_outlined, Icons.cameraswitch_outlined]) {
              final r = tester.getRect(find.byIcon(icon).first);
              expect(r.left >= 0 && r.right <= s.width && r.top >= 0 && r.bottom <= s.height, isTrue, reason: '$icon off screen on $what');
              if (icon != Icons.cameraswitch_outlined) expect((r.center.dy - close.center.dy).abs(), lessThan(6), reason: '$icon not in the top row on $what');
            }
          }
        }
      }
      tester.view.reset();
    });
  }
}
