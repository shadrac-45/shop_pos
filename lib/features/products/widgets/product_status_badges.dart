/// ============================================
/// Product Status Badges — ShopPOS
/// ============================================
/// Small pills for stock and expiry state, used
/// on till cards, the inventory list and anywhere
/// else a product's health is shown. Colour only
/// from [AppTone]: amber = needs attention soon,
/// red = can't be sold. Every badge carries an
/// icon and words, never colour alone.
/// ============================================
library;

import 'package:flutter/material.dart';

import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/product_status.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final AppTone tone;

  /// Icon only (label goes to the tooltip/semantics), for tight spaces.
  final bool iconOnly;

  /// Full wording for screen readers when [label] is abbreviated.
  final String? semanticLabel;

  const StatusBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.tone,
    this.iconOnly = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: EdgeInsets.symmetric(horizontal: iconOnly ? 4 : 7, vertical: 3),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone.fg),
          if (!iconOnly) ...[
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: tone.text,
                  fontFeatures: AppText.tabular,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final full = semanticLabel ?? label;
    return Semantics(
      label: full,
      excludeSemantics: true,
      child: iconOnly ? Tooltip(message: full, child: pill) : pill,
    );
  }

  // ── Presets ─────────────────────────────────────────────

  /// [short] abbreviates the label for narrow cards; the full wording
  /// stays in the semantics label.
  static StatusBadge stock(StockLevel level, int units,
      {bool iconOnly = false, bool short = false}) {
    final full = level == StockLevel.out ? 'Out of stock' : 'Low stock, $units left';
    return switch (level) {
      StockLevel.out => StatusBadge(
          label: short ? 'Sold out' : 'Out of stock',
          semanticLabel: full,
          icon: Icons.remove_shopping_cart_rounded,
          tone: AppTone.danger,
          iconOnly: iconOnly),
      _ => StatusBadge(
          label: short ? 'Low · $units left' : 'Low stock · $units left',
          semanticLabel: full,
          icon: Icons.inventory_2_rounded,
          tone: AppTone.warning,
          iconOnly: iconOnly),
    };
  }

  static StatusBadge expiry(ExpiryState state, int? days,
      {bool iconOnly = false, bool short = false}) {
    if (state == ExpiryState.expired) {
      return StatusBadge(
          label: 'Expired', icon: Icons.event_busy_rounded, tone: AppTone.danger, iconOnly: iconOnly);
    }
    final full = days == null
        ? 'Expiring soon'
        : 'Expiring soon, ${days <= 1 ? '1 day' : '$days days'} left';
    final label = days == null
        ? (short ? 'Exp. soon' : 'Expiring soon')
        : short
            ? 'Exp. ${days <= 1 ? 1 : days}d'
            : 'Expires in ${days <= 1 ? '1 day' : '${days}d'}';
    return StatusBadge(
        label: label,
        semanticLabel: full,
        icon: Icons.schedule_rounded,
        tone: AppTone.warning,
        iconOnly: iconOnly);
  }
}

/// The status line for a product: nothing when all is well, otherwise the
/// most urgent badge first.
///
/// [forTill] uses what can be sold (expired leftovers don't matter to a
/// cashier); otherwise any expired stock on the shelf is flagged.
class ProductStatusBadges extends StatelessWidget {
  final Product product;
  final bool forTill;

  /// At most one full badge plus one icon-only badge, for tight cards.
  final bool compact;

  const ProductStatusBadges({
    super.key,
    required this.product,
    this.forTill = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final h = product.health; // cached single-pass snapshot
    final level = h.stock;
    final expiry = forTill ? h.tillExpiry : h.shelfExpiry;
    final units = h.sellable;

    final badges = <StatusBadge>[];
    // An "expired" product with nothing sellable reads as expired, not as
    // out of stock: that tells the owner why, and what to do.
    if (expiry == ExpiryState.expired && level == StockLevel.out) {
      badges.add(StatusBadge.expiry(expiry, null, short: compact));
    } else {
      if (level != StockLevel.normal) {
        badges.add(StatusBadge.stock(level, units, short: compact));
      }
      if (expiry != ExpiryState.normal) {
        badges.add(StatusBadge.expiry(expiry, h.daysToNextExpiry,
            iconOnly: compact && badges.isNotEmpty, short: compact));
      }
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    if (compact) {
      return Row(
        children: [
          Flexible(child: badges.first),
          if (badges.length > 1) ...[const SizedBox(width: 4), badges[1]],
        ],
      );
    }
    return Wrap(spacing: 6, runSpacing: 4, children: badges);
  }
}

/// True when [ProductStatusBadges] would show something.
bool hasProductAlert(Product p, {bool forTill = false}) =>
    p.health.alert(forTill: forTill);

/// Kept for callers that only need a colour for a stock figure.
Color stockTextColor(StockLevel level) => switch (level) {
      StockLevel.out => AppColors.dangerDarkText,
      StockLevel.low => AppColors.warningDarkText,
      StockLevel.normal => AppColors.textSecondary,
    };
