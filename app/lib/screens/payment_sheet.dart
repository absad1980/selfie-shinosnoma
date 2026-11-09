import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import '../l10n_more.dart';
import '../theme.dart';
import '../unlock_code.dart';
import '../widgets/ui.dart';
import 'legal_sheet.dart';

/// Prices in somoni: monthly 10, lifetime 50.
const prices = {'month': 10, 'life': 50};

/// Plan → phone + e-wallet → pay to the owner's Alif and send the receipt → enter the owner's activation code.
/// [codeOnly]: straight to entering a code (the customer already paid and got the code later).
/// Returns true once the app is activated.
Future<bool> openPayment(BuildContext context, AppState st, {bool codeOnly = false}) async {
  final ok = await showNeuSheet<bool>(context, title: st.t('payTitle'), body: (_) => _PayFlow(st: st, codeOnly: codeOnly));
  return ok == true;
}

class _PayFlow extends StatefulWidget {
  final AppState st;
  final bool codeOnly;
  const _PayFlow({required this.st, required this.codeOnly});
  @override
  State<_PayFlow> createState() => _PayFlowState();
}

class _PayFlowState extends State<_PayFlow> {
  late int step = widget.codeOnly ? 3 : 1;
  String pick = 'life';
  final phone = TextEditingController(), code = TextEditingController();
  String? wallet, err;
  static int _wrong = 0; // wrong codes in a row
  static DateTime? _lockedUntil;

  AppState get st => widget.st;
  String money(String k) => '${prices[k]} ${st.lang == 'en' ? 'TJS' : 'смн'}';
  String get digits => phone.text.replaceAll(' ', '');

  @override
  void initState() {
    super.initState();
    if (st.payPhone.length == 9) phone.text = _PhoneFormatter.fmt(st.payPhone);
  }

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // only the current step is shown (no cross-fade, so steps never overlap)
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      layoutBuilder: (current, previous) => current ?? const SizedBox(),
      child: KeyedSubtree(key: ValueKey(step), child: step == 1 ? _plans() : step == 2 ? _phoneBank() : _payAndCode()),
    );
  }

  Widget _plans() {
    const plans = ['month', 'life'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      Text(st.t('paySub'), style: tx(13, FontWeight.w600, C.ink2)),
      const SizedBox(height: 12),
      for (final k in plans) ...[
        GestureDetector(
          onTap: () => setState(() => pick = k),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: pick == k ? insetDeco(16) : raisedDeco(16, d: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(st.t('plan_$k'), style: tx(14, FontWeight.w800, pick == k ? C.indigo : C.ink)),
                    if (k == 'life') _badge(st.t('best')),
                  ]),
                  const SizedBox(height: 2),
                  Text(st.t('plan_${k}_sub'), style: tx(11.5, FontWeight.w600, C.mute)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(k), style: tx(13, FontWeight.w800)),
                if (k == 'month') Text(st.t('perMonth'), style: tx(10, FontWeight.w600, C.mute)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 10),
      BigButton('${st.t('next')} · ${money(pick)}', yellow: true, onTap: () => setState(() => step = 2)),
      TextButton(onPressed: () => setState(() => step = 3), child: Text(st.t('haveCode'), style: tx(12.5, FontWeight.w700, C.indigo))),
      InfoNote(st.t('payNote')),
      const SizedBox(height: 14),
      LegalLinks(st),
    ]);
  }

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: tx(10.5, FontWeight.w800, const Color(0xFF1D5A42))),
      );

  Widget _phoneField() => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: insetDeco(20),
        child: Row(children: [
          Text('+992', style: tx(19, FontWeight.w800, C.indigo)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9), _PhoneFormatter()],
              style: tx(21, FontWeight.w700, C.ink, .8),
              decoration: InputDecoration(border: InputBorder.none, hintText: '90 123 45 67', hintStyle: tx(21, FontWeight.w600, C.mute)),
              onChanged: (_) => setState(() => err = null),
            ),
          ),
        ]),
      );

  Widget _error() => err == null
      ? const SizedBox.shrink()
      : Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, textAlign: TextAlign.center, style: tx(12.5, FontWeight.w700, const Color(0xFFC0392B))));

  Widget _phoneBank() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${st.t('plan_$pick')} · ${money(pick)}', style: tx(13, FontWeight.w800)),
      const SizedBox(height: 4),
      Text(st.t('payPhoneSub'), style: tx(12.5, FontWeight.w600, C.ink2)),
      const SizedBox(height: 12),
      _phoneField(),
      SubLabel(st.t('wallet')),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.6,
        children: [
          for (final b in banks)
            GestureDetector(
              onTap: () => setState(() {
                wallet = b.id;
                err = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: wallet == b.id ? insetDeco(14) : raisedDeco(14, d: 3),
                child: Row(children: [
                  bankBadge(b.id, b.ab, 34),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.names[st.lang]!, maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(12, FontWeight.w800, wallet == b.id ? C.indigo : C.ink)),
                      if (b.app.isNotEmpty) Text(b.app, maxLines: 1, style: tx(9.5, FontWeight.w600, C.mute)),
                    ]),
                  ),
                ]),
              ),
            ),
        ],
      ),
      _error(),
      const SizedBox(height: 14),
      BigButton('${st.t('next')} · ${money(pick)}', yellow: true, onTap: () {
        if (digits.length != 9) return setState(() => err = st.t('badPhone'));
        if (wallet == null) return setState(() => err = st.t('pickWallet'));
        st.payPhone = digits;
        st.saveSettings();
        setState(() => step = 3);
      }),
      TextButton(onPressed: () => setState(() => step = 1), child: Text(st.t('back'), style: tx(12.5, FontWeight.w700, C.indigo))),
    ]);
  }

  /// Pay (when coming from the plans) and enter the activation code the owner sends after checking the payment.
  Widget _payAndCode() {
    final b = wallet == null ? null : banks.firstWhere((x) => x.id == wallet);
    final cameFromPlans = wallet != null;
    final locked = _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (cameFromPlans) ...[
        Center(
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(colors: [C.violet, C.pink]).createShader(r),
            child: Text(money(pick), style: tx(42, FontWeight.w800, Colors.white)),
          ),
        ),
        Text(st.t('payTransfer'), textAlign: TextAlign.center, style: tx(12.5, FontWeight.w600, C.ink2)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: insetDeco(18),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st.t('recipient').toUpperCase(), style: tx(10, FontWeight.w800, C.mute, 1.3)),
                Text(AppState.ownerNumber, style: tx(17, FontWeight.w800)),
              ]),
            ),
            NeuChip(st.t('copy'), on: false, onTap: () {
              Clipboard.setData(ClipboardData(text: AppState.ownerNumber.replaceAll(' ', '')));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(st.t('copied')), duration: const Duration(seconds: 1)));
            }),
          ]),
        ),
        const SizedBox(height: 8),
        if (b != null) Text(st.t('openBank', b.app.isNotEmpty ? b.app : b.names[st.lang]!), style: tx(12.5, FontWeight.w700, C.indigo)),
        const SizedBox(height: 6),
        InfoNote(st.t('paySendReceipt', '+992 ${_PhoneFormatter.fmt(digits)}')),
        const SizedBox(height: 4),
      ] else ...[
        Text(st.t('codePhone'), style: tx(12.5, FontWeight.w600, C.ink2)),
        const SizedBox(height: 8),
        _phoneField(),
      ],
      SubLabel(st.t('codeLabel')),
      Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: insetDeco(20),
        child: TextField(
          controller: code,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
          style: tx(24, FontWeight.w800, C.ink, 4),
          decoration: InputDecoration(border: InputBorder.none, hintText: '0000 0000', hintStyle: tx(24, FontWeight.w700, C.mute, 4)),
          onChanged: (_) => setState(() => err = null),
        ),
      ),
      _error(),
      const SizedBox(height: 14),
      BigButton(st.t('activate'), yellow: true, icon: Icons.lock_open_rounded, onTap: locked ? null : _activate),
      TextButton(
        onPressed: () => setState(() => step = cameFromPlans ? 2 : 1),
        child: Text(st.t('back'), style: tx(12.5, FontWeight.w700, C.indigo)),
      ),
    ]);
  }

  void _activate() {
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) return setState(() => err = st.t('codeWait'));
    if (digits.length != 9) return setState(() => err = st.t('badPhone'));
    final r = checkCode(code.text, digits);
    if (r.result == CodeResult.ok) {
      _wrong = 0;
      st.activate(plan: r.plan!, until: r.until, phone: digits);
      Navigator.of(context).pop(true);
      return;
    }
    if (r.result == CodeResult.expired) return setState(() => err = st.t('codeExpired'));
    _wrong++;
    if (_wrong >= 5) {
      _wrong = 0;
      _lockedUntil = DateTime.now().add(const Duration(minutes: 5));
      return setState(() => err = st.t('codeWait'));
    }
    setState(() => err = st.t('codeBad'));
  }
}

/// Shows the 9 digits as "90 123 45 67".
class _PhoneFormatter extends TextInputFormatter {
  static String fmt(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    final parts = <String>[];
    if (d.isNotEmpty) parts.add(d.substring(0, min(2, d.length)));
    if (d.length > 2) parts.add(d.substring(2, min(5, d.length)));
    if (d.length > 5) parts.add(d.substring(5, min(7, d.length)));
    if (d.length > 7) parts.add(d.substring(7, min(9, d.length)));
    return parts.join(' ');
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = fmt(newValue.text);
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

/// The bank's own app logo (round), or a letter badge when we don't have the logo.
Widget bankBadge(String id, String ab, double size) {
  if (bankLogos.contains(id)) {
    return ClipOval(child: Image.asset('assets/banks/$id.png', width: size, height: size, fit: BoxFit.cover, filterQuality: FilterQuality.medium));
  }
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF8B7BEF), C.violet])),
    child: Text(ab, style: tx(size * .31, FontWeight.w800, Colors.white)),
  );
}

/// Shows a phone number as "90 123 45 67" (used by the owner's code screen too).
String fmtPhone(String raw) => _PhoneFormatter.fmt(raw);
