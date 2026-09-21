import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/api/gawago_api.dart';
import '../core/errors/api_error.dart';
import '../core/storage/session_storage.dart';
import '../core/theme/gawago_colors.dart';
import '../shared/constants/gawago_options.dart';
import '../shared/utils/map_tile_guard.dart';
import '../features/worker/presentation/worker_home_screen.dart';
import '../features/household/presentation/household_home_screen.dart';
import '../features/admin/presentation/admin_home_screen.dart';

class GawaGoApp extends StatefulWidget {
  const GawaGoApp({super.key});

  @override
  State<GawaGoApp> createState() => _GawaGoAppState();
}

class _GawaGoAppState extends State<GawaGoApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    SessionStorage.sessionExpired.addListener(_handleExpiredSession);
  }

  @override
  void dispose() {
    SessionStorage.sessionExpired.removeListener(_handleExpiredSession);
    super.dispose();
  }

  void _handleExpiredSession() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LandingPage()),
        (route) => false,
      );
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Your session expired. Please log in again.'),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'GawaGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: GawaGoColors.deepGreen,
        colorScheme: ColorScheme.fromSeed(
          seedColor: GawaGoColors.primary,
          brightness: Brightness.dark,
        ),
      ),
      home: const _SessionGate(),
    );
  }
}

class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  late final Future<AuthSession?> _session = SessionStorage.restore();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthSession?>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: GawaGoColors.deepGreen,
            body: Center(
              child: CircularProgressIndicator(color: GawaGoColors.primary),
            ),
          );
        }

        final session = snapshot.data;
        if (session == null || !session.isAuthenticated) {
          return const LandingPage();
        }
        if (session.role == 'household') {
          return HouseholdHomeScreen(
            onLogout: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LandingPage()),
                (route) => false,
              );
            },
          );
        }
        if (session.role == 'admin' || session.role == 'superadmin') {
          return AdminHomeScreen(
            isSuperAdmin: session.role == 'superadmin',
            onLogout: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LandingPage()),
                (route) => false,
              );
            },
          );
        }
        return WorkerHomeScreen(
          onLogout: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LandingPage()),
              (route) => false,
            );
          },
        );
      },
    );
  }
}

enum LandingMode { stats, login, signupChoice, householdSignup, workerSignup }

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  LandingMode _mode = LandingMode.stats;

  void _setMode(LandingMode mode) {
    setState(() => _mode = mode);
  }

  void _openWorkerDashboard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkerHomeScreen(
          onLogout: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LandingPage()),
              (route) => false,
            );
          },
        ),
      ),
    );
  }

  void _openHouseholdDashboard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HouseholdHomeScreen(
          onLogout: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LandingPage()),
              (route) => false,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 380;
    final horizontalPadding = compact ? 18.0 : 22.0;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.72, -0.12),
            radius: 1.08,
            colors: [Color(0xFF135736), GawaGoColors.deepGreen],
            stops: [0.0, 0.72],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              6,
              horizontalPadding,
              28,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    size.height -
                    MediaQuery.paddingOf(context).top -
                    MediaQuery.paddingOf(context).bottom -
                    34,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopNav(
                    onLogin: () => _setMode(LandingMode.login),
                    onSignup: () => _setMode(LandingMode.signupChoice),
                  ),
                  SizedBox(height: compact ? 18 : 22),
                  const _LocationPill(),
                  SizedBox(height: compact ? 24 : 30),
                  _HeroHeadline(compact: compact),
                  const SizedBox(height: 22),
                  const _HeroCopy(),
                  const SizedBox(height: 34),
                  _HeroActions(
                    onPostJob: () => _setMode(LandingMode.householdSignup),
                    onFindWork: () => _setMode(LandingMode.workerSignup),
                  ),
                  const SizedBox(height: 34),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _LandingPanel(
                      mode: _mode,
                      onStats: () => _setMode(LandingMode.stats),
                      onLogin: () => _setMode(LandingMode.login),
                      onWorkerDashboard: _openWorkerDashboard,
                      onHouseholdDashboard: _openHouseholdDashboard,
                      onSignupChoice: () => _setMode(LandingMode.signupChoice),
                      onHouseholdSignup: () =>
                          _setMode(LandingMode.householdSignup),
                      onWorkerSignup: () => _setMode(LandingMode.workerSignup),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopNav extends StatelessWidget {
  const _TopNav({required this.onLogin, required this.onSignup});

  final VoidCallback onLogin;
  final VoidCallback onSignup;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Gawa'),
                TextSpan(
                  text: 'Go',
                  style: TextStyle(color: GawaGoColors.primary),
                ),
              ],
            ),
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        _NavButton(label: 'Login', outlined: true, onPressed: onLogin),
        const SizedBox(width: 10),
        _NavButton(label: 'Sign Up', onPressed: onSignup),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.onPressed,
    this.outlined = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: outlined ? Colors.transparent : GawaGoColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
            side: outlined
                ? const BorderSide(color: Color(0xFF71907E))
                : BorderSide.none,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _LocationPill extends StatelessWidget {
  const _LocationPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF124A31),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: GawaGoColors.primary),
          SizedBox(width: 8),
          Text(
            'TAYABAS CITY',
            style: TextStyle(
              color: GawaGoColors.primaryLight,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroHeadline extends StatelessWidget {
  const _HeroHeadline({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: const [
          TextSpan(text: 'Find '),
          TextSpan(
            text: 'trusted\n',
            style: TextStyle(color: GawaGoColors.primary),
          ),
          TextSpan(text: 'helpers and\nskilled workers\nnear you.'),
        ],
      ),
      style: TextStyle(
        color: Colors.white,
        fontSize: compact ? 43 : 48,
        height: 1.08,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'GawaGo connects households and workers with smart matching, '
      'transparent rates, and a fair reputation system.',
      style: TextStyle(
        color: Colors.white,
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    );
  }
}

class _HeroActions extends StatelessWidget {
  const _HeroActions({required this.onPostJob, required this.onFindWork});

  final VoidCallback onPostJob;
  final VoidCallback onFindWork;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Post a Job',
            filled: true,
            onPressed: onPostJob,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(label: 'Find Work', onPressed: onFindWork),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 47,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: filled ? GawaGoColors.primary : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
            side: filled
                ? BorderSide.none
                : const BorderSide(color: Color(0xFF789586)),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _LandingPanel extends StatelessWidget {
  const _LandingPanel({
    required this.mode,
    required this.onStats,
    required this.onLogin,
    required this.onWorkerDashboard,
    required this.onHouseholdDashboard,
    required this.onSignupChoice,
    required this.onHouseholdSignup,
    required this.onWorkerSignup,
  });

  final LandingMode mode;
  final VoidCallback onStats;
  final VoidCallback onLogin;
  final VoidCallback onWorkerDashboard;
  final VoidCallback onHouseholdDashboard;
  final VoidCallback onSignupChoice;
  final VoidCallback onHouseholdSignup;
  final VoidCallback onWorkerSignup;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      LandingMode.stats => const _StatsCard(key: ValueKey('stats')),
      LandingMode.login => _LoginPanel(
        key: const ValueKey('login'),
        onBack: onStats,
        onWorkerDashboard: onWorkerDashboard,
        onHouseholdDashboard: onHouseholdDashboard,
      ),
      LandingMode.signupChoice => _SignupChoicePanel(
        key: const ValueKey('signup-choice'),
        onHousehold: onHouseholdSignup,
        onWorker: onWorkerSignup,
      ),
      LandingMode.householdSignup => _SignupFormPanel(
        key: const ValueKey('household-signup'),
        role: SignupRole.household,
        onBack: onSignupChoice,
        onLogin: onLogin,
      ),
      LandingMode.workerSignup => _SignupFormPanel(
        key: const ValueKey('worker-signup'),
        role: SignupRole.worker,
        onBack: onSignupChoice,
        onLogin: onLogin,
      ),
    };
  }
}

class _SignupChoicePanel extends StatelessWidget {
  const _SignupChoicePanel({
    super.key,
    required this.onHousehold,
    required this.onWorker,
  });

  final VoidCallback onHousehold;
  final VoidCallback onWorker;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RoleCard(
          title: 'Household',
          subtitle: 'Post jobs and hire trusted workers',
          icon: const _HouseholdIcon(),
          onPressed: onHousehold,
        ),
        const SizedBox(height: 12),
        _RoleCard(
          title: 'Worker',
          subtitle: 'Find jobs near your barangay',
          icon: const _WorkerIcon(),
          onPressed: onWorker,
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final Widget icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      decoration: BoxDecoration(
        color: GawaGoColors.cream,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2D9CA)),
      ),
      child: Column(
        children: [
          icon,
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF536458),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 138,
            height: 40,
            child: TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(
                backgroundColor: GawaGoColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text(
                'Create Account',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HouseholdIcon extends StatelessWidget {
  const _HouseholdIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 74,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 2,
            child: Container(
              width: 82,
              height: 49,
              decoration: const BoxDecoration(
                color: Color(0xFFE2F1F7),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 30,
            child: Container(
              width: 46,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFFFFA65E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 28,
            child: Container(
              width: 25,
              height: 35,
              decoration: const BoxDecoration(
                color: Color(0xFF073E68),
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: 96,
              height: 25,
              decoration: const BoxDecoration(
                color: Color(0xFF2DBDA6),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerIcon extends StatelessWidget {
  const _WorkerIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 6,
            child: Container(
              width: 78,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFFDDEBF1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: 19,
            child: Container(
              width: 62,
              height: 37,
              decoration: const BoxDecoration(
                color: Color(0xFFFFA65E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: Container(
              width: 40,
              height: 52,
              decoration: const BoxDecoration(
                color: Color(0xFF073E68),
                borderRadius: BorderRadius.all(Radius.circular(22)),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            child: Container(
              width: 80,
              height: 18,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFFB67761).withValues(alpha: 0.9),
                    width: 4,
                  ),
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(40),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum SignupRole { household, worker }

class _SignupFormPanel extends StatefulWidget {
  const _SignupFormPanel({
    super.key,
    required this.role,
    required this.onBack,
    required this.onLogin,
  });

  final SignupRole role;
  final VoidCallback onBack;
  final VoidCallback onLogin;

  @override
  State<_SignupFormPanel> createState() => _SignupFormPanelState();
}

class _SignupFormPanelState extends State<_SignupFormPanel> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _streetController = TextEditingController();
  final _bioController = TextEditingController();
  final _hourlyRateController = TextEditingController(text: '0.00');
  final _dailyRateController = TextEditingController(text: '0.00');
  final _yearsController = TextEditingController(text: '0');
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final Set<String> _selectedSkills = {};

  String? _barangay;
  LatLng? _selectedLocation;
  bool _isSubmitting = false;

  bool get isWorker => widget.role == SignupRole.worker;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    _bioController.dispose();
    _hourlyRateController.dispose();
    _dailyRateController.dispose();
    _yearsController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final missing = [
      if (_firstNameController.text.trim().isEmpty) 'first name',
      if (_lastNameController.text.trim().isEmpty) 'last name',
      if (_usernameController.text.trim().isEmpty) 'username',
      if (_emailController.text.trim().isEmpty) 'email',
      if (_phoneController.text.trim().isEmpty) 'phone number',
      if (_barangay == null) 'barangay',
      if (_selectedLocation == null) 'map location',
      if (isWorker && _selectedSkills.isEmpty) 'at least one skill',
      if (isWorker &&
          (double.tryParse(_hourlyRateController.text) ?? 0) <= 0 &&
          (double.tryParse(_dailyRateController.text) ?? 0) <= 0)
        'hourly or daily service rate',
      if (_passwordController.text.isEmpty) 'password',
    ];
    if (missing.isNotEmpty) {
      _showMessage('Please complete: ${missing.join(', ')}.');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showMessage('Passwords do not match.');
      return;
    }
    if (_passwordController.text.length < 8) {
      _showMessage('Password must be at least 8 characters.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await GawaGoApi.register(
        role: isWorker ? 'worker' : 'household',
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        username: _usernameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        phone: _phoneController.text,
        barangay: _barangay!,
        streetAddress: _streetController.text,
        bio: _bioController.text,
        hourlyRate: _hourlyRateController.text,
        dailyRate: _dailyRateController.text,
        yearsExperience: int.tryParse(_yearsController.text.trim()) ?? 0,
        skills: _selectedSkills.toList(),
        latitude: _selectedLocation?.latitude,
        longitude: _selectedLocation?.longitude,
      );
      if (!mounted) return;
      _showMessage('Account created. Please login to continue.');
      widget.onLogin();
    } catch (error) {
      if (!mounted) return;
      _showMessage(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final title = isWorker ? 'Register as Worker' : 'Register as Household';
    final subtitle = isWorker
        ? 'Set up your worker profile to start applying for jobs near you.'
        : 'Create your account to start finding trusted workers near you.';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: GawaGoColors.cardGreen.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: GawaGoColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'GG',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'GawaGo Community Platform',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                _BackChip(label: 'Back', onPressed: widget.onBack),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: GawaGoColors.mutedText,
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 24),
                const _SectionTitle('Personal Information'),
                const SizedBox(height: 14),
                _ResponsiveInputs(
                  fields: [
                    _InputSpec('First Name', 'Juan', _firstNameController),
                    _InputSpec('Last Name', 'dela Cruz', _lastNameController),
                    _InputSpec('Username', 'juandc', _usernameController),
                    _InputSpec(
                      'Email',
                      'juan@email.com',
                      _emailController,
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const _SectionTitle('Contact & Location'),
                const SizedBox(height: 14),
                _ResponsiveInputs(
                  fields: [
                    _InputSpec(
                      'Phone Number',
                      '9XXXXXXXXX',
                      _phoneController,
                      prefix: '+63',
                      keyboardType: TextInputType.phone,
                    ),
                    _InputSpec(
                      'Street / House No.',
                      'e.g. 45 Mabini St.',
                      _streetController,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SignupDropdownField(
                  label: 'Barangay',
                  value: _barangay,
                  hint: '--- Select Barangay ---',
                  items: gawagoBarangays,
                  onChanged: (value) => setState(() => _barangay = value),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose your exact location pin for distance matching.',
                  style: TextStyle(
                    color: GawaGoColors.mutedText,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                _WorkerLocationPreview(
                  value: _selectedLocation,
                  onChanged: (value) =>
                      setState(() => _selectedLocation = value),
                ),
                if (isWorker) ...[
                  const SizedBox(height: 22),
                  const _SectionTitle('Worker Profile'),
                  const SizedBox(height: 14),
                  const _FormLabel('Bio / About Me'),
                  const SizedBox(height: 8),
                  _MultiLineInput(
                    hint:
                        'Tell households about yourself and your experience...',
                    controller: _bioController,
                  ),
                  const SizedBox(height: 14),
                  _ResponsiveInputs(
                    fields: [
                      _InputSpec(
                        'Hourly Rate (PHP)',
                        '0.00',
                        _hourlyRateController,
                        keyboardType: TextInputType.number,
                      ),
                      _InputSpec(
                        'Daily Rate (PHP)',
                        '0.00',
                        _dailyRateController,
                        keyboardType: TextInputType.number,
                      ),
                      _InputSpec(
                        'Years of Experience',
                        '0',
                        _yearsController,
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SkillsBox(
                    selectedSkills: _selectedSkills,
                    onChanged: (skills) => setState(
                      () => _selectedSkills
                        ..clear()
                        ..addAll(skills),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                const _SectionTitle('Security'),
                const SizedBox(height: 14),
                _ResponsiveInputs(
                  fields: [
                    _InputSpec(
                      'Password',
                      '********',
                      _passwordController,
                      obscure: true,
                    ),
                    _InputSpec(
                      'Confirm Password',
                      '********',
                      _confirmPasswordController,
                      obscure: true,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: TextButton.styleFrom(
                      backgroundColor: GawaGoColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isWorker
                                ? 'Create Worker Account'
                                : 'Create Household Account',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Already have an account? ',
                    style: TextStyle(
                      color: GawaGoColors.mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  InkWell(
                    onTap: widget.onLogin,
                    child: const Text(
                      'Login here',
                      style: TextStyle(
                        color: GawaGoColors.primaryLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                        decorationColor: GawaGoColors.primaryLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: GawaGoColors.primaryLight,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: GawaGoColors.borderGreen)),
      ],
    );
  }
}

class _InputSpec {
  const _InputSpec(
    this.label,
    this.hint,
    this.controller, {
    this.prefix,
    this.obscure = false,
    this.keyboardType,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String? prefix;
  final bool obscure;
  final TextInputType? keyboardType;
}

class _ResponsiveInputs extends StatelessWidget {
  const _ResponsiveInputs({required this.fields});

  final List<_InputSpec> fields;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 560;
        final gap = twoColumns ? 12.0 : 14.0;
        final itemWidth = twoColumns
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: fields
              .map(
                (field) => SizedBox(
                  width: field.label == 'Street / House No.'
                      ? constraints.maxWidth
                      : itemWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FormLabel(field.label),
                      const SizedBox(height: 8),
                      _TextInput(
                        hint: field.hint,
                        controller: field.controller,
                        prefix: field.prefix,
                        obscureText: field.obscure,
                        keyboardType: field.keyboardType,
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _SignupDropdownField extends StatelessWidget {
  const _SignupDropdownField({
    required this.label,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final String hint;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormLabel(label),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: onChanged,
          dropdownColor: GawaGoColors.cream,
          style: const TextStyle(
            color: GawaGoColors.ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF7D8A82),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
            filled: true,
            fillColor: GawaGoColors.cream,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(
                color: GawaGoColors.primary,
                width: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkerLocationPreview extends StatefulWidget {
  const _WorkerLocationPreview({required this.value, required this.onChanged});

  final LatLng? value;
  final ValueChanged<LatLng> onChanged;

  static const _tayabasCenter = LatLng(14.0253, 121.5929);

  @override
  State<_WorkerLocationPreview> createState() => _WorkerLocationPreviewState();
}

class _WorkerLocationPreviewState extends State<_WorkerLocationPreview> {
  final MapController _controller = MapController();
  bool _locating = false;

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was denied.');
      }
      final position = await Geolocator.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);
      widget.onChanged(point);
      _controller.move(point, 16);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF0C3A27),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Exact Worker Location',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'Pin required for accurate distance',
                style: TextStyle(
                  color: GawaGoColors.primaryLight,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: FlutterMap(
                mapController: _controller,
                options: MapOptions(
                  initialCenter:
                      widget.value ?? _WorkerLocationPreview._tayabasCenter,
                  initialZoom: 14,
                  onTap: (_, point) => widget.onChanged(point),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                  ),
                ),
                children: [
                  if (shouldLoadMapTiles) osmTileLayer(),
                  MarkerLayer(
                    markers: widget.value == null
                        ? const []
                        : [
                            Marker(
                              point: widget.value!,
                              width: 42,
                              height: 52,
                              alignment: Alignment.topCenter,
                              child: const _MapPin(
                                label: 'W',
                                color: Color(0xFFE85D04),
                              ),
                            ),
                          ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _MiniMapButton(
                  label: _locating ? 'Locating...' : 'Use My Current Location',
                  onPressed: _locating ? null : _useCurrentLocation,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: _MiniMapButton(
                  label: 'Pin on Map Manually',
                  outlined: true,
                  onPressed: null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Use browser location or click the map so households can see accurate distance and routes.',
            style: TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 9,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Icon(Icons.location_pin, color: color, size: 42),
        Positioned(
          top: 7,
          child: Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniMapButton extends StatelessWidget {
  const _MiniMapButton({
    required this.label,
    this.outlined = false,
    this.onPressed,
  });

  final String label;
  final bool outlined;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: outlined ? Colors.transparent : GawaGoColors.primary,
          foregroundColor: outlined ? GawaGoColors.mutedText : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: outlined
                ? const BorderSide(color: GawaGoColors.borderGreen)
                : BorderSide.none,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _MultiLineInput extends StatelessWidget {
  const _MultiLineInput({required this.hint, this.controller});

  final String hint;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: 4,
      style: const TextStyle(
        color: GawaGoColors.ink,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFF7D8A82),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: GawaGoColors.cream,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: GawaGoColors.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _SkillsBox extends StatefulWidget {
  const _SkillsBox({required this.selectedSkills, required this.onChanged});

  final Set<String> selectedSkills;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_SkillsBox> createState() => _SkillsBoxState();
}

class _SkillsBoxState extends State<_SkillsBox> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SKILLS  (select all that apply)',
          style: TextStyle(
            color: GawaGoColors.primaryLight,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: GawaGoColors.borderGreen),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 2,
            children: gawagoSkills
                .map(
                  (skill) => SizedBox(
                    width: 136,
                    child: Material(
                      type: MaterialType.transparency,
                      child: CheckboxListTile(
                        value: widget.selectedSkills.contains(skill),
                        onChanged: (checked) {
                          final next = Set<String>.of(widget.selectedSkills);
                          setState(() {
                            if (checked ?? false) {
                              next.add(skill);
                            } else {
                              next.remove(skill);
                            }
                          });
                          widget.onChanged(next);
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        checkColor: Colors.white,
                        activeColor: GawaGoColors.primary,
                        title: Text(
                          skill,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _LoginPanel extends StatefulWidget {
  const _LoginPanel({
    super.key,
    required this.onBack,
    required this.onWorkerDashboard,
    required this.onHouseholdDashboard,
  });

  final VoidCallback onBack;
  final VoidCallback onWorkerDashboard;
  final VoidCallback onHouseholdDashboard;

  @override
  State<_LoginPanel> createState() => _LoginPanelState();
}

class _LoginPanelState extends State<_LoginPanel> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      _showMessage('Please enter your username/email and password.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await GawaGoApi.login(
        username: _usernameController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const _SessionGate()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Two-step reset in one dialog: request a code by email, then submit
  /// that code with the new password. The email field locks once the code
  /// has gone out so the two steps cannot disagree.
  Future<void> _openForgotPasswordDialog() async {
    final email = TextEditingController();
    final code = TextEditingController();
    final newPassword = TextEditingController();
    var codeSent = false;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> sendCode() async {
            if (email.text.trim().isEmpty) {
              _showMessage('Enter the email on your account.');
              return;
            }
            setDialogState(() => busy = true);
            try {
              await GawaGoApi.requestPasswordReset(email.text);
              setDialogState(() => codeSent = true);
              _showMessage(
                'If that email is registered, a code is on its way.',
              );
            } catch (error) {
              _showMessage(friendlyApiError(error));
            } finally {
              setDialogState(() => busy = false);
            }
          }

          Future<void> submitReset() async {
            if (code.text.trim().isEmpty) {
              _showMessage('Enter the reset code from your email.');
              return;
            }
            if (newPassword.text.length < 8) {
              _showMessage('Password must be at least 8 characters.');
              return;
            }
            setDialogState(() => busy = true);
            try {
              await GawaGoApi.resetPassword(
                email: email.text,
                token: code.text,
                newPassword: newPassword.text,
              );
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              _showMessage('Password updated. You can log in now.');
            } catch (error) {
              _showMessage(friendlyApiError(error));
            } finally {
              setDialogState(() => busy = false);
            }
          }

          return AlertDialog(
            title: const Text('Reset your password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: email,
                  enabled: !codeSent,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                if (codeSent) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: code,
                    decoration: const InputDecoration(labelText: 'Reset code'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              if (codeSent)
                FilledButton(
                  onPressed: busy ? null : submitReset,
                  child: Text(busy ? 'Saving...' : 'Reset Password'),
                )
              else
                FilledButton(
                  onPressed: busy ? null : sendCode,
                  child: Text(busy ? 'Sending...' : 'Send Code'),
                ),
            ],
          );
        },
      ),
    );

    email.dispose();
    code.dispose();
    newPassword.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(26, 28, 26, 30),
      decoration: BoxDecoration(
        color: GawaGoColors.cardGreen.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              _BackChip(label: 'Back', onPressed: widget.onBack),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Login to GawaGo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Enter your credentials. We will open the\nright dashboard for your account.',
                    style: TextStyle(
                      color: GawaGoColors.mutedText,
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _FormLabel('Email or Username'),
          const SizedBox(height: 8),
          _TextInput(
            hint: 'Enter your email or username',
            controller: _usernameController,
          ),
          const SizedBox(height: 17),
          const _FormLabel('Password'),
          const SizedBox(height: 8),
          _TextInput(
            hint: 'Enter your password',
            obscureText: true,
            controller: _passwordController,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _openForgotPasswordDialog,
              style: TextButton.styleFrom(
                foregroundColor: GawaGoColors.primary,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Forgot your password?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: _isSubmitting ? null : _login,
              style: TextButton.styleFrom(
                backgroundColor: GawaGoColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Login',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackChip extends StatelessWidget {
  const _BackChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: GawaGoColors.primaryLight,
          backgroundColor: const Color(0xFF124A31),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: const BorderSide(color: GawaGoColors.borderGreen),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: GawaGoColors.mutedText,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.hint,
    this.obscureText = false,
    this.prefix,
    this.controller,
    this.keyboardType,
  });

  final String hint;
  final bool obscureText;
  final String? prefix;
  final TextEditingController? controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: GawaGoColors.ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: prefix == null
              ? null
              : Container(
                  width: 54,
                  alignment: Alignment.center,
                  child: Text(
                    prefix!,
                    style: const TextStyle(
                      color: GawaGoColors.primaryLight,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
          hintStyle: const TextStyle(
            color: Color(0xFF7D8A82),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
          filled: true,
          fillColor: GawaGoColors.cream,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(
              color: GawaGoColors.primary,
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsCard extends StatefulWidget {
  const _StatsCard({super.key});

  @override
  State<_StatsCard> createState() => _StatsCardState();
}

class _StatsCardState extends State<_StatsCard> {
  final Future<List<dynamic>> _jobs = GawaGoApi.getList('/jobs/?status=open');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _jobs,
      builder: (context, snapshot) {
        final openJobs = snapshot.data?.length ?? 0;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 27),
          decoration: BoxDecoration(
            color: GawaGoColors.cardGreen.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: GawaGoColors.borderGreen),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _LivePill(),
              const SizedBox(height: 22),
              const Text(
                'Open Jobs',
                style: TextStyle(
                  color: GawaGoColors.mutedText,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$openJobs',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 56,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Jobs waiting for workers to apply',
                style: TextStyle(
                  color: GawaGoColors.mutedText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 26),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.04)),
              const SizedBox(height: 24),
              const Row(
                children: [
                  Expanded(
                    child: _Metric(value: '0', label: 'Verified Workers'),
                  ),
                  Expanded(
                    child: _Metric(value: '0', label: 'Completed Services'),
                  ),
                  Expanded(
                    child: _Metric(value: '0', label: 'Registered Accounts'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF124A31),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: GawaGoColors.primary),
          SizedBox(width: 8),
          Text(
            'OPEN JOBS LIVE',
            style: TextStyle(
              color: GawaGoColors.primaryLight,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          width: double.infinity,
          height: 30,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: GawaGoColors.mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
