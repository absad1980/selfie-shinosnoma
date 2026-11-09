import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show Canvas, Paint, FilterQuality, PaintingStyle;
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gal/gal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'app_state.dart';

/// Paper sizes for print sheets (mm).
const sheetSizes = {'s10': (w: 100.0, h: 150.0), 'a4': (w: 210.0, h: 297.0)};

({int cols, int rows, int n}) sheetCount(Preset p, double pw, double ph) {
  const m = 3.0, g = 3.0;
  final cols = ((pw - 2 * m + g) / (p.w + g)).floor(), rows = ((ph - 2 * m + g) / (p.h + g)).floor();
  return (cols: cols, rows: rows, n: cols * rows);
}

class Exporter {
  final AppState st;
  final RawShot shot;
  Exporter(this.st, this.shot);

  Future<ui.Image> _source() async {
    final bytes = shot.file != null ? await (shot.done ?? shot.file!).readAsBytes() : (await rootBundle.load('assets/samples/${st.resultAsset(shot)}.jpg')).buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }

  /// The finished photo at exact print pixels (e.g. 827×1063 for 3,5×4,5 cm at 600 DPI).
  Future<ui.Image> renderPhoto() async {
    final src = await _source();
    final w = st.outPx.w, h = st.outPx.h;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
    // cover-crop, keeping the top (head) in frame
    final scale = (w / src.width) > (h / src.height) ? w / src.width : h / src.height;
    final sw = w / scale, sh = h / scale;
    final sx = (src.width - sw) / 2;
    c.drawImageRect(src, Rect.fromLTWH(sx, 0, sw, sh), Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..filterQuality = FilterQuality.high);
    return rec.endRecording().toImage(w, h);
  }

  /// Several copies on 10×15 or A4 paper, with thin cut lines.
  Future<ui.Image> renderSheet(String layout, ui.Image photo) async {
    final paper = sheetSizes[layout]!;
    final ppm = st.dpi / 25.4;
    final W = (paper.w * ppm).round(), H = (paper.h * ppm).round();
    final p = st.preset;
    final cnt = sheetCount(p, paper.w, paper.h);
    const g = 3.0;
    final gw = cnt.cols * p.w + (cnt.cols - 1) * g, gh = cnt.rows * p.h + (cnt.rows - 1) * g;
    final ox = (paper.w - gw) / 2, oy = (paper.h - gh) / 2;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
    final line = Paint()
      ..color = const Color(0xFFC9CFDD)
      ..strokeWidth = 1;
    for (var r = 0; r < cnt.rows; r++) {
      for (var k = 0; k < cnt.cols; k++) {
        final dst = Rect.fromLTWH((ox + k * (p.w + g)) * ppm, (oy + r * (p.h + g)) * ppm, p.w * ppm, p.h * ppm);
        c.drawImageRect(photo, Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.high);
        c.drawRect(dst.inflate(.5), line..style = PaintingStyle.stroke);
      }
    }
    return rec.endRecording().toImage(W, H);
  }

  Future<Uint8List> _png(ui.Image img) async => (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

  /// Encodes to the chosen format and writes the DPI so printers use the true size.
  Future<Uint8List> encodeImage(ui.Image img) async {
    final png = await _png(img);
    switch (st.fmt) {
      case 'PNG':
        return _pngWithDpi(png, st.dpi);
      case 'WebP':
        return FlutterImageCompress.compressWithList(png, quality: 92, format: CompressFormat.webp, keepExif: false);
      case 'HEIC':
        return FlutterImageCompress.compressWithList(png, quality: 92, format: CompressFormat.heic, keepExif: false);
      default:
        final jpg = await FlutterImageCompress.compressWithList(png, quality: 95, format: CompressFormat.jpeg, keepExif: false);
        return _jpegWithDpi(jpg, st.dpi);
    }
  }

  /// PDF: one photo or a print sheet, every photo placed at its real size in millimetres.
  Future<Uint8List> buildPdf(String layout, ui.Image photo) async {
    final p = st.preset;
    final jpg = _jpegWithDpi(await FlutterImageCompress.compressWithList(await _png(photo), quality: 95, format: CompressFormat.jpeg), st.dpi);
    final img = pw.MemoryImage(jpg);
    final doc = pw.Document(title: 'СЭЛФИ ШИНОСНОМА', creator: 'СЭЛФИ ШИНОСНОМА');
    if (layout == 'single') {
      doc.addPage(pw.Page(pageFormat: PdfPageFormat(p.w * PdfPageFormat.mm, p.h * PdfPageFormat.mm), build: (_) => pw.Image(img, fit: pw.BoxFit.fill)));
    } else {
      final paper = sheetSizes[layout]!;
      final cnt = sheetCount(p, paper.w, paper.h);
      const g = 3.0;
      final gw = cnt.cols * p.w + (cnt.cols - 1) * g, gh = cnt.rows * p.h + (cnt.rows - 1) * g;
      final ox = (paper.w - gw) / 2, oy = (paper.h - gh) / 2;
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(paper.w * PdfPageFormat.mm, paper.h * PdfPageFormat.mm),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(children: [
          for (var r = 0; r < cnt.rows; r++)
            for (var k = 0; k < cnt.cols; k++)
              pw.Positioned(
                left: (ox + k * (p.w + g)) * PdfPageFormat.mm,
                top: (oy + r * (p.h + g)) * PdfPageFormat.mm,
                child: pw.Container(
                  width: p.w * PdfPageFormat.mm,
                  height: p.h * PdfPageFormat.mm,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromInt(0xFFC9CFDD), width: .3)),
                  child: pw.Image(img, fit: pw.BoxFit.fill),
                ),
              ),
        ]),
      ));
    }
    return doc.save();
  }

  /// Produces the file bytes for the current format and layout.
  Future<({Uint8List bytes, String name, String mime})> build() async {
    final photo = await renderPhoto();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final size = '${(st.preset.w / 10).toString().replaceAll('.0', '')}x${(st.preset.h / 10).toString().replaceAll('.0', '')}';
    final base = 'Selfie_Shinosnoma_${size}cm_${st.dpi}dpi_$stamp';
    if (st.fmt == 'PDF') return (bytes: await buildPdf(st.layout, photo), name: '$base.pdf', mime: 'application/pdf');
    final img = st.layout == 'single' ? photo : await renderSheet(st.layout, photo);
    final ext = {'JPEG': 'jpg', 'PNG': 'png', 'WebP': 'webp', 'HEIC': 'heic'}[st.fmt]!;
    final mime = {'JPEG': 'image/jpeg', 'PNG': 'image/png', 'WebP': 'image/webp', 'HEIC': 'image/heic'}[st.fmt]!;
    return (bytes: await encodeImage(img), name: '$base.$ext', mime: mime);
  }

  Future<File> _temp(Uint8List bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// Saves to Pictures (images) and Download (all formats). Returns where it went,
  /// or null when those folders weren't usable and the customer must pick one.
  Future<String?> save() async {
    final out = await build();
    final f = await _temp(out.bytes, out.name);
    final isImage = st.fmt != 'PDF';
    try {
      if (Platform.isAndroid) {
        await MediaStore.ensureInitialized();
        MediaStore.appFolder = 'Selfie Shinosnoma';
        final ms = MediaStore();
        var ok = false;
        if (isImage) ok = (await ms.saveFile(tempFilePath: f.path, dirType: DirType.photo, dirName: DirName.pictures)) != null;
        final f2 = await _temp(out.bytes, out.name); // saveFile moves the temp file
        final dl = (await ms.saveFile(tempFilePath: f2.path, dirType: DirType.download, dirName: DirName.download)) != null;
        if (ok || dl) return isImage ? 'Pictures · Download' : 'Download';
      } else {
        // iPhone: Photos for images, plus the app's folder in the Files app
        if (isImage) await Gal.putImageBytes(out.bytes, album: 'СЭЛФИ ШИНОСНОМА');
        final docs = await getApplicationDocumentsDirectory();
        await File('${docs.path}/${out.name}').writeAsBytes(out.bytes, flush: true);
        return isImage ? 'Photos · Files' : 'Files';
      }
    } catch (_) {}
    return null;
  }

  /// Fallback: the phone's own folder chooser.
  Future<String?> saveWithPicker() async {
    final out = await build();
    final uri = await FilePicker.saveFile(fileName: out.name, bytes: out.bytes, mimeType: out.mime);
    return uri?.pathSegments.isNotEmpty == true ? Uri.decodeComponent(uri!.pathSegments.last) : null;
  }

  Future<void> share() async {
    final out = await build();
    final f = await _temp(out.bytes, out.name);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: out.mime)]));
  }

  /// Opens the phone's print screen with the PDF at actual size.
  Future<void> printIt() async {
    final photo = await renderPhoto();
    final pdf = await buildPdf(st.layout, photo);
    await Printing.layoutPdf(onLayout: (_) async => pdf, name: 'СЭЛФИ ШИНОСНОМА', usePrinterSettings: false);
  }
}

// ---------- DPI tags ----------

/// Writes the DPI into the JPEG's JFIF header (adds one if the encoder didn't).
Uint8List _jpegWithDpi(Uint8List jpg, int dpi) {
  if (jpg.length < 4 || jpg[0] != 0xFF || jpg[1] != 0xD8) return jpg;
  final hasJfif = jpg.length > 20 && jpg[2] == 0xFF && jpg[3] == 0xE0 && String.fromCharCodes(jpg.sublist(6, 10)) == 'JFIF';
  if (hasJfif) {
    final out = Uint8List.fromList(jpg);
    out[13] = 1; // dots per inch
    out[14] = dpi >> 8;
    out[15] = dpi & 0xFF;
    out[16] = dpi >> 8;
    out[17] = dpi & 0xFF;
    return out;
  }
  final app0 = [0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x02, 0x01, dpi >> 8, dpi & 0xFF, dpi >> 8, dpi & 0xFF, 0x00, 0x00];
  return Uint8List.fromList([0xFF, 0xD8, ...app0, ...jpg.sublist(2)]);
}

/// Adds a pHYs chunk (pixels per metre) right after IHDR.
Uint8List _pngWithDpi(Uint8List png, int dpi) {
  if (png.length < 33) return png;
  final ppm = (dpi / .0254).round();
  final data = ByteData(9)
    ..setUint32(0, ppm)
    ..setUint32(4, ppm)
    ..setUint8(8, 1);
  final type = 'pHYs'.codeUnits;
  final body = Uint8List.fromList([...type, ...data.buffer.asUint8List()]);
  final len = ByteData(4)..setUint32(0, 9);
  final crc = ByteData(4)..setUint32(0, _crc32(body));
  const ihdrEnd = 8 + 25; // signature + IHDR chunk
  return Uint8List.fromList([...png.sublist(0, ihdrEnd), ...len.buffer.asUint8List(), ...body, ...crc.buffer.asUint8List(), ...png.sublist(ihdrEnd)]);
}

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
