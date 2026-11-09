import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme.dart';
import 'photos.dart';

/// "Working on your photo" card: scan line reveals the result while each step ticks off (~1.45 s).
class ReworkOverlay extends StatefulWidget {
  final RawShot shot;
  final AppState st;
  final Future<void>? work; // real processing; the card stays until it finishes
  const ReworkOverlay({super.key, required this.shot, required this.st, this.work});
  @override
  State<ReworkOverlay> createState() => _ReworkOverlayState();
}

class _ReworkOverlayState extends State<ReworkOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    Future.wait([c.forward().orCancel.catchError((_) {}), widget.work ?? Future.value()]).whenComplete(() async {
      if (mounted) setState(() {}); // show the finished result
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.st;
    final steps = ['st_face', 'st_light', 'st_shadow', 'st_red', 'st_bg', if (widget.shot.suit >= 0) 'st_suit', 'st_crop'];
    final r = st.preset.ratio;
    const ph = 193.0;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 338,
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          decoration: raisedDeco(28, d: 8),
          child: AnimatedBuilder(
            animation: c,
            builder: (context, _) {
              final k = c.value;
              final idx = (k * steps.length).floor();
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: ph * r,
                  height: ph,
                  decoration: raisedDeco(14, d: 4),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(fit: StackFit.expand, children: [
                    RawShotImage(widget.shot),
                    ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: k, child: SizedBox(height: ph, child: ResultImage(widget.shot, st)))),
                    Positioned(
                      top: ph * k - 1.5,
                      left: 0,
                      right: 0,
                      height: 3,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [Colors.transparent, C.indigo, C.pink, Colors.transparent]),
                          boxShadow: [BoxShadow(color: Color(0x996A7BEF), blurRadius: 14, spreadRadius: 3)],
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Text(st.t('working'), style: tx(18, FontWeight.w800)),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(colors: [C.violet, C.pink]).createShader(b),
                  child: Text('${(k * 100).round()}%', style: tx(38, FontWeight.w800, Colors.white)),
                ),
                const SizedBox(height: 6),
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.5),
                    child: Row(children: [
                      _dot(i < idx || k >= 1 ? 2 : (i == idx ? 1 : 0)),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          steps[i] == 'st_crop' ? '${st.t('st_crop')} ${st.fmtSize(st.preset)}' : st.t(steps[i]),
                          style: tx(15.5, FontWeight.w600, i <= idx ? C.ink : C.mute),
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.lock_outline, size: 14, color: C.ok),
                  const SizedBox(width: 6),
                  Text(st.t('ondevice'), style: tx(12.5, FontWeight.w700, C.ok)),
                ]),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _dot(int state) {
    if (state == 2) {
      return Container(width: 20, height: 20, decoration: const BoxDecoration(shape: BoxShape.circle, color: C.ok), child: const Icon(Icons.check, size: 14, color: Colors.white));
    }
    if (state == 1) {
      return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: C.indigo));
    }
    return Container(width: 20, height: 20, decoration: insetDeco(10));
  }
}
