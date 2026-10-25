import 'package:flutter/material.dart';

/// Returns [colors] if the caller passed any, otherwise colours taken from
/// the app's theme, so an effect matches the app before anything is set.
List<Color> resolvePalette(BuildContext context, List<Color>? colors) {
  if (colors != null && colors.isNotEmpty) return colors;
  final scheme = Theme.of(context).colorScheme;
  return <Color>[scheme.primary, scheme.secondary, scheme.tertiary];
}