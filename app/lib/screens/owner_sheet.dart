import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import '../theme.dart';
import '../unlock_code.dart';
import '../widgets/ui.dart';
import 'payment_sheet.dart';

const _sms = MethodChannel('tj.selfieshinosnoma/sms');

/// Owner app only: after checking the payment in Alif, make the customer's activation code.
Future<void> openOwnerMode(BuildContext context, AppState st) =>
    showNeuSheet<void>(context, title: st.t('ownerCodeTitle'), body: (_) => _CodeMaker(st: st));

class _CodeMaker extends StatefulWidget {
  final AppState st;
  const _CodeMaker({required this.st});
  @override
  State<_CodeMaker> createState() => _CodeMakerState();
}

class _CodeMakerState extends State<_CodeMaker> {
  final phone = TextEditingController();
  String plan = 'life';
  String? code, err, sent; // sent: 'sent' | 'failed' | 'denied'
  bool sending = false;

  AppState get st => widget.st;
  String get digits => phone.text.replaceAll(RegExp(r'\D'), '');

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (unlockSecretIsDev) InfoNote(st.t('ownerDevKey'), color: const Color(0xFFC0392B)),
      InfoNote(st.t('ownerCheckAlif'), color: const Color(0xFF8A6500)),
      SubLabel(st.t('ownerCustomer')),
      Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: insetDeco(20),
        child: Row(children: [
          Text('+992', style: tx(19, FontWeight.w800, C.indigo)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
              style: tx(21, FontWeight.w700, C.ink, .8),
              decoration: InputDecoration(border: InputBorder.none, hintText: '901234567', hintStyle: tx(21, FontWeight.w600, C.mute)),
              onChanged: (_) => setState(() {
                code = null;
                err = null;
                sent = null;
              }),
            ),
          ),
        ]),
      ),
      SubLabel(st.t('plans')),
      Row(children: [
        for (final p in ['month', 'life']) ...[
          Expanded(
            child: NeuChip('${st.t('plan_$p')} · ${prices[p]} смн', on: plan == p, onTap: () => setState(() {
              plan = p;
              code = null;
              sent = null;
            })),
          ),
          if (p == 'month') const SizedBox(width: 8),
        ],
      ]),
      if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, textAlign: TextAlign.center, style: tx(12.5, FontWeight.w700, const Color(0xFFC0392B)))),
      const SizedBox(height: 14),
      if (sending)
        const Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: C.indigo)))
      else
        BigButton(st.t('ownerMake'), yellow: true, icon: Icons.send_rounded, onTap: _makeAndSend),
      if (sent != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(st.t(sent == 'sent' ? 'smsSent' : (sent == 'denied' ? 'smsDenied' : 'smsFailed'), '+992 ${fmtPhone(digits)}'),
              textAlign: TextAlign.center, style: tx(13, FontWeight.w800, sent == 'sent' ? const Color(0xFF2E7D5B) : const Color(0xFFC0392B))),
        ),
      if (code != null) ...[
        const SizedBox(height: 16),
        Text(st.t('ownerCodeFor', '+992 ${fmtPhone(digits)} · ${st.t('plan_$plan')}'), textAlign: TextAlign.center, style: tx(12.5, FontWeight.w700, C.ink2)),
        const SizedBox(height: 6),
        Center(child: SelectableText(prettyCode(code!), style: tx(38, FontWeight.w800, C.indigo, 3))),
        const SizedBox(height: 8),
        Center(
          child: NeuChip(st.t('copy'), on: false, onTap: () {
            final text = st.t('ownerMessage', prettyCode(code!));
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(st.t('copied')), duration: const Duration(seconds: 1)));
          }),
        ),
      ],
      const SizedBox(height: 10),
    ]);
  }

  /// Payment checked in Alif → make the code and send it to the customer by SMS straight away.
  Future<void> _makeAndSend() async {
    if (digits.length != 9) return setState(() => err = st.t('badPhone'));
    final c = makeCode(digits, plan);
    setState(() {
      code = c;
      sending = true;
      sent = null;
    });
    String r;
    try {
      r = await _sms.invokeMethod<String>('send', {'to': '+992$digits', 'text': st.t('ownerMessage', prettyCode(c))}) ?? 'failed';
    } catch (_) {
      r = 'failed';
    }
    if (mounted) {
      setState(() {
        sending = false;
        sent = r;
      });
    }
  }
}
