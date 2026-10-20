import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';

/// Headings use Space Grotesk; everything else inherits Plus Jakarta Sans.
TextTheme gawagoTextTheme(TextTheme base) {
  TextStyle? heading(TextStyle? style) =>
      style?.copyWith(fontFamily: GawaGoColors.fontHeading);
  return base
      .apply(fontFamily: GawaGoColors.fontBody)
      .copyWith(
        displayLarge: heading(base.displayLarge),
        displayMedium: heading(base.displayMedium),
        displaySmall: heading(base.displaySmall),
        headlineLarge: heading(base.headlineLarge),
        headlineMedium: heading(base.headlineMedium),
        headlineSmall: heading(base.headlineSmall),
        titleLarge: heading(base.titleLarge),
      );
}

const gawagoCardShadow = [
  BoxShadow(color: Color(0x1A1F2A19), blurRadius: 22, offset: Offset(0, 8)),
];

/// Heading font for widgets that build their own [TextStyle].
TextStyle gawagoHeading({
  double? fontSize,
  FontWeight fontWeight = FontWeight.w700,
  Color color = GawaGoColors.ink,
  double? height,
}) {
  return TextStyle(
    fontFamily: GawaGoColors.fontHeading,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: -0.2,
  );
}

ThemeData authenticatedTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: GawaGoColors.primary,
        brightness: Brightness.light,
        surface: GawaGoColors.surface,
      ).copyWith(
        primary: GawaGoColors.leafDeep,
        onPrimary: Colors.white,
        primaryContainer: GawaGoColors.leafTint,
        onPrimaryContainer: GawaGoColors.leafDeep,
        secondaryContainer: GawaGoColors.leafTint,
        onSecondaryContainer: GawaGoColors.leafDeep,
        surface: GawaGoColors.surface,
        onSurface: GawaGoColors.ink,
        onSurfaceVariant: GawaGoColors.textMuted,
        outline: GawaGoColors.lineStrong,
        outlineVariant: GawaGoColors.border,
        error: GawaGoColors.danger,
      );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
  );
  const buttonText = TextStyle(
    fontFamily: GawaGoColors.fontBody,
    fontWeight: FontWeight.w700,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: GawaGoColors.fontBody,
  );
  return base.copyWith(
    textTheme: gawagoTextTheme(base.textTheme),
    scaffoldBackgroundColor: Colors.transparent,
    cardTheme: CardThemeData(
      color: GawaGoColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: GawaGoColors.border),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: GawaGoColors.sidebar,
      foregroundColor: GawaGoColors.cream,
      elevation: 8,
      shadowColor: Color(0x2E1A2415),
      centerTitle: false,
      toolbarHeight: 56,
      titleTextStyle: TextStyle(
        fontFamily: GawaGoColors.fontHeading,
        color: GawaGoColors.cream,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: GawaGoColors.surface,
      indicatorColor: GawaGoColors.leafTint,
      elevation: 8,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GawaGoColors.primary,
        foregroundColor: GawaGoColors.onPrimary,
        disabledBackgroundColor: GawaGoColors.primary.withValues(alpha: 0.4),
        disabledForegroundColor: GawaGoColors.onPrimary.withValues(alpha: 0.6),
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: GawaGoColors.primary,
        foregroundColor: GawaGoColors.onPrimary,
        elevation: 0,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: GawaGoColors.leafDeep,
        side: const BorderSide(color: GawaGoColors.primary, width: 1.5),
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: GawaGoColors.leafDeep,
        textStyle: buttonText,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: GawaGoColors.leafTint,
      selectedColor: GawaGoColors.primary,
      side: const BorderSide(color: GawaGoColors.leafLine),
      labelStyle: const TextStyle(
        color: GawaGoColors.leafDeep,
        fontWeight: FontWeight.w700,
      ),
      shape: const StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GawaGoColors.input,
      hintStyle: const TextStyle(color: GawaGoColors.textFaint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: GawaGoColors.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: GawaGoColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: GawaGoColors.primary, width: 1.5),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: GawaGoColors.leafDeep,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: GawaGoColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: GawaGoColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: GawaGoColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: GawaGoColors.border,
  );
}

class AuthenticatedBackground extends StatelessWidget {
  const AuthenticatedBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: GawaGoColors.workspace, child: child);
  }
}

class AuthenticatedScaffold extends StatefulWidget {
  const AuthenticatedScaffold({
    super.key,
    required this.roleLabel,
    required this.mainDestinations,
    required this.accountDestinations,
    required this.onLogout,
    required this.child,
    this.title = 'GawaGo',
    this.actions = const [],
  });

  final String title;
  final String roleLabel;
  final List<GawaGoDrawerDestination> mainDestinations;
  final List<GawaGoDrawerDestination> accountDestinations;
  final VoidCallback onLogout;
  final List<Widget> actions;
  final Widget child;

  @override
  State<AuthenticatedScaffold> createState() => _AuthenticatedScaffoldState();
}

class AuthenticatedDetailScaffold extends StatelessWidget {
  const AuthenticatedDetailScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.bottomNavigationBar,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          MobileDashboardDetailTopbar(
            title: title,
            onBack: () => Navigator.maybePop(context),
            actions: actions,
          ),
          Expanded(child: AuthenticatedBackground(child: child)),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class MobileDashboardDetailTopbar extends StatelessWidget {
  const MobileDashboardDetailTopbar({
    super.key,
    required this.title,
    required this.onBack,
    this.actions = const [],
  });

  final String title;
  final VoidCallback onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: const BoxDecoration(
          color: GawaGoColors.sidebar,
          boxShadow: [
            BoxShadow(
              color: Color(0x2E1A2415),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: GawaGoColors.fontHeading,
                  color: GawaGoColors.cream,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            IconTheme(
              data: const IconThemeData(color: Colors.white),
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthenticatedScaffoldState extends State<AuthenticatedScaffold> {
  bool _menuOpen = false;

  void _setMenuOpen(bool value) {
    if (_menuOpen == value) return;
    setState(() => _menuOpen = value);
  }

  GawaGoDrawerDestination _closeAfterTap(GawaGoDrawerDestination destination) {
    return GawaGoDrawerDestination(
      icon: destination.icon,
      label: destination.label,
      selected: destination.selected,
      onTap: () {
        _setMenuOpen(false);
        destination.onTap();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mainDestinations = widget.mainDestinations
        .map(_closeAfterTap)
        .toList();
    final accountDestinations = widget.accountDestinations
        .map(_closeAfterTap)
        .toList();

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              MobileDashboardTopbar(
                title: widget.title,
                open: _menuOpen,
                onMenuPressed: () => _setMenuOpen(!_menuOpen),
                actions: widget.actions,
              ),
              Expanded(child: AuthenticatedBackground(child: widget.child)),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_menuOpen,
              child: AnimatedOpacity(
                opacity: _menuOpen ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: GestureDetector(
                  onTap: () => _setMenuOpen(false),
                  child: Container(color: const Color(0x731A2415)),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            left: _menuOpen ? 0 : -320,
            width: MediaQuery.sizeOf(context).width * 0.72 > 300
                ? 300
                : MediaQuery.sizeOf(context).width * 0.72,
            child: _DashboardSidebarPanel(
              roleLabel: widget.roleLabel,
              mainDestinations: mainDestinations,
              accountDestinations: accountDestinations,
              onLogout: () {
                _setMenuOpen(false);
                widget.onLogout();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MobileDashboardTopbar extends StatelessWidget {
  const MobileDashboardTopbar({
    super.key,
    required this.title,
    required this.open,
    required this.onMenuPressed,
    this.actions = const [],
  });

  final String title;
  final bool open;
  final VoidCallback onMenuPressed;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: const BoxDecoration(
          color: GawaGoColors.sidebar,
          boxShadow: [
            BoxShadow(
              color: Color(0x2E1A2415),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _BurgerButton(open: open, onPressed: onMenuPressed),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: GawaGoColors.fontHeading,
                  color: GawaGoColors.cream,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            IconTheme(
              data: const IconThemeData(color: Colors.white),
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ],
        ),
      ),
    );
  }
}

class _BurgerButton extends StatelessWidget {
  const _BurgerButton({required this.open, required this.onPressed});

  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    Widget bar(int index) {
      final top = index == 0;
      final bottom = index == 2;
      final offsetY = open && top
          ? 7.0
          : open && bottom
          ? -7.0
          : 0.0;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 18,
        height: 2,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
        transform: Matrix4.identity()
          ..setTranslationRaw(0.0, offsetY, 0.0)
          ..rotateZ(
            open && top
                ? 0.785398
                : open && bottom
                ? -0.785398
                : 0,
          ),
      );
    }

    return SizedBox(
      width: 40,
      height: 40,
      child: Tooltip(
        message: 'Open navigation menu',
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white.withValues(alpha: 0.10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              bar(0),
              AnimatedOpacity(
                opacity: open ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: bar(1),
                ),
              ),
              bar(2),
            ],
          ),
        ),
      ),
    );
  }
}

class MobileDashboardAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const MobileDashboardAppBar({
    super.key,
    this.title = 'GawaGo Community Platform',
    this.actions = const [],
  });

  final String title;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leadingWidth: 62,
      leading: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.only(left: 14),
          child: IconButton(
            tooltip: 'Open navigation menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              fixedSize: const Size(40, 40),
              minimumSize: const Size(40, 40),
            ),
            icon: const Icon(Icons.menu_rounded, size: 28),
          ),
        ),
      ),
      title: Text(title),
      actions: actions,
    );
  }
}

class GawaGoDrawerDestination {
  const GawaGoDrawerDestination({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
}

class GawaGoDashboardDrawer extends StatelessWidget {
  const GawaGoDashboardDrawer({
    super.key,
    required this.roleLabel,
    required this.mainDestinations,
    required this.accountDestinations,
    required this.onLogout,
  });

  final String roleLabel;
  final List<GawaGoDrawerDestination> mainDestinations;
  final List<GawaGoDrawerDestination> accountDestinations;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 292,
      backgroundColor: GawaGoColors.sidebar,
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 22, 20, 20),
              child: _DrawerBrand(),
            ),
            const Divider(height: 1, color: Color(0x1AF5F1E6)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 22, 14, 16),
                children: [
                  ...mainDestinations.map(_DrawerItem.new),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: Text(
                      roleLabel.toUpperCase(),
                      style: const TextStyle(
                        color: GawaGoColors.sidebarSection,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  ...accountDestinations.map(_DrawerItem.new),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout, size: 22),
                  label: const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Log Out'),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GawaGoColors.logout,
                    backgroundColor: const Color(0x1AD08A76),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: GawaGoColors.fontBody,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardSidebarPanel extends StatelessWidget {
  const _DashboardSidebarPanel({
    required this.roleLabel,
    required this.mainDestinations,
    required this.accountDestinations,
    required this.onLogout,
  });

  final String roleLabel;
  final List<GawaGoDrawerDestination> mainDestinations;
  final List<GawaGoDrawerDestination> accountDestinations;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GawaGoColors.sidebar,
      elevation: 18,
      shadowColor: const Color(0x47081810),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: _DrawerBrand(compact: true),
            ),
            const Divider(height: 1, color: Color(0x1AF5F1E6)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  ...mainDestinations.map(_DrawerItem.new),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                    child: Text(
                      roleLabel.toUpperCase(),
                      style: const TextStyle(
                        color: GawaGoColors.sidebarSection,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  ...accountDestinations.map(_DrawerItem.new),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout, size: 20),
                  label: const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Log Out'),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GawaGoColors.logout,
                    backgroundColor: const Color(0x1AD08A76),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: GawaGoColors.fontBody,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerBrand extends StatelessWidget {
  const _DrawerBrand({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: compact ? 40 : 48,
          height: compact ? 40 : 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: GawaGoColors.primary,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Text(
            'GG',
            style: TextStyle(
              fontFamily: GawaGoColors.fontHeading,
              color: GawaGoColors.onPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'GawaGo Community\nPlatform',
            style: TextStyle(
              fontFamily: GawaGoColors.fontHeading,
              color: GawaGoColors.cream,
              fontSize: compact ? 14.5 : 16,
              height: 1.3,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem(this.destination);

  final GawaGoDrawerDestination destination;

  @override
  Widget build(BuildContext context) {
    final foreground = destination.selected
        ? GawaGoColors.primary
        : GawaGoColors.mutedText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: destination.selected
            ? const Color(0x299EBF5E)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: destination.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(destination.icon, color: foreground, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    destination.label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationControlsCard extends StatelessWidget {
  const NotificationControlsCard({
    super.key,
    required this.onChooseDate,
    required this.onClearDate,
    required this.onMarkAllRead,
    this.selectedDateLabel,
    this.markingAllRead = false,
  });

  final VoidCallback onChooseDate;
  final VoidCallback onClearDate;
  final VoidCallback onMarkAllRead;
  final String? selectedDateLabel;
  final bool markingAllRead;

  @override
  Widget build(BuildContext context) {
    final hasFilter = selectedDateLabel != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: onChooseDate,
              icon: const Icon(Icons.filter_alt_outlined),
              label: Text(hasFilter ? selectedDateLabel! : 'Filter Date'),
            ),
            if (hasFilter) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onClearDate,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Clear date filter'),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: markingAllRead ? null : onMarkAllRead,
              icon: markingAllRead
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_all),
              label: Text(markingAllRead ? 'Marking...' : 'Mark all as read'),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationActionMenu extends StatelessWidget {
  const NotificationActionMenu({
    super.key,
    required this.onSelected,
    this.showMarkRead = false,
  });

  final ValueChanged<String> onSelected;
  final bool showMarkRead;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Notification options',
      icon: const Icon(Icons.more_vert),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onSelected: onSelected,
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'details', child: Text('View Details')),
        if (showMarkRead)
          const PopupMenuItem(value: 'read', child: Text('Mark as read')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}
