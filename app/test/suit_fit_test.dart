import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:selfie_shinosnoma/processing.dart';

/// Puts suits on the two base photos (grey t-shirts) and saves the results for a visual check.
/// Face boxes are given by hand here; on the phone ML Kit measures them.
void main() {
  final anchors = jsonDecode(File('assets/suits/anchors.json').readAsStringSync()) as Map<String, dynamic>;
  SuitLayer layer(String n) {
    return SuitLayer.fromJson(File('assets/suits/$n.png').readAsBytesSync(), anchors[n] as Map<String, dynamic>);
  }

  void fit(String person, List<double> face, String suit) {
    final src = img.decodeJpg(File('assets/samples/$person.jpg').readAsBytesSync())!;
    final rgba = src.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
    // stand-in for ML Kit's person mask: the plain light backdrop is "not person"
    final mask = Float32List(src.width * src.height);
    for (final p in src) {
      final mx = [p.r, p.g, p.b].reduce((a, b) => a > b ? a : b).toDouble(), mn = [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b).toDouble();
      final lum = .299 * p.r + .587 * p.g + .114 * p.b;
      mask[p.y * src.width + p.x] = (lum > 205 && (mx - mn) < 22) ? 0 : 1;
    }
    final out = processPixelsForTest(rgba, src.width, src.height, face, suit: layer(suit), mask: mask);
    Directory('build/test_out').createSync(recursive: true);
    File('build/test_out/fit_${person}_$suit.jpg').writeAsBytesSync(out);
  }

  test('suits fit the base photos', () {
    for (final s in ['m01', 'm04', 'm06', 'm10']) {
      fit('man', [102, 105, 252, 292], s);
    }
    for (final s in ['w02', 'w06', 'w09']) {
      fit('woman', [100, 100, 258, 292], s);
    }
  });
}

