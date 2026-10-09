import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tokens.dart';

/// Saisie d'un code à usage unique (6 chiffres par défaut) — miroir de `OtpInput` côté web.
/// Un seul champ réel (clavier numérique, collage, saisie automatique SMS) rendu en cases.
class TratraOtpInput extends StatefulWidget {
  const TratraOtpInput({
    super.key,
    required this.onChanged,
    this.onCompleted,
    this.length = 6,
    this.enabled = true,
    this.hasError = false,
    this.autofocus = true,
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final int length;
  final bool enabled;
  final bool hasError;
  final bool autofocus;

  @override
  State<TratraOtpInput> createState() => _TratraOtpInputState();
}

class _TratraOtpInputState extends State<TratraOtpInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    widget.onChanged(value);
    if (value.length == widget.length) widget.onCompleted?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.text;
    return Semantics(
      label: 'Code de vérification à ${widget.length} chiffres',
      textField: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? () => _focus.requestFocus() : null,
        child: Stack(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < widget.length; i++) ...[
                  Expanded(child: _Cell(
                    char: i < value.length ? value[i] : '',
                    active: _focus.hasFocus && widget.enabled && i == value.length.clamp(0, widget.length - 1),
                    error: widget.hasError,
                    enabled: widget.enabled,
                  )),
                  if (i != widget.length - 1) const SizedBox(width: TtSpace.s2),
                ],
              ],
            ),
            // Champ réel invisible, au-dessus des cases : capte clavier, collage et autofill.
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: widget.length,
                  enableInteractiveSelection: false,
                  showCursor: false,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(counterText: '', border: InputBorder.none, filled: false),
                  onChanged: _onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.char, required this.active, required this.error, required this.enabled});
  final String char;
  final bool active;
  final bool error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final border = error ? TtColors.danger : (active ? TtColors.primary : (char.isEmpty ? TtColors.line : TtColors.fog));
    return AnimatedContainer(
      duration: TtMotion.fast,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled ? TtColors.surface : TtColors.canvas,
        borderRadius: TtRadius.controlAll,
        border: Border.all(color: border, width: active || error ? 2 : 1),
        boxShadow: active && !error
            ? [BoxShadow(color: TtColors.primary.withValues(alpha: 0.15), blurRadius: 0, spreadRadius: 3)]
            : const [],
      ),
      child: Text(char, style: TratraTheme.style(TtType.h2)),
    );
  }
}
