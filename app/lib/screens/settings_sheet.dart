import 'package:flutter/material.dart';

import '../app_state.dart';
import '../flavor.dart';
import '../export.dart';
import '../theme.dart';
import '../widgets/photos.dart';
import '../widgets/ui.dart';
import 'legal_sheet.dart';
import 'payment_sheet.dart';

/// Settings: save & print first (preview, layout, format, DPI, Save/Share/Print), then plan, auto-delete, privacy, legal.
Future<void> openSettings(BuildContext context, AppState st, void Function(String) toast) {
  return showNeuSheet(
    context,
    title: st.t('settings'),
    body: (_) => _Settings(st: st, toast: toast),
  );
}

class _Settings extends StatefulWidget {
  final AppState st;
  final void Function(String) toast;
  const _Settings({required this.st, required this.toast});
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  bool busy = false;
  AppState get st => widget.st;

  ({int w, int h}) get layoutPx {
    if (st.layout == 'single') return st.outPx;
    final p = sheetSizes[st.layout]!;
    return (w: (p.w / 25.4 * st.dpi).round(), h: (p.h / 25.4 * st.dpi).round());
  }

  String get info {
    final px = layoutPx;
    return '${st.fmt} · ${px.w}×${px.h} px · ${st.dpi} DPI${st.layout == 'single' ? ' · ≈ ${st.sizeEstimate}' : ''}';
  }

  Future<void> _act(String act) async {
    final shot = st.current;
    if (shot == null || !shot.processed) return widget.toast(st.t('needRework'));
    if (!st.isUnlocked(shot)) {
      final paid = await openPayment(context, st);
      if (!paid || !mounted) return;
      widget.toast(st.t('payGot'));
      setState(() {});
    }
    setState(() => busy = true);
    final ex = Exporter(st, shot);
    try {
      if (act == 'save') {
        var where = await ex.save();
        where ??= await ex.saveWithPicker(); // folders missing: let the customer choose
        widget.toast(where == null ? st.t('saveFail') : '${st.t('savedTo', where)} · ${st.fmt} · ${st.dpi} DPI');
      } else if (act == 'share') {
        await ex.share();
      } else {
        await ex.printIt();
      }
    } catch (e) {
      widget.toast(st.t('saveFail'));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final shot = st.current;
    final p = st.preset;
    final a = sheetCount(p, 100, 150), b = sheetCount(p, 210, 297);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shot == null || !shot.processed) InfoNote(st.t('needRework'), color: const Color(0xFF8A6500)),
        SubLabel(st.t('exportTitle')),
        Container(height: 190, decoration: insetDeco(18), alignment: Alignment.center, padding: const EdgeInsets.all(10), child: shot == null ? null : _preview(shot)),
        SubLabel(st.t('layout')),
        NeuSeg(
          items: [('single', st.t('single')), ('s10', st.t('sheet10', '${a.n}')), ('a4', st.t('sheetA4', '${b.n}'))],
          value: st.layout,
          onChanged: (v) => setState(() => st.update(() => st.layout = v)),
        ),
        SubLabel(st.t('format')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in ['JPEG', 'PNG', 'PDF', 'WebP', 'HEIC']) NeuChip(f, on: st.fmt == f, onTap: () => setState(() => st.update(() => st.fmt = f))),
          ],
        ),
        SubLabel(st.t('res')),
        Wrap(
          spacing: 8,
          children: [
            for (final d in [300, 600]) NeuChip('$d DPI', on: st.dpi == d, onTap: () => setState(() => st.update(() => st.dpi = d))),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: insetDeco(12),
          child: Text(info, textAlign: TextAlign.center, style: tx(12.5, FontWeight.w700, C.indigo)),
        ),
        const SizedBox(height: 16),
        if (busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: C.indigo)),
                const SizedBox(width: 10),
                Text(st.t('working2'), style: tx(13, FontWeight.w700, C.indigo)),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                flex: 14,
                child: BigButton(st.t('toPhone'), yellow: true, icon: Icons.download_rounded, onTap: () => _act('save')),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 10, child: BigButton(st.t('share'), onTap: () => _act('share'))),
              const SizedBox(width: 8),
              Expanded(flex: 10, child: BigButton(st.t('print'), onTap: () => _act('print'))),
            ],
          ),
        const SizedBox(height: 18),
        if (!kOwnerApp) // the owner app has no plans or payment
          _row(
            st.t('planRow'),
            !st.planActive ? st.t('planNone') : (st.plan == 'life' ? st.t('activeLife') : st.t('activeUntil', _date(st.planUntil!))),
            NeuChip(
              st.t('plans'),
              on: false,
              onTap: () async {
                if (await openPayment(context, st)) {
                  widget.toast(st.t('payGot'));
                  if (mounted) setState(() {});
                }
              },
            ),
          ),
        _row(
          st.t('autodel'),
          st.t('autodelSub'),
          Switch(
            value: st.autodel,
            activeThumbColor: Colors.white,
            activeTrackColor: C.indigo,
            onChanged: (v) {
              st.setAutodel(v);
              setState(() {});
            },
          ),
        ),
        InfoNote(st.t('privacy'), color: const Color(0xFF2E7D5B)),
        const SizedBox(height: 16),
        LegalLinks(st),
        const SizedBox(height: 6),
        Text(st.t('version'), textAlign: TextAlign.center, style: tx(12, FontWeight.w600, C.mute)),
      ],
    );
  }

  Widget _row(String title, String sub, Widget trailing) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFDCE1EA))),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: tx(14, FontWeight.w700)),
              Text(sub, style: tx(11.5, FontWeight.w600, C.mute)),
            ],
          ),
        ),
        trailing,
      ],
    ),
  );

  /// Single photo, or the print sheet with every copy placed to scale.
  Widget _preview(RawShot shot) {
    final p = st.preset;
    Widget photo() => shot.processed ? ResultImage(shot, st) : RawShotImage(shot);
    if (st.layout == 'single') {
      return AspectRatio(
        aspectRatio: p.ratio,
        child: Container(decoration: raisedDeco(6, d: 3), clipBehavior: Clip.antiAlias, child: photo()),
      );
    }
    final paper = sheetSizes[st.layout]!;
    final c = sheetCount(p, paper.w, paper.h);
    return AspectRatio(
      aspectRatio: paper.w / paper.h,
      child: LayoutBuilder(
        builder: (context, box) {
          final k = box.maxWidth / paper.w;
          const g = 3.0;
          final gw = c.cols * p.w + (c.cols - 1) * g, gh = c.rows * p.h + (c.rows - 1) * g;
          final ox = (paper.w - gw) / 2, oy = (paper.h - gh) / 2;
          return Container(
            decoration: BoxDecoration(color: Colors.white, boxShadow: outShadow(3)),
            child: Stack(
              children: [
                for (var r = 0; r < c.rows; r++)
                  for (var q = 0; q < c.cols; q++) Positioned(left: (ox + q * (p.w + g)) * k, top: (oy + r * (p.h + g)) * k, width: p.w * k, height: p.h * k, child: photo()),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// dd.mm.yyyy from seconds since epoch.
String _date(double sec) {
  final d = DateTime.fromMillisecondsSinceEpoch((sec * 1000).round());
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}
