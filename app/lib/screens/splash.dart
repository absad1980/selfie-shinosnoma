import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import 'legal_sheet.dart';
import '../theme.dart';
import '../widgets/painters.dart';
import 'home.dart';

/// Logo screen: the monogram draws itself, then home opens after ~3.3 s.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3300))..forward();

  @override
  void initState() {
    super.initState();
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (_, _, _) => const HomeScreen(),
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
        ));
      }
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return Scaffold(
      body: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          final t = c.value * 3.3; // seconds
          final arc = Curves.easeInOutCubic.transform(_seg(t, .15, 1.25));
          final bars = Curves.easeOutBack.transform(_seg(t, .75, 1.3)).clamp(0.0, 1.2);
          final cam = Curves.easeOutBack.transform(_seg(t, 1.35, 1.8));
          final name = _seg(t, 1.5, 2.1), tag = _seg(t, 1.85, 2.45), legal = _seg(t, 1.9, 2.5);
          return Container(
            decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(0, -.25), radius: 1.1, colors: [Color(0xFFF4F6FA), C.paper])),
            child: SafeArea(
              child: Stack(children: [
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(color: C.paper, borderRadius: BorderRadius.circular(60), boxShadow: outShadow(14)),
                      alignment: Alignment.center,
                      child: SizedBox(width: 184, height: 184, child: CustomPaint(painter: LogoPainter(arc: arc, bars: bars, cam: cam))),
                    ),
                    const SizedBox(height: 22),
                    Opacity(
                      opacity: name,
                      child: Transform.translate(
                        offset: Offset(0, 8 * (1 - name)),
                        child: Column(children: [
                          Text('СЭЛФИ', style: tx(25, FontWeight.w800, C.ink, 1.5)),
                          const SizedBox(height: 4),
                          Text('ШИНОСНОМА', style: tx(13, FontWeight.w600, C.ink2, 4.6)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Opacity(opacity: tag, child: Text(st.t('tagline'), style: tx(13, FontWeight.w500, C.mute))),
                  ]),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 90,
                  child: Center(
                    child: Container(
                      width: 120,
                      height: 8,
                      decoration: insetDeco(4),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: c.value,
                        child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), gradient: const LinearGradient(colors: [C.sky, C.indigo, C.pink]))),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 28,
                  right: 28,
                  bottom: 36,
                  child: Opacity(opacity: legal, child: _LegalLine(st.t('legalLine'), st.t('termsLink'), st.t('privacyLink'))),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _LegalLine extends StatelessWidget {
  final String line, terms, privacy;
  const _LegalLine(this.line, this.terms, this.privacy);

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final link = tx(11.5, FontWeight.w700, C.indigo).copyWith(decoration: TextDecoration.underline);
    final base = tx(11.5, FontWeight.w600, C.ink2);
    final a = line.split('{terms}');
    final b = a.length > 1 ? a[1].split('{privacy}') : ['', ''];
    // tapping a link opens that page (the logo screen pauses while it's open)
    Future<void> open(String kind) async {
      final ctrl = context.findAncestorStateOfType<_SplashScreenState>()?.c;
      ctrl?.stop();
      await openLegal(context, st, kind);
      ctrl?.forward();
    }

    return Text.rich(
      TextSpan(style: base, children: [
        TextSpan(text: a[0]),
        TextSpan(text: terms, style: link, recognizer: TapGestureRecognizer()..onTap = () => open('terms')),
        TextSpan(text: b[0]),
        TextSpan(text: privacy, style: link, recognizer: TapGestureRecognizer()..onTap = () => open('privacy')),
        if (b.length > 1) TextSpan(text: b[1]),
      ]),
      textAlign: TextAlign.center,
    );
  }
}
