import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Monochrome styling inspired by the supplied mobile reference.
const rosterInk = Color(0xFF242424);
const rosterPaper = Color(0xFFFFFFFF);
const rosterSurface = Color(0xFFF4F4F4);
const rosterLine = Color(0xFFDDDDDD);
const rosterMuted = Color(0xFF686868);
const rosterOutline = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(10)),
  side: BorderSide(color: rosterLine),
);

ThemeData plannerTheme() {
  const scheme = ColorScheme.light(
    primary: rosterInk,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFEEEEEE),
    onPrimaryContainer: rosterInk,
    secondary: rosterInk,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFEEEEEE),
    onSecondaryContainer: rosterInk,
    tertiary: rosterMuted,
    onTertiary: Colors.white,
    tertiaryContainer: rosterSurface,
    onTertiaryContainer: rosterInk,
    surface: Colors.white,
    onSurface: rosterInk,
    onSurfaceVariant: rosterMuted,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFFAFAFA),
    surfaceContainer: rosterSurface,
    surfaceContainerHigh: Color(0xFFEEEEEE),
    surfaceContainerHighest: Color(0xFFE8E8E8),
    outline: Color(0xFFBDBDBD),
    outlineVariant: rosterLine,
    surfaceTint: Colors.transparent,
    inverseSurface: rosterInk,
    onInverseSurface: Colors.white,
    inversePrimary: Color(0xFFEEEEEE),
    error: Color(0xFF9C302B),
    onError: Colors.white,
    errorContainer: Color(0xFFFCF1F0),
    onErrorContainer: Color(0xFF9C302B),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: rosterPaper,
  );
  final text = base.textTheme.apply(
    bodyColor: rosterInk,
    displayColor: rosterInk,
  );
  const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );
  return base.copyWith(
    shadowColor: Colors.transparent,
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall!.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          height: 1.2),
      titleLarge: text.titleLarge!.copyWith(
          fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: text.titleMedium!.copyWith(
          fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0),
      bodyLarge: text.bodyLarge!
          .copyWith(fontSize: 15, height: 1.45, letterSpacing: 0),
      bodyMedium: text.bodyMedium!
          .copyWith(fontSize: 14, height: 1.45, letterSpacing: 0),
      bodySmall: text.bodySmall!
          .copyWith(color: rosterMuted, fontSize: 12, height: 1.4),
      labelLarge: text.labelLarge!.copyWith(
          fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: rosterInk,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: rosterInk,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      backgroundColor: rosterInk,
      foregroundColor: Colors.white,
      textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0),
      elevation: 0,
      shape: buttonShape,
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: rosterInk,
      backgroundColor: Colors.white,
      side: const BorderSide(color: rosterLine),
      shape: buttonShape,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    )),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
      foregroundColor: rosterInk,
      minimumSize: const Size(48, 48),
      shape: buttonShape,
    )),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      labelStyle: const TextStyle(color: rosterMuted, fontSize: 14),
      hintStyle: const TextStyle(color: rosterMuted, fontSize: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: rosterLine)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: rosterLine)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: rosterInk, width: 1.5)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: const Color(0xFFEEEEEE),
      indicatorShape: buttonShape,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: 'Roboto',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w400,
            color:
                states.contains(WidgetState.selected) ? rosterInk : rosterMuted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color:
              states.contains(WidgetState.selected) ? rosterInk : rosterMuted,
          size: 22)),
    ),
    listTileTheme:
        const ListTileThemeData(iconColor: rosterInk, textColor: rosterInk),
    dividerTheme: const DividerThemeData(color: rosterLine, thickness: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: rosterInk, linearTrackColor: rosterLine, linearMinHeight: 3),
    textSelectionTheme: const TextSelectionThemeData(
        cursorColor: rosterInk,
        selectionColor: Color(0xFFDDDDDD),
        selectionHandleColor: rosterInk),
  );
}
