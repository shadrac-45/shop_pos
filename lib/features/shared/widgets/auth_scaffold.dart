/// ============================================
/// Auth Scaffold — ShopPOS
/// ============================================
/// Shared frame for the sign-in flow (welcome,
/// role select, admin login, staff PIN).
///
/// Wide screens: a split layout — a deep green
/// brand panel with a live-looking product
/// preview (sales card, receipt, stock alert)
/// built from the same glass language as the
/// till, beside a clean white form side.
/// Phones: the ambient canvas with a compact
/// brand banner above the form when there is
/// room for it.
///
/// Original composition; direction from the
/// "classic split with product preview" login
/// pattern common to modern SaaS sign-in pages.
/// ============================================
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:shop_pos/core/constants/app_assets.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';
import 'package:shop_pos/features/shared/widgets/magic/dot_pattern.dart';

/// From this width the brand panel sits beside the form.
const double _splitWidth = 900;

class AuthScaffold extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  /// Show the brand panel / banner. Off for screens that need every
  /// pixel (e.g. a tall form on a short phone).
  final bool showcase;

  const AuthScaffold({
    super.key,
    required this.child,
    this.maxWidth = 380,
    this.showcase = true,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= _splitWidth;

    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showcase && !wide && size.height >= 760) ...[
                const _BrandBanner(),
                const SizedBox(height: AppSpacing.xl),
              ],
              child,
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: AmbientBackdrop(
        child: SafeArea(
          child: wide && showcase
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(
                      flex: 11,
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: _BrandPanel(),
                      ),
                    ),
                    Expanded(flex: 10, child: form),
                  ],
                )
              : form,
        ),
      ),
    );
  }
}

// ── Brand mark ─────────────────────────────────────────────────────────

/// The ShopPOS logo on a white tile, as in the app's sidebar.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 52});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x14047857), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Semantics(
        label: 'ShopPOS',
        image: true,
        child: Image.asset(AppAssets.shopposLogo, fit: BoxFit.contain),
      ),
    );
  }
}

/// Logo, title and subtitle at the top of an auth screen.
class AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  /// True when drawn on a dark surface; the sign-in flow is light now, so
  /// this defaults to false.
  final bool onInk;
  final CrossAxisAlignment alignment;

  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onInk = false,
    this.alignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final centered = alignment == CrossAxisAlignment.center;
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        const BrandMark(),
        const SizedBox(height: AppSpacing.lg),
        Text(
          title,
          textAlign: textAlign,
          style: TextStyle(
            color: onInk ? AppColors.onInk : AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: textAlign,
          style: TextStyle(
            color: onInk ? AppColors.onInkMuted : AppColors.textSecondary,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// A large tappable choice ("Admin", "Staff", ...): white card, hairline
/// border, green-tinted icon tile when [color] is the brand green.
class RoleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const RoleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = color == AppColors.primary;
    return Material(
      color: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderLg,
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.borderLg,
        hoverColor: AppColors.primarySoft,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: brand ? AppColors.primaryLight : AppColors.surfaceBg,
                borderRadius: AppSpacing.borderMd,
              ),
              child: Icon(icon, color: brand ? AppColors.primaryDark : AppColors.textSecondary, size: 24),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ]),
            ),
            const Icon(Icons.arrow_forward_rounded,
                color: AppColors.textMuted, size: 20),
          ]),
        ),
      ),
    );
  }
}

// ── Brand panel ────────────────────────────────────────────────────────

/// Deep green gradient with a faint glow and dot texture — the base both
/// the full panel and the phone banner sit on.
class _GreenSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  const _GreenSurface({required this.child, required this.radius});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryDark, AppColors.primary],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DotPattern(color: Color(0x1FFFFFFF), fadeCenter: Alignment.topRight),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.8, -0.6),
                      radius: 0.9,
                      colors: [Color(0x406EE7B7), Color(0x006EE7B7)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(child: child),
          ],
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return const _GreenSurface(
      radius: BorderRadius.all(Radius.circular(28)),
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BrandMark(size: 40),
                SizedBox(width: AppSpacing.md),
                Text('ShopPOS',
                    style: TextStyle(
                        color: AppColors.onInk,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4)),
              ],
            ),
            Spacer(),
            Expanded(
              flex: 6,
              // Decorative mock data: hidden from screen readers.
              child: ExcludeSemantics(child: Center(child: FittedBox(child: _ProductPreview()))),
            ),
            Spacer(),
            Text(
              'Run your shop\nwith confidence.',
              style: TextStyle(
                color: AppColors.onInk,
                fontSize: 34,
                height: 1.12,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.0,
              ),
            ),
            SizedBox(height: AppSpacing.md),
            Text(
              'Sales, stock and expiry in one place — online or off.',
              style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 16, height: 1.4),
            ),
            SizedBox(height: AppSpacing.xl),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              children: [
                _Feature('Works offline'),
                _Feature('Stock & expiry alerts'),
                _Feature('Syncs every till'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final String label;
  const _Feature(this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.successOnInk),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: AppColors.onInk, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Phone banner: the green surface with the headline beside a tilted
/// receipt.
class _BrandBanner extends StatelessWidget {
  const _BrandBanner();

  static const double _edge = 16;

  /// Space between the text and the card, including what the tilt adds
  /// to the card's corners (136 × sin 0.06 ≈ 8).
  static const double _gap = 18;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: _GreenSurface(
        radius: const BorderRadius.all(Radius.circular(24)),
        child: LayoutBuilder(builder: (context, c) {
          // The card gets a fixed slice of the width and the text the
          // rest, so the card can never grow into the headline.
          final cardWidth = (c.maxWidth * 0.34).clamp(92.0, 150.0);
          // Smallest phones: a size down keeps the headline to two lines.
          final narrow = c.maxWidth < 300;
          return Stack(
            children: [
              Positioned(
                right: _edge,
                top: _edge,
                bottom: _edge,
                width: cardWidth,
                child: Transform.rotate(
                  angle: -0.06,
                  child: const ExcludeSemantics(
                    child: FittedBox(child: _ReceiptCard()),
                  ),
                ),
              ),
              // Painted last: the words always sit above the decoration.
              Positioned(
                left: 20,
                top: 20,
                right: _edge + cardWidth + _gap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Run your shop\nwith confidence.',
                        style: TextStyle(
                            color: AppColors.onInk,
                            fontSize: narrow ? 17 : 19,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5)),
                    const SizedBox(height: 8),
                    const Text('Sales, stock & expiry — online or off.',
                        style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ── Product preview (illustration built from UI) ───────────────────────

/// A composed glimpse of the product: today's sales, a receipt, a stock
/// alert and a payment confirmation, floating on the green panel.
class _ProductPreview extends StatelessWidget {
  const _ProductPreview();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 440,
      height: 340,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, top: 24, child: _SalesCard()),
          Positioned(
            right: 0,
            top: 0,
            child: RotationTransition(
              turns: AlwaysStoppedAnimation(0.012),
              child: _ReceiptCard(),
            ),
          ),
          Positioned(left: 24, bottom: 34, child: _GlassChip(
            icon: Icons.inventory_2_rounded,
            iconColor: AppColors.warningOnInk, // low-stock meaning
            title: 'Sugar 1kg',
            subtitle: 'Low stock · 3 left',
          )),
          Positioned(right: 36, bottom: 0, child: _GlassChip(
            icon: Icons.check_circle_rounded,
            iconColor: AppColors.successOnInk,
            title: 'Payment received',
            subtitle: 'MoMo · GH₵ 82.00',
          )),
        ],
      ),
    );
  }
}

/// Frosted white-on-green card.
class _GreenGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _GreenGlass({required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x33022C22), blurRadius: 30, offset: Offset(0, 14)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: const Color(0x24FFFFFF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x40FFFFFF)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SalesCard extends StatelessWidget {
  const _SalesCard();

  @override
  Widget build(BuildContext context) {
    const bars = [0.42, 0.58, 0.47, 0.72, 0.64, 0.86, 1.0];
    return SizedBox(
      width: 236,
      child: _GreenGlass(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("TODAY'S SALES",
                style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('GH₵ 4,820.50',
                  style: AppText.money(size: 26, weight: FontWeight.w800, color: AppColors.onInk)),
            ),
            const SizedBox(height: 2),
            const Row(
              children: [
                Icon(Icons.trending_up_rounded, size: 16, color: AppColors.successOnInk),
                SizedBox(width: 4),
                Flexible(
                  child: Text('12% vs yesterday',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < bars.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: FractionallySizedBox(
                        heightFactor: bars[i],
                        alignment: Alignment.bottomCenter,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: i == bars.length - 1
                                ? AppColors.onInk
                                : const Color(0x59FFFFFF),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A paper receipt: solid white with charcoal text — the one opaque thing
/// in the composition, just as figures stay solid in the app itself.
class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard();

  @override
  Widget build(BuildContext context) {
    TextStyle line({bool bold = false}) => TextStyle(
          color: bold ? AppColors.textPrimary : AppColors.textSecondary,
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          fontFeatures: AppText.tabular,
        );
    Widget row(String l, String r, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
                child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: line(bold: bold))),
            const SizedBox(width: 6),
            Text(r, style: line(bold: bold)),
          ]),
        );

    return Container(
      width: 196,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Color(0x40022C22), blurRadius: 32, offset: Offset(0, 16)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.receipt_long_rounded, size: 14, color: AppColors.primaryDark),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text('Receipt #1042',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          row('Milo Tin 400g', '52.00'),
          row('Voltic Water ×6', '30.00'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: _DashedLine(),
          ),
          row('Total', 'GH₵ 82.00', bold: true),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.primaryLight),
              ),
              child: const Text('PAID',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppColors.primaryDark)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = (c.maxWidth / 7).floor();
      return Row(
        children: [
          for (var i = 0; i < n; i++)
            Expanded(
              child: Container(
                height: 1.2,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                color: AppColors.border,
              ),
            ),
        ],
      );
    });
  }
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _GlassChip({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return _GreenGlass(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0x26FFFFFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: AppColors.onInk, fontSize: 13, fontWeight: FontWeight.w700)),
              Text(subtitle,
                  style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
