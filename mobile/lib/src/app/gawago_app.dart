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

enum _HouseholdNavItem { dashboard, postJob, myJobs, profile, notifications }

class _HouseholdDashboardScreen extends StatefulWidget {
  const _HouseholdDashboardScreen();

  @override
  State<_HouseholdDashboardScreen> createState() =>
      _HouseholdDashboardScreenState();
}

class _HouseholdDashboardScreenState extends State<_HouseholdDashboardScreen> {
  _HouseholdNavItem _activeItem = _HouseholdNavItem.dashboard;

  void _selectItem(_HouseholdNavItem item) {
    setState(() => _activeItem = item);
    Navigator.of(context).maybePop();
  }

  Future<void> _logout() async {
    await SessionStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GawaGoColors.deepGreen,
      drawer: _HouseholdDashboardDrawer(
        activeItem: _activeItem,
        onSelect: _selectItem,
        onLogout: _logout,
      ),
      appBar: AppBar(
        backgroundColor: GawaGoColors.deepGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'GawaGo Community Platform',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _HouseholdDashboardBody(activeItem: _activeItem),
      ),
    );
  }
}

class _HouseholdDashboardDrawer extends StatelessWidget {
  const _HouseholdDashboardDrawer({
    required this.activeItem,
    required this.onSelect,
    required this.onLogout,
  });

  final _HouseholdNavItem activeItem;
  final ValueChanged<_HouseholdNavItem> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 296,
      backgroundColor: GawaGoColors.deepGreen,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Column(
          children: [
            const _WorkerDrawerHeader(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _WorkerDrawerTile(
                    icon: Icons.grid_view_rounded,
                    label: 'Dashboard',
                    selected: activeItem == _HouseholdNavItem.dashboard,
                    onTap: () => onSelect(_HouseholdNavItem.dashboard),
                  ),
                  _WorkerDrawerTile(
                    icon: Icons.post_add,
                    label: 'Post a Job',
                    selected: activeItem == _HouseholdNavItem.postJob,
                    onTap: () => onSelect(_HouseholdNavItem.postJob),
                  ),
                  _WorkerDrawerTile(
                    icon: Icons.description_outlined,
                    label: 'My Jobs',
                    selected: activeItem == _HouseholdNavItem.myJobs,
                    onTap: () => onSelect(_HouseholdNavItem.myJobs),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
                    child: Text(
                      'ACCOUNT',
                      style: TextStyle(
                        color: Color(0xFF55715F),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  _WorkerDrawerTile(
                    icon: Icons.person_outline,
                    label: 'My Profile',
                    selected: activeItem == _HouseholdNavItem.profile,
                    onTap: () => onSelect(_HouseholdNavItem.profile),
                  ),
                  _WorkerDrawerTile(
                    icon: Icons.notifications_none,
                    label: 'Notifications',
                    selected: activeItem == _HouseholdNavItem.notifications,
                    onTap: () => onSelect(_HouseholdNavItem.notifications),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: TextButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Log Out'),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: const Color(0xFFFF9B9B),
                    backgroundColor: const Color(0xFF252D22),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                      side: const BorderSide(color: Color(0xFF8A4B32)),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
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

class _HouseholdDashboardBody extends StatelessWidget {
  const _HouseholdDashboardBody({required this.activeItem});

  final _HouseholdNavItem activeItem;

  @override
  Widget build(BuildContext context) {
    return switch (activeItem) {
      _HouseholdNavItem.dashboard => const _HouseholdHomePage(),
      _HouseholdNavItem.postJob => const _HouseholdPostJobPage(),
      _HouseholdNavItem.myJobs => const _HouseholdMyJobsPage(),
      _HouseholdNavItem.profile => const _HouseholdProfilePage(),
      _HouseholdNavItem.notifications => const _HouseholdNotificationsPage(),
    };
  }
}

class _HouseholdHomePage extends StatelessWidget {
  const _HouseholdHomePage();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 10, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HouseholdWelcomeCard(),
          SizedBox(height: 16),
          _HouseholdMetricGrid(),
          SizedBox(height: 20),
          Text(
            'Recent Posted Jobs',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 10),
          _HouseholdRecentJobsPreview(),
        ],
      ),
    );
  }
}

class _HouseholdWelcomeCard extends StatelessWidget {
  const _HouseholdWelcomeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: GawaGoColors.cardGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: const Text(
        'Welcome, Household',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _HouseholdMetricGrid extends StatelessWidget {
  const _HouseholdMetricGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 360;

        return GridView.count(
          crossAxisCount: twoColumns ? 2 : 1,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: twoColumns ? 1.75 : 3,
          children: const [
            _WorkerMetricCard(
              label: 'In Progress',
              value: '0',
              icon: Icons.timelapse,
            ),
            _WorkerMetricCard(
              label: 'Cancelled Jobs',
              value: '0',
              icon: Icons.cancel_outlined,
            ),
            _WorkerMetricCard(
              label: 'Completed',
              value: '0',
              icon: Icons.check_circle_outline,
            ),
            _WorkerMetricCard(
              label: 'Applications',
              value: '0',
              icon: Icons.group_outlined,
            ),
          ],
        );
      },
    );
  }
}

class _HouseholdRecentJobsPreview extends StatelessWidget {
  const _HouseholdRecentJobsPreview();

  @override
  Widget build(BuildContext context) {
    return const _WorkerInsidePanel(
      title: 'No recent jobs loaded yet',
      value:
          'After backend data is connected, this section will list posted jobs with barangay, rate, status, and application counts.',
      icon: Icons.table_chart_outlined,
    );
  }
}

class _HouseholdPostJobPage extends StatefulWidget {
  const _HouseholdPostJobPage();

  @override
  State<_HouseholdPostJobPage> createState() => _HouseholdPostJobPageState();
}

class _HouseholdPostJobPageState extends State<_HouseholdPostJobPage> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _streetController = TextEditingController();
  final _workersNeededController = TextEditingController(text: '1');
  final _rateController = TextEditingController();
  final _customServiceTypeController = TextEditingController();

  String? _serviceType;
  String _scheduleType = 'One - Time';
  String? _barangay;
  String _rateType = 'Per Day';
  DateTime? _preferredDate;
  TimeOfDay? _preferredTime;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _streetController.dispose();
    _workersNeededController.dispose();
    _rateController.dispose();
    _customServiceTypeController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Select preferred date';
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return 'Select preferred time';
    return time.format(context);
  }

  void _submitPreview() {
    final missing = [
      if (_titleController.text.trim().isEmpty) 'job title',
      if (_serviceType == null) 'service type',
      if (_serviceType == 'Other' &&
          _customServiceTypeController.text.trim().isEmpty)
        'specific service type',
      if (_preferredDate == null) 'preferred date',
      if (_preferredTime == null) 'preferred time',
      if (_barangay == null) 'barangay',
      if (_rateController.text.trim().isEmpty) 'offered rate',
    ];

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          missing.isEmpty
              ? 'Post Job flow is ready for backend connection.'
              : 'Please complete: ${missing.join(', ')}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      child: _WorkerSectionCard(
        title: 'Post a New Job',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HouseholdTextField(
              label: 'Job Title',
              controller: _titleController,
            ),
            _HouseholdDropdownField(
              label: 'Service Type',
              value: _serviceType,
              hint: '---Select Service---',
              items: gawagoSkills,
              onChanged: (value) {
                setState(() {
                  _serviceType = value;
                  if (value != 'Other') _customServiceTypeController.clear();
                });
              },
            ),
            if (_serviceType == 'Other')
              _HouseholdTextField(
                label: 'Specify Service Type',
                controller: _customServiceTypeController,
                hint: 'e.g. Pet Grooming, Massage, etc.',
              ),
            _HouseholdDropdownField(
              label: 'Schedule Type',
              value: _scheduleType,
              items: const ['One - Time', 'Part-Time', 'Full-Time'],
              onChanged: (value) => setState(() => _scheduleType = value!),
            ),
            Row(
              children: [
                Expanded(
                  child: _HouseholdPickerField(
                    label: 'Preferred Date',
                    value: _formatDate(_preferredDate),
                    icon: Icons.calendar_today_outlined,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _preferredDate = picked);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HouseholdPickerField(
                    label: 'Preferred Time',
                    value: _formatTime(_preferredTime),
                    icon: Icons.access_time,
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (picked != null) {
                        setState(() => _preferredTime = picked);
                      }
                    },
                  ),
                ),
              ],
            ),
            _HouseholdTextField(
              label: 'Job Description',
              controller: _descriptionController,
              lines: 3,
            ),
            _HouseholdDropdownField(
              label: 'Barangay',
              value: _barangay,
              hint: '---Select Barangay---',
              items: gawagoBarangays,
              onChanged: (value) => setState(() => _barangay = value),
            ),
            _HouseholdTextField(
              label: 'Street / House No.',
              controller: _streetController,
            ),
            const _LightHouseholdJobLocationPreview(),
            const SizedBox(height: 12),
            _HouseholdTextField(
              label: 'Workers Needed',
              controller: _workersNeededController,
              keyboardType: TextInputType.number,
            ),
            _HouseholdTextField(
              label: 'Offered Rate',
              controller: _rateController,
              keyboardType: TextInputType.number,
            ),
            _HouseholdDropdownField(
              label: 'Rate Type',
              value: _rateType,
              items: const ['Per Day', 'Per Hour', 'Fixed Rate'],
              onChanged: (value) => setState(() => _rateType = value!),
            ),
            const _ReferenceImageUploadPreview(),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: _HouseholdPrimaryButton(
                label: 'Post Job',
                onPressed: _submitPreview,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HouseholdTextField extends StatelessWidget {
  const _HouseholdTextField({
    required this.label,
    required this.controller,
    this.lines = 1,
    this.keyboardType,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final int lines;
  final TextInputType? keyboardType;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileSubheading(label),
          TextField(
            controller: controller,
            maxLines: lines,
            keyboardType: keyboardType,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: GawaGoColors.mutedText.withValues(alpha: 0.72),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
              filled: true,
              fillColor: GawaGoColors.panelGreen,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: GawaGoColors.borderGreen),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: GawaGoColors.borderGreen),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: GawaGoColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HouseholdDropdownField extends StatelessWidget {
  const _HouseholdDropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? value;
  final String? hint;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileSubheading(label),
          DropdownButtonFormField<String>(
            initialValue: value,
            dropdownColor: GawaGoColors.panelGreen,
            iconEnabledColor: GawaGoColors.primaryLight,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: GawaGoColors.mutedText),
              filled: true,
              fillColor: GawaGoColors.panelGreen,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: GawaGoColors.borderGreen),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: GawaGoColors.borderGreen),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: GawaGoColors.primary),
              ),
            ),
            items: items
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _HouseholdPickerField extends StatelessWidget {
  const _HouseholdPickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileSubheading(label),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: GawaGoColors.panelGreen,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: GawaGoColors.borderGreen),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  Icon(icon, color: GawaGoColors.primaryLight, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LightHouseholdJobLocationPreview extends StatefulWidget {
  const _LightHouseholdJobLocationPreview();

  @override
  State<_LightHouseholdJobLocationPreview> createState() =>
      _LightHouseholdJobLocationPreviewState();
}

class _LightHouseholdJobLocationPreviewState
    extends State<_LightHouseholdJobLocationPreview> {
  static const _tayabasCenter = LatLng(14.0253, 121.5929);
  LatLng? _selectedPin;

  void _useCenterPin() {
    setState(() => _selectedPin = _tayabasCenter);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Job location pin set for preview.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Job Location',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Text(
                _selectedPin == null ? 'Pin required' : 'Pin ready',
                style: TextStyle(
                  color: GawaGoColors.primaryLight,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: _tayabasCenter,
                  initialZoom: 13,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                  ),
                  onTap: (_, point) => setState(() => _selectedPin = point),
                ),
                children: [
                  if (shouldLoadMapTiles) osmTileLayer(),
                  if (_selectedPin != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selectedPin!,
                          width: 42,
                          height: 52,
                          alignment: Alignment.topCenter,
                          child: const _MapPin(
                            label: 'J',
                            color: GawaGoColors.primary,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _ProfileMiniButton(
                  label: 'Use My Current Location',
                  onPressed: _useCenterPin,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _ProfileMiniButton(
                  label: 'Pin on Map Manually',
                  outlined: true,
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tap the map to place the job pin.'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _selectedPin == null
                ? 'No saved job coordinates yet'
                : 'Selected: ${_selectedPin!.latitude.toStringAsFixed(6)}, ${_selectedPin!.longitude.toStringAsFixed(6)}',
            style: const TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceImageUploadPreview extends StatefulWidget {
  const _ReferenceImageUploadPreview();

  @override
  State<_ReferenceImageUploadPreview> createState() =>
      _ReferenceImageUploadPreviewState();
}

class _ReferenceImageUploadPreviewState
    extends State<_ReferenceImageUploadPreview> {
  final List<String> _images = [];

  void _addPreviewImage() {
    if (_images.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum of 5 reference images.')),
      );
      return;
    }
    setState(() => _images.add('Reference image ${_images.length + 1}'));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.image_outlined,
            color: GawaGoColors.primaryLight,
            size: 28,
          ),
          const SizedBox(height: 8),
          const Text(
            'Reference Images',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add local image placeholders now; real image picking will connect during backend/API work.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          if (_images.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._images.map(
              (image) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: GawaGoColors.cardGreen,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: GawaGoColors.borderGreen),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.image,
                      color: GawaGoColors.primaryLight,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        image,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _images.remove(image)),
                      icon: const Icon(Icons.close, size: 18),
                      color: GawaGoColors.mutedText,
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          _HouseholdPrimaryButton(
            label: 'Select Images',
            onPressed: _addPreviewImage,
          ),
        ],
      ),
    );
  }
}

enum _HouseholdJobFilter { all, open, completed }

class _HouseholdMyJobsPage extends StatefulWidget {
  const _HouseholdMyJobsPage();

  @override
  State<_HouseholdMyJobsPage> createState() => _HouseholdMyJobsPageState();
}

class _HouseholdMyJobsPageState extends State<_HouseholdMyJobsPage> {
  _HouseholdJobFilter _filter = _HouseholdJobFilter.all;

  String get _filterLabel {
    return switch (_filter) {
      _HouseholdJobFilter.all => 'all jobs',
      _HouseholdJobFilter.open => 'open jobs',
      _HouseholdJobFilter.completed => 'completed jobs',
    };
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'My Jobs',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          _HouseholdJobTabs(
            selected: _filter,
            onChanged: (filter) => setState(() => _filter = filter),
          ),
          const SizedBox(height: 14),
          _WorkerInsidePanel(
            title: 'No $_filterLabel loaded yet',
            value:
                'This area will show job cards grouped by all, open, and completed status once the backend is connected.',
            icon: Icons.work_history_outlined,
          ),
          const SizedBox(height: 12),
          const _HouseholdJobCardPreview(),
        ],
      ),
    );
  }
}

class _HouseholdJobTabs extends StatelessWidget {
  const _HouseholdJobTabs({required this.selected, required this.onChanged});

  final _HouseholdJobFilter selected;
  final ValueChanged<_HouseholdJobFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HouseholdFilterChip(
          label: 'All Jobs',
          selected: selected == _HouseholdJobFilter.all,
          onTap: () => onChanged(_HouseholdJobFilter.all),
        ),
        const SizedBox(width: 8),
        _HouseholdFilterChip(
          label: 'Open',
          selected: selected == _HouseholdJobFilter.open,
          onTap: () => onChanged(_HouseholdJobFilter.open),
        ),
        const SizedBox(width: 8),
        _HouseholdFilterChip(
          label: 'Completed',
          selected: selected == _HouseholdJobFilter.completed,
          onTap: () => onChanged(_HouseholdJobFilter.completed),
        ),
      ],
    );
  }
}

class _HouseholdFilterChip extends StatelessWidget {
  const _HouseholdFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
        height: 38,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: selected
                ? GawaGoColors.primary
                : GawaGoColors.panelGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: const BorderSide(color: GawaGoColors.borderGreen),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HouseholdJobCardPreview extends StatelessWidget {
  const _HouseholdJobCardPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SmallGreenPill(label: 'Status'),
          const SizedBox(height: 12),
          const Text(
            'Job card layout preview',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Offer rate, schedule, applicants, and details action will load from backend job records.',
            style: TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          _HouseholdPrimaryButton(
            label: 'View Details',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Job details screen is ready to connect after backend data.',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HouseholdProfilePage extends StatelessWidget {
  const _HouseholdProfilePage();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(8, 12, 8, 28),
      child: Column(
        children: [
          _WorkerSectionCard(
            title: 'My Profile',
            child: _HouseholdProfileSummary(),
          ),
          SizedBox(height: 14),
          _WorkerSectionCard(
            title: 'Edit Profile Information',
            child: _HouseholdProfileEditForm(),
          ),
          SizedBox(height: 14),
          _HouseholdFeedbackPreview(),
        ],
      ),
    );
  }
}

class _HouseholdProfileSummary extends StatelessWidget {
  const _HouseholdProfileSummary();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: Color(0xFF124A31),
          child: Text(
            'H',
            style: TextStyle(
              color: GawaGoColors.primaryLight,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Household Name',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 3),
        Text(
          '@username',
          style: TextStyle(
            color: GawaGoColors.mutedText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 8),
        _SmallGreenPill(label: 'Household'),
        SizedBox(height: 18),
        _HouseholdInfoLines(),
      ],
    );
  }
}

class _HouseholdInfoLines extends StatelessWidget {
  const _HouseholdInfoLines();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoLine(label: 'Account Type:', value: 'Household'),
        _InfoLine(label: 'Barangay:', value: 'Not set'),
        _InfoLine(label: 'Phone Number:', value: 'Not set'),
        _InfoLine(label: 'Email:', value: 'Not set'),
        Divider(height: 18, color: GawaGoColors.borderGreen),
        _InfoLine(label: 'Posted Jobs:', value: '0'),
        _InfoLine(label: 'Completed Jobs:', value: '0'),
        _InfoLine(label: 'Worker Feedback:', value: 'No feedback yet'),
      ],
    );
  }
}

class _HouseholdProfileEditForm extends StatefulWidget {
  const _HouseholdProfileEditForm();

  @override
  State<_HouseholdProfileEditForm> createState() =>
      _HouseholdProfileEditFormState();
}

class _HouseholdProfileEditFormState extends State<_HouseholdProfileEditForm> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _streetController = TextEditingController();
  String? _barangay;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ProfileSubheading('Profile Photo'),
        const _FilePickerMock(),
        const SizedBox(height: 18),
        const _ProfileSubheading('Personal Information'),
        _HouseholdTextField(
          label: 'First Name',
          controller: _firstNameController,
        ),
        _HouseholdTextField(
          label: 'Last Name',
          controller: _lastNameController,
        ),
        _HouseholdTextField(label: 'Username', controller: _usernameController),
        _HouseholdTextField(label: 'Email', controller: _emailController),
        _HouseholdTextField(
          label: 'Phone Number',
          controller: _phoneController,
          keyboardType: TextInputType.phone,
        ),
        _HouseholdDropdownField(
          label: 'Barangay',
          value: _barangay,
          hint: '---Select Barangay---',
          items: gawagoBarangays,
          onChanged: (value) => setState(() => _barangay = value),
        ),
        _HouseholdTextField(
          label: 'Street / House No.',
          controller: _streetController,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: _HouseholdPrimaryButton(
            label: 'Edit Profile',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Profile form is ready for backend save connection.',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HouseholdFeedbackPreview extends StatelessWidget {
  const _HouseholdFeedbackPreview();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Feedback & Rating',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 10),
        _WorkerInsidePanel(
          title: 'No worker feedback yet',
          value:
              'Worker feedback and reviews submitted by the household will appear here after completed jobs.',
          icon: Icons.rate_review_outlined,
        ),
      ],
    );
  }
}

class _HouseholdNotificationsPage extends StatefulWidget {
  const _HouseholdNotificationsPage();

  @override
  State<_HouseholdNotificationsPage> createState() =>
      _HouseholdNotificationsPageState();
}

class _HouseholdNotificationsPageState
    extends State<_HouseholdNotificationsPage> {
  DateTime? _filterDate;
  bool _markedRead = false;

  String get _filterText {
    if (_filterDate == null) return 'No date filter selected';
    return '${_filterDate!.month.toString().padLeft(2, '0')}/${_filterDate!.day.toString().padLeft(2, '0')}/${_filterDate!.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _filterDate = picked);
    }
  }

  void _markAllRead() {
    setState(() => _markedRead = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All loaded notifications marked as read locally.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HouseholdNotificationsHeader(onMarkAll: _markAllRead),
          const SizedBox(height: 14),
          _HouseholdNotificationFilter(
            value: _filterText,
            onPickDate: _pickDate,
            onClear: _filterDate == null
                ? null
                : () => setState(() => _filterDate = null),
          ),
          const SizedBox(height: 14),
          _NotificationEmptyState(
            message: _markedRead
                ? 'Loaded notification previews are marked as read locally.'
                : 'When backend data is connected, household updates for worker applications, completion requests, and reviews will show here.',
          ),
          const SizedBox(height: 12),
          _NotificationCardPreview(
            title: 'New worker application',
            message:
                'Application notifications will appear here when workers apply to household job postings.',
            icon: Icons.person_add_alt,
          ),
          const SizedBox(height: 12),
          _NotificationCardPreview(
            title: 'Job completion update',
            message:
                'Completion requests, review reminders, and job status updates will appear here.',
            icon: Icons.task_alt,
          ),
        ],
      ),
    );
  }
}

class _HouseholdNotificationsHeader extends StatelessWidget {
  const _HouseholdNotificationsHeader({required this.onMarkAll});

  final VoidCallback onMarkAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GawaGoColors.cardGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Notifications',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          _HouseholdPrimaryButton(
            label: 'Mark All as Read',
            onPressed: onMarkAll,
          ),
        ],
      ),
    );
  }
}

class _HouseholdNotificationFilter extends StatelessWidget {
  const _HouseholdNotificationFilter({
    required this.value,
    required this.onPickDate,
    this.onClear,
  });

  final String value;
  final VoidCallback onPickDate;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(value),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                alignment: Alignment.centerLeft,
                backgroundColor: GawaGoColors.cardGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                  side: const BorderSide(color: GawaGoColors.borderGreen),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close),
              color: GawaGoColors.mutedText,
              tooltip: 'Clear date filter',
            ),
          ],
        ],
      ),
    );
  }
}

class _HouseholdPrimaryButton extends StatelessWidget {
  const _HouseholdPrimaryButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: TextButton(
        onPressed: onPressed ?? () {},
        style: TextButton.styleFrom(
          backgroundColor: GawaGoColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
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

enum _WorkerNavItem {
  dashboard,
  findJobs,
  profile,
  applications,
  getVerified,
  notifications,
}

class _WorkerDashboardScreen extends StatefulWidget {
  const _WorkerDashboardScreen();

  @override
  State<_WorkerDashboardScreen> createState() => _WorkerDashboardScreenState();
}

class _WorkerDashboardScreenState extends State<_WorkerDashboardScreen> {
  _WorkerNavItem _activeItem = _WorkerNavItem.dashboard;

  void _selectItem(_WorkerNavItem item) {
    setState(() => _activeItem = item);
    Navigator.of(context).maybePop();
  }

  Future<void> _logout() async {
    await SessionStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GawaGoColors.deepGreen,
      drawer: _WorkerDashboardDrawer(
        activeItem: _activeItem,
        onSelect: _selectItem,
        onLogout: _logout,
      ),
      appBar: AppBar(
        backgroundColor: GawaGoColors.deepGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'GawaGo Community Platform',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _WorkerDashboardBody(activeItem: _activeItem),
      ),
    );
  }
}

class _WorkerDashboardDrawer extends StatelessWidget {
  const _WorkerDashboardDrawer({
    required this.activeItem,
    required this.onSelect,
    required this.onLogout,
  });

  final _WorkerNavItem activeItem;
  final ValueChanged<_WorkerNavItem> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 296,
      backgroundColor: GawaGoColors.deepGreen,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Column(
          children: [
            const _WorkerDrawerHeader(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _WorkerDrawerTile(
                    icon: Icons.grid_view_rounded,
                    label: 'Dashboard',
                    selected: activeItem == _WorkerNavItem.dashboard,
                    onTap: () => onSelect(_WorkerNavItem.dashboard),
                  ),
                  _WorkerDrawerTile(
                    icon: Icons.search,
                    label: 'Find Jobs',
                    selected: activeItem == _WorkerNavItem.findJobs,
                    onTap: () => onSelect(_WorkerNavItem.findJobs),
                  ),
                  _WorkerDrawerTile(
                    icon: Icons.person_outline,
                    label: 'My Profile',
                    selected: activeItem == _WorkerNavItem.profile,
                    onTap: () => onSelect(_WorkerNavItem.profile),
                  ),
                  _WorkerDrawerTile(
                    icon: Icons.description_outlined,
                    label: 'My Applications',
                    selected: activeItem == _WorkerNavItem.applications,
                    onTap: () => onSelect(_WorkerNavItem.applications),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
                    child: Text(
                      'ACCOUNT',
                      style: TextStyle(
                        color: Color(0xFF55715F),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  _WorkerDrawerTile(
                    icon: Icons.verified_outlined,
                    label: 'Get Verified',
                    selected: activeItem == _WorkerNavItem.getVerified,
                    onTap: () => onSelect(_WorkerNavItem.getVerified),
                  ),
                  _WorkerDrawerTile(
                    icon: Icons.notifications_none,
                    label: 'Notifications',
                    selected: activeItem == _WorkerNavItem.notifications,
                    onTap: () => onSelect(_WorkerNavItem.notifications),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: TextButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Log Out'),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: const Color(0xFFFF9B9B),
                    backgroundColor: const Color(0xFF252D22),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                      side: const BorderSide(color: Color(0xFF8A4B32)),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
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

class _WorkerDrawerHeader extends StatelessWidget {
  const _WorkerDrawerHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: GawaGoColors.borderGreen)),
      ),
      child: const Row(
        children: [
          _GawaGoLogoMark(size: 40),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'GawaGo Community\nPlatform',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.2,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerDrawerTile extends StatelessWidget {
  const _WorkerDrawerTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : GawaGoColors.mutedText;

    return Material(
      color: selected ? const Color(0xFF174E31) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 49,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            border: selected
                ? const Border(
                    top: BorderSide(color: GawaGoColors.borderGreen),
                    bottom: BorderSide(color: GawaGoColors.borderGreen),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
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
    );
  }
}

class _GawaGoLogoMark extends StatelessWidget {
  const _GawaGoLogoMark({this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GawaGoColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'GG',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.25,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _WorkerDashboardBody extends StatelessWidget {
  const _WorkerDashboardBody({required this.activeItem});

  final _WorkerNavItem activeItem;

  String get _title {
    return switch (activeItem) {
      _WorkerNavItem.dashboard => 'Dashboard',
      _WorkerNavItem.findJobs => 'Find Jobs',
      _WorkerNavItem.profile => 'My Profile',
      _WorkerNavItem.applications => 'My Applications',
      _WorkerNavItem.getVerified => 'Get Verified',
      _WorkerNavItem.notifications => 'Notifications',
    };
  }

  String get _subtitle {
    return switch (activeItem) {
      _WorkerNavItem.dashboard =>
        'Track job activity, applications, and profile readiness.',
      _WorkerNavItem.findJobs =>
        'Browse available household requests near your barangay.',
      _WorkerNavItem.profile =>
        'Manage your skills, rates, location, and worker information.',
      _WorkerNavItem.applications =>
        'Review jobs you applied to and monitor application status.',
      _WorkerNavItem.getVerified =>
        'Submit identity documents to earn a verified worker badge.',
      _WorkerNavItem.notifications =>
        'See updates for accepted, rejected, and completed applications.',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (activeItem == _WorkerNavItem.findJobs) {
      return const _FindJobsPage();
    }

    if (activeItem == _WorkerNavItem.profile) {
      return const _WorkerProfilePage();
    }

    if (activeItem == _WorkerNavItem.getVerified) {
      return const _WorkerVerificationPage();
    }

    if (activeItem == _WorkerNavItem.notifications) {
      return const _WorkerNotificationsPage();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _subtitle,
            style: const TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          if (activeItem == _WorkerNavItem.dashboard) ...[
            const _WorkerMetricGrid(),
            const SizedBox(height: 16),
            const _WorkerInsidePanel(
              title: 'Suggested Next Step',
              value:
                  'Complete your profile and verification to appear higher in smart matching results.',
              icon: Icons.verified_user_outlined,
            ),
          ] else
            _WorkerInsidePanel(
              title: _title,
              value:
                  'This section is ready for the next build step. We will connect it to real job, profile, verification, and notification data.',
              icon: _iconFor(activeItem),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(_WorkerNavItem item) {
    return switch (item) {
      _WorkerNavItem.dashboard => Icons.grid_view_rounded,
      _WorkerNavItem.findJobs => Icons.search,
      _WorkerNavItem.profile => Icons.person_outline,
      _WorkerNavItem.applications => Icons.description_outlined,
      _WorkerNavItem.getVerified => Icons.verified_outlined,
      _WorkerNavItem.notifications => Icons.notifications_none,
    };
  }
}

class _WorkerMetricGrid extends StatelessWidget {
  const _WorkerMetricGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 360;

        return GridView.count(
          crossAxisCount: twoColumns ? 2 : 1,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: twoColumns ? 1.55 : 2.6,
          children: const [
            _WorkerMetricCard(
              label: 'Available Jobs',
              value: '0',
              icon: Icons.work_outline,
            ),
            _WorkerMetricCard(
              label: 'My Applications',
              value: '0',
              icon: Icons.description_outlined,
            ),
            _WorkerMetricCard(
              label: 'Completed Services',
              value: '0',
              icon: Icons.check_circle_outline,
            ),
            _WorkerMetricCard(
              label: 'Rating',
              value: 'No ratings yet',
              icon: Icons.star_border_rounded,
            ),
          ],
        );
      },
    );
  }
}

class _WorkerMetricCard extends StatelessWidget {
  const _WorkerMetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: GawaGoColors.primaryLight, size: 22),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerInsidePanel extends StatelessWidget {
  const _WorkerInsidePanel({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GawaGoColors.cardGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: GawaGoColors.primaryLight, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    color: GawaGoColors.mutedText,
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerNotificationsPage extends StatelessWidget {
  const _WorkerNotificationsPage();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NotificationsHeaderCard(),
          SizedBox(height: 14),
          _NotificationEmptyState(),
          SizedBox(height: 12),
          _NotificationCardPreview(
            title: 'Hire request',
            message:
                'Hire requests will appear here with accept or reject actions once backend notifications are connected.',
            icon: Icons.work_outline,
          ),
          SizedBox(height: 12),
          _NotificationCardPreview(
            title: 'Verification update',
            message:
                'Verification approval, rejection, and admin notes will appear here.',
            icon: Icons.verified_outlined,
          ),
        ],
      ),
    );
  }
}

class _NotificationsHeaderCard extends StatelessWidget {
  const _NotificationsHeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GawaGoColors.cardGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Notifications',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Mark All as Read'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: GawaGoColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
                textStyle: const TextStyle(
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

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState({
    this.message =
        'When backend data is connected, worker updates for hire requests, applications, verification, and completed jobs will show here.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.notifications_none,
            color: GawaGoColors.primaryLight,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No notifications loaded yet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  message,
                  style: const TextStyle(
                    color: GawaGoColors.mutedText,
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCardPreview extends StatelessWidget {
  const _NotificationCardPreview({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: GawaGoColors.primary, width: 4),
          top: BorderSide(color: GawaGoColors.borderGreen),
          right: BorderSide(color: GawaGoColors.borderGreen),
          bottom: BorderSide(color: GawaGoColors.borderGreen),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: GawaGoColors.primaryLight, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notification type',
                  style: TextStyle(
                    color: GawaGoColors.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  message,
                  style: const TextStyle(
                    color: GawaGoColors.mutedText,
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FindJobsPage extends StatelessWidget {
  const _FindJobsPage();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Jobs',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          const _JobFilterPanel(),
          const SizedBox(height: 18),
          const Text(
            'Jobs matching your skills will appear first',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          const _NoJobsFlowState(),
          const SizedBox(height: 12),
          const _WorkerJobCardPreview(),
        ],
      ),
    );
  }
}

class _JobFilterPanel extends StatelessWidget {
  const _JobFilterPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GawaGoColors.borderGreen),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 9,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              Expanded(
                child: _FilterField(
                  label: 'Filter by Job Type',
                  value: 'All Types',
                  isSelect: true,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _FilterField(label: 'Barangay', value: 'e.g. Poblacion'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                backgroundColor: GawaGoColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                  side: const BorderSide(color: GawaGoColors.primary),
                ),
              ),
              child: const Text(
                'Filter',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
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

class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.label,
    required this.value,
    this.isSelect = false,
  });

  final String label;
  final String value;
  final bool isSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: GawaGoColors.mutedText,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: GawaGoColors.cardGreen,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: GawaGoColors.borderGreen),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (isSelect)
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: Color(0xFF5D5B55),
                  size: 17,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoJobsFlowState extends StatelessWidget {
  const _NoJobsFlowState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GawaGoColors.borderGreen),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: const [
          Icon(Icons.search_off, color: GawaGoColors.primaryLight, size: 34),
          SizedBox(height: 10),
          Text(
            'No jobs loaded yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Once backend data is connected, available jobs will show here based on skills, availability, verification, and distance.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerJobCardPreview extends StatelessWidget {
  const _WorkerJobCardPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'Job card layout preview',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const _SkillMatchBadge(),
            ],
          ),
          const SizedBox(height: 6),
          const _JobInfoLine(
            text:
                'Description, location, schedule, rate, and household name will load from the backend.',
          ),
          const SizedBox(height: 8),
          const _DistanceBadge(label: 'Distance indicator'),
          const SizedBox(height: 11),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                backgroundColor: GawaGoColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                  side: const BorderSide(color: GawaGoColors.primary),
                ),
              ),
              child: const Text(
                'View Details',
                style: TextStyle(
                  fontSize: 11,
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

class _SkillMatchBadge extends StatelessWidget {
  const _SkillMatchBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF124A31),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GawaGoColors.borderGreen),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Text(
        'Matches Your Skills',
        style: TextStyle(
          color: GawaGoColors.primaryLight,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _JobInfoLine extends StatelessWidget {
  const _JobInfoLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text.rich(
        TextSpan(children: [TextSpan(text: text)]),
        style: const TextStyle(
          color: GawaGoColors.mutedText,
          fontSize: 11,
          height: 1.18,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _DistanceBadge extends StatelessWidget {
  const _DistanceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF124A31),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: GawaGoColors.primaryLight,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _WorkerVerificationPage extends StatelessWidget {
  const _WorkerVerificationPage();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 28),
      child: _WorkerSectionCard(
        title: 'Get Verified',
        child: Column(
          children: [
            _VerificationStatusCard(),
            SizedBox(height: 16),
            _VerificationDocumentCard(
              title: 'Primary ID',
              filename: 'No file uploaded yet',
              action: 'Upload Primary ID',
              icon: Icons.badge_outlined,
            ),
            SizedBox(height: 16),
            _VerificationDocumentCard(
              title: 'Supporting Documents',
              filename: 'Optional document not uploaded',
              action: 'Upload Supporting Document',
              icon: Icons.folder_copy_outlined,
            ),
            SizedBox(height: 16),
            _VerificationDocumentCard(
              title: 'Admin Note',
              filename: 'No admin note yet.',
              icon: Icons.note_alt_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationStatusCard extends StatelessWidget {
  const _VerificationStatusCard();

  @override
  Widget build(BuildContext context) {
    return const _SoftContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verification not submitted yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'When backend auth and uploads are connected, workers can submit documents here and see their approval status.',
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
    );
  }
}

class _VerificationDocumentCard extends StatelessWidget {
  const _VerificationDocumentCard({
    required this.title,
    required this.filename,
    this.action,
    required this.icon,
  });

  final String title;
  final String filename;
  final String? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _SoftContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            filename,
            style: const TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(icon, color: GawaGoColors.primaryLight, size: 16),
                const SizedBox(width: 7),
                Text(
                  action!,
                  style: const TextStyle(
                    color: GawaGoColors.primaryLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkerProfilePage extends StatelessWidget {
  const _WorkerProfilePage();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(8, 12, 8, 28),
      child: Column(
        children: [
          _WorkerSectionCard(
            title: 'My Profile',
            child: _WorkerProfileSummary(),
          ),
          SizedBox(height: 14),
          _WorkerSectionCard(
            title: 'Edit Profile Information',
            child: _WorkerProfileEditForm(),
          ),
          SizedBox(height: 14),
          _WorkerRatingSection(),
        ],
      ),
    );
  }
}

class _WorkerSectionCard extends StatelessWidget {
  const _WorkerSectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      decoration: BoxDecoration(
        color: GawaGoColors.cardGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: GawaGoColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _SoftContentCard extends StatelessWidget {
  const _SoftContentCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: child,
    );
  }
}

class _WorkerProfileSummary extends StatelessWidget {
  const _WorkerProfileSummary();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: Color(0xFF124A31),
          child: Text(
            'I',
            style: TextStyle(
              color: GawaGoColors.primaryLight,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Worker Name',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 3),
        Text(
          '@username',
          style: TextStyle(
            color: GawaGoColors.mutedText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 8),
        _SmallGreenPill(label: 'Worker'),
        SizedBox(height: 18),
        _WorkerInfoLines(),
        SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _SmallGreenPill(label: 'Selected Skill'),
            _SmallGreenPill(label: 'Selected Skill'),
            _SmallGreenPill(label: 'Selected Skill'),
          ],
        ),
      ],
    );
  }
}

class _WorkerInfoLines extends StatelessWidget {
  const _WorkerInfoLines();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoLine(label: 'Barangay:', value: 'Not set'),
        _InfoLine(label: 'Phone:', value: 'Not set'),
        _InfoLine(label: 'Email:', value: 'Not set'),
        Divider(height: 18, color: GawaGoColors.borderGreen),
        _InfoLine(label: 'Verification:', value: 'Not submitted'),
        _InfoLine(label: 'Rating:', value: 'No ratings yet'),
        _InfoLine(label: 'Jobs Done:', value: '0'),
        _InfoLine(label: 'Hourly Rate:', value: 'Not set'),
        _InfoLine(label: 'Daily Rate:', value: 'Not set'),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallGreenPill extends StatelessWidget {
  const _SmallGreenPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF124A31),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GawaGoColors.primary),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: GawaGoColors.primaryLight,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _WorkerProfileEditForm extends StatelessWidget {
  const _WorkerProfileEditForm();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileSubheading('Profile Photo'),
        _FilePickerMock(),
        SizedBox(height: 6),
        Text(
          'Accepted: JPG, PNG. Clear face photo recommended.',
          style: TextStyle(
            color: GawaGoColors.mutedText,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 18),
        _ProfileSubheading('Personal Information'),
        _ProfileInput(label: 'First Name', value: ''),
        _ProfileInput(label: 'Last Name', value: ''),
        _ProfileInput(label: 'Email', value: ''),
        _ProfileInput(label: 'Phone Number', value: ''),
        _ProfileInput(label: 'Barangay', value: '---Select Barangay---'),
        _ProfileInput(label: 'Street / House No.', value: ''),
        SizedBox(height: 8),
        _LightWorkerLocationPreview(),
        SizedBox(height: 18),
        _ProfileSubheading('Worker Information'),
        _ProfileInput(label: 'Bio / About Me', value: '', lines: 3),
        _ProfileInput(label: 'Hourly Rate (PHP)', value: ''),
        _ProfileInput(label: 'Daily Rate (PHP)', value: ''),
        SizedBox(height: 10),
        _AvailabilityHeader(),
        SizedBox(height: 14),
        _ProfileSubheading('Skills (Select all that apply)'),
        _ProfileSkillChecklist(),
        SizedBox(height: 16),
        Align(alignment: Alignment.centerRight, child: _EditProfileButton()),
      ],
    );
  }
}

class _ProfileSubheading extends StatelessWidget {
  const _ProfileSubheading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _FilePickerMock extends StatelessWidget {
  const _FilePickerMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Row(
        children: [
          Container(
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: GawaGoColors.cardGreen,
              border: Border(
                right: BorderSide(color: GawaGoColors.borderGreen),
              ),
            ),
            child: const Text(
              'Choose File',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No file chosen',
              style: TextStyle(
                color: GawaGoColors.mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInput extends StatelessWidget {
  const _ProfileInput({
    required this.label,
    required this.value,
    this.lines = 1,
  });

  final String label;
  final String value;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: TextEditingController(text: value),
            maxLines: lines,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: GawaGoColors.panelGreen,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: GawaGoColors.borderGreen),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: GawaGoColors.borderGreen),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: GawaGoColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LightWorkerLocationPreview extends StatelessWidget {
  const _LightWorkerLocationPreview();

  static const _workerPin = LatLng(14.0253, 121.5929);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Exact Account Location',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Text(
                'Location ready',
                style: TextStyle(
                  color: GawaGoColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: _workerPin,
                  initialZoom: 15,
                  interactionOptions: InteractionOptions(
                    flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                  ),
                ),
                children: [
                  if (shouldLoadMapTiles) osmTileLayer(),
                  MarkerLayer(
                    markers: const [
                      Marker(
                        point: _workerPin,
                        width: 42,
                        height: 52,
                        alignment: Alignment.topCenter,
                        child: _MapPin(label: 'W', color: Color(0xFF3B82F6)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _ProfileMiniButton(label: 'Use My Current Location'),
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: _ProfileMiniButton(
                  label: 'Pin on Map Manually',
                  outlined: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'No saved coordinates yet',
            style: TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMiniButton extends StatelessWidget {
  const _ProfileMiniButton({
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
      height: 32,
      child: TextButton(
        onPressed: onPressed ?? () {},
        style: TextButton.styleFrom(
          backgroundColor: outlined
              ? GawaGoColors.panelGreen
              : GawaGoColors.primary,
          foregroundColor: outlined ? GawaGoColors.mutedText : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
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
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvailabilityHeader extends StatelessWidget {
  const _AvailabilityHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: _ProfileSubheading('Availability Windows')),
        SizedBox(
          height: 30,
          child: TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              foregroundColor: GawaGoColors.mutedText,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: GawaGoColors.borderGreen),
              ),
            ),
            child: const Text(
              'Add Window',
              style: TextStyle(
                fontSize: 11,
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

class _ProfileSkillChecklist extends StatefulWidget {
  const _ProfileSkillChecklist();

  @override
  State<_ProfileSkillChecklist> createState() => _ProfileSkillChecklistState();
}

class _ProfileSkillChecklistState extends State<_ProfileSkillChecklist> {
  static const _skills = [
    'House Cleaning',
    'Cooking',
    'Laundry',
    'Childcare',
    'Elder Care',
    'Gardening',
    'Electrical Work',
    'Plumbing',
    'Carpentry',
    'Painting',
    'Aircon Repair/Cleaning',
    'Welding',
    'Driving',
    'Other',
  ];

  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        children: _skills.map((skill) {
          final selected = _selected.contains(skill);

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: CheckboxListTile(
              value: selected,
              onChanged: (checked) {
                setState(() {
                  if (checked ?? false) {
                    _selected.add(skill);
                  } else {
                    _selected.remove(skill);
                  }
                });
              },
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
              tileColor: GawaGoColors.cardGreen,
              activeColor: GawaGoColors.primary,
              checkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: selected
                      ? GawaGoColors.borderGreen
                      : Colors.transparent,
                ),
              ),
              title: Text(
                skill,
                style: const TextStyle(
                  color: GawaGoColors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: TextButton(
        onPressed: () {},
        style: TextButton.styleFrom(
          backgroundColor: GawaGoColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: const Text(
          'Edit Profile',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _WorkerRatingSection extends StatelessWidget {
  const _WorkerRatingSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: GawaGoColors.cardGreen,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: GawaGoColors.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Feedback & Rating',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'From households',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              children: [
                _NoRatingBox(),
                SizedBox(height: 16),
                _RatingBars(),
                Divider(height: 28, color: GawaGoColors.borderGreen),
                _RatingStatBox(value: '0', label: 'TOTAL REVIEWS'),
                SizedBox(height: 9),
                _RatingStatBox(value: '--', label: 'AVERAGE RATING'),
                SizedBox(height: 9),
                _RatingStatBox(value: '--', label: '5-STAR RATE'),
                SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recent reviews',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                SizedBox(height: 12),
                _EmptyReviewsBox(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoRatingBox extends StatelessWidget {
  const _NoRatingBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: const Column(
        children: [
          Text(
            'No\nratings\nyet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 27,
              height: 0.92,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '0 reviews',
            style: TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingBars extends StatelessWidget {
  const _RatingBars();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [5, 4, 3, 2, 1]
          .map(
            (stars) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    child: Text(
                      '$stars star',
                      style: TextStyle(
                        color: GawaGoColors.mutedText,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: 0,
                        minHeight: 5,
                        backgroundColor: GawaGoColors.cardGreen,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          GawaGoColors.primary,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    '0',
                    style: TextStyle(
                      color: GawaGoColors.mutedText,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _RatingStatBox extends StatelessWidget {
  const _RatingStatBox({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: GawaGoColors.panelGreen,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: GawaGoColors.borderGreen),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyReviewsBox extends StatelessWidget {
  const _EmptyReviewsBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: GawaGoColors.borderGreen,
          style: BorderStyle.solid,
        ),
      ),
      child: const Text(
        'No household feedback or ratings yet.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: GawaGoColors.mutedText,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
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
              onPressed: () {},
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
