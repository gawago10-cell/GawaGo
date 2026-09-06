import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';

ThemeData authenticatedTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: GawaGoColors.primary,
    brightness: Brightness.light,
    surface: GawaGoColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.transparent,
    cardTheme: CardThemeData(
      color: GawaGoColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: GawaGoColors.border),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0F2D1F),
      foregroundColor: Colors.white,
      elevation: 8,
      shadowColor: Color(0x2E0F2D1F),
      centerTitle: false,
      toolbarHeight: 56,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFFF8FCF9),
      indicatorColor: GawaGoColors.primary.withValues(alpha: 0.18),
      elevation: 8,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GawaGoColors.input,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: GawaGoColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: GawaGoColors.border),
      ),
    ),
    dividerColor: GawaGoColors.border,
  );
}

class AuthenticatedBackground extends StatelessWidget {
  const AuthenticatedBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5F0E8), Color(0xFFFFFDF8), Color(0xFFF5F0E8)],
        ),
      ),
      child: child,
    );
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
          color: Color(0xFF0F2D1F),
          boxShadow: [
            BoxShadow(
              color: Color(0x2E0F2D1F),
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
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
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
                  child: Container(color: const Color(0x73103D29)),
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
          color: Color(0xFF0F2D1F),
          boxShadow: [
            BoxShadow(
              color: Color(0x2E0F2D1F),
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
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
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
      backgroundColor: GawaGoColors.deepGreen,
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 22, 20, 20),
              child: _DrawerBrand(),
            ),
            const Divider(height: 1, color: Color(0xFF1F4030)),
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
                        color: Color(0xFF789D85),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
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
                    foregroundColor: const Color(0xFFFF9B9B),
                    side: const BorderSide(color: Color(0xFF6A2B2B)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
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
      color: GawaGoColors.deepGreen,
      elevation: 18,
      shadowColor: const Color(0x47081810),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: _DrawerBrand(compact: true),
            ),
            const Divider(height: 1, color: Color(0xFF1F4030)),
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
                        color: Color(0xFF789D85),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
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
                    foregroundColor: const Color(0xFFFF9B9B),
                    side: const BorderSide(color: Color(0xFF6A2B2B)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
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
            borderRadius: BorderRadius.circular(compact ? 10 : 14),
          ),
          child: const Text(
            'GG',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'GawaGo Community\nPlatform',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 14 : 16,
              height: 1.35,
              fontWeight: FontWeight.w900,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: destination.selected
            ? const Color(0xFF1A4A2E)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: destination.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: destination.selected
                    ? const Color(0xFF2D6A45)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  destination.icon,
                  color: const Color(0xFFA5C9B0),
                  size: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    destination.label,
                    style: const TextStyle(
                      color: Color(0xFFA5C9B0),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
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
