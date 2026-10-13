/// ============================================
/// Main Shell Screen — ShopPOS
/// ============================================
/// Navigation shell that switches between the
/// app's top-level destinations (Sales, Products,
/// Reports, Settings).
///
/// A frosted bottom bar on phones, a floating
/// frosted sidebar on wide screens (tablets,
/// desktops), over the ambient canvas.
///
/// Uses [IndexedStack] so tab state (search queries,
/// scroll positions, loaded data) is preserved.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/constants/app_assets.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/responsive/app_breakpoints.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_motion.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/screens/owner_products_screen.dart';
import 'package:shop_pos/features/reports/screens/daily_report_screen.dart';
import 'package:shop_pos/features/sales/screens/cashier_history_screen.dart';
import 'package:shop_pos/features/sales/screens/cashier_sales_screen.dart';
import 'package:shop_pos/features/settings/screens/settings_screen.dart';
import 'package:shop_pos/features/settings/widgets/change_pin_dialog.dart';
import 'package:shop_pos/features/settings/widgets/cloud_section.dart' show SyncStatusChip;
import 'package:shop_pos/features/cloud/screens/alerts_screens.dart';
import 'package:shop_pos/features/notifications/notification_center.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';
import 'package:shop_pos/features/shared/widgets/sign_out_button.dart';

class _NavDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget body;

  const _NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.body,
  });
}

class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  int _currentIndex = 0;

  static const _sales = _NavDestination(
    label: 'Sales',
    icon: Icons.point_of_sale_outlined,
    selectedIcon: Icons.point_of_sale_rounded,
    body: CashierSalesScreen(),
  );
  static const _mySales = _NavDestination(
    label: 'My Sales',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
    body: CashierHistoryScreen(),
  );
  static const _products = _NavDestination(
    label: 'Products',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2_rounded,
    body: OwnerProductsScreen(),
  );
  static const _reports = _NavDestination(
    label: 'Reports',
    icon: Icons.analytics_outlined,
    selectedIcon: Icons.analytics_rounded,
    body: DailyReportScreen(),
  );
  static const _settings = _NavDestination(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    body: SettingsScreen(),
  );

  /// Tabs follow the role's permissions (see [Permissions]), so a manager
  /// gets the owner's screens and a stock clerk gets only Products.
  static List<_NavDestination> _destinationsFor(AppUser? user) {
    final canReport = Permissions.can(user, Permission.viewReports);
    final canStock = Permissions.can(user, Permission.restock) ||
        Permissions.can(user, Permission.manageProducts);
    return [
      if (Permissions.can(user, Permission.sell)) _sales,
      if (Permissions.can(user, Permission.sell) && !canReport) _mySales,
      if (canStock) _products,
      if (canReport) _reports,
      _settings,
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _promptIfDefaultPin();
      // Owners/managers on a cloud till: today's important alerts.
      if (mounted) await showLoginAlertSummary(context, ref);
    });
  }

  /// A user who still has a default PIN (the owner, signing in by email)
  /// is asked to replace it straight away; PIN login refuses it anyway.
  Future<void> _promptIfDefaultPin() async {
    final auth = ref.read(currentUserProvider.notifier);
    final user = ref.read(currentUserProvider);
    if (!mounted || user == null || !await auth.hasDefaultPin()) return;
    if (!mounted) return;

    final changed = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangePinDialog(user: user),
    );
    if (!mounted) return;
    if (changed == true) {
      context.showSuccessSnackbar('Your PIN has been updated.');
    } else {
      context.showErrorSnackbar(
        'Your PIN is still a default PIN, so PIN login stays disabled for '
        'you. Change it in Settings → Change PIN.',
      );
    }
  }

  /// Navigation back to the role picker is handled app-wide in
  /// [ShopPOSApp] whenever the user becomes null.
  void _logout() => confirmAndSignOut(context, ref);

  Future<void> _changePin(AppUser user) async {
    final changed = await showAppDialog<bool>(
      context: context,
      builder: (_) => ChangePinDialog(user: user),
    );
    if (changed == true && mounted) {
      context.showSuccessSnackbar('Your PIN has been updated.');
    }
  }

  void _select(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final storeName = ref.watch(storeSettingsProvider).storeName.trim();

    final destinations = _destinationsFor(user);
    final safeIndex = _currentIndex.clamp(0, destinations.length - 1);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppBreakpoints.rail;

    final body = IndexedStack(
      index: safeIndex,
      children: destinations.map((d) => d.body).toList(),
    );

    final header = _ShellHeader(
      storeName: storeName,
      title: destinations[safeIndex].label,
      showBrand: !wide,
      trailing: [
        const SyncStatusChip(),
        const SizedBox(width: AppSpacing.xs),
        const NotificationBell(),
        if (user != null)
          _AccountButton(
            user: user,
            showName: wide,
            onChangePin: () => _changePin(user),
            onLogout: _logout,
          ),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: AmbientBackdrop(
        child: SafeArea(
          bottom: false,
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md, AppSpacing.md, 0, AppSpacing.md),
                      child: _Sidebar(
                        destinations: destinations,
                        selectedIndex: safeIndex,
                        onSelect: _select,
                        expanded: width >= 1200,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          header,
                          Expanded(child: body),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    header,
                    Expanded(child: body),
                  ],
                ),
        ),
      ),
      // NavigationBar needs two or more destinations; during sign-out the
      // user is briefly null and only Settings remains.
      bottomNavigationBar: wide || destinations.length < 2
          ? null
          : _BottomBar(
              destinations: destinations,
              selectedIndex: safeIndex,
              onSelect: _select,
            ),
    );
  }
}

/// Page title on the canvas, with the store name above it and the sync
/// chip, notifications and account on the right. No bar fill: the page
/// content is the focus, not the chrome.
class _ShellHeader extends StatelessWidget {
  final String storeName;
  final String title;
  final bool showBrand;
  final List<Widget> trailing;

  const _ShellHeader({
    required this.storeName,
    required this.title,
    required this.showBrand,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            if (showBrand) ...[
              const _BrandMark(size: 38),
              const SizedBox(width: AppSpacing.md),
            ] else
              const SizedBox(width: AppSpacing.sm),
            // Store name above the page title on its own line, so it never
            // gets squeezed out by the sync chip on narrow screens.
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (storeName.isNotEmpty)
                    Text(
                      storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  AnimatedSwitcher(
                    duration: AppMotion.fast,
                    transitionBuilder: (child, a) =>
                        FadeTransition(opacity: a, child: child),
                    child: Text(
                      title,
                      key: ValueKey(title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...trailing,
          ],
        ),
      ),
    );
  }
}

/// Floating frosted sidebar for tablets and desktops. Labels sit beside
/// the icons when there is room (≥ 1200dp), under them otherwise.
class _Sidebar extends StatelessWidget {
  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool expanded;

  const _Sidebar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: SizedBox(
        width: expanded ? 220 : 92,
        // Scrolls rather than overflowing on short landscape screens.
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
          crossAxisAlignment:
              expanded ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(expanded ? AppSpacing.lg : 0,
                  AppSpacing.lg, expanded ? AppSpacing.lg : 0, AppSpacing.xl),
              child: Row(
                mainAxisAlignment:
                    expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  const _BrandMark(size: 42),
                  if (expanded) ...[
                    const SizedBox(width: AppSpacing.md),
                    const Text(
                      'ShopPOS',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            for (var i = 0; i < destinations.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 3),
                child: _SidebarItem(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  expanded: expanded,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _NavDestination destination;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.primaryDark : AppColors.textSecondary;
    final icon = Icon(
      selected ? destination.selectedIcon : destination.icon,
      color: fg,
      size: 24,
    );
    final label = Text(
      destination.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: expanded ? TextAlign.start : TextAlign.center,
      style: TextStyle(
        color: selected ? AppColors.textPrimary : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: expanded ? 15 : 11.5,
      ),
    );

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppSpacing.borderMd,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 52),
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? AppSpacing.md : AppSpacing.xs,
              vertical: expanded ? AppSpacing.md : 10,
            ),
            // The active page is a solid white pill on the glass: the one
            // opaque thing in the sidebar, so it is found at a glance.
            decoration: BoxDecoration(
              color: selected ? AppColors.cardBg : Colors.transparent,
              borderRadius: AppSpacing.borderMd,
              border: Border.all(
                color: selected ? AppColors.border : Colors.transparent,
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                          color: Color(0x0D18201C),
                          blurRadius: 8,
                          offset: Offset(0, 2)),
                    ]
                  : null,
            ),
            child: expanded
                ? Row(children: [
                    icon,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: label),
                    if (selected)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ])
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    icon,
                    const SizedBox(height: 4),
                    label,
                  ]),
          ),
        ),
      ),
    );
  }
}

/// Phone navigation: the Material bar inside a frosted strip.
class _BottomBar extends StatelessWidget {
  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _BottomBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.zero,
      shadow: false,
      child: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelect,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

// The ShopPOS logo on a white tile.
class _BrandMark extends StatelessWidget {
  final double size;
  const _BrandMark({this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.14),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: AppSpacing.borderMd,
          border: Border.all(color: AppColors.border),
        ),
        child: Semantics(
          label: 'ShopPOS',
          image: true,
          child: Image.asset(AppAssets.shopposLogo, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// Profile control in the header: a compact chip (avatar, name, role) on
/// wide screens, the avatar alone on phones. Opens a menu with Change PIN
/// and Sign out — sign-out lives here rather than as a large button, and
/// never as a bare icon that is easy to hit mid-sale.
class _AccountButton extends StatelessWidget {
  final AppUser user;
  final bool showName;
  final VoidCallback onChangePin;
  final VoidCallback onLogout;

  const _AccountButton({
    required this.user,
    required this.showName,
    required this.onChangePin,
    required this.onLogout,
  });

  String get _initials {
    final parts = user.name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  Widget _avatar(double radius) => CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primaryLight,
        child: Text(
          _initials,
          style: TextStyle(
            color: AppColors.primaryDark,
            fontSize: radius * 0.75,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final role = AppConstants.roleLabel(user.role);
    return MenuAnchor(
      // MenuAnchor keeps the menu on screen by itself; just a small gap.
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.cardBg),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: const WidgetStatePropertyAll(Color(0x2618201C)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: AppSpacing.borderLg,
          side: const BorderSide(color: AppColors.border),
        )),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(AppSpacing.sm)),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
          child: Row(
            children: [
              _avatar(20),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(role, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            ],
          ),
        ),
        const Divider(),
        const SizedBox(height: AppSpacing.xs),
        MenuItemButton(
          leadingIcon: const Icon(Icons.pin_outlined, size: 20, color: AppColors.textSecondary),
          onPressed: onChangePin,
          style: _menuItemStyle(),
          child: const Text('Change PIN'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout_rounded, size: 20, color: AppColors.danger),
          onPressed: onLogout,
          style: _menuItemStyle(danger: true),
          child: const Text('Sign out'),
        ),
      ],
      builder: (context, controller, _) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        if (!showName) {
          return Tooltip(
            message: '${user.name} · $role',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: toggle,
              child: Padding(padding: const EdgeInsets.all(4), child: _avatar(19)),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          child: Material(
            color: AppColors.cardBg,
            shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: toggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _avatar(16),
                    const SizedBox(width: AppSpacing.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13, height: 1.2)),
                          Text(role,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 11.5, height: 1.2)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static ButtonStyle _menuItemStyle({bool danger = false}) => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(220, 44)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpacing.md)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppSpacing.borderSm)),
        foregroundColor:
            WidgetStatePropertyAll(danger ? AppColors.dangerDarkText : AppColors.textPrimary),
        overlayColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ||
                s.contains(WidgetState.pressed) ||
                s.contains(WidgetState.focused)
            ? (danger ? AppColors.dangerTint : AppColors.surfaceBg)
            : null),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );
}
