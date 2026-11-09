import 'dart:async';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../l10n.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/painters.dart';
import '../widgets/photos.dart';
import '../widgets/rework.dart';
import '../processing.dart';
import 'camera.dart';
import '../flavor.dart';
import 'owner_sheet.dart';
import 'settings_sheet.dart';

void showToast(BuildContext context, String msg) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: C.paper,
    elevation: 6,
    margin: const EdgeInsets.fromLTRB(24, 0, 24, 140),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    duration: const Duration(milliseconds: 2200),
    content: Text(msg, textAlign: TextAlign.center, style: tx(13, FontWeight.w700)),
  ));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final list = ScrollController();
  Timer? _ownerT; // holding the logo opens owner mode
  late final AnimationController breathe = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  late final AnimationController shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  late final AnimationController btnShine = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat();
  late final AnimationController kyTween = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  double s = 1, boardH = 500, ky = 68;
  bool dragging = false, busy = false, _placed = false;
  Timer? _auto, _delHide;
  int? delIdx, removingIdx;

  double get itemH => 114 * s;
  double get padTop => 16 * s;
  double get thumbC => 50.5 * s;
  double get kMin => 40 * s;
  double get kMax => boardH - 40 * s;
  double center(int i) => padTop + i * itemH + thumbC - (list.hasClients ? list.offset : 0);

  @override
  void initState() {
    super.initState();
    list.addListener(() {
      if (!dragging && !kyTween.isAnimating) _pickNearest();
    });
  }

  @override
  void dispose() {
    for (final c in [breathe, shine, btnShine, kyTween]) {
      c.dispose();
    }
    _auto?.cancel();
    _delHide?.cancel();
    list.dispose();
    super.dispose();
  }

  AppState get st => AppScope.of(context);

  void _pickNearest() {
    final n = st.items.length;
    if (n == 0) return;
    final off = list.hasClients ? list.offset : 0;
    final i = ((ky + off - padTop - thumbC) / itemH).round().clamp(0, n - 1);
    if (i != st.sel) {
      setState(() => delIdx = null);
      st.select(i);
    }
  }

  void _scrollToIdx(int i, {bool animate = true}) {
    if (st.items.isEmpty) return;
    i = i.clamp(0, st.items.length - 1);
    var c = center(i);
    final lo = kMin + 30 * s, hi = kMax - 30 * s;
    if (list.hasClients && (c < lo || c > hi)) {
      final target = (list.offset + c - c.clamp(lo, hi)).clamp(0.0, list.position.maxScrollExtent);
      list.jumpTo(target);
      c = center(i);
    }
    st.select(i);
    final from = ky, to = c.clamp(kMin, kMax);
    if (!animate) {
      setState(() => ky = to);
      return;
    }
    kyTween
      ..stop()
      ..reset();
    final anim = CurvedAnimation(parent: kyTween, curve: Curves.easeOutCubic);
    void l() => setState(() => ky = from + (to - from) * anim.value);
    kyTween.addListener(l);
    kyTween.forward().whenComplete(() => kyTween.removeListener(l));
  }

  void _startAuto() {
    _auto?.cancel();
    _auto = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!list.hasClients) return;
      final z = 70 * s;
      double d = 0;
      if (ky < kMin + z) d = -(4 + (kMin + z - ky) * .35);
      if (ky > kMax - z) d = 4 + (ky - (kMax - z)) * .35;
      if (d != 0) {
        list.jumpTo((list.offset + d).clamp(0.0, list.position.maxScrollExtent));
        _pickNearest();
      }
    });
  }

  /// Runs the real on-phone processing for camera photos; returns problems found (l10n keys).
  Future<List<String>> _process(RawShot shot) async {
    final key = '${st.presetId}|${st.bg}|${shot.suit}';
    final sf = kSuits ? suitFile(shot.gender, shot.suit) : null;
    final suit = sf == null ? null : await SuitLayer.load(sf);
    final r = await PhotoProcessor.run(shot.file!, presetId: st.presetId, ratio: st.preset.ratio, bg: st.bg, suit: suit);
    if (r.file != null) {
      shot.done = r.file;
      shot.doneKey = key;
    }
    return r.problems;
  }

  Future<void> _rework() async {
    final shot = st.current;
    if (busy || shot == null) return;
    setState(() => busy = true);
    List<String> problems = [];
    final work = shot.file != null ? _process(shot).then((p) => problems = p).catchError((_) => problems = ['ck_noface']) : null;
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: C.paper.withValues(alpha: .86),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => ReworkOverlay(shot: shot, st: st, work: work),
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (shot.file != null && shot.done == null) {
      // no face found: stay unprocessed and say how to retake
      showToast(context, st.t(problems.isEmpty ? 'ck_noface' : problems.first));
      return;
    }
    st.markProcessed(shot);
    showToast(context, problems.isEmpty ? st.t('ready') : st.t('tipRetake', st.t(problems.first)));
  }

  /// A camera photo was reworked for another size/background: redo it in the background.
  Future<void> _refreshIfNeeded() async {
    final shot = st.current;
    if (shot == null || shot.file == null || !shot.processed || shot.doneKey == '${st.presetId}|${st.bg}|${shot.suit}' || busy) return;
    setState(() => busy = true);
    try {
      await _process(shot);
    } catch (_) {}
    if (!mounted) return;
    setState(() => busy = false);
    st.update(() {});
  }

  void _deleteAt(int i) {
    if (busy || removingIdx != null) return;
    setState(() {
      removingIdx = i;
      delIdx = null;
    });
    Future.delayed(const Duration(milliseconds: 330), () {
      if (!mounted) return;
      st.deleteAt(i);
      setState(() => removingIdx = null);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToIdx(st.sel));
      showToast(context, st.t('deleted'));
    });
  }

  void _showDel(int i) {
    _scrollToIdx(i);
    setState(() => delIdx = i);
    _delHide?.cancel();
    _delHide = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => delIdx = null);
    });
  }

  Future<void> _openCamera({bool auto = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CameraScreen(autoShoot: auto)));
    if (!mounted) return;
    if (list.hasClients) list.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToIdx(st.sel, animate: false));
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          s = c.maxWidth / 390;
          return Column(children: [
            _header(st),
            Expanded(child: LayoutBuilder(builder: (context, bc) {
              boardH = bc.maxHeight;
              if (!_placed) {
                _placed = true;
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToIdx(st.sel, animate: false));
              }
              ky = ky.clamp(kMin, kMax);
              return _board(st);
            })),
            _timerRow(st),
            SizedBox(height: 12 * s),
            _selfieButton(st),
            SizedBox(height: 18 * s),
          ]);
        }),
      ),
    );
  }

  Widget _header(AppState st) {
    return SizedBox(
      height: 66 * s,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14 * s),
        child: Row(children: [
          // owner app only: holding the logo for 3 s opens owner mode (PIN-protected)
          GestureDetector(
            onLongPressStart: kOwnerApp ? (_) => _ownerT = Timer(const Duration(seconds: 3), () => openOwnerMode(context, st)) : null,
            onLongPressEnd: kOwnerApp ? (_) => _ownerT?.cancel() : null,
            child: SizedBox(width: 56 * s, height: 56 * s, child: CustomPaint(painter: LogoPainter())),
          ),
          SizedBox(width: 6 * s),
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('СЭЛФИ', style: tx(16 * s, FontWeight.w800, C.ink, 1.4 * s)),
            Text('ШИНОСНОМА', style: tx(10.5 * s, FontWeight.w700, C.ink2, 2.6 * s)),
          ]),
          const Spacer(),
          GestureDetector(
            onTap: st.cycleLang,
            child: Container(
              height: 46 * s,
              padding: EdgeInsets.symmetric(horizontal: 12 * s),
              decoration: raisedDeco(23 * s, d: 4),
              child: Row(children: [
                Icon(Icons.language, size: 20 * s, color: C.indigo),
                SizedBox(width: 6 * s),
                Text(langChip[st.lang]!, style: tx(14 * s, FontWeight.w800, C.indigo)),
              ]),
            ),
          ),
          SizedBox(width: 8 * s),
          if (kOwnerApp) ...[
            _roundBtn(child: Icon(Icons.key_rounded, size: 22 * s, color: C.indigo), onTap: () => openOwnerMode(context, st)),
            SizedBox(width: 8 * s),
          ],
          _roundBtn(child: Icon(Icons.tune_rounded, size: 24 * s, color: C.ink), onTap: () => openSettings(context, st, (m) => showToast(context, m))),
        ]),
      ),
    );
  }

  Widget _roundBtn({required Widget child, required VoidCallback onTap, bool pressed = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48 * s,
          height: 48 * s,
          decoration: pressed ? insetDeco(24 * s) : raisedDeco(24 * s, d: 4),
          alignment: Alignment.center,
          child: child,
        ),
      );

  Widget _board(AppState st) {
    final paneW = 390 * s - 200 * s - 8 * s;
    return Stack(children: [
      Positioned.fill(child: CustomPaint(painter: CurvePainter(s: s, ky: ky))),
      // raw shots
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: 128 * s,
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent], stops: [0, .05, .95, 1]).createShader(r),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            controller: list,
            padding: EdgeInsets.symmetric(vertical: padTop),
            itemExtent: itemH,
            itemCount: st.items.length,
            itemBuilder: (context, i) => _rawItem(st, i),
          ),
        ),
      ),
      // ПАХШ triangle
      Positioned(
        left: 118 * s,
        top: ky - 40 * s,
        width: 80 * s,
        height: 80 * s,
        child: GestureDetector(
          onTap: _rework,
          onVerticalDragStart: (_) {
            kyTween.stop();
            dragging = true;
            _startAuto();
          },
          onVerticalDragUpdate: (d) {
            setState(() => ky = (ky + d.delta.dy).clamp(kMin, kMax));
            _pickNearest();
          },
          onVerticalDragEnd: (_) {
            dragging = false;
            _auto?.cancel();
            _scrollToIdx(st.sel);
          },
          child: AnimatedBuilder(
            animation: Listenable.merge([breathe, shine]),
            builder: (context, _) {
              // rests at real size, then swells to 110% with a blue glow (never shrinks)
              final t = breathe.value;
              final g = busy ? (0.5 - (t * 4 % 1 - .5).abs()) * 2 : (t < .4 ? 0.0 : (t < .7 ? Curves.easeInOut.transform((t - .4) / .3) : Curves.easeInOut.transform(1 - (t - .7) / .3)));
              return Transform.scale(
                scale: 1 + (busy ? .12 : .1) * g,
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF3F7EF6).withValues(alpha: .55 * g), blurRadius: 20 * s, spreadRadius: -6 * s)]),
                  child: CustomPaint(painter: KnobPainter(shine: shine.value, label: st.t('push'))),
                ),
              );
            },
          ),
        ),
      ),
      // result pane
      Positioned(left: 200 * s, right: 8 * s, top: 0, bottom: 0, child: _rightPane(st, paneW)),
    ]);
  }

  Widget _rawItem(AppState st, int i) {
    final shot = st.items[i];
    final sel = i == st.sel, del = delIdx == i;
    final w = 66 * s, h = 85 * s;
    final item = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (delIdx != i) setState(() => delIdx = null);
        _scrollToIdx(i);
      },
      onDoubleTap: () => _showDel(i),
      onLongPress: () => _showDel(i),
      child: Padding(
        padding: EdgeInsets.only(left: 12 * s, top: 8 * s),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(clipBehavior: Clip.none, children: [
            AnimatedScale(
              scale: sel ? 1.06 : 1,
              duration: const Duration(milliseconds: 250),
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10 * s),
                  boxShadow: sel
                      ? [const BoxShadow(color: C.paper, spreadRadius: 3), const BoxShadow(color: C.indigo, spreadRadius: 5), ...outShadow(5)]
                      : outShadow(4),
                ),
                child: ClipRRect(borderRadius: BorderRadius.circular(10 * s), child: RawShotImage(shot)),
              ),
            ),
            if (!del)
              Positioned(
                top: -5 * s,
                right: -5 * s,
                child: Container(
                  width: (shot.processed ? 17 : 12) * s,
                  height: (shot.processed ? 17 : 12) * s,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: shot.processed ? C.ok : C.yellow, border: Border.all(color: C.zoneL, width: 2.5)),
                  child: shot.processed ? Icon(Icons.check, size: 11 * s, color: Colors.white) : null,
                ),
              ),
            if (del)
              Positioned(
                top: -9 * s,
                right: -9 * s,
                child: GestureDetector(
                  onTap: () => _deleteAt(i),
                  child: Container(
                    width: 28 * s,
                    height: 28 * s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [Color(0xFFFF7070), Color(0xFFE0353B)]),
                      border: Border.all(color: C.zoneL, width: 2.5),
                      boxShadow: const [BoxShadow(color: Color(0x73E0353B), blurRadius: 8, offset: Offset(0, 3))],
                    ),
                    child: Icon(Icons.delete_outline_rounded, size: 16 * s, color: Colors.white),
                  ),
                ),
              ),
          ]),
          SizedBox(height: 6 * s),
          SizedBox(
            width: 104 * s,
            child: Text(shot.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(9.5 * s, FontWeight.w700, sel ? C.indigo : C.ink2)),
          ),
        ]),
      ),
    );
    final removing = removingIdx == i;
    return AnimatedSlide(
      offset: removing ? const Offset(-1.3, 0) : Offset.zero,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInCubic,
      child: AnimatedOpacity(opacity: removing ? 0 : 1, duration: const Duration(milliseconds: 300), child: item),
    );
  }

  Widget _rightPane(AppState st, double paneW) {
    final shot = st.current;
    final r = st.preset.ratio;
    var ch = 240 * s, cw = ch * r;
    if (cw > paneW) {
      cw = paneW;
      ch = cw / r;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dropdown<String>(
        label: st.t('size'),
        value: st.presetId,
        items: {for (final p in presets) p.id: '${st.t('c_${p.id}')} · ${st.fmtSize(p)}'},
        onChanged: (v) {
          st.setPreset(v);
          _refreshIfNeeded();
        },
      ),
      SizedBox(height: 10 * s),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        child: Container(
          key: ValueKey('${shot?.id}-${shot?.processed}-${shot?.suit}-${st.presetId}-${st.bg}-${shot != null && st.isUnlocked(shot)}'),
          width: cw,
          height: ch,
          decoration: shot != null && shot.processed ? raisedDeco(14 * s) : insetDeco(14 * s),
          clipBehavior: Clip.antiAlias,
          child: shot != null && shot.processed
              ? ResultImage(shot, st)
              : Padding(
                  padding: EdgeInsets.all(12 * s),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 46 * s,
                      height: 46 * s,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF9CCBFF), Color(0xFF3F7EF6), Color(0xFF1C3FC2)])),
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28 * s),
                    ),
                    SizedBox(height: 8 * s),
                    Text(st.t('empty'), textAlign: TextAlign.center, style: tx(11.5 * s, FontWeight.w600, C.ink2)),
                  ]),
                ),
        ),
      ),
      if (shot != null && shot.processed) ...[
        SizedBox(height: 10 * s),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 8 * s),
          decoration: insetDeco(14 * s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${st.fmt} · ≈ ${st.sizeEstimate}', style: tx(13 * s, FontWeight.w800)),
            Text('${st.outPx.w} × ${st.outPx.h} px · ${st.dpi} DPI', style: tx(11.5 * s, FontWeight.w700, C.indigo)),
          ]),
        ),
      ],
      SizedBox(height: 10 * s),
      _dropdown<String>(
        label: st.t('background'),
        value: st.bg,
        items: {for (final b in ['white', 'grey', 'blue']) b: st.t(b)},
        onChanged: (v) {
          st.setBg(v);
          _refreshIfNeeded();
        },
      ),
      SizedBox(height: 10 * s),
      if (shot != null && kSuits)
        _dropdown<int>(
          label: st.t('suit'),
          value: shot.suit,
          items: {for (var k = 0; k < st.suitsFor(shot.gender).length; k++) k: st.suitsFor(shot.gender)[k]},
          onChanged: (v) {
            st.setSuit(v);
            _refreshIfNeeded();
          },
        ),
    ]);
  }

  Widget _dropdown<T>({required String label, required T value, required Map<T, String> items, required ValueChanged<T> onChanged}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: tx(11 * s, FontWeight.w700, C.mute, 1.3 * s)),
      SizedBox(height: 5 * s),
      Container(
        height: 46 * s,
        padding: EdgeInsets.only(left: 13 * s, right: 8 * s),
        decoration: raisedDeco(14 * s, d: 4),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            value: value,
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: C.indigo, size: 22 * s),
            dropdownColor: C.paper,
            borderRadius: BorderRadius.circular(14),
            style: tx(13.5 * s, FontWeight.w700),
            items: [for (final e in items.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    ]);
  }

  Widget _timerRow(AppState st) {
    Widget chip(int v) {
      final on = st.timer == v;
      return GestureDetector(
        onTap: () {
          st.setTimer(v);
          if (v > 0) _openCamera(auto: true); // a timer choice opens the camera and shoots by itself
        },
        child: Container(
          height: 42 * s,
          constraints: BoxConstraints(minWidth: 58 * s),
          padding: EdgeInsets.symmetric(horizontal: 10 * s),
          alignment: Alignment.center,
          decoration: on ? insetDeco(21 * s) : raisedDeco(21 * s, d: 4),
          child: Text(v == 0 ? st.t('off') : '$v ${st.t('sec')}', style: tx(13.5 * s, FontWeight.w700, on ? C.indigo : C.ink2)),
        ),
      );
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(st.t('timer').toUpperCase(), style: tx(10 * s, FontWeight.w700, C.mute, 1.3 * s)),
      SizedBox(width: 8 * s),
      for (final v in [0, 3, 5, 10]) ...[chip(v), SizedBox(width: 8 * s)],
    ]);
  }

  Widget _selfieButton(AppState st) {
    final fs = st.lang == 'ru' ? 27.0 : st.lang == 'en' ? 38.0 : 33.0;
    return GestureDetector(
      onTap: () => _openCamera(),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 20 * s),
        height: 90 * s,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(45 * s),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFDB55), Color(0xFFFFC21A), Color(0xFFFFAE00)], stops: [0, .55, 1]),
          boxShadow: outShadow(9),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 80 * s,
                height: 80 * s,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE58A), Color(0xFFFFB300)])),
                alignment: Alignment.center,
                child: SizedBox(width: 72 * s, height: 72 * s, child: CustomPaint(painter: RgbCameraPainter())),
              ),
              SizedBox(width: 12 * s),
              Text(st.t('take'), style: tx(fs * s, FontWeight.w800)),
            ]),
          ),
          // slow light sweep from left to right
          AnimatedBuilder(
            animation: btnShine,
            builder: (context, _) {
              final p = (btnShine.value / .55).clamp(0.0, 1.0);
              return Positioned(
                left: (-0.45 + 1.7 * Curves.easeInOut.transform(p)) * 350 * s,
                top: -10,
                bottom: -10,
                width: 120 * s,
                child: Transform(
                  transform: Matrix4.skewX(-.35),
                  child: const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0x00FFFFFF), Color(0xB3FFFFFF), Color(0x00FFFFFF)]))),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }
}
