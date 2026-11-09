import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../flavor.dart';
import '../live_face.dart';
import '../main.dart';
import '../processing.dart';
import '../theme.dart';
import '../widgets/painters.dart';

/// Real phone camera: face oval, night boost, screen light, timer, front/back switch.
/// With [autoShoot] the countdown starts by itself (used when a timer chip is chosen).
class CameraScreen extends StatefulWidget {
  final bool autoShoot;
  const CameraScreen({super.key, this.autoShoot = false});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> cams = [];
  CameraController? ctrl;
  bool front = true, night = false, light = false, good = false, counting = false, flash = false, captured = false, failed = false, checking = false;
  List<String>? rejected; // problems found in the last shot (l10n keys)
  int? count;
  String? label;
  Timer? _labelT;
  // live face guide
  FaceFit fit = FaceFit.none;
  bool _live = false, _frameBusy = false;
  int _lastCheck = 0;
  int? _rot; // turn that makes frames upright, found from the first frames with a face
  Uint8List? _detModel;
  Size _screen = Size.zero;
  bool _switching = false; // a camera is being closed/opened: ignore extra taps

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  /// Leaving the app releases the camera (Android gives it to other apps); coming back opens it again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (cams.isEmpty) return;
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
      _close();
    } else if (s == AppLifecycleState.resumed && ctrl == null && !_switching) {
      _open();
    }
  }

  Future<void> _init() async {
    try {
      cams = await availableCameras();
      _detModel = (await rootBundle.load('assets/models/face_detect.nnm')).buffer.asUint8List();
      await _open();
      if (widget.autoShoot) Future.delayed(const Duration(milliseconds: 700), _shoot);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  /// Closes the current camera completely (most phones can run only one camera at a time).
  Future<void> _close() async {
    final old = ctrl;
    if (old == null) return;
    if (mounted) setState(() => ctrl = null); // stop showing its preview first
    await _stopLive(old);
    try {
      await old.dispose();
    } catch (_) {}
  }

  /// Opens the front or back camera: the old one is fully closed first, then the new one is opened.
  /// If a phone refuses the high resolution, a lower one is tried.
  Future<void> _open() async {
    _switching = true;
    try {
      await _close();
      final want = front ? CameraLensDirection.front : CameraLensDirection.back;
      final cam = cams.firstWhere((c) => c.lensDirection == want, orElse: () => cams.first);
      CameraController? c;
      for (final res in [ResolutionPreset.high, ResolutionPreset.medium]) {
        final t = CameraController(cam, res, enableAudio: false, imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420);
        try {
          await t.initialize();
          c = t;
          break;
        } catch (_) {
          try {
            await t.dispose();
          } catch (_) {}
        }
      }
      if (c == null) {
        if (mounted) setState(() => failed = true);
        return;
      }
      _rot = null;
      if (night) await _applyNight(c);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        ctrl = c;
        failed = false;
        fit = FaceFit.none;
        good = false;
      });
      await _startLive();
    } finally {
      _switching = false;
    }
  }

  Future<void> _startLive() async {
    final c = ctrl;
    if (c == null || _live || _detModel == null) return;
    try {
      await c.startImageStream(_onFrame);
      _live = true;
    } catch (_) {
      _live = false; // no live frames on this phone: the oval stays a plain guide
    }
  }

  Future<void> _stopLive([CameraController? c]) async {
    final cc = c ?? ctrl;
    if (cc == null || !_live) return;
    _live = false;
    try {
      await cc.stopImageStream();
    } catch (_) {}
  }

  /// A few times a second: find the face in a small grey copy of the preview and judge the fit.
  Future<void> _onFrame(CameraImage frame) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_frameBusy || !mounted || counting || checking || now - _lastCheck < 350 || _screen == Size.zero) return;
    _frameBusy = true;
    _lastCheck = now;
    try {
      if (_rot == null) {
        // first find which turn makes this camera's frames upright
        const turns = [0, 90, 180, 270];
        final i = await bestTurnInBackground([for (final t in turns) smallGreyFrame(frame, t)], _detModel!);
        if (i != null) _rot = turns[i];
        _frameBusy = false;
        return;
      }
      final small = smallGreyFrame(frame, _rot!);
      final faces = await detectInBackground(small, _detModel!);
      final f = judge(faces, _screen, small.w / small.h, front);
      if (mounted && f != fit) {
        setState(() {
          fit = f;
          good = f == FaceFit.good;
        });
      }
    } catch (_) {}
    _frameBusy = false;
  }

  Future<void> _applyNight(CameraController c) async {
    try {
      final max = await c.getMaxExposureOffset();
      await c.setExposureOffset(night ? max * .6 : 0);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _live = false;
    _labelT?.cancel();
    ctrl?.dispose();
    super.dispose();
  }

  Future<void> _flip() async {
    if (cams.length < 2 || _switching || counting) return;
    final st = AppScope.of(context);
    setState(() => front = !front);
    await _open();
    if (!mounted || ctrl == null) return; // the message shows only when the camera really works
    setState(() => label = st.t(front ? 'camFront' : 'camBack'));
    _labelT?.cancel();
    _labelT = Timer(const Duration(milliseconds: 1400), () => mounted ? setState(() => label = null) : null);
  }

  Future<void> _shoot() async {
    final c = ctrl;
    if (c == null || !c.value.isInitialized || counting || _switching) return;
    final st = AppScope.of(context);
    setState(() => counting = true);
    for (var n = st.timer; n > 0; n--) {
      if (!mounted) return;
      setState(() => count = n);
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    setState(() {
      count = null;
      flash = true;
    });
    File? f;
    await _stopLive();
    try {
      final shot = await c.takePicture();
      final dir = await getApplicationDocumentsDirectory();
      f = await File(shot.path).copy('${dir.path}/raw_${DateTime.now().millisecondsSinceEpoch}.jpg');
      try {
        await File(shot.path).delete();
      } catch (_) {}
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      flash = false;
      checking = f != null;
    });
    if (f == null) {
      setState(() => counting = false);
      await _startLive();
      return;
    }
    // eyes closed, head turned, smiling, no face…: say why and don't keep the photo
    List<String> problems;
    try {
      problems = await PhotoProcessor.check(f);
    } catch (_) {
      problems = const [];
    }
    if (!mounted) return;
    if (problems.isNotEmpty) {
      try {
        await f.delete();
      } catch (_) {}
      setState(() {
        checking = false;
        counting = false;
        rejected = problems;
        fit = FaceFit.none;
        good = false;
      });
      return;
    }
    st.addCapture(f, 'u');
    setState(() {
      checking = false;
      captured = true;
    });
    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final c = ctrl;
    _screen = MediaQuery.sizeOf(context);
    // very large phone font settings are capped here so the camera controls always fit
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (c != null && c.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(width: c.value.previewSize!.height, height: c.value.previewSize!.width, child: CameraPreview(c)),
              ),
            if (failed)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(st.t('noCamera'), textAlign: TextAlign.center, style: tx(16, FontWeight.w700, Colors.white)),
                ),
              ),
            // screen light: a bright frame lights the face in the dark
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: light && front ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 26)),
                ),
              ),
            ),
            IgnorePointer(child: CustomPaint(painter: _OvalPainter(good))),
            Positioned(
              // hint sits just below the oval
              top: ovalRect(MediaQuery.of(context).size).bottom + 14,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(label ?? st.t(fitKey(fit)), textAlign: TextAlign.center, style: tx(13, FontWeight.w700, Colors.white)),
                    if (!kSuits && label == null) ...[
                      const SizedBox(height: 3),
                      Text(st.t('dressTip'), textAlign: TextAlign.center, style: tx(11, FontWeight.w600, Colors.white70)),
                    ],
                  ]),
                ),
              ),
            ),
            if (count != null)
              Center(
                child: Text(
                  '$count',
                  style: tx(150, FontWeight.w800, Colors.white).copyWith(shadows: const [Shadow(color: Colors.black54, blurRadius: 30)]),
                ),
              ),
            // top bar pinned to the top of the screen
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      _pill(icon: Icons.close, onTap: () => Navigator.of(context).pop()),
                      const SizedBox(width: 8),
                      // the three switches shrink together on narrow phones instead of running off the screen
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _pill(
                                  icon: Icons.nightlight_round,
                                  text: st.t('night'),
                                  on: night,
                                  onTap: () async {
                                    setState(() => night = !night);
                                    if (ctrl != null) await _applyNight(ctrl!);
                                  },
                                ),
                                const SizedBox(width: 8),
                                _pill(icon: Icons.light_mode_outlined, text: st.t('light'), on: light, onTap: () => setState(() => light = !light)),
                                const SizedBox(width: 8),
                                _pill(
                                  icon: Icons.timer_outlined,
                                  text: st.timer == 0 ? st.t('off') : '${st.timer} ${st.t('sec')}',
                                  on: st.timer > 0,
                                  onTap: () {
                                    const o = [0, 3, 5, 10];
                                    st.setTimer(o[(o.indexOf(st.timer) + 1) % o.length]);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 200 + MediaQuery.paddingOf(context).bottom,
                padding: EdgeInsets.fromLTRB(16, 30, 16, 26 + MediaQuery.paddingOf(context).bottom),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
                ),
                child: Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    GestureDetector(
                      onTap: _shoot,
                      child: Container(
                        width: 100,
                        height: 100,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 5),
                        ),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFDB55), Color(0xFFFFAE00)]),
                          ),
                          alignment: Alignment.center,
                          child: SizedBox(width: 62, height: 62, child: CustomPaint(painter: RgbCameraPainter())),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _pill(icon: Icons.cameraswitch_outlined, onTap: _flip, size: 52),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: flash ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: const ColoredBox(color: Colors.white),
              ),
            ),
            if (checking)
              Container(
                color: const Color(0x8C2E3654),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 5)),
                    const SizedBox(height: 18),
                    Text(st.t('checking'), style: tx(18, FontWeight.w800, Colors.white)),
                  ],
                ),
              ),
            if (rejected != null)
              Container(
                color: const Color(0xD92E3654),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFF6B6B), width: 7),
                      ),
                      child: const Icon(Icons.close_rounded, size: 70, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text(st.t('rejected'), textAlign: TextAlign.center, style: tx(20, FontWeight.w800, Colors.white)),
                    const SizedBox(height: 12),
                    for (final k in rejected!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• ${st.t(k)}', textAlign: TextAlign.center, style: tx(16, FontWeight.w700, const Color(0xFFFFD86B))),
                      ),
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: () {
                        setState(() => rejected = null);
                        _startLive();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                        decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(28)),
                        child: Text(st.t('retake'), style: tx(17, FontWeight.w800, C.ink)),
                      ),
                    ),
                  ],
                ),
              ),
            if (captured)
              Container(
                color: const Color(0x8C2E3654),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF3BE39B), width: 7),
                      ),
                      child: const Icon(Icons.check_rounded, size: 70, color: Colors.white),
                    ),
                    const SizedBox(height: 14),
                    Text(st.t('captured'), style: tx(22, FontWeight.w800, Colors.white)),
                    const SizedBox(height: 6),
                    Text(st.t('capturedSub'), style: tx(13, FontWeight.w500, Colors.white70)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill({required IconData icon, String? text, bool on = false, required VoidCallback onTap, double size = 44}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: size,
        constraints: BoxConstraints(minWidth: size),
        padding: EdgeInsets.symmetric(horizontal: text == null ? 0 : 12),
        decoration: BoxDecoration(color: on ? C.yellow : Colors.white24, borderRadius: BorderRadius.circular(size / 2)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: on ? C.ink : Colors.white),
            if (text != null) ...[const SizedBox(width: 6), Text(text, maxLines: 1, softWrap: false, style: tx(12, FontWeight.w700, on ? C.ink : Colors.white))],
          ],
        ),
      ),
    );
  }
}

class _OvalPainter extends CustomPainter {
  final bool good;
  _OvalPainter(this.good);
  @override
  void paint(Canvas canvas, Size size) {
    final r = ovalRect(size);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = good ? const Color(0xFF3BE39B) : Colors.white;
    if (good) {
      canvas.drawOval(r, p);
    } else {
      final path = Path()..addOval(r);
      for (final m in path.computeMetrics()) {
        for (double d = 0; d < m.length; d += 18) {
          canvas.drawPath(m.extractPath(d, d + 10), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_OvalPainter o) => o.good != good;
}
