import 'package:flutter/material.dart';
import '../theme.dart';

/// Shared neumorphic controls used by the sheets.

Future<T?> showNeuSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) body}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.paper,
    barrierColor: const Color(0x612E3654),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .9),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 6, decoration: insetDeco(3)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
            child: Row(children: [
              Expanded(child: Text(title, style: tx(18, FontWeight.w800))),
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(width: 44, height: 44, decoration: raisedDeco(22, d: 4), child: const Icon(Icons.close, color: C.ink, size: 20)),
              ),
            ]),
          ),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 24), child: body(ctx))),
        ]),
      ),
    ),
  );
}

class SubLabel extends StatelessWidget {
  final String text;
  const SubLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text.toUpperCase(), style: tx(11, FontWeight.w800, C.mute, 1.4)),
      );
}

class NeuChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const NeuChip(this.label, {super.key, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: on ? insetDeco(22) : raisedDeco(22, d: 4),
          child: Center(widthFactor: 1, child: Text(label, style: tx(13, FontWeight.w700, on ? C.indigo : C.ink))),
        ),
      );
}

class NeuSeg extends StatelessWidget {
  final List<(String, String)> items; // (value, label)
  final String value;
  final ValueChanged<String> onChanged;
  const NeuSeg({super.key, required this.items, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: insetDeco(14),
        child: Row(children: [
          for (final it in items)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(it.$1),
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: it.$1 == value ? raisedDeco(11, d: 3) : null,
                  child: Text(it.$2, textAlign: TextAlign.center, maxLines: 2, style: tx(12, FontWeight.w700, it.$1 == value ? C.indigo : C.ink2)),
                ),
              ),
            ),
        ]),
      );
}

class BigButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool yellow;
  final VoidCallback? onTap;
  const BigButton(this.label, {super.key, this.icon, this.yellow = false, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? .5 : 1,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: yellow
                ? BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFDB55), Color(0xFFFFB300)]), boxShadow: outShadow(6))
                : raisedDeco(28, d: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18, color: C.ink), const SizedBox(width: 6)],
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: tx(13.5, FontWeight.w800)))),
            ]),
          ),
        ),
      );
}

class InfoNote extends StatelessWidget {
  final String text;
  final Color color;
  const InfoNote(this.text, {super.key, this.color = const Color(0xFF3F55B5)});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: insetDeco(14),
        child: Text(text, style: tx(12.5, FontWeight.w600, color)),
      );
}
