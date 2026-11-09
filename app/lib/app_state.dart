import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'flavor.dart';
import 'l10n.dart';

/// Document sizes for Tajikistan only (millimetres).
class Preset {
  final String id;
  final int w, h;
  const Preset(this.id, this.w, this.h);
  double get ratio => w / h;
}

const presets = [
  Preset('tj', 35, 45),
  Preset('s34', 30, 40),
  Preset('s3545', 35, 45),
  Preset('s46', 40, 60),
];

/// "Bad conditions" a raw selfie can have, used to show what rework fixes.
class RawFx {
  final bool cast, night, harsh;
  final int shadow; // -1 left, 0 none, 1 right
  const RawFx({this.cast = false, this.night = false, this.harsh = false, this.shadow = 0});
}

class RawShot {
  final int id;
  final String gender; // 'm' or 'f'
  final String? asset; // bundled sample photo (assets/samples/<name>.jpg)
  final File? file; // real camera capture
  final String fileName;
  final RawFx fx;
  final double tilt;
  bool processed;
  int suit; // index into the suit list for the gender (every photo gets a suit)
  File? done; // processed result for real camera photos
  String? doneKey; // size+background the result was made for
  RawShot({
    required this.id,
    required this.gender,
    this.asset,
    this.file,
    required this.fileName,
    this.fx = const RawFx(),
    this.tilt = 0,
    this.processed = false,
    required this.suit,
  });
}

class AppState extends ChangeNotifier {
  String lang = 'tg'; // Tajik on first install, whatever the phone language is
  final List<RawShot> items = [];
  int sel = 0;
  String presetId = 'tj';
  String bg = 'white';
  int timer = 0;
  String fmt = 'JPEG';
  int dpi = 600;
  String layout = 'single'; // 'single', 's10', 'a4'
  bool autodel = true;

  /// At start-up: load the auto-delete choice and, if on, delete the app's own raw shots and
  /// reworked copies older than 7 days. Saved results in Pictures/Download are never touched.
  Future<void> housekeeping() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final cfg = File('${docs.path}/settings.json');
      if (await cfg.exists()) {
        final m = jsonDecode(await cfg.readAsString()) as Map<String, dynamic>;
        autodel = m['autodel'] as bool? ?? true;
        plan = m['plan'] as String?;
        planUntil = (m['planUntil'] as num?)?.toDouble();
        payPhone = m['payPhone'] as String? ?? '';
        notifyListeners();
      }
      if (!autodel) return;
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      await for (final e in docs.list()) {
        final name = e.uri.pathSegments.last;
        if (e is File && (name.startsWith('raw_') || name.startsWith('done_')) && (await e.lastModified()).isBefore(cutoff)) {
          await e.delete();
        }
      }
    } catch (_) {}
  }

  Future<void> setAutodel(bool v) async {
    update(() => autodel = v);
    await saveSettings();
    if (v) await housekeeping();
  }

  /// Receiving number for e-wallet payments (the owner's number).
  static const ownerNumber = '+992 98 544 67 44';

  void update(void Function() f) {
    f();
    notifyListeners();
  }
  String? plan; // null, 'month', 'life'
  double? planUntil; // monthly plan end (seconds since epoch)
  String payPhone = ''; // the customer's +992 number used for payments (9 digits)
  int _seq = 0;

  Preset get preset => presets.firstWhere((p) => p.id == presetId);
  RawShot? get current => items.isEmpty ? null : items[sel.clamp(0, items.length - 1)];
  bool get planActive => plan == 'life' || (plan == 'month' && (planUntil ?? 0) * 1000 > DateTime.now().millisecondsSinceEpoch);
  /// The owner app is always free: no plans, no payment, no watermark.
  bool isUnlocked(RawShot s) => kOwnerApp || planActive;

  String t(String key, [String? n]) => tr(lang, key, n);
  /// Captured photos have unknown gender ('u'), so both lists are offered.
  List<String> suitsFor(String g) => g == 'u' ? [...suitNames[lang]!['m']!, ...suitNames[lang]!['f']!] : suitNames[lang]![g]!;

  /// Pixel size and estimated file size of the single finished photo.
  ({int w, int h}) get outPx => (w: (preset.w / 25.4 * dpi).round(), h: (preset.h / 25.4 * dpi).round());
  String get sizeEstimate {
    final px = outPx.w * outPx.h;
    const f = {'JPEG': .19, 'PNG': 1.55, 'WebP': .12, 'HEIC': .1};
    final b = fmt == 'PDF' ? px * .19 + 12000 : px * (f[fmt] ?? .19);
    final ru = lang != 'en';
    if (b < 1048576) return '${(b / 1024).round()} ${ru ? 'КБ' : 'KB'}';
    final m = (b / 1048576).toStringAsFixed(1);
    return '${ru ? m.replaceAll('.', ',') : m} ${ru ? 'МБ' : 'MB'}';
  }
  String suitName(RawShot s) => s.suit < 0 ? t('own') : suitsFor(s.gender)[s.suit];

  /// Photo shown as the reworked result (sample suit photos stand in for the suit engine).
  String resultAsset(RawShot s) {
    if (s.suit < 0) return s.asset ?? (s.gender == 'm' ? 'man' : 'woman');
    return '${s.gender == 'm' ? 'm' : 'w'}${(s.suit + 1).toString().padLeft(2, '0')}';
  }

  String _time(int mins) => '${(mins ~/ 60).toString().padLeft(2, '0')}${(mins % 60).toString().padLeft(2, '0')}';

  AppState() {
    // Every sample AI photo starts as a raw shot.
    final names = ['man', 'woman', for (var n = 1; n <= 10; n++) 'm${n.toString().padLeft(2, '0')}', for (var n = 1; n <= 9; n++) 'w${n.toString().padLeft(2, '0')}'];
    const fxs = [
      RawFx(cast: true, shadow: -1),
      RawFx(night: true),
      RawFx(shadow: 1, harsh: true),
      RawFx(cast: true),
      RawFx(shadow: -1),
      RawFx(harsh: true),
    ];
    const tilts = [-.03, .025, -.02, .03, .015, -.025];
    for (var i = names.length - 1; i >= 0; i--) {
      final ph = names[i];
      final g = ph.startsWith('m') ? 'm' : 'f';
      _seq++;
      final suit = !kSuits ? -1 : (RegExp(r'^[mw]\d\d$').hasMatch(ph) ? int.parse(ph.substring(1)) - 1 : (g == 'm' ? 9 : 8));
      items.insert(
        0,
        RawShot(
          id: _seq,
          gender: g,
          asset: ph,
          fileName: 'IMG_${_time(8 * 60 + 5 + i * 17)}${((_seq * 23 + 7) % 60).toString().padLeft(2, '0')}.jpg',
          fx: fxs[i % 6],
          tilt: tilts[i % 6],
          processed: i == 0,
          suit: suit,
        ),
      );
    }
  }

  void setLang(String l) {
    lang = l;
    notifyListeners();
  }

  void cycleLang() => setLang(langs[(langs.indexOf(lang) + 1) % langs.length]);

  void select(int i) {
    if (items.isEmpty) return;
    final n = i.clamp(0, items.length - 1);
    if (n != sel) {
      sel = n;
      notifyListeners();
    }
  }

  void setPreset(String id) {
    presetId = id;
    notifyListeners();
  }

  void setBg(String b) {
    bg = b;
    notifyListeners();
  }

  void setSuit(int s) {
    current?.suit = s;
    notifyListeners();
  }

  void setTimer(int s) {
    timer = s;
    notifyListeners();
  }

  void markProcessed(RawShot s) {
    s.processed = true;
    notifyListeners();
  }

  void deleteAt(int i) {
    if (i < 0 || i >= items.length) return;
    items.removeAt(i);
    sel = items.isEmpty ? 0 : i.clamp(0, items.length - 1);
    notifyListeners();
  }

  /// A real photo taken with the phone camera becomes a new raw shot at the top.
  void addCapture(File f, String gender) {
    _seq++;
    final now = DateTime.now();
    final stamp = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    items.insert(0, RawShot(id: _seq, gender: gender, file: f, fileName: 'IMG_$stamp.jpg', suit: kSuits ? 0 : -1));
    sel = 0;
    notifyListeners();
  }

  /// The owner's activation code was accepted: monthly (until [until]) or lifetime.
  void activate({required String plan, DateTime? until, required String phone}) {
    this.plan = plan;
    planUntil = until == null ? null : until.millisecondsSinceEpoch / 1000;
    payPhone = phone;
    notifyListeners();
    saveSettings();
  }

  /// Settings kept on the phone between launches (auto-delete, plan, payment phone).
  Future<void> saveSettings() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      await File('${docs.path}/settings.json').writeAsString(jsonEncode({
        'autodel': autodel,
        'plan': plan,
        'planUntil': planUntil,
        'payPhone': payPhone,
      }));
    } catch (_) {}
  }

  String fmtSize(Preset p) {
    String f(int v) {
      final s = v % 10 == 0 ? (v ~/ 10).toString() : (v / 10).toStringAsFixed(1);
      return lang == 'en' ? s : s.replaceAll('.', ',');
    }

    return '${f(p.w)} × ${f(p.h)} ${lang == 'en' ? 'cm' : 'см'}';
  }
}
