import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme.dart';
import 'painters.dart';

/// A raw shot as it came from the camera: the sample photos get "bad conditions"
/// (colour cast, side shadow, night, overexposure) so rework has something to fix.
class RawShotImage extends StatelessWidget {
  final RawShot shot;
  const RawShotImage(this.shot, {super.key});

  @override
  Widget build(BuildContext context) {
    final fx = shot.fx;
    Widget img = shot.file != null
        ? Image.file(shot.file!, fit: BoxFit.cover, alignment: Alignment.topCenter, cacheWidth: 300)
        : Image.asset('assets/samples/${shot.asset}.jpg', fit: BoxFit.cover, alignment: Alignment.topCenter, cacheWidth: 300);
    if (shot.file == null) {
      img = Transform.rotate(angle: shot.tilt, child: Transform.scale(scale: 1.14, child: img));
      if (fx.cast) img = ColorFiltered(colorFilter: const ColorFilter.mode(Color(0xFFE9C79A), BlendMode.multiply), child: img);
      if (!fx.night) img = ColorFiltered(colorFilter: const ColorFilter.mode(Color(0x8CCDC8BE), BlendMode.multiply), child: img);
    }
    return ClipRect(
      child: Stack(fit: StackFit.expand, children: [
        img,
        if (fx.shadow != 0)
          DecoratedBox(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
            colors: fx.shadow < 0 ? [Colors.black.withValues(alpha: .55), Colors.transparent] : [Colors.transparent, Colors.black.withValues(alpha: .55)],
            stops: fx.shadow < 0 ? const [0, .6] : const [.4, 1],
          ))),
        if (fx.harsh) const ColoredBox(color: Color(0x38FFFAEB)),
        if (fx.night) const ColoredBox(color: Color(0x990A0E28)),
      ]),
    );
  }
}

/// The reworked result. Until paid it carries the logo watermark on the chest.
class ResultImage extends StatelessWidget {
  final RawShot shot;
  final AppState st;
  const ResultImage(this.shot, this.st, {super.key});

  @override
  Widget build(BuildContext context) {
    final img = shot.file != null
        ? Image.file(shot.done ?? shot.file!, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true)
        : Image.asset('assets/samples/${st.resultAsset(shot)}.jpg', fit: BoxFit.cover, alignment: Alignment.topCenter);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final s = w * .28;
      return Stack(fit: StackFit.expand, children: [
        ColoredBox(color: Colors.white, child: img),
        if (!st.isUnlocked(shot)) ...[
          Positioned(
            left: (w - s) / 2,
            top: h * .655,
            width: s,
            height: s,
            child: Opacity(opacity: .55, child: CustomPaint(painter: LogoPainter(shColor: Colors.white, camColor: Colors.white, solidArc: true))),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: h * .655 + s + w * .005,
            child: Opacity(
              opacity: .6,
              child: Text('СЭЛФИ ШИНОСНОМА', textAlign: TextAlign.center, style: tx(w * .06, FontWeight.w800, Colors.white).copyWith(shadows: const [Shadow(color: Color(0x66000000), blurRadius: 4)])),
            ),
          ),
        ],
      ]);
    });
  }
}
