import 'package:flutter/material.dart';
import '../app_state.dart';
import '../l10n_more.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Terms of Use / Privacy Policy (short drafts; the full text will live on the website).
Future<void> openLegal(BuildContext context, AppState st, String kind) {
  final items = (legalTexts[st.lang] ?? legalTexts['en']!)[kind]!;
  return showNeuSheet(
    context,
    title: st.t(kind == 'terms' ? 'termsTitle' : 'privacyTitle'),
    body: (_) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(st.t('legalUpdated'), style: tx(12, FontWeight.w600, C.mute)),
      const SizedBox(height: 10),
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 22, child: Text('${i + 1}.', style: tx(13.5, FontWeight.w800, C.indigo))),
            Expanded(child: Text(items[i], style: tx(13.5, FontWeight.w500, C.ink).copyWith(height: 1.5))),
          ]),
        ),
      InfoNote(st.t('legalWeb')),
    ]),
  );
}

class LegalLinks extends StatelessWidget {
  final AppState st;
  const LegalLinks(this.st, {super.key});
  @override
  Widget build(BuildContext context) {
    final link = tx(12, FontWeight.w700, C.indigo).copyWith(decoration: TextDecoration.underline);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      GestureDetector(onTap: () => openLegal(context, st, 'terms'), child: Text(st.t('termsTitle'), style: link)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('·', style: tx(12, FontWeight.w700, C.mute))),
      GestureDetector(onTap: () => openLegal(context, st, 'privacy'), child: Text(st.t('privacyTitle'), style: link)),
    ]);
  }
}
