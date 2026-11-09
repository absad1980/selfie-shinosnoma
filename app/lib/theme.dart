import 'package:flutter/material.dart';

/// Design tokens (neumorphic light theme).
class C {
  static const ink = Color(0xFF2E3654);
  static const ink2 = Color(0xFF5A6382);
  static const mute = Color(0xFF98A0B8);
  static const paper = Color(0xFFE9EDF4);
  static const hi = Color(0xFFFFFFFF);
  static const lo = Color(0xFFAEB7CA);
  static const zoneL = Color(0xFFD3DEF3);
  static const zoneR = Color(0xFFE9E1F7);
  static const indigo = Color(0xFF6A7BEF);
  static const violet = Color(0xFF5E5BD8);
  static const pink = Color(0xFFD77FD0);
  static const sky = Color(0xFF8DB7F5);
  static const mint = Color(0xFF8ED9B5);
  static const ok = Color(0xFF4FBF8F);
  static const yellow = Color(0xFFFFC21A);
  static const red = Color(0xFFEF3B4A);
  static const green = Color(0xFF22B45E);
  static const blue = Color(0xFF2F6DF0);
}

/// Montserrat is bundled as a variable font, so weight is passed as a font variation too.
TextStyle tx(double size, FontWeight w, [Color color = C.ink, double? spacing]) => TextStyle(
      fontFamily: 'Montserrat',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: color,
      letterSpacing: spacing,
      height: 1.25,
    );

/// Raised neumorphic shadow pair.
List<BoxShadow> outShadow([double d = 7]) => [
      BoxShadow(color: C.lo, offset: Offset(d, d), blurRadius: d * 2.2),
      BoxShadow(color: C.hi, offset: Offset(-d, -d), blurRadius: d * 2.2),
    ];

/// Flat "pressed-in" look (Flutter has no inset shadow, so a soft inner gradient stands in).
BoxDecoration insetDeco(double radius) => BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFD9DFEA), Color(0xFFF2F5FA)],
      ),
    );

BoxDecoration raisedDeco(double radius, {Color color = C.paper, double d = 5}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: outShadow(d),
    );

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: C.paper,
      fontFamily: 'Montserrat',
      colorScheme: ColorScheme.fromSeed(seedColor: C.indigo, surface: C.paper),
    );
