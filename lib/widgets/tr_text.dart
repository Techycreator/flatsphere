import 'package:flutter/material.dart' as m;
import 'package:flutter/services.dart' as s;

import '../l10n/ml_strings.dart';

/// Returns the Malayalam text for [s] when the app language is Malayalam; otherwise [s] unchanged.
String trl(m.BuildContext context, String s) =>
    m.Localizations.localeOf(context).languageCode == 'ml' ? (mlStrings[s] ?? s) : s;

/// Drop-in replacement for the material Text widget that translates known fixed strings.
class Text extends m.StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final m.TextStyle? style;
  final m.StrutStyle? strutStyle;
  final m.TextAlign? textAlign;
  final m.TextDirection? textDirection;
  final m.Locale? locale;
  final bool? softWrap;
  final m.TextOverflow? overflow;
  final m.TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final m.TextWidthBasis? textWidthBasis;
  final m.TextHeightBehavior? textHeightBehavior;
  final m.Color? selectionColor;

  @override
  m.Widget build(m.BuildContext context) => m.Text(
    trl(context, data),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler: textScaler,
    maxLines: maxLines,
    semanticsLabel: semanticsLabel,
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}

m.InputDecoration? _trDecoration(m.BuildContext context, m.InputDecoration? d) => d?.copyWith(
  labelText: d.labelText == null ? null : trl(context, d.labelText!),
  hintText: d.hintText == null ? null : trl(context, d.hintText!),
  helperText: d.helperText == null ? null : trl(context, d.helperText!),
  errorText: d.errorText == null ? null : trl(context, d.errorText!),
);

/// Drop-in replacement for the material TextField that translates its label, hint, helper and error text.
class TextField extends m.StatelessWidget {
  const TextField({
    super.key,
    this.controller,
    this.decoration,
    this.enabled,
    this.autofocus = false,
    this.inputFormatters,
    this.keyboardType,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.textCapitalization = m.TextCapitalization.none,
  });

  final m.TextEditingController? controller;
  final m.InputDecoration? decoration;
  final bool? enabled;
  final bool autofocus;
  final List<s.TextInputFormatter>? inputFormatters;
  final s.TextInputType? keyboardType;
  final int? maxLength;
  final int? maxLines;
  final int? minLines;
  final bool obscureText;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final m.TextCapitalization textCapitalization;

  @override
  m.Widget build(m.BuildContext context) => m.TextField(
    controller: controller,
    decoration: _trDecoration(context, decoration),
    enabled: enabled,
    autofocus: autofocus,
    inputFormatters: inputFormatters,
    keyboardType: keyboardType,
    maxLength: maxLength,
    maxLines: maxLines,
    minLines: minLines,
    obscureText: obscureText,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    textCapitalization: textCapitalization,
  );
}

/// Drop-in replacement for the material DropdownButtonFormField that translates its decoration texts.
class DropdownButtonFormField<T> extends m.StatelessWidget {
  const DropdownButtonFormField({
    super.key,
    this.initialValue,
    required this.items,
    this.onChanged,
    this.decoration,
    this.isExpanded = false,
    this.isDense = true,
  });

  final T? initialValue;
  final List<m.DropdownMenuItem<T>>? items;
  final void Function(T?)? onChanged;
  final m.InputDecoration? decoration;
  final bool isExpanded;
  final bool isDense;

  @override
  m.Widget build(m.BuildContext context) => m.DropdownButtonFormField<T>(
    initialValue: initialValue,
    items: items,
    onChanged: onChanged,
    decoration: _trDecoration(context, decoration),
    isExpanded: isExpanded,
    isDense: isDense,
  );
}