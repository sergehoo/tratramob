import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tokens.dart';

/// Champ de saisie de la marque (miroir de `TextField` côté web) : étiquette au-dessus,
/// bordure `control` 12, anneau de focus vert, aide/erreur en dessous.
/// S'utilise seul ou dans un `Form` (validator).
class TratraInput extends StatefulWidget {
  const TratraInput({
    super.key,
    this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.controller,
    this.initialValue,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.leadingIcon,
    this.suffix,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.required = false,
    this.optional = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
    this.autovalidateMode,
    this.onTap,
  });

  final String? label;
  final String? hint;
  final String? helper;
  final String? errorText;
  final TextEditingController? controller;
  final String? initialValue;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? leadingIcon;
  final Widget? suffix;

  /// Mot de passe : ajoute un bouton afficher/masquer.
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool required;

  /// Affiche « (facultatif) » à côté de l'étiquette.
  final bool optional;
  final bool autofocus;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final TextCapitalization textCapitalization;
  final AutovalidateMode? autovalidateMode;
  final VoidCallback? onTap;

  @override
  State<TratraInput> createState() => _TratraInputState();
}

class _TratraInputState extends State<TratraInput> {
  late bool _hidden = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final multiline = widget.maxLines != 1;
    final suffix = widget.obscureText
        ? IconButton(
            tooltip: _hidden ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
            onPressed: () => setState(() => _hidden = !_hidden),
            icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
          )
        : widget.suffix;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text.rich(
            TextSpan(
              style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600, fontSize: 14),
              children: [
                TextSpan(text: widget.label),
                if (widget.required) const TextSpan(text: ' *', style: TextStyle(color: TtColors.danger)),
                if (widget.optional)
                  TextSpan(
                    text: '  (facultatif)',
                    style: TratraTheme.style(TtType.caption, color: TtColors.ash)
                        .copyWith(fontWeight: FontWeight.w400),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        TextFormField(
          controller: widget.controller,
          initialValue: widget.controller == null ? widget.initialValue : null,
          focusNode: widget.focusNode,
          keyboardType: widget.keyboardType ?? (multiline ? TextInputType.multiline : null),
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          inputFormatters: widget.inputFormatters,
          validator: widget.validator,
          autovalidateMode: widget.autovalidateMode,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          onTap: widget.onTap,
          obscureText: _hidden,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          autofocus: widget.autofocus,
          maxLines: widget.obscureText ? 1 : widget.maxLines,
          minLines: widget.minLines,
          maxLength: widget.maxLength,
          textCapitalization: widget.textCapitalization,
          style: TratraTheme.style(TtType.body),
          cursorColor: TtColors.primaryDark,
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText: widget.helper,
            helperMaxLines: 3,
            errorText: widget.errorText,
            errorMaxLines: 3,
            counterText: '',
            filled: true,
            fillColor: widget.enabled && !widget.readOnly ? TtColors.surface : TtColors.canvas,
            prefixIcon: widget.leadingIcon == null ? null : Icon(widget.leadingIcon, size: 20),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}
