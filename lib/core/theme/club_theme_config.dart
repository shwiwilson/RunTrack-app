import 'package:flutter/material.dart';

@immutable
class ClubThemeConfig {
  const ClubThemeConfig({
    required this.name,
    required this.colors,
    required this.buttons,
    required this.fontFamily,
    required this.borderRadius,
    required this.edgePadding,
  });

  final String name;
  final ClubThemeColors colors;
  final ClubButtonThemes buttons;
  final String fontFamily;
  final double borderRadius;
  final double edgePadding;

  Color get primaryColor => colors.primary;
  Color get backgroundColor => colors.background;
  Color get surfaceColor => colors.surface;
  Color get strokeColor => colors.outline;

  factory ClubThemeConfig.fromJson(Map<String, dynamic> json) {
    final colorsJson = json['colors'] as Map<String, dynamic>;
    final buttonsJson = json['buttons'] as Map<String, dynamic>;
    final typographyJson = json['typography'] as Map<String, dynamic>;
    final shapeJson = json['shape'] as Map<String, dynamic>;
    final spacingJson = json['spacing'] as Map<String, dynamic>;

    return ClubThemeConfig(
      name: json['name'] as String,
      colors: ClubThemeColors.fromJson(colorsJson),
      buttons: ClubButtonThemes.fromJson(buttonsJson),
      fontFamily: typographyJson['fontFamily'] as String,
      borderRadius: (shapeJson['borderRadius'] as num).toDouble(),
      edgePadding: (spacingJson['edgePadding'] as num).toDouble(),
    );
  }

  factory ClubThemeConfig.fromMap(Map<String, dynamic> json) {
    return ClubThemeConfig.fromJson(json);
  }

  ThemeData toThemeData() {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    );
    final buttonPadding = EdgeInsets.all(edgePadding / 1.5);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: colors.primary,
          brightness: _brightnessFor(colors.background),
        ).copyWith(
          primary: colors.primary,
          onPrimary: colors.onPrimary,
          primaryContainer: colors.primaryContainer,
          onPrimaryContainer: colors.onPrimaryContainer,
          secondary: colors.secondary,
          onSecondary: colors.onSecondary,
          secondaryContainer: colors.secondaryContainer,
          onSecondaryContainer: colors.onSecondaryContainer,
          tertiary: colors.tertiary,
          onTertiary: colors.onTertiary,
          tertiaryContainer: colors.tertiaryContainer,
          onTertiaryContainer: colors.onTertiaryContainer,
          error: colors.error,
          onError: colors.onError,
          surface: colors.surface,
          onSurface: colors.onSurface,
          surfaceContainerHighest: colors.surfaceVariant,
          surfaceContainerHigh: colors.surfaceVariant,
          surfaceContainer: colors.surface,
          surfaceContainerLow: colors.surface,
          surfaceContainerLowest: colors.background,
          onSurfaceVariant: colors.onSurfaceVariant,
          outline: colors.outline,
          outlineVariant: colors.outlineVariant,
          inverseSurface: colors.inverseSurface,
          onInverseSurface: colors.inverseOnSurface,
          inversePrimary: colors.inversePrimary,
          surfaceTint: Colors.transparent,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      fontFamily: fontFamily.isEmpty ? null : fontFamily,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true, // Center the app bar title
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: colors.onPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.surface,
        selectedItemColor: colors.primary,
        unselectedItemColor: colors.onSurfaceVariant,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels:
            false, // Emphasize the selected tab by hiding unselected labels
        selectedIconTheme: const IconThemeData(
          size: 30, // Larger icon for selected tab
        ),
        unselectedIconTheme: IconThemeData(
          size: 24,
          color: colors.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        selectedLabelStyle: base.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w900, // Bolder text for selected tab
          fontSize: 12,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _buttonStyle(buttons.elevated, shape, buttonPadding),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _buttonStyle(buttons.filled, shape, buttonPadding),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _buttonStyle(
          buttons.outlined,
          shape,
          buttonPadding,
          border: true,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _buttonStyle(buttons.text, shape, buttonPadding),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: _stateColor(
            buttons.icon.foregroundColor,
            buttons.icon.disabledForegroundColor,
          ),
        ),
      ),
      textTheme: base.textTheme
          .apply(
            bodyColor: colors.onBackground,
            displayColor: colors.onBackground,
          )
          .copyWith(
            headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
            headlineSmall: base.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            labelLarge: base.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
      extensions: <ThemeExtension<dynamic>>[
        ClubThemeTokens(
          strokeColor: colors.outline,
          subtleStrokeColor: colors.outlineVariant,
          subtleFillColor: colors.surfaceVariant,
          successColor: colors.success,
          warningColor: colors.warning,
          borderRadius: borderRadius,
          edgePadding: edgePadding,
        ),
      ],
    );
  }

  ButtonStyle _buttonStyle(
    ClubButtonColorSet colors,
    OutlinedBorder shape,
    EdgeInsets padding, {
    bool border = false,
  }) {
    return ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      backgroundColor: _stateColor(
        colors.backgroundColor,
        colors.disabledBackgroundColor,
      ),
      foregroundColor: _stateColor(
        colors.foregroundColor,
        colors.disabledForegroundColor,
      ),
      padding: WidgetStatePropertyAll(padding),
      shape: WidgetStatePropertyAll(shape),
      side: border
          ? WidgetStateProperty.resolveWith((states) {
              final color = states.contains(WidgetState.disabled)
                  ? colors.disabledBorderColor
                  : colors.borderColor;
              return BorderSide(color: color ?? this.colors.outline);
            })
          : null,
    );
  }

  static WidgetStateProperty<Color?> _stateColor(
    Color? enabled,
    Color? disabled,
  ) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return disabled;
      }

      return enabled;
    });
  }

  static Brightness _brightnessFor(Color color) {
    return ThemeData.estimateBrightnessForColor(color);
  }
}

@immutable
class ClubThemeColors {
  const ClubThemeColors({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.background,
    required this.onBackground,
    required this.surface,
    required this.onSurface,
    required this.surfaceVariant,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.error,
    required this.onError,
    required this.success,
    required this.warning,
    required this.inverseSurface,
    required this.inverseOnSurface,
    required this.inversePrimary,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color background;
  final Color onBackground;
  final Color surface;
  final Color onSurface;
  final Color surfaceVariant;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color error;
  final Color onError;
  final Color success;
  final Color warning;
  final Color inverseSurface;
  final Color inverseOnSurface;
  final Color inversePrimary;

  factory ClubThemeColors.fromJson(Map<String, dynamic> json) {
    return ClubThemeColors(
      primary: _colorFromHex(json['primary'] as String),
      onPrimary: _colorFromHex(json['onPrimary'] as String),
      primaryContainer: _colorFromHex(json['primaryContainer'] as String),
      onPrimaryContainer: _colorFromHex(json['onPrimaryContainer'] as String),
      secondary: _colorFromHex(json['secondary'] as String),
      onSecondary: _colorFromHex(json['onSecondary'] as String),
      secondaryContainer: _colorFromHex(json['secondaryContainer'] as String),
      onSecondaryContainer: _colorFromHex(
        json['onSecondaryContainer'] as String,
      ),
      tertiary: _colorFromHex(json['tertiary'] as String),
      onTertiary: _colorFromHex(json['onTertiary'] as String),
      tertiaryContainer: _colorFromHex(json['tertiaryContainer'] as String),
      onTertiaryContainer: _colorFromHex(json['onTertiaryContainer'] as String),
      background: _colorFromHex(json['background'] as String),
      onBackground: _colorFromHex(json['onBackground'] as String),
      surface: _colorFromHex(json['surface'] as String),
      onSurface: _colorFromHex(json['onSurface'] as String),
      surfaceVariant: _colorFromHex(json['surfaceVariant'] as String),
      onSurfaceVariant: _colorFromHex(json['onSurfaceVariant'] as String),
      outline: _colorFromHex(json['outline'] as String),
      outlineVariant: _colorFromHex(json['outlineVariant'] as String),
      error: _colorFromHex(json['error'] as String),
      onError: _colorFromHex(json['onError'] as String),
      success: _colorFromHex(json['success'] as String),
      warning: _colorFromHex(json['warning'] as String),
      inverseSurface: _colorFromHex(json['inverseSurface'] as String),
      inverseOnSurface: _colorFromHex(json['inverseOnSurface'] as String),
      inversePrimary: _colorFromHex(json['inversePrimary'] as String),
    );
  }

  static Color _colorFromHex(String value) {
    final hex = value.replaceFirst('#', '');
    final normalized = hex.length == 6 ? 'FF$hex' : hex;
    return Color(int.parse(normalized, radix: 16));
  }
}

@immutable
class ClubButtonThemes {
  const ClubButtonThemes({
    required this.elevated,
    required this.filled,
    required this.outlined,
    required this.text,
    required this.icon,
  });

  final ClubButtonColorSet elevated;
  final ClubButtonColorSet filled;
  final ClubButtonColorSet outlined;
  final ClubButtonColorSet text;
  final ClubButtonColorSet icon;

  factory ClubButtonThemes.fromJson(Map<String, dynamic> json) {
    return ClubButtonThemes(
      elevated: ClubButtonColorSet.fromJson(
        json['elevated'] as Map<String, dynamic>,
      ),
      filled: ClubButtonColorSet.fromJson(
        json['filled'] as Map<String, dynamic>,
      ),
      outlined: ClubButtonColorSet.fromJson(
        json['outlined'] as Map<String, dynamic>,
      ),
      text: ClubButtonColorSet.fromJson(json['text'] as Map<String, dynamic>),
      icon: ClubButtonColorSet.fromJson(json['icon'] as Map<String, dynamic>),
    );
  }
}

@immutable
class ClubButtonColorSet {
  const ClubButtonColorSet({
    required this.foregroundColor,
    this.backgroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.borderColor,
    this.disabledBorderColor,
  });

  final Color? backgroundColor;
  final Color foregroundColor;
  final Color? disabledBackgroundColor;
  final Color? disabledForegroundColor;
  final Color? borderColor;
  final Color? disabledBorderColor;

  factory ClubButtonColorSet.fromJson(Map<String, dynamic> json) {
    return ClubButtonColorSet(
      backgroundColor: _optionalColor(json['backgroundColor']),
      foregroundColor: _colorFromHex(json['foregroundColor'] as String),
      disabledBackgroundColor: _optionalColor(json['disabledBackgroundColor']),
      disabledForegroundColor: _optionalColor(json['disabledForegroundColor']),
      borderColor: _optionalColor(json['borderColor']),
      disabledBorderColor: _optionalColor(json['disabledBorderColor']),
    );
  }

  static Color? _optionalColor(Object? value) {
    if (value is! String) {
      return null;
    }

    return _colorFromHex(value);
  }

  static Color _colorFromHex(String value) {
    final hex = value.replaceFirst('#', '');
    final normalized = hex.length == 6 ? 'FF$hex' : hex;
    return Color(int.parse(normalized, radix: 16));
  }
}

@immutable
class ClubThemeTokens extends ThemeExtension<ClubThemeTokens> {
  const ClubThemeTokens({
    required this.strokeColor,
    required this.subtleStrokeColor,
    required this.subtleFillColor,
    required this.successColor,
    required this.warningColor,
    required this.borderRadius,
    required this.edgePadding,
  });

  final Color strokeColor;
  final Color subtleStrokeColor;
  final Color subtleFillColor;
  final Color successColor;
  final Color warningColor;
  final double borderRadius;
  final double edgePadding;

  @override
  ClubThemeTokens copyWith({
    Color? strokeColor,
    Color? subtleStrokeColor,
    Color? subtleFillColor,
    Color? successColor,
    Color? warningColor,
    double? borderRadius,
    double? edgePadding,
  }) {
    return ClubThemeTokens(
      strokeColor: strokeColor ?? this.strokeColor,
      subtleStrokeColor: subtleStrokeColor ?? this.subtleStrokeColor,
      subtleFillColor: subtleFillColor ?? this.subtleFillColor,
      successColor: successColor ?? this.successColor,
      warningColor: warningColor ?? this.warningColor,
      borderRadius: borderRadius ?? this.borderRadius,
      edgePadding: edgePadding ?? this.edgePadding,
    );
  }

  @override
  ClubThemeTokens lerp(ThemeExtension<ClubThemeTokens>? other, double t) {
    if (other is! ClubThemeTokens) {
      return this;
    }

    return ClubThemeTokens(
      strokeColor: Color.lerp(strokeColor, other.strokeColor, t) ?? strokeColor,
      subtleStrokeColor:
          Color.lerp(subtleStrokeColor, other.subtleStrokeColor, t) ??
          subtleStrokeColor,
      subtleFillColor:
          Color.lerp(subtleFillColor, other.subtleFillColor, t) ??
          subtleFillColor,
      successColor:
          Color.lerp(successColor, other.successColor, t) ?? successColor,
      warningColor:
          Color.lerp(warningColor, other.warningColor, t) ?? warningColor,
      borderRadius: _lerpDouble(borderRadius, other.borderRadius, t),
      edgePadding: _lerpDouble(edgePadding, other.edgePadding, t),
    );
  }

  static ClubThemeTokens of(BuildContext context) {
    return Theme.of(context).extension<ClubThemeTokens>() ??
        const ClubThemeTokens(
          strokeColor: Color(0xFFDDDDDD),
          subtleStrokeColor: Color(0xFFEFEFEF),
          subtleFillColor: Color(0xFFF7F7F7),
          successColor: Color(0xFF1D7A46),
          warningColor: Color(0xFFB7791F),
          borderRadius: 8,
          edgePadding: 16,
        );
  }

  static double _lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
