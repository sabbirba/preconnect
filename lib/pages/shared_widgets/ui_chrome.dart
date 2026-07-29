part of 'package:preconnect/pages/ui_kit.dart';

class BracuPalette {
  static const Color bgTopLight = Colors.white;
  static const Color bgBottomLight = Colors.white;
  static const Color primary = Color(0xFF1E6BE3);
  static const Color accent = Color(0xFF22B573);
  static const Color info = Color(0xFF2C9DFF);
  static const Color warning = Color(0xFFEF6C35);
  static const Color favorite = Color(0xFFFFA726);
  static const Color danger = Color(0xFFD63B3B);
  static const Color cardLight = Colors.white;
  static const Color cardDark = Colors.black;

  static bool _isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color bgTop(BuildContext context) {
    return _isDark(context) ? Colors.black : bgTopLight;
  }

  static Color bgBottom(BuildContext context) {
    return _isDark(context) ? Colors.black : bgBottomLight;
  }

  static Color card(BuildContext context) {
    return _isDark(context) ? cardDark : cardLight;
  }

  static Color decorColor(BuildContext context) {
    return _isDark(context)
        ? const Color(0xFFE2E8F0).withValues(alpha: 0.08)
        : const Color(0xFF94A3B8).withValues(alpha: 0.14);
  }

  static Color textPrimary(BuildContext context) {
    return _isDark(context) ? Colors.white : Colors.black87;
  }

  static Color textSecondary(BuildContext context) {
    return _isDark(context) ? Colors.white70 : Colors.black54;
  }
}

class BracuPageScaffold extends StatefulWidget {
  const BracuPageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    required this.body,
    this.actions = const [],
    this.showMenu = false,
    this.showBack = true,
    this.onHeaderTap,
    this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget body;
  final List<Widget> actions;
  final bool showMenu;
  final bool showBack;
  final VoidCallback? onHeaderTap;
  final Color? subtitleColor;

  @override
  State<BracuPageScaffold> createState() => _BracuPageScaffoldState();
}

class _BracuPageScaffoldState extends State<BracuPageScaffold> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );
    return ValueListenableBuilder(
      valueListenable: HomeCardPreferences.decorationNotifier,
      builder: (BuildContext context, decorationsEnabled, Widget? child) {
        final enabled = decorationsEnabled == true;
        final baseColor = Theme.of(context).scaffoldBackgroundColor;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: enabled
                      ? BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              BracuPalette.bgTop(context),
                              BracuPalette.bgBottom(context),
                            ],
                          ),
                        )
                      : BoxDecoration(color: baseColor),
                ),
              ),
              AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlayStyle,
                child: Material(
                  type: MaterialType.transparency,
                  child: SafeArea(
                    child: Stack(
                      children: [
                        if (enabled) ...[
                          Positioned(
                            top: -90,
                            right: -70,
                            child: DecorBlob(
                              color: BracuPalette.decorColor(context),
                              size: 240,
                            ),
                          ),
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.center,
                              child: DecorLogoEmblem(
                                size: 280,
                                color: BracuPalette.decorColor(context),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: -100,
                            left: -80,
                            child: DecorBlob(
                              color: BracuPalette.decorColor(context),
                              size: 260,
                            ),
                          ),
                        ],
                        Column(
                          children: [
                            Padding(
                              padding: widget.showBack
                                  ? const EdgeInsets.fromLTRB(4, 2, 14, 2)
                                  : const EdgeInsets.fromLTRB(14, 2, 14, 2),
                              child: _PageHeader(
                                title: widget.title,
                                subtitle: widget.subtitle,
                                icon: widget.icon,
                                actions: widget.actions,
                                showMenu: widget.showMenu,
                                showBack: widget.showBack,
                                onHeaderTap: widget.onHeaderTap,
                                subtitleColor: widget.subtitleColor,
                              ),
                            ),
                            Expanded(child: widget.body),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    required this.showMenu,
    required this.showBack,
    this.onHeaderTap,
    this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final bool showMenu;
  final bool showBack;
  final VoidCallback? onHeaderTap;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    final canPop = navigator?.canPop() ?? false;
    final backScope = BracuBackScope.maybeOf(context);
    final canScopeBack = backScope?.canGoBack ?? false;
    final hasBack = showBack && (canPop || canScopeBack);
    final row = Row(
      children: [
        if (showMenu) const SizedBox(width: 0, height: 0),
        if (hasBack)
          Transform.translate(
            offset: const Offset(-2, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (canScopeBack && backScope != null) {
                  backScope.onBack();
                  return;
                }
                if (canPop && navigator != null) {
                  navigator.maybePop();
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 28,
                  color: BracuPalette.textPrimary(context),
                ),
              ),
            ),
          ),
        const Gap(8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: subtitleColor ?? BracuPalette.textSecondary(context),
                ),
              ),
              const Gap(1),
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: BracuPalette.textPrimary(context),
                ),
              ),
            ],
          ),
        ),
        ...actions,
      ],
    );
    if (onHeaderTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onHeaderTap,
      child: row,
    );
  }
}

class BracuCard extends StatelessWidget {
  const BracuCard({
    super.key,
    required this.child,
    this.isHighlighted = false,
    this.highlightColor,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final bool isHighlighted;
  final Color? highlightColor;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final highlight = highlightColor ?? BracuPalette.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBorderColor = BracuPalette.textSecondary(
      context,
    ).withValues(alpha: isDark ? 0.22 : 0.16);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isHighlighted
              ? highlight.withValues(alpha: isDark ? 0.7 : 0.9)
              : baseBorderColor,
          width: isHighlighted ? 1.6 : 1,
        ),
      ),
      child: child,
    );
  }
}

class BracuSectionTitle extends StatelessWidget {
  const BracuSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: BracuPalette.textPrimary(context),
      ),
    );
  }
}

class BracuLoading extends StatelessWidget {
  const BracuLoading({super.key, this.itemCount = 3, this.compact});

  final int itemCount;
  final bool? compact;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: BracuSpinner(size: 28, strokeWidth: 2.6),
      ),
    );
  }
}

class BracuSkeletonList extends StatelessWidget {
  const BracuSkeletonList({
    super.key,
    this.itemCount = 3,
    this.compact = false,
    this.showLabel = false,
    this.label = '',
  });

  final int itemCount;
  final bool compact;
  final bool showLabel;
  final String label;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class BracuSkeletonGrid extends StatelessWidget {
  const BracuSkeletonGrid({
    super.key,
    this.itemCount = 6,
    this.crossAxisCount = 3,
    this.spacing = 10,
    this.itemHeight = 72,
  });

  final int itemCount;
  final int crossAxisCount;
  final double spacing;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class BracuMetricGridData {
  const BracuMetricGridData({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;
}

class BracuMetricGrid extends StatelessWidget {
  const BracuMetricGrid({super.key, required this.items});

  final List<BracuMetricGridData> items;

  @override
  Widget build(BuildContext context) {
    final count = items.length;
    if (count == 0) return const SizedBox.shrink();
    return Row(
      children: [
        for (var index = 0; index < count; index++) ...[
          Expanded(child: _BracuMetricTile(data: items[index])),
        ],
      ],
    );
  }
}

class _BracuMetricTile extends StatelessWidget {
  const _BracuMetricTile({required this.data});

  final BracuMetricGridData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(data.icon, color: BracuPalette.primary, size: 15),
              const Gap(6),
              Flexible(
                child: Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Gap(3),
          Text(
            data.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class BracuEmptyState extends StatelessWidget {
  const BracuEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 44,
              color: BracuPalette.textSecondary(context).withValues(alpha: 0.4),
            ),
            const Gap(16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: BracuPalette.textSecondary(context),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DecorBlob extends StatelessWidget {
  const DecorBlob({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 2),
      ),
    );
  }
}

class DecorLogoEmblem extends StatelessWidget {
  const DecorLogoEmblem({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * (348.78 / 380.09),
      child: CustomPaint(painter: _LogoEmblemPainter(color: color)),
    );
  }
}

class _LogoEmblemPainter extends CustomPainter {
  const _LogoEmblemPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final scale = size.width / 380.09;

    canvas.save();
    canvas.scale(scale, scale);
    canvas.translate(-108.09, -247.16);

    final ringPath = Path()
      ..moveTo(298.14, 247.16)
      ..cubicTo(377.75, 247.16, 442.67, 312.09, 442.67, 391.69)
      ..arcToPoint(
        const Offset(404.83, 489.0),
        radius: const Radius.circular(143.94),
        largeArc: false,
        clockwise: true,
      )
      ..lineTo(397.68, 481.85)
      ..arcToPoint(
        const Offset(432.56, 391.68),
        radius: const Radius.circular(133.86),
        largeArc: false,
        clockwise: false,
      )
      ..cubicTo(432.56, 317.68, 372.18, 257.26, 298.14, 257.26)
      ..cubicTo(224.1, 257.26, 163.72, 317.66, 163.72, 391.7)
      ..arcToPoint(
        const Offset(198.38, 481.63),
        radius: const Radius.circular(133.86),
        largeArc: false,
        clockwise: false,
      )
      ..lineTo(191.22, 488.79)
      ..arcToPoint(
        const Offset(153.6, 391.7),
        radius: const Radius.circular(144.0),
        largeArc: false,
        clockwise: true,
      )
      ..cubicTo(153.6, 312.09, 218.53, 247.16, 298.14, 247.16)
      ..close();

    canvas.drawPath(ringPath, paint);

    void drawRibbonWave(double startY) {
      final wavePath = Path()
        ..moveTo(208.18, startY)
        ..cubicTo(
          236.27,
          startY + 5.29,
          259.45,
          startY + 23.29,
          297.74,
          startY + 44.86,
        )
        ..cubicTo(
          312.9,
          startY + 30.62,
          335.74,
          startY + 17.92,
          373.74,
          startY + 17.92,
        )
        ..lineTo(373.74, startY + 29.34)
        ..cubicTo(
          354.86,
          startY + 31.99,
          330.81,
          startY + 44.65,
          307.76,
          startY + 57.31,
        )
        ..lineTo(307.76, startY + 65.31)
        ..lineTo(307.64, startY + 65.63)
        ..lineTo(307.49, startY + 65.91)
        ..lineTo(307.29, startY + 66.2)
        ..lineTo(307.06, startY + 66.45)
        ..lineTo(306.78, startY + 66.68)
        ..lineTo(306.49, startY + 66.87)
        ..lineTo(306.17, startY + 67.03)
        ..lineTo(305.87, startY + 67.14)
        ..lineTo(292.49, startY + 67.14)
        ..lineTo(292.12, startY + 67.06)
        ..lineTo(291.78, startY + 66.95)
        ..lineTo(291.45, startY + 66.81)
        ..lineTo(291.14, startY + 66.59)
        ..lineTo(290.84, startY + 66.29)
        ..lineTo(290.62, startY + 65.97)
        ..lineTo(290.44, startY + 65.68)
        ..lineTo(290.34, startY + 65.35)
        ..lineTo(290.34, startY + 57.74)
        ..cubicTo(
          273.28,
          startY + 42.12,
          254.72,
          startY + 32.14,
          208.18,
          startY + 17.0,
        )
        ..close();

      canvas.drawPath(wavePath, paint);
    }

    drawRibbonWave(430.1);
    drawRibbonWave(462.64);
    drawRibbonWave(494.32);

    canvas.save();
    canvas.translate(298.14, 368.0);
    canvas.scale(14.0, 14.0);
    canvas.translate(-10.6865, -34.515);

    final infinityPath = Path();
    infinityPath.moveTo(8.903, 35.4);
    infinityPath.relativeLineTo(2.655, -2.79);
    infinityPath.relativeCubicTo(0.453, -0.475, 1.13, -0.723, 1.845, -0.723);
    infinityPath.relativeCubicTo(1.48, 0, 2.68, 1.177, 2.68, 2.629);
    infinityPath.relativeCubicTo(0, 1.45, -1.2, 2.628, -2.68, 2.628);
    infinityPath.relativeArcToPoint(
      const Offset(-1.87, -0.746),
      radius: const Radius.circular(2.7),
    );

    infinityPath.moveTo(12.470, 33.632);
    infinityPath.relativeLineTo(-2.654, 2.789);
    infinityPath.relativeCubicTo(-0.453, 0.476, -1.13, 0.723, -1.846, 0.723);
    infinityPath.relativeCubicTo(-1.48, 0, -2.68, -1.177, -2.68, -2.628);
    infinityPath.relativeCubicTo(0, -1.451, 1.2, -2.629, 2.68, -2.629);
    infinityPath.relativeArcToPoint(
      const Offset(1.87, 0.746),
      radius: const Radius.circular(2.7),
    );

    final infinityStrokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(infinityPath, infinityStrokePaint);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LogoEmblemPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class BracuBackScope extends InheritedWidget {
  const BracuBackScope({
    super.key,
    required this.canGoBack,
    required this.onBack,
    required super.child,
  });

  final bool canGoBack;
  final VoidCallback onBack;

  static BracuBackScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BracuBackScope>();
  }

  @override
  bool updateShouldNotify(BracuBackScope oldWidget) {
    return canGoBack != oldWidget.canGoBack;
  }
}

class SimpleProgressBar extends StatelessWidget {
  const SimpleProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
    this.backgroundAlpha = 0.12,
  });

  final double value;
  final Color color;
  final double height;
  final double backgroundAlpha;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: color.withValues(alpha: backgroundAlpha),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

class SectionBadge extends StatelessWidget {
  const SectionBadge({
    super.key,
    required this.label,
    required this.color,
    this.size = 40,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w700,
    this.backgroundAlpha = 0.12,
    this.borderRadius = 12,
  });

  final String label;
  final Color color;
  final double size;
  final double fontSize;
  final FontWeight fontWeight;
  final double backgroundAlpha;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final displayLabel = formatSectionBadge(label);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Colors.transparent),
      alignment: Alignment.center,
      child: Text(
        displayLabel,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
    );
  }
}

class ShowMoreButton extends StatelessWidget {
  const ShowMoreButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OutlinedButton(
        onPressed: onPressed,
        style: bracuOutlinedButtonStyle(
          context,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          borderRadius: 16,
        ),
        child: Text(
          'Show More',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: BracuPalette.textPrimary(context),
          ),
        ),
      ),
    );
  }
}

class QuickAccessCard extends StatelessWidget {
  const QuickAccessCard({
    super.key,
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isLoading = false,
  });

  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Colors.transparent),
              child: isLoading
                  ? BracuSpinner(size: 22, color: color, strokeWidth: 2.2)
                  : Icon(icon, color: color, size: 22),
            ),
            const Gap(12),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
            ),
            const Gap(2),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FriendActionCard extends StatelessWidget {
  const FriendActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.width,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: const BoxDecoration(color: Colors.transparent),
              child: Icon(icon, color: color, size: 20),
            ),
            const Gap(8),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
            ),
            const Gap(2),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 10.5, color: textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  static ShimmerState? of(BuildContext context) {
    return context.findAncestorStateOfType<ShimmerState>();
  }

  @override
  State<Shimmer> createState() => ShimmerState();
}

class ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  Listenable get animation => _controller;
  double get value => _controller.value;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class ShimmerContainer extends StatelessWidget {
  const ShimmerContainer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  final double width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final shimmer = Shimmer.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF2C2C2C)
        : const Color(0xFFE0E0E0);
    final highlightColor = isDark
        ? const Color(0xFF3D3D3D)
        : const Color(0xFFF5F5F5);

    if (shimmer == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: borderRadius ?? BorderRadius.circular(8),
        ),
      );
    }

    if (kIsWeb) {
      return AnimatedBuilder(
        animation: shimmer.animation,
        builder: (context, child) {
          final opacity = 0.35 + (shimmer.value - 0.5).abs() * 0.4;
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: opacity),
              borderRadius: borderRadius ?? BorderRadius.circular(8),
            ),
          );
        },
      );
    }

    return AnimatedBuilder(
      animation: shimmer.animation,
      builder: (context, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: borderRadius ?? BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.3, 0.5, 0.7],
              transform: _SlidingGradientTransform(slidePercent: shimmer.value),
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {ui.TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent - 0.5) * 2,
      0.0,
      0.0,
    );
  }
}
