import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ── DTF by Vino — design system (Figma redesign) ────────────────────────────
/// Flat, near-black surfaces with a single customizable accent. Montserrat type.
/// Colors, radii and type scale are taken 1:1 from the Figma file "DTF-PDF".
abstract final class AppColors {
  static const bgDeep     = Color(0xFF0D0E12); // app background
  static const bgCard     = Color(0xFF151618); // cards, list items
  static const bgElevated = Color(0xFF323234); // chips, secondary buttons, inputs
  static const textPrimary   = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB4B7BC); // body / secondary text
  static const textMuted     = Color(0xFF747474); // labels, timestamps
  static const divider       = Color(0xFF26272B);
  static const online        = Color(0xFF7AAA56); // green (follow notification)
  static const danger        = Color(0xFFFD424B); // red (like / angry)

  // AMOLED customization was removed in the redesign — these aliases keep the
  // old black-theme code paths compiling while rendering the single flat look.
  static const blackBg       = bgDeep;
  static const blackCard     = bgCard;
  static const blackElevated = bgElevated;
}

/// Corner radii from the design (10 = cards/buttons, 28 = pills, 5 = small).
abstract final class AppRadius {
  static const double card  = 10;
  static const double pill  = 28;
  static const double small = 5;
}

class AppTheme {
  static ThemeData build(Color accent, {bool black = false}) {
    final base = ThemeData.dark();
    const card = AppColors.bgCard;
    const elevated = AppColors.bgElevated;

    TextStyle m(double size, FontWeight w, Color c, {double? height}) =>
        GoogleFonts.montserrat(
            fontSize: size, fontWeight: w, color: c, height: height);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgDeep,
      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: card,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.montserratTextTheme(base.textTheme).copyWith(
        displayLarge:   m(28, FontWeight.w700, AppColors.textPrimary, height: 1.2),
        displayMedium:  m(22, FontWeight.w700, AppColors.textPrimary, height: 1.2),
        headlineLarge:  m(18, FontWeight.w700, AppColors.textPrimary, height: 1.25),
        headlineMedium: m(16, FontWeight.w700, AppColors.textPrimary, height: 1.25),
        titleMedium:    m(14, FontWeight.w600, AppColors.textPrimary, height: 1.3),
        bodyLarge:    m(14, FontWeight.w400, AppColors.textPrimary,   height: 1.4),
        bodyMedium:   m(13, FontWeight.w400, AppColors.textSecondary, height: 1.4),
        bodySmall:    m(12, FontWeight.w400, AppColors.textMuted,     height: 1.3),
        labelLarge:   m(14, FontWeight.w600, AppColors.textPrimary),
        labelMedium:  m(12, FontWeight.w500, AppColors.textSecondary),
        labelSmall:   m(11, FontWeight.w500, AppColors.textMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgDeep,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: GoogleFonts.montserrat(
            color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        elevation: 0,
      ),
      tabBarTheme: TabBarThemeData(
        indicator: BoxDecoration(
          color: accent.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: accent.withValues(alpha: 0.55), width: 1),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: accent,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? const Color(0xFF6EBAF3)
              : const Color(0xFFB4B7BC),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accent
              : AppColors.bgElevated,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dividerTheme: const DividerThemeData(
          color: AppColors.divider, thickness: 1, space: 0),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevated,
        contentTextStyle: GoogleFonts.montserrat(
            color: AppColors.textPrimary, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgElevated,
        hintStyle: GoogleFonts.montserrat(
            color: AppColors.textMuted, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: BorderSide(color: accent, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle:
              GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle:
            GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600),
      )),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: const MenuStyle(
            backgroundColor: WidgetStatePropertyAll(elevated)),
      ),
    );
  }
}

/// Flat card surface used across the app (replaces the old glass card).
/// Kept name + signature so existing call sites keep working.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final bool isViewed;

  const GlassCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    this.isViewed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: glassCardDecoration(isViewed: isViewed),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Material(
          type: MaterialType.transparency,
          child: child,
        ),
      ),
    );
  }
}

/// Shared flat-card decoration. [black] is ignored (kept for call-site compat).
BoxDecoration glassCardDecoration({bool isViewed = false, bool black = false}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(AppRadius.card),
    color: isViewed
        ? const Color(0xFF101113)
        : AppColors.bgCard,
    border: Border.all(
      color: Colors.white.withValues(alpha: isViewed ? 0.03 : 0.05),
      width: 1,
    ),
  );
}

/// Flat elevated pill/container. [active] tints it with the accent
/// (selected tabs, toggles). Replaces the old blurred glass.
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool active;
  final Color? accentOverride;

  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.active = false,
    this.accentOverride,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentOverride ?? Theme.of(context).colorScheme.primary;
    final br = borderRadius ?? BorderRadius.circular(AppRadius.card);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: br,
        color: active
            ? accent.withValues(alpha: 0.18)
            : AppColors.bgElevated,
        border: active
            ? Border.all(color: accent.withValues(alpha: 0.55), width: 1)
            : null,
      ),
      child: child,
    );
  }
}

/// Full-screen flat background: near-black fill + tiled DTF watermark.
/// The old custom-photo / AMOLED / gradient options were removed in the
/// redesign (accent-only customization).
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: AppColors.bgDeep)),
        const Positioned.fill(child: _Watermark()),
        child,
      ],
    );
  }
}

/// Faint tiled monogram behind everything, matching the Figma background.
class _Watermark extends StatelessWidget {
  const _Watermark();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.16,
        child: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/watermark.png'),
              repeat: ImageRepeat.repeat,
              scale: 2.4,
            ),
          ),
        ),
      ),
    );
  }
}

/// Scales down slightly on press then snaps back — satisfying tap feedback.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final Duration duration;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.93,
    this.duration = const Duration(milliseconds: 90),
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween(begin: 1.0, end: widget.scale)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      onLongPress: () {
        _ctrl.reverse();
        widget.onLongPress?.call();
      },
      child: ScaleTransition(scale: _anim, child: widget.child),
    );
  }
}
