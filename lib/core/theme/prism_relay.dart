import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class PrismRelay {
  static const canvas = Color(0xFFF4F3FA);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF282733);
  static const inkSecondary = Color(0xFF535360);
  static const inkMuted = Color(0xFF62616D);
  static const line = Color(0xFFEAE8F3);
  static const lineStrong = Color(0xFFDCD9E8);
  static const accent = Color(0xFF6E5AD3);
  static const brandLight = Color(0xFF8476ED);
  static const periwinkle = Color(0xFF8271DE);
  static const violetDeep = Color(0xFF362A92);
  static const plum = Color(0xFF6151A6);
  static const lilac = Color(0xFFE9DEFC);
  static const lilacSoft = Color(0xFFF2EAFD);
  static const lilacBorder = Color(0xFFCFC1F5);
  static const mint = Color(0xFFABE2CB);
  static const mintSurface = Color(0xFFE3F3E9);
  static const greenInk = Color(0xFF266550);
  static const peach = Color(0xFFFEB987);
  static const peachSurface = Color(0xFFFEF0E4);
  static const amberInk = Color(0xFF87512F);
  static const blush = Color(0xFFFEE8E8);
  static const errorInk = Color(0xFF9D4053);
  static const heroViolet = [
    Color(0xFF4B3EC4),
    Color(0xFF5B4DD2),
    Color(0xFF6B5BE0),
  ];
  static const skySoft = Color(0xFFE7EEFB);
  static const skyInk = Color(0xFF3B517E);
  static const coralSoft = Color(0xFFFBE7E8);

  static const welcomeFace = LinearGradient(
    begin: Alignment(-.42, -1),
    end: Alignment(.4, 1),
    colors: [Color(0xFFF3EBFF), Color(0xFFFBF0FB), Color(0xFFFFF6EF)],
    stops: [0, .46, 1],
  );
  static const welcomeWash = RadialGradient(
    center: Alignment(.78, -.34),
    radius: .9,
    colors: [Color(0xFFFFD9C8), Color(0x00FFD9C8)],
  );
  static const welcomeWash2 = RadialGradient(
    center: Alignment(-.78, .38),
    radius: .95,
    colors: [Color(0xFFD9C8FB), Color(0x00D9C8FB)],
  );
  static const accentGradient = LinearGradient(
    begin: Alignment(-.7, -1),
    end: Alignment(.7, 1),
    colors: [Color(0xFF7A5BF0), Color(0xFF5B3BE3)],
  );

  static const rowGap = 8.0;
  static const heroHeight = 200.0;
  static const artStage = 176.0;
  static const motion = Duration(milliseconds: 160);
  static const dockMotion = Duration(milliseconds: 240);
  static const lift = Duration(milliseconds: 220);
  static const seat = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;
  static const fontFamily = 'PlusJakartaSans';
  static const shadowRaised = [
    BoxShadow(color: Color(0x14222232), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(
      color: Color(0x3D3F2F6B),
      blurRadius: 26,
      offset: Offset(0, 12),
      spreadRadius: -16,
    ),
  ];
  static const hairline = [
    BoxShadow(color: Color(0x0F383743), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static const numbers = [FontFeature.tabularFigures()];

  static final ThemeData light = ThemeData(
    colorScheme: const ColorScheme.light(
      primary: accent,
      onPrimary: surface,
      primaryContainer: lilac,
      onPrimaryContainer: ink,
      secondary: greenInk,
      onSecondary: surface,
      secondaryContainer: mintSurface,
      onSecondaryContainer: greenInk,
      tertiary: amberInk,
      tertiaryContainer: peachSurface,
      onTertiaryContainer: amberInk,
      error: errorInk,
      onError: surface,
      errorContainer: blush,
      onErrorContainer: errorInk,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: inkSecondary,
      surfaceContainerLowest: surface,
      surfaceContainerLow: canvas,
      surfaceContainer: surface,
      surfaceContainerHigh: lilacSoft,
      surfaceContainerHighest: lilac,
      outline: inkMuted,
      outlineVariant: lineStrong,
      inversePrimary: lilac,
      surfaceTint: Colors.transparent,
      scrim: ink,
    ),
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
    dividerColor: line,
    splashFactory: InkRipple.splashFactory,
    fontFamily: fontFamily,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
          fontSize: 33,
          height: 1.08,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.1),
      headlineLarge: TextStyle(
          fontSize: 26,
          height: 1.12,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7),
      headlineSmall: TextStyle(
          fontSize: 20,
          height: 1.18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.45),
      titleLarge: TextStyle(
          fontSize: 17, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: TextStyle(
          fontSize: 17, height: 1.3, fontWeight: FontWeight.w800, letterSpacing: -0.3),
      titleSmall: TextStyle(
          fontSize: 15, height: 1.35, fontWeight: FontWeight.w700, letterSpacing: -0.1),
      bodyLarge: TextStyle(fontSize: 15.5, height: 1.55),
      bodyMedium: TextStyle(fontSize: 15, height: 1.5),
      bodySmall: TextStyle(fontSize: 13, height: 1.42, color: inkMuted),
      labelLarge: TextStyle(
          fontSize: 14, height: 1.35, fontWeight: FontWeight.w700, letterSpacing: -0.1),
      labelMedium: TextStyle(
          fontSize: 13, height: 1.35, fontWeight: FontWeight.w600, letterSpacing: 0),
      labelSmall: TextStyle(
          fontSize: 12, height: 1.35, fontWeight: FontWeight.w600, letterSpacing: 0),
    ),
    appBarTheme: const AppBarThemeData(
      backgroundColor: canvas,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 60,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 26,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.65,
        fontFamily: fontFamily,
      ),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: surface,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          iconSize: 24,
          disabledForegroundColor: const Color(0xFF77717E)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(surface),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent
            : const Color(0xFFE4DBE1),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: line),
        borderRadius: BorderRadius.circular(18),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: accent,
      circularTrackColor: lilacSoft,
      linearTrackColor: lilacSoft,
      linearMinHeight: 5,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Color(0x5C282733),
      dragHandleColor: lineStrong,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: lineStrong),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: periwinkle, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: plum,
      selectionColor: lilac,
      selectionHandleColor: plum,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      contentTextStyle: const TextStyle(
          color: surface, fontSize: 14, fontFamily: fontFamily),
      actionTextColor: lilac,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
