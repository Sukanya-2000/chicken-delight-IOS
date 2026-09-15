import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

import 'services/rms_http_client.dart';

void main() => runApp(const PizzaHutRiderApp());

@pragma('vm:entry-point')
Future<void> riderBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await RiderBackgroundTracker().run();
}

class PizzaHutRiderApp extends StatelessWidget {
  const PizzaHutRiderApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Rider',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFC8102E),
            primary: const Color(0xFFC8102E),
            secondary: const Color(0xFFFFC72C),
            surface: const Color(0xFFFFFBF7),
          ),
          scaffoldBackgroundColor: const Color(0xFFFFFBF7),
          textTheme: const TextTheme(
            headlineSmall: TextStyle(fontWeight: FontWeight.w900),
            titleLarge: TextStyle(fontWeight: FontWeight.w900),
            titleMedium: TextStyle(fontWeight: FontWeight.w800),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        home: RiderAuthGate(apiClient: RiderApiClient()),
      );
}

class RiderAuthGate extends StatefulWidget {
  const RiderAuthGate({super.key, required this.apiClient});

  final RiderApiClient apiClient;

  @override
  State<RiderAuthGate> createState() => _RiderAuthGateState();
}

class _RiderAuthGateState extends State<RiderAuthGate> {
  static const _savedSessionKey = 'rider_saved_session';
  static const _storageChannel =
      MethodChannel('com.example.pizza_hut/rider_storage');
  RiderDriver? _driver;
  RiderBranch? _branch;
  bool _loadingSession = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  RiderApiClient get _activeApiClient {
    final apiUrl = _branch?.apiUrl;
    if (apiUrl == null || apiUrl.trim().isEmpty) return widget.apiClient;
    return widget.apiClient.withBaseUrl(apiUrl);
  }

  Future<void> _restoreSession() async {
    try {
      final values = await _storageChannel.invokeListMethod<String>(
            'getStringList',
            {'key': _savedSessionKey},
          ) ??
          const <String>[];
      if (values.isNotEmpty) {
        final decoded = jsonDecode(values.first);
        if (decoded is Map<String, dynamic>) {
          final branchJson = decoded['branch'];
          final driverJson = decoded['driver'];
          final branch = branchJson is Map<String, dynamic>
              ? RiderBranch.fromJson(branchJson)
              : null;
          final driver = driverJson is Map<String, dynamic>
              ? RiderDriver.fromJson(driverJson)
              : null;
          if (driver != null &&
              driver.id.trim().isNotEmpty &&
              driver.password.trim().isNotEmpty) {
            _branch = branch;
            _driver = driver;
          } else if (driver != null && driver.password.trim().isEmpty) {
            await _storageChannel.invokeMethod<void>(
              'setStringList',
              {'key': _savedSessionKey, 'values': const <String>[]},
            );
          }
        }
      }
    } catch (_) {
      // Ignore corrupt saved sessions and show the normal login flow.
    }
    if (!mounted) return;
    setState(() => _loadingSession = false);
  }

  Future<void> _persistSession({
    required RiderBranch? branch,
    required RiderDriver? driver,
  }) async {
    if (driver == null) {
      await _storageChannel.invokeMethod<void>(
        'setStringList',
        {'key': _savedSessionKey, 'values': const <String>[]},
      );
      return;
    }
    await _storageChannel.invokeMethod<void>(
      'setStringList',
      {
        'key': _savedSessionKey,
        'values': [
          jsonEncode({
            if (branch != null) 'branch': branch.toJson(),
            'driver': driver.toJson(),
          }),
        ],
      },
    );
  }

  void _setAuthenticated(RiderBranch branch, RiderDriver driver) {
    setState(() {
      _branch = branch;
      _driver = driver;
    });
    unawaited(_persistSession(branch: branch, driver: driver));
  }

  void _setDriver(RiderDriver driver) {
    setState(() => _driver = driver);
    unawaited(_persistSession(branch: _branch, driver: driver));
  }

  Future<void> _logout() async {
    final driver = _driver;
    final apiClient = _activeApiClient;
    await _persistSession(branch: null, driver: null);
    if (driver != null) {
      try {
        await apiClient.updateDriverStatus(driver, 'offline');
      } catch (_) {
        // Local logout should still complete if RMS is temporarily unreachable.
      }
    }
    if (!mounted) return;
    setState(() {
      _driver = null;
      _branch = null;
    });
  }

  Future<void> _forceLocalLogout() async {
    await _persistSession(branch: null, driver: null);
    if (!mounted) return;
    setState(() {
      _driver = null;
      _branch = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final driver = _driver;
    if (driver == null) {
      final branch = _branch;
      if (branch == null) {
        return RiderRestaurantSelectScreen(
          apiClient: widget.apiClient,
          onBranchSelected: (value) => setState(() => _branch = value),
        );
      }
      return RiderAuthScreen(
        apiClient: _activeApiClient,
        branch: branch,
        onChangeBranch: () => setState(() => _branch = null),
        onAuthenticated: (value) => _setAuthenticated(branch, value),
      );
    }
    return RiderHomeScreen(
      apiClient: _activeApiClient,
      branch: _branch,
      driver: driver,
      onDriverChanged: _setDriver,
      onLogout: () => unawaited(_logout()),
      onForceLogout: _forceLocalLogout,
    );
  }
}

class RiderRestaurantSelectScreen extends StatefulWidget {
  const RiderRestaurantSelectScreen({
    super.key,
    required this.apiClient,
    required this.onBranchSelected,
  });

  final RiderApiClient apiClient;
  final ValueChanged<RiderBranch> onBranchSelected;

  @override
  State<RiderRestaurantSelectScreen> createState() =>
      _RiderRestaurantSelectScreenState();
}

class _RiderRestaurantSelectScreenState
    extends State<RiderRestaurantSelectScreen> {
  static const _savedBranchesKey = 'rider_saved_restaurants';
  static const _storageChannel =
      MethodChannel('com.example.pizza_hut/rider_storage');
  List<RiderBranch> branches = const <RiderBranch>[];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    final rawBranches = await _storageChannel.invokeListMethod<String>(
          'getStringList',
          {'key': _savedBranchesKey},
        ) ??
        const <String>[];
    final loaded =
        rawBranches.map(RiderBranch.tryParse).whereType<RiderBranch>().toList();
    if (!mounted) return;
    setState(() {
      branches = loaded;
      loading = false;
    });
  }

  Future<void> _persistBranches(List<RiderBranch> next) async {
    await _storageChannel.invokeMethod<void>(
      'setStringList',
      {
        'key': _savedBranchesKey,
        'values': next.map((saved) => jsonEncode(saved.toJson())).toList(),
      },
    );
    if (!mounted) return;
    setState(() => branches = next);
  }

  Future<void> _saveBranch(RiderBranch branch) async {
    final next = [
      branch,
      ...branches.where((saved) => saved.id != branch.id),
    ];
    await _persistBranches(next);
  }

  Future<void> _deleteBranch(RiderBranch branch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete restaurant?'),
        content: Text('Remove ${branch.label} from saved restaurants?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _persistBranches(
      branches.where((saved) => saved.id != branch.id).toList(),
    );
  }

  Future<void> _scan(BuildContext context) async {
    final branch = await Navigator.of(context).push<RiderBranch>(
      MaterialPageRoute(
        builder: (_) => RiderQrScannerScreen(apiClient: widget.apiClient),
      ),
    );
    if (branch == null) return;
    await _saveBranch(branch);
    widget.onBranchSelected(branch);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      child: const Icon(Icons.qr_code_scanner, size: 46),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Select restaurant',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Choose a saved restaurant or scan a new QR code.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (loading) ...[
                      const SizedBox(height: 28),
                      const Center(child: CircularProgressIndicator()),
                    ] else if (branches.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      ...branches.map(
                        (branch) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      widget.onBranchSelected(branch),
                                  icon: const Icon(Icons.restaurant_outlined),
                                  label: Text(branch.label),
                                  style: OutlinedButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    minimumSize: const Size(0, 54),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: 'Delete restaurant',
                                onPressed: () => _deleteBranch(branch),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: branches.isEmpty ? 28 : 8),
                    FilledButton.icon(
                      onPressed: () => _scan(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add restaurant'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class RiderQrScannerScreen extends StatefulWidget {
  const RiderQrScannerScreen({super.key, this.apiClient});

  final RiderApiClient? apiClient;

  @override
  State<RiderQrScannerScreen> createState() => _RiderQrScannerScreenState();
}

class _RiderQrScannerScreenState extends State<RiderQrScannerScreen> {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );
  StreamSubscription<BarcodeCapture>? _barcodeSubscription;
  bool handled = false;
  bool verifying = false;

  @override
  void initState() {
    super.initState();
    _barcodeSubscription = controller.barcodes.listen(_handleDetect);
  }

  @override
  void dispose() {
    _barcodeSubscription?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (handled) return;
    final rawValue = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    if (rawValue.isEmpty) return;

    _resolveQr(rawValue);
  }

  Future<void> _resolveQr(String rawValue) async {
    final branch = RiderBranch.tryParseAny(rawValue);
    if (branch == null) {
      handled = true;
      if (mounted) setState(() => verifying = true);
      try {
        final verifiedBranch = await (widget.apiClient ?? RiderApiClient())
            .verifyStoreQr(rawValue);
        if (!mounted) return;
        Navigator.of(context).pop(verifiedBranch);
      } catch (_) {
        final signedBranch = RiderBranch.tryParseAny(rawValue);
        if (signedBranch != null) {
          if (!mounted) return;
          Navigator.of(context).pop(signedBranch);
          return;
        }
        if (!mounted) return;
        await _showInvalidQr(rawValue);
        if (!mounted) return;
        setState(() {
          handled = false;
          verifying = false;
        });
      }
      return;
    }

    handled = true;
    Navigator.of(context).pop(branch);
  }

  Future<void> _showInvalidQr(String rawValue) async {
    final preview =
        rawValue.length > 420 ? '${rawValue.substring(0, 420)}...' : rawValue;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('QR not recognized'),
        content: SingleChildScrollView(
          child: SelectableText(
            preview.isEmpty ? '(empty scan)' : preview,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: rawValue));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Scanned QR copied.')),
              );
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Scan again'),
          ),
        ],
      ),
    );
  }

  Future<void> _enterQrData() async {
    final controller = TextEditingController();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final rawValue = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter QR data'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Paste QR token, URL, or restaurant JSON',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (rawValue == null || rawValue.trim().isEmpty || !mounted) return;

    var branch = RiderBranch.tryParseAny(rawValue);
    if (branch == null) {
      try {
        branch = await (widget.apiClient ?? RiderApiClient())
            .verifyStoreQr(rawValue);
      } catch (_) {
        branch = RiderBranch.tryParseAny(rawValue);
      }
    }
    if (branch == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter a valid restaurant QR code.')),
      );
      return;
    }
    navigator.pop(branch);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan restaurant QR')),
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: controller),
            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 32,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (verifying) ...[
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 10),
                              Text('Verifying QR...'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed: verifying ? null : _enterQrData,
                      icon: const Icon(Icons.keyboard_alt_outlined),
                      label: const Text('Enter QR data'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class RiderAuthScreen extends StatefulWidget {
  const RiderAuthScreen({
    super.key,
    required this.apiClient,
    required this.branch,
    required this.onChangeBranch,
    required this.onAuthenticated,
  });

  final RiderApiClient apiClient;
  final RiderBranch branch;
  final VoidCallback onChangeBranch;
  final ValueChanged<RiderDriver> onAuthenticated;

  @override
  State<RiderAuthScreen> createState() => _RiderAuthScreenState();
}

class _RiderAuthScreenState extends State<RiderAuthScreen> {
  static const _locationChannel =
      MethodChannel('com.example.pizza_hut/location');
  final form = GlobalKey<FormState>();
  final driverId = TextEditingController();
  final password = TextEditingController();
  bool submitting = false;
  bool showPassword = false;

  @override
  void dispose() {
    driverId.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        child: const Icon(Icons.delivery_dining, size: 48),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Rider',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Login to receive RMS delivery assignments',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: submitting ? null : widget.onChangeBranch,
                        icon: const Icon(Icons.restaurant_outlined),
                        label: Text(widget.branch.label),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: driverId,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Driver ID',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: password,
                        obscureText: !showPassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => showPassword = !showPassword),
                            icon: Icon(showPassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                          ),
                        ),
                        validator: _required,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: submitting ? null : _submit,
                        child: submitting
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  Future<void> _submit() async {
    final currentForm = form.currentState;
    if (currentForm == null || !currentForm.validate()) return;
    setState(() => submitting = true);
    try {
      var driver = (await widget.apiClient.loginDriver(
        driverId: driverId.text.trim(),
        password: password.text,
        branchId: widget.branch.id,
      ))
          .withRestaurantId(widget.branch.id)
          .withPassword(password.text);
      try {
        final location = await _requestLocation().timeout(
          const Duration(seconds: 25),
        );
        await widget.apiClient.tryUpdateDriverLocation(
          driver,
          latitude: location.latitude,
          longitude: location.longitude,
        );
      } catch (_) {
        // Do not block login if emulator/device location is unavailable.
      }
      if (!mounted) return;
      widget.onAuthenticated(driver);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<RiderLocationFix> _requestLocation() async {
    try {
      final result = await _locationChannel.invokeMapMethod<String, dynamic>(
        'getCurrentLocation',
      );
      final latitude = result?['latitude'];
      final longitude = result?['longitude'];
      if (latitude is num && longitude is num) {
        return RiderLocationFix(
          latitude: latitude.toDouble(),
          longitude: longitude.toDouble(),
        );
      }
      throw Exception('Could not read rider location.');
    } on PlatformException catch (error) {
      switch (error.code) {
        case 'permission_denied':
          throw Exception('Location permission is required for rider login.');
        case 'permission_denied_forever':
          throw Exception(
              'Location permission is blocked. Enable it in settings.');
        case 'service_disabled':
          throw Exception('Turn on location services to continue.');
        case 'timeout':
          throw Exception('Timed out waiting for rider location.');
        default:
          throw Exception(error.message ?? 'Could not read rider location.');
      }
    }
  }
}

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({
    super.key,
    required this.apiClient,
    required this.branch,
    required this.driver,
    required this.onDriverChanged,
    required this.onLogout,
    required this.onForceLogout,
  });

  final RiderApiClient apiClient;
  final RiderBranch? branch;
  final RiderDriver driver;
  final ValueChanged<RiderDriver> onDriverChanged;
  final VoidCallback onLogout;
  final Future<void> Function() onForceLogout;

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  static const _locationChannel =
      MethodChannel('com.example.pizza_hut/location');
  static const _storageChannel =
      MethodChannel('com.example.pizza_hut/rider_storage');
  static const _activityStoragePrefix = 'rider_delivered_orders';
  final List<RiderOrder> _orders = [];
  final List<RiderOrder> _activityOrders = [];
  final Set<String> _countedActivityOrderIds = {};
  late final RiderPusherLocationClient _locationPusher;
  Timer? _refreshTimer;
  Timer? _locationTimer;
  Timer? _checkoutPollTimer;
  RiderOrder? _selectedOrder;
  RiderOrder? _lastDeliveredOrder;
  RiderActivityStats _activityStats = const RiderActivityStats.empty();
  int _tabIndex = 0;
  bool _loading = true;
  late bool _online;
  bool _posCheckedIn = true;
  bool _posCheckUpdating = false;
  bool _updating = false;
  bool _backgroundTrackingEnabled = true;
  bool _ordersRefreshInFlight = false;
  bool _remoteLogoutHandled = false;
  Future<void> _activityPersistence = Future<void>.value();
  String _trackerStatus = 'Tracker starting...';

  @override
  void initState() {
    super.initState();
    _online = true;
    _locationPusher = RiderPusherLocationClient(
      baseUrl: widget.apiClient.baseUrl,
      driver: widget.driver,
      onDriverStatusChange: _handleRemoteDriverStatusChange,
    );
    unawaited(_locationPusher.startStatusListener());
    _startLocationBroadcasting();
    unawaited(_startBackgroundTrackingService());
    unawaited(_initializeRiderData());
    unawaited(_logoutIfCheckedOutFromRms());
    _checkoutPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_logoutIfCheckedOutFromRms()),
    );
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _loadOrders());
  }

  Future<void> _initializeRiderData() async {
    await _loadLocalActivityOrders();
    await _loadOrders();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _locationTimer?.cancel();
    _checkoutPollTimer?.cancel();
    _locationPusher.dispose();
    super.dispose();
  }

  void _startLocationBroadcasting() {
    _locationTimer?.cancel();
    if (!_online) return;
    unawaited(_sendLocationUpdate());
  }

  void _scheduleNextLocationUpdate() {
    _locationTimer?.cancel();
    if (!_online || !mounted) return;
    _locationTimer = Timer(
      _locationBroadcastIntervalFor(_currentTrackingPhase),
      () => unawaited(_sendLocationUpdate()),
    );
  }

  Duration _locationBroadcastIntervalFor(String phase) {
    switch (phase) {
      case 'en-route':
        return const Duration(seconds: 6);
      case 'returning':
        return const Duration(seconds: 40);
      default:
        return const Duration(seconds: 70);
    }
  }

  Future<void> _startBackgroundTrackingService() async {
    if (!_online || !_backgroundTrackingEnabled) return;
    try {
      await _locationChannel.invokeMethod<bool>(
        'ensureBackgroundTrackingPermission',
      );
      await _locationChannel.invokeMethod<void>(
        'startRiderTrackingService',
        {
          'driverName': widget.driver.name,
          'phase': _currentTrackingPhase,
          'activeOrderCount': _orders.length,
        },
      );
      if (mounted) {
        setState(() => _trackerStatus = 'Background tracker active');
      }
    } catch (_) {
      // Older installs still use the Flutter-side tracker if the service is
      // unavailable for any Android-specific reason.
    }
  }

  Future<void> _stopBackgroundTrackingService() async {
    try {
      await _locationChannel.invokeMethod<void>('stopRiderTrackingService');
    } catch (_) {}
  }

  Future<void> _sendLocationUpdate() async {
    if (!_online) return;
    try {
      if (await _logoutIfCheckedOutFromRms()) return;
      final location = await _requestLocation().timeout(
        const Duration(seconds: 25),
      );
      final activeOrderIds = _orders
          .where((order) => order.shouldShowInDelivery)
          .map((order) => order.id)
          .where((id) => id.trim().isNotEmpty)
          .toSet();
      _locationPusher.updateActiveOrderIds(activeOrderIds);
      await _locationPusher.publishLocation(
        latitude: location.latitude,
        longitude: location.longitude,
        phase: _currentTrackingPhase,
        activeOrderIds: activeOrderIds,
      );
      await widget.apiClient.tryUpdateDriverLocation(
        widget.driver,
        latitude: location.latitude,
        longitude: location.longitude,
      );
      if (mounted) {
        final time = TimeOfDay.now().format(context);
        setState(() => _trackerStatus = 'Location sent at $time');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _trackerStatus = 'Tracker error: $error');
      }
    } finally {
      _scheduleNextLocationUpdate();
    }
  }

  void _handleRemoteDriverStatusChange(Map<String, dynamic> data) {
    if (_remoteLogoutHandled) return;
    final payloadData = data['data'];
    final payload = payloadData is Map<String, dynamic> ? payloadData : data;
    final eventDriverIds = _driverIdsFromStatusPayload(payload);
    final currentDriverIds = {
      _normalizeDriverEventId(widget.driver.id),
      _normalizeDriverEventId(widget.driver.driverId),
    }..removeWhere((id) => id.isEmpty);
    final status = '${payload['status'] ?? ''}'.trim().toLowerCase();
    final message =
        '${data['message'] ?? payload['message'] ?? ''}'.trim().toLowerCase();
    final checkedOut = _isTruthy(payload['checkedOut']) ||
        _isFalsy(payload['posCheckedIn']) ||
        status == 'offline' ||
        status == 'checked-out' ||
        message.contains('checked out');
    final isForThisDriver = eventDriverIds.isEmpty ||
        eventDriverIds.any((id) => currentDriverIds.contains(id));
    if (checkedOut && isForThisDriver) {
      unawaited(_runLogoutApiAndLogout());
      return;
    }
    unawaited(_logoutIfCheckedOutFromRms());
  }

  String _normalizeDriverEventId(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  Set<String> _driverIdsFromStatusPayload(Map<String, dynamic> data) {
    final employee = data['employeeId'];
    return <String>{
      '${data['driverId'] ?? ''}',
      '${data['driver_id'] ?? ''}',
      '${data['_id'] ?? ''}',
      '${data['id'] ?? ''}',
      '${data['driverCode'] ?? ''}',
      if (employee is Map) ...[
        '${employee['_id'] ?? ''}',
        '${employee['id'] ?? ''}',
        '${employee['employeeId'] ?? ''}',
      ] else
        '${employee ?? ''}',
    }.map(_normalizeDriverEventId).where((id) => id.isNotEmpty).toSet();
  }

  bool _isTruthy(dynamic value) {
    if (value == true) return true;
    final text = '$value'.trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  bool _isFalsy(dynamic value) {
    if (value == false) return true;
    final text = '$value'.trim().toLowerCase();
    return text == 'false' || text == '0' || text == 'no';
  }

  Future<void> _runLogoutApiAndLogout() async {
    if (_remoteLogoutHandled) return;
    _remoteLogoutHandled = true;
    _refreshTimer?.cancel();
    _locationTimer?.cancel();
    _checkoutPollTimer?.cancel();
    unawaited(_locationPusher.dispose());
    unawaited(_stopBackgroundTrackingService());
    await _showPosCheckoutLogoutMessage();
    await _storageChannel.invokeMethod<void>(
      'setStringList',
      {'key': 'rider_saved_session', 'values': const <String>[]},
    );
    await widget.onForceLogout();
    unawaited(
      widget.apiClient
          .updateDriverStatus(widget.driver, 'offline')
          .catchError((_) => widget.driver),
    );
  }

  Future<void> _showPosCheckoutLogoutMessage() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "You're checked out from POS, so logging out from rider app.",
        ),
        duration: Duration(milliseconds: 1200),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1200));
  }

  Future<bool> _logoutIfCheckedOutFromRms() async {
    if (_remoteLogoutHandled) return true;
    try {
      if (await widget.apiClient.isDriverLoginBlockedByPosCheckout(
        widget.driver,
      )) {
        await _runLogoutApiAndLogout();
        return true;
      }
    } catch (_) {}

    try {
      final checkedIn =
          await widget.apiClient.isDriverCheckedInAtPos(widget.driver);
      if (!checkedIn) {
        await _runLogoutApiAndLogout();
        return true;
      }
    } catch (_) {}

    try {
      final remoteDriver =
          await widget.apiClient.fetchDriverProfile(widget.driver);
      final status = remoteDriver.status.trim().toLowerCase();
      if (!remoteDriver.posCheckedIn ||
          status == 'offline' ||
          status == 'checked-out') {
        await _runLogoutApiAndLogout();
        return true;
      }
    } on RmsApiException catch (error) {
      if (error.code == '401' || error.code == '403') {
        await _runLogoutApiAndLogout();
        return true;
      }
    } catch (_) {
      // Keep the rider on the current screen if RMS cannot be checked.
    }
    return false;
  }

  Future<RiderLocationFix> _requestLocation() async {
    final result = await _locationChannel.invokeMapMethod<String, dynamic>(
      'getCurrentLocation',
    );
    final latitude = result?['latitude'];
    final longitude = result?['longitude'];
    if (latitude is num && longitude is num) {
      return RiderLocationFix(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      );
    }
    throw Exception('Could not read rider location.');
  }

  Future<void> _loadOrders() async {
    if (!_online) return;
    if (_ordersRefreshInFlight) return;
    _ordersRefreshInFlight = true;
    if (mounted && _orders.isEmpty) setState(() => _loading = true);

    try {
      if (await _logoutIfCheckedOutFromRms()) return;
      final orders =
          await widget.apiClient.fetchDriverAssignments(widget.driver);
      final activeOrders =
          orders.where((order) => order.shouldShowInDelivery).toList();
      RiderActivityReport activityReport = const RiderActivityReport.empty();
      try {
        activityReport = await widget.apiClient.fetchDriverActivity(
          widget.driver,
        );
      } catch (_) {
        // Assignment refresh must still show active orders if activity is unavailable.
      }
      final assignmentDeliveredOrders =
          orders.where((order) => order.countsTowardActivity).toList();
      final deliveredOrders = _mergeActivityOrders(
        activityReport.orders.where((order) => order.countsTowardActivity),
        assignmentDeliveredOrders,
      );
      final activeKeys = _activityKeysFor(activeOrders);
      final activeFingerprints = _activityFingerprintsFor(activeOrders);
      final safeDeliveredOrders = deliveredOrders
          .where(
            (order) =>
                !_hasAnyActivityKey(order, activeKeys) &&
                !_hasAnyActivityFingerprint(order, activeFingerprints),
          )
          .toList();
      final safeLocalDeliveredOrders = _activityOrders
          .where(
            (order) =>
                order.countsTowardActivity &&
                !_hasAnyActivityKey(order, activeKeys) &&
                !_hasAnyActivityFingerprint(order, activeFingerprints),
          )
          .toList();
      final visibleDeliveredOrders = _mergeActivityOrders(
        safeDeliveredOrders,
        safeLocalDeliveredOrders,
      );
      _locationPusher.updateActiveOrderIds(
        activeOrders.map((order) => order.id),
      );
      if (!mounted) return;
      setState(() {
        _orders
          ..clear()
          ..addAll(activeOrders);
        _forgetActivityOrders(activeKeys);
        _forgetActivityOrdersByFingerprint(activeFingerprints);
        _activityOrders
          ..clear()
          ..addAll(visibleDeliveredOrders);
        _countedActivityOrderIds
          ..clear()
          ..addAll(_activityOrders.map(_activityIdFor));
        _activityStats = RiderActivityStats.fromDeliveredOrders(
          _activityOrders,
        ).mergedWith(activityReport.stats);
        _selectedOrder = _syncSelectedOrder(activeOrders);
        _loading = false;
      });
      unawaited(_persistLocalActivityOrders());
      unawaited(_startBackgroundTrackingService());
    } on RmsApiException catch (error) {
      if (error.code == '401' ||
          error.code == '403' ||
          error.message.toLowerCase().contains('checked out')) {
        await _runLogoutApiAndLogout();
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _trackerStatus = 'RMS temporarily unavailable; staying online';
      });
      unawaited(_startBackgroundTrackingService());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _trackerStatus = 'RMS temporarily unavailable; staying online';
      });
      unawaited(_startBackgroundTrackingService());
    } finally {
      _ordersRefreshInFlight = false;
    }
  }

  String get _currentTrackingPhase {
    if (_orders.any((order) => order.isActiveDelivery)) return 'en-route';
    if (_orders.any((order) => order.isDelivered)) return 'returning';
    return 'available';
  }

  RiderOrder? _syncSelectedOrder(List<RiderOrder> orders) {
    final selected = _selectedOrder;
    if (selected == null && orders.isNotEmpty) return orders.first;
    if (selected == null) return null;
    for (final order in orders) {
      if (order.id == selected.id) return order;
    }
    return orders.isEmpty ? null : orders.first;
  }

  Future<void> _updateStatus(RiderOrder order, String status) async {
    setState(() => _updating = true);
    try {
      await widget.apiClient.updateOrderStatus(
        order.id,
        status,
        driver: widget.driver,
        assignmentId: order.assignmentId,
      );
      if (status == 'completed' || status == 'delivered') {
        setState(() {
          final deliveredOrder =
              order.copyWith(status: 'delivered', deliveredAt: DateTime.now());
          _rememberActivityOrder(deliveredOrder);
          _lastDeliveredOrder = deliveredOrder;
          _orders.removeWhere(
            (current) =>
                current.id == order.id ||
                (current.assignmentId.isNotEmpty &&
                    current.assignmentId == order.assignmentId),
          );
          _selectedOrder = _syncSelectedOrder(_orders);
          _activityStats = RiderActivityStats.fromDeliveredOrders(
            _activityOrders,
          );
        });
      }
      await _loadOrders();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Set<String> _activityKeysFor(Iterable<RiderOrder> orders) => {
        for (final order in orders) ..._activityKeys(order),
      };

  Set<String> _activityKeys(RiderOrder order) => {
        if (order.id.trim().isNotEmpty) 'id:${order.id.trim()}',
        if (order.assignmentId.trim().isNotEmpty)
          'assignment:${order.assignmentId.trim()}',
        if (order.number.trim().isNotEmpty) 'number:${order.number.trim()}',
      };

  bool _hasAnyActivityKey(RiderOrder order, Set<String> keys) =>
      _activityKeys(order).any(keys.contains);

  Set<String> _activityFingerprintsFor(Iterable<RiderOrder> orders) => {
        for (final order in orders) ..._activityFingerprints(order),
      };

  Set<String> _activityFingerprints(RiderOrder order) {
    final number = _normalizeActivityText(order.number);
    final customer = _normalizeActivityText(order.customerName);
    final total = (order.total * 100).round();
    return {
      if (number.isNotEmpty) 'number:$number',
      if (number.isNotEmpty && total > 0) 'number-total:$number:$total',
      if (number.isNotEmpty && customer.isNotEmpty)
        'number-customer:$number:$customer',
    };
  }

  bool _hasAnyActivityFingerprint(RiderOrder order, Set<String> fingerprints) =>
      _activityFingerprints(order).any(fingerprints.contains);

  String _normalizeActivityText(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  void _forgetActivityOrders(Set<String> keys) {
    if (keys.isEmpty) return;
    _activityOrders.removeWhere((order) => _hasAnyActivityKey(order, keys));
    _countedActivityOrderIds
      ..clear()
      ..addAll(_activityOrders.map(_activityIdFor));
  }

  void _forgetActivityOrdersByFingerprint(Set<String> fingerprints) {
    if (fingerprints.isEmpty) return;
    _activityOrders.removeWhere(
      (order) => _hasAnyActivityFingerprint(order, fingerprints),
    );
    _countedActivityOrderIds
      ..clear()
      ..addAll(_activityOrders.map(_activityIdFor));
  }

  void _rememberActivityOrder(RiderOrder order) {
    final activityId = _activityIdFor(order);
    if (!_countedActivityOrderIds.add(activityId)) return;
    _activityOrders.insert(0, order);
    _persistLocalActivityOrders();
  }

  List<RiderOrder> _mergeActivityOrders(
    Iterable<RiderOrder> primary,
    Iterable<RiderOrder> fallback,
  ) {
    final seen = <String>{};
    final merged = <RiderOrder>[];
    for (final order in [...primary, ...fallback]) {
      final activityId = _activityIdFor(order);
      if (seen.add(activityId)) merged.add(order);
    }
    return merged;
  }

  String _activityIdFor(RiderOrder order) => order.id.trim().isEmpty
      ? '${order.number}-${order.createdAt.toIso8601String()}'
      : order.id;

  String get _activityStorageKey =>
      '${_activityStoragePrefix}_${widget.driver.id}';

  Future<void> _loadLocalActivityOrders() async {
    final values = await _storageChannel.invokeListMethod<String>(
          'getStringList',
          {'key': _activityStorageKey},
        ) ??
        const <String>[];
    final orders = <RiderOrder>[];
    for (final value in values) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) {
          final order = RiderOrder.fromActivityJson(decoded);
          if (order.countsTowardActivity) orders.add(order);
        }
      } catch (_) {}
    }
    _activityOrders
      ..clear()
      ..addAll(orders);
    _countedActivityOrderIds
      ..clear()
      ..addAll(_activityOrders.map(_activityIdFor));
    if (mounted) {
      setState(
        () => _activityStats = RiderActivityStats.fromDeliveredOrders(
          _activityOrders,
        ),
      );
    }
  }

  Future<void> _persistLocalActivityOrders() async {
    final values = _activityOrders
        .where((order) => order.countsTowardActivity)
        .take(100)
        .map((order) => jsonEncode(order.toActivityJson()))
        .toList();
    _activityPersistence = _activityPersistence.then((_) async {
      await _storageChannel.invokeMethod<void>(
        'setStringList',
        {
          'key': _activityStorageKey,
          'values': values,
        },
      );
    });
    await _activityPersistence;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex,
          children: [
            _DeliveryTab(
              driver: widget.driver,
              loading: _loading,
              online: _online,
              orders: _orders,
              selectedOrder: _selectedOrder,
              updating: _updating,
              onRefresh: _loadOrders,
              onOnlineChanged: _setOnline,
              onSelectOrder: (order) => setState(() => _selectedOrder = order),
              onDelivered: (order) => _updateStatus(order, 'completed'),
              onAvailableForNextOrders: () => _setAvailableForNextOrders(),
              lastDeliveredOrder: _lastDeliveredOrder,
            ),
            _ActivityTab(
              stats: _activityStats,
              orders: _activityOrders,
              activeOrders: _orders,
              onRefresh: _loadOrders,
            ),
            _SettingsTab(
              online: _online,
              backgroundTrackingEnabled: _backgroundTrackingEnabled,
              posCheckedIn: _posCheckedIn,
              posCheckUpdating: _posCheckUpdating,
              trackerStatus: _trackerStatus,
              trackerChannel: _locationPusher.restaurantChannelName,
              driver: widget.driver,
              onOnlineChanged: _setOnline,
              onBackgroundTrackingChanged: _setBackgroundTrackingEnabled,
              onPosCheckedInChanged: _setPosCheckedIn,
              onLogout: () {
                unawaited(_stopBackgroundTrackingService());
                widget.onLogout();
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.delivery_dining_outlined),
            selectedIcon: Icon(Icons.delivery_dining),
            label: 'Delivery',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_toggle_off),
            selectedIcon: Icon(Icons.history),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Future<void> _setOnline(
    bool value, {
    bool notifyOnFailure = true,
  }) async {
    if (!value) {
      if (mounted) setState(() => _online = true);
      _startLocationBroadcasting();
      unawaited(_startBackgroundTrackingService());
      return;
    }
    if (mounted) setState(() => _online = true);
    try {
      final updated = await widget.apiClient.updateDriverStatus(
        widget.driver,
        'available',
      );
      widget.onDriverChanged(updated);
      _startLocationBroadcasting();
      unawaited(_startBackgroundTrackingService());
      _loadOrders();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _online = true;
        _trackerStatus = 'RMS temporarily unavailable; staying online';
      });
      _startLocationBroadcasting();
      unawaited(_startBackgroundTrackingService());
      if (notifyOnFailure) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Still online. RMS will sync when it responds.'),
          ),
        );
      }
    }
  }

  Future<void> _setAvailableForNextOrders([RiderOrder? order]) async {
    if (_updating) return;
    final completedOrder = order ?? _lastDeliveredOrder;
    setState(() => _updating = true);
    try {
      if (completedOrder != null &&
          completedOrder.assignmentId.trim().isNotEmpty) {
        await widget.apiClient.completeDriverAssignment(
          completedOrder.assignmentId,
          driver: widget.driver,
        );
      }
      await _setOnline(true);
      await _setPosCheckedIn(true);
      if (!mounted) return;
      setState(() => _lastDeliveredOrder = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are available for next orders.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _setBackgroundTrackingEnabled(bool value) {
    setState(() {
      _backgroundTrackingEnabled = value;
      _trackerStatus =
          value ? 'Background tracker enabled' : 'Background tracker disabled';
    });
    if (value) {
      unawaited(_startBackgroundTrackingService());
    } else {
      unawaited(_stopBackgroundTrackingService());
    }
  }

  Future<void> _setPosCheckedIn(bool value) async {
    if (_posCheckUpdating) return;
    setState(() => _posCheckUpdating = true);
    try {
      if (value) {
        await widget.apiClient.checkInDriverAtPos(
          widget.driver,
          branchId: widget.branch?.id ?? widget.driver.restaurantId,
        );
      } else {
        await widget.apiClient.checkOutDriverAtPos(
          widget.driver,
          branchId: widget.branch?.id ?? widget.driver.restaurantId,
        );
      }
      if (!mounted) return;
      setState(() => _posCheckedIn = value);
      unawaited(_sendLocationUpdate());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'POS check-in enabled. Refresh POS drivers if needed.'
                : 'POS check-in disabled.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _posCheckUpdating = false);
    }
  }

  Future<void> _ensureDefaultPosCheckIn() async {
    if (!_online || !_posCheckedIn || _posCheckUpdating) return;
    try {
      await widget.apiClient.checkInDriverAtPos(
        widget.driver,
        branchId: widget.branch?.id ?? widget.driver.restaurantId,
      );
      if (!mounted) return;
      setState(() => _posCheckedIn = true);
    } catch (_) {
      // Keep the switch on by default; the rider can retry by toggling it.
    }
  }
}

class _DeliveryTab extends StatelessWidget {
  const _DeliveryTab({
    required this.driver,
    required this.loading,
    required this.online,
    required this.orders,
    required this.selectedOrder,
    required this.updating,
    required this.onRefresh,
    required this.onOnlineChanged,
    required this.onSelectOrder,
    required this.onDelivered,
    required this.onAvailableForNextOrders,
    required this.lastDeliveredOrder,
  });

  final RiderDriver driver;
  final bool loading;
  final bool online;
  final List<RiderOrder> orders;
  final RiderOrder? selectedOrder;
  final bool updating;
  final Future<void> Function() onRefresh;
  final ValueChanged<bool> onOnlineChanged;
  final ValueChanged<RiderOrder> onSelectOrder;
  final ValueChanged<RiderOrder> onDelivered;
  final Future<void> Function() onAvailableForNextOrders;
  final RiderOrder? lastDeliveredOrder;

  @override
  Widget build(BuildContext context) {
    final activeOrders =
        orders.where((order) => order.shouldShowInDelivery).toList();
    final selected = selectedOrder?.shouldShowInDelivery == true
        ? selectedOrder
        : activeOrders.isEmpty
            ? null
            : activeOrders.first;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _RiderHeader(
            driver: driver,
            online: online,
            orderCount: activeOrders.length,
            onOnlineChanged: onOnlineChanged,
            onRefresh: onRefresh,
          ),
          const SizedBox(height: 18),
          if (!online)
            const _InlineNotice(
              icon: Icons.pause_circle,
              text: 'You are offline. Go online to receive deliveries.',
            ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (activeOrders.isEmpty) ...[
            if (lastDeliveredOrder != null) ...[
              ActiveDeliveryPanel(
                order: lastDeliveredOrder!,
                updating: updating,
                onDelivered: () {},
                onBeAvailable: onAvailableForNextOrders,
              ),
            ] else ...[
              const _EmptyDeliveries(),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAvailableForNextOrders,
                icon: const Icon(Icons.person_pin_circle_outlined),
                label: const Text('Available for next orders'),
              ),
            ],
          ] else ...[
            Text(
              'Assigned orders',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            ...activeOrders.map(
              (order) => RiderOrderCard(
                order: order,
                selected: selected?.id == order.id,
                onTap: () => onSelectOrder(order),
              ),
            ),
            const SizedBox(height: 18),
            if (selected != null)
              ActiveDeliveryPanel(
                order: selected,
                updating: updating,
                onDelivered: () => onDelivered(selected),
                onBeAvailable: onAvailableForNextOrders,
              ),
          ],
        ],
      ),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({
    required this.stats,
    required this.orders,
    required this.activeOrders,
    required this.onRefresh,
  });

  final RiderActivityStats stats;
  final List<RiderOrder> orders;
  final List<RiderOrder> activeOrders;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final activeKeys = {
      for (final order in activeOrders) ...[
        if (order.id.trim().isNotEmpty) 'id:${order.id.trim()}',
        if (order.assignmentId.trim().isNotEmpty)
          'assignment:${order.assignmentId.trim()}',
        if (order.number.trim().isNotEmpty) 'number:${order.number.trim()}',
      ],
    };
    final activeFingerprints = {
      for (final order in activeOrders) ..._activityFingerprints(order),
    };
    bool isActiveOrder(RiderOrder order) {
      final keys = {
        if (order.id.trim().isNotEmpty) 'id:${order.id.trim()}',
        if (order.assignmentId.trim().isNotEmpty)
          'assignment:${order.assignmentId.trim()}',
        if (order.number.trim().isNotEmpty) 'number:${order.number.trim()}',
      };
      final fingerprints = _activityFingerprints(order);
      return keys.any(activeKeys.contains) ||
          fingerprints.any(activeFingerprints.contains);
    }

    final countedOrders = orders
        .where(
          (order) => order.countsTowardActivity && !isActiveOrder(order),
        )
        .toList();
    final visibleStats =
        RiderActivityStats.fromDeliveredOrders(countedOrders).mergedWith(stats);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text('Activity', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          _ActivityCard(
            icon: Icons.timer_outlined,
            label: 'Average delivery time',
            value: visibleStats.averageDeliveryTimeLabel,
          ),
          const SizedBox(height: 14),
          _ActivityCard(
            icon: Icons.delivery_dining,
            label: 'Deliveries today',
            value: '${visibleStats.deliveriesToday}',
          ),
          const SizedBox(height: 14),
          _ActivityCard(
            icon: Icons.payments,
            label: 'Total value',
            value: visibleStats.totalValueLabel,
          ),
          if (countedOrders.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Counted returns',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    ...countedOrders.map(
                      (order) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Order #${order.number} - ${order.activityStatusLabel}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Text(
                                  '\$${order.total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Time ${RiderActivityStats.deliveryTimeLabelFor(order)}  -  Value \$${order.total.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: .62),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Set<String> _activityFingerprints(RiderOrder order) {
    final number = _normalizeActivityText(order.number);
    final customer = _normalizeActivityText(order.customerName);
    final total = (order.total * 100).round();
    return {
      if (number.isNotEmpty) 'number:$number',
      if (number.isNotEmpty && total > 0) 'number-total:$number:$total',
      if (number.isNotEmpty && customer.isNotEmpty)
        'number-customer:$number:$customer',
    };
  }

  static String _normalizeActivityText(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.online,
    required this.backgroundTrackingEnabled,
    required this.posCheckedIn,
    required this.posCheckUpdating,
    required this.trackerStatus,
    required this.trackerChannel,
    required this.driver,
    required this.onOnlineChanged,
    required this.onBackgroundTrackingChanged,
    required this.onPosCheckedInChanged,
    required this.onLogout,
  });

  final bool online;
  final bool backgroundTrackingEnabled;
  final bool posCheckedIn;
  final bool posCheckUpdating;
  final String trackerStatus;
  final String trackerChannel;
  final RiderDriver driver;
  final ValueChanged<bool> onOnlineChanged;
  final ValueChanged<bool> onBackgroundTrackingChanged;
  final ValueChanged<bool> onPosCheckedInChanged;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.person,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${driver.name}\nDriver ID: ${driver.driverId}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: online,
            onChanged: onOnlineChanged,
            title: const Text('Online with RMS'),
            secondary: const Icon(Icons.radio_button_checked),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: backgroundTrackingEnabled,
            onChanged: onBackgroundTrackingChanged,
            title: const Text('Run in background'),
            subtitle: const Text('Keep tracking active after leaving the app.'),
            secondary: const Icon(Icons.sync_lock_outlined),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: posCheckedIn,
            onChanged: posCheckUpdating ? null : onPosCheckedInChanged,
            title: const Text('POS check-in'),
            subtitle: const Text('Enable this so POS can show your map icon.'),
            secondary: posCheckUpdating
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_searching),
            title: const Text('Tracker status'),
            subtitle: Text('$trackerStatus\n$trackerChannel'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.help_outline),
            title: const Text('Help'),
            subtitle: const Text('Contact dispatch or restaurant support.'),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Help request sent to dispatch.')),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: onLogout,
          ),
        ],
      );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );
}

class RiderPusherLocationClient {
  RiderPusherLocationClient({
    required this.baseUrl,
    required this.driver,
    this.onDriverStatusChange,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? createRmsHttpClient();

  // Previous Pusher details kept for future reference:
  // PUSHER_KEY = "4ad8906fa64132edd1c8"
  // PUSHER_CLUSTER = "ap2"
  // New Pusher details:
  // PUSHER_APP_ID = "2194095"
  // PUSHER_SECRET = "5d4f20a74b12501b14a2"
  static const _apiKey = String.fromEnvironment(
    'PUSHER_KEY',
    defaultValue: '3b1830ff63eb0e184a68',
  );
  static const _cluster = String.fromEnvironment(
    'PUSHER_CLUSTER',
    defaultValue: 'us2',
  );
  static const _fallbackClusters = <String>[
    _cluster,
    'mt1',
    'ap1',
    'ap3',
    'ap4',
    'eu',
    'us2',
    'sa1',
  ];

  final String baseUrl;
  final RiderDriver driver;
  final ValueChanged<Map<String, dynamic>>? onDriverStatusChange;
  final http.Client _httpClient;
  WebSocket? _socket;
  Future<void>? _connecting;
  final Set<String> _activeOrderIds = <String>{};
  final Set<String> _subscribedChannels = <String>{};
  double? _lastLatitude;
  double? _lastLongitude;
  int? _lastTimestamp;

  String get restaurantChannelName => _channelName;
  String get _channelName => 'private-restaurant-${driver.restaurantId}';
  String get _attendanceChannelName => 'attendance-${driver.restaurantId}';
  Set<String> get _channelNames => {
        _channelName,
        _attendanceChannelName,
        ..._activeOrderIds.map((id) => 'private-order-$id'),
      };

  void updateActiveOrderIds(Iterable<String> orderIds) {
    final next =
        orderIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    if (_activeOrderIds.length == next.length &&
        _activeOrderIds.containsAll(next)) {
      return;
    }
    _activeOrderIds
      ..clear()
      ..addAll(next);
    _resetConnection();
  }

  Future<void> publishLocation({
    required double latitude,
    required double longitude,
    required String phase,
    required Set<String> activeOrderIds,
  }) async {
    if (driver.restaurantId.trim().isEmpty) return;
    if (driver.id.trim().isEmpty) return;
    updateActiveOrderIds(activeOrderIds);
    await _ensureConnected();
    final now = DateTime.now().millisecondsSinceEpoch;
    final movement = _calculateMovement(latitude, longitude, now);
    final sanitizedActiveOrderIds = _activeOrderIds.toList(growable: false);
    _sendLocationPayload({
      'driverId': driver.id,
      'lat': latitude,
      'lng': longitude,
      'bearing': movement.bearing,
      'speed': movement.speed,
      'phase': phase,
      'status': phase == 'available' ? 'available' : 'on-delivery',
      'activeOrderIds': sanitizedActiveOrderIds,
      'activeOrders': sanitizedActiveOrderIds,
      'activeOrderCount': sanitizedActiveOrderIds.length,
      'orderCount': sanitizedActiveOrderIds.length,
      'timestamp': now,
    });
    _sendDriverStatePayload({
      'driverId': driver.id,
      'status': sanitizedActiveOrderIds.isEmpty ? 'available' : 'on-delivery',
      'activeOrderIds': sanitizedActiveOrderIds,
      'activeOrders': sanitizedActiveOrderIds,
      'activeOrderCount': sanitizedActiveOrderIds.length,
      'orderCount': sanitizedActiveOrderIds.length,
      'phase': phase,
      'timestamp': now,
    });
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    _lastTimestamp = now;
  }

  void _sendLocationPayload(Map<String, dynamic> payload) {
    for (final channelName in _channelNames) {
      if (!_subscribedChannels.contains(channelName)) continue;
      _send({
        'event': 'client-driver-location',
        'channel': channelName,
        'data': jsonEncode(payload),
      });
    }
  }

  void _sendDriverStatePayload(Map<String, dynamic> payload) {
    if (!_subscribedChannels.contains(_channelName)) return;
    _send({
      'event': 'client-driver-status-change',
      'channel': _channelName,
      'data': jsonEncode(payload),
    });
  }

  Future<void> startStatusListener() async {
    if (driver.restaurantId.trim().isEmpty) return;
    await _ensureConnected();
  }

  Future<void> _ensureConnected() async {
    final channels = _channelNames;
    if (_socket?.readyState == WebSocket.open &&
        _subscribedChannels.containsAll(channels)) {
      return;
    }
    _connecting ??= _connect();
    try {
      await _connecting;
    } finally {
      _connecting = null;
    }
  }

  Future<void> _connect() async {
    Exception? lastError;
    for (final cluster in _fallbackClusters.toSet()) {
      try {
        await _connectToCluster(cluster);
        return;
      } on Exception catch (error) {
        lastError = error;
        if (!_isWrongClusterError(error)) rethrow;
      }
    }
    throw lastError ?? Exception('Pusher connection failed.');
  }

  Future<void> _connectToCluster(String cluster) async {
    await _resetConnection();
    final socket = await WebSocket.connect(
      'wss://ws-$cluster.pusher.com/app/$_apiKey'
      '?protocol=7&client=js&version=8.4.0&flash=false',
    ).timeout(const Duration(seconds: 10));
    _socket = socket;

    final socketIdCompleter = Completer<String>();
    final subscriptionCompleters = {
      for (final channelName in _channelNames) channelName: Completer<void>(),
    };
    socket.listen(
      (message) => _handleMessage(
        message,
        socketIdCompleter: socketIdCompleter,
        subscriptionCompleters: subscriptionCompleters,
      ),
      onError: (_) => _resetConnection(),
      onDone: _resetConnection,
      cancelOnError: false,
    );

    final socketId = await socketIdCompleter.future.timeout(
      const Duration(seconds: 10),
    );
    for (final channelName in [_channelName, _attendanceChannelName]) {
      await _subscribeChannel(
        socketId: socketId,
        channelName: channelName,
        completer: subscriptionCompleters[channelName],
      );
    }
    for (final channelName in subscriptionCompleters.keys) {
      if (channelName == _channelName ||
          channelName == _attendanceChannelName) {
        continue;
      }
      try {
        await _subscribeChannel(
          socketId: socketId,
          channelName: channelName,
          completer: subscriptionCompleters[channelName],
        );
      } catch (_) {
        // Order tracking channels are useful for customer maps, but restaurant
        // tracking must continue even if one order channel cannot auth.
      }
    }
  }

  bool _isWrongClusterError(Exception error) {
    final message = error.toString().toLowerCase();
    return message.contains('code: 4001') ||
        message.contains('not in this cluster');
  }

  Future<void> _subscribeChannel({
    required String socketId,
    required String channelName,
    required Completer<void>? completer,
  }) async {
    if (completer == null) return;
    final data = <String, dynamic>{
      'channel': channelName,
    };
    if (channelName.startsWith('private-')) {
      final auth = await _authorize(socketId, channelName);
      data['auth'] = auth['auth'];
      if (auth['channel_data'] != null) {
        data['channel_data'] = auth['channel_data'];
      }
    }
    _send({
      'event': 'pusher:subscribe',
      'data': data,
    });
    await completer.future.timeout(const Duration(seconds: 10));
  }

  Future<Map<String, dynamic>> _authorize(
    String socketId,
    String channelName,
  ) async {
    final body = {
      'socket_id': socketId,
      'channel_name': channelName,
    };
    http.Response? lastResponse;
    for (final path in const ['/api/delivery/auth', '/api/pusher/auth']) {
      final response = await _httpClient
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              if (driver.token.trim().isNotEmpty)
                'Authorization': 'Bearer ${driver.token.trim()}',
              if (driver.restaurantId.trim().isNotEmpty)
                'X-Branch-Id': driver.restaurantId.trim(),
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));
      lastResponse = response;
      if (response.statusCode == 404 || response.statusCode == 405) continue;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        break;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        if (decoded['auth'] is String) return decoded;
        if (data is Map<String, dynamic> && data['auth'] is String) {
          return data;
        }
      }
    }
    if (lastResponse != null &&
        (lastResponse.statusCode < 200 || lastResponse.statusCode >= 300)) {
      throw Exception('Pusher auth failed with ${lastResponse.statusCode}.');
    }
    throw Exception('Pusher auth response was invalid.');
  }

  Future<void> _handleMessage(
    dynamic message, {
    required Completer<String> socketIdCompleter,
    required Map<String, Completer<void>> subscriptionCompleters,
  }) async {
    if (message is! String) return;
    final decoded = jsonDecode(message);
    if (decoded is! Map<String, dynamic>) return;
    final event = decoded['event'];
    if (event == 'pusher:connection_established') {
      final data = _decodePusherData(decoded['data']);
      final socketId = data['socket_id'];
      if (socketId is String && !socketIdCompleter.isCompleted) {
        socketIdCompleter.complete(socketId);
      }
    } else if (event == 'pusher:ping') {
      _send({'event': 'pusher:pong', 'data': {}});
    } else if (event == 'pusher_internal:subscription_succeeded' &&
        decoded['channel'] is String) {
      final channelName = decoded['channel'] as String;
      _subscribedChannels.add(channelName);
      final completer = subscriptionCompleters[channelName];
      if (completer != null && !completer.isCompleted) completer.complete();
    } else if (event == 'driver-status-change' ||
        event == 'attendance-updated') {
      onDriverStatusChange?.call(_decodePusherData(decoded['data']));
    } else if (event == 'pusher:error') {
      final details = _decodePusherData(decoded['data']);
      final message =
          details.isEmpty ? '${decoded['data'] ?? decoded}' : '$details';
      if (!socketIdCompleter.isCompleted) {
        socketIdCompleter
            .completeError(Exception('Pusher connection failed: $message'));
      }
      for (final completer in subscriptionCompleters.values) {
        if (!completer.isCompleted) {
          completer
              .completeError(Exception('Pusher subscribe failed: $message'));
        }
      }
    }
  }

  Map<String, dynamic> _decodePusherData(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return const {};
  }

  _RiderMovement _calculateMovement(
    double latitude,
    double longitude,
    int timestamp,
  ) {
    final previousLatitude = _lastLatitude;
    final previousLongitude = _lastLongitude;
    final previousTimestamp = _lastTimestamp;
    if (previousLatitude == null ||
        previousLongitude == null ||
        previousTimestamp == null) {
      return const _RiderMovement(bearing: 0, speed: 0);
    }
    final elapsedSeconds = (timestamp - previousTimestamp) / 1000;
    if (elapsedSeconds <= 0) return const _RiderMovement(bearing: 0, speed: 0);
    final distance = _distanceMeters(
      previousLatitude,
      previousLongitude,
      latitude,
      longitude,
    );
    return _RiderMovement(
      bearing: _bearingDegrees(
        previousLatitude,
        previousLongitude,
        latitude,
        longitude,
      ),
      speed: (distance / elapsedSeconds) * 3.6,
    );
  }

  double _distanceMeters(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    const earthRadiusMeters = 6371000;
    final dLat = _degreesToRadians(toLatitude - fromLatitude);
    final dLng = _degreesToRadians(toLongitude - fromLongitude);
    final lat1 = _degreesToRadians(fromLatitude);
    final lat2 = _degreesToRadians(toLatitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _bearingDegrees(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    final lat1 = _degreesToRadians(fromLatitude);
    final lat2 = _degreesToRadians(toLatitude);
    final dLng = _degreesToRadians(toLongitude - fromLongitude);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double _degreesToRadians(double degrees) => degrees * math.pi / 180;

  void _send(Map<String, dynamic> event) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw Exception('Pusher is not connected.');
    }
    socket.add(jsonEncode(event));
  }

  Future<void> _resetConnection() async {
    _subscribedChannels.clear();
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }

  Future<void> dispose() async {
    await _resetConnection();
  }
}

class RiderBackgroundTracker {
  RiderBackgroundTracker({
    MethodChannel? channel,
    http.Client? httpClient,
  })  : _channel = channel ??
            const MethodChannel('com.example.pizza_hut/background_tracking'),
        _httpClient = httpClient ?? createRmsHttpClient();

  final MethodChannel _channel;
  final http.Client _httpClient;
  RiderPusherLocationClient? _pusher;

  Future<void> run() async {
    while (true) {
      var nextDelay = const Duration(seconds: 70);
      try {
        nextDelay = _backgroundBroadcastIntervalFor(await _tick());
      } catch (_) {}
      await Future<void>.delayed(nextDelay);
    }
  }

  Duration _backgroundBroadcastIntervalFor(String phase) {
    return phase == 'en-route'
        ? const Duration(seconds: 6)
        : const Duration(seconds: 70);
  }

  Future<String> _tick() async {
    final session = await _loadSession();
    if (session == null) {
      await _pusher?.dispose();
      _pusher = null;
      return 'available';
    }
    final apiClient = RiderApiClient(
      httpClient: _httpClient,
      baseUrl: session.baseUrl,
    );
    final orders = await apiClient.fetchDriverAssignments(session.driver);
    final activeOrders =
        orders.where((order) => order.shouldShowInDelivery).toList();
    final activeOrderIds = activeOrders
        .map((order) => order.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    final location = await _requestLocation();
    final pusher = _pusher ??= RiderPusherLocationClient(
      baseUrl: apiClient.baseUrl,
      driver: session.driver,
    );
    pusher.updateActiveOrderIds(activeOrderIds);
    final phase = activeOrderIds.isEmpty ? 'available' : 'en-route';
    await pusher.publishLocation(
      latitude: location.latitude,
      longitude: location.longitude,
      phase: phase,
      activeOrderIds: activeOrderIds,
    );
    await apiClient.tryUpdateDriverLocation(
      session.driver,
      latitude: location.latitude,
      longitude: location.longitude,
    );
    return phase;
  }

  Future<_RiderBackgroundSession?> _loadSession() async {
    final config = await _channel.invokeMapMethod<String, dynamic>('getConfig');
    final baseUrl = '${config?['baseUrl'] ?? ''}'.trim();
    final driverJson = config?['driver'];
    if (baseUrl.isEmpty || driverJson is! Map) return null;
    final driver = RiderDriver.fromJson(
      Map<String, dynamic>.from(driverJson),
    );
    if (driver.id.trim().isEmpty || driver.token.trim().isEmpty) return null;
    return _RiderBackgroundSession(baseUrl: baseUrl, driver: driver);
  }

  Future<RiderLocationFix> _requestLocation() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getCurrentLocation',
    );
    final latitude = result?['latitude'];
    final longitude = result?['longitude'];
    if (latitude is num && longitude is num) {
      return RiderLocationFix(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      );
    }
    throw Exception('Could not read rider location.');
  }
}

class _RiderBackgroundSession {
  const _RiderBackgroundSession({
    required this.baseUrl,
    required this.driver,
  });

  final String baseUrl;
  final RiderDriver driver;
}

class _RiderMovement {
  const _RiderMovement({required this.bearing, required this.speed});

  final double bearing;
  final double speed;
}

class RiderApiClient {
  RiderApiClient({http.Client? httpClient, String? baseUrl})
      : _httpClient = httpClient ?? createRmsHttpClient(),
        baseUrl = _normalizeBaseUrl(
          baseUrl ??
              const String.fromEnvironment(
                'RMS_API_BASE_URL',
                defaultValue: 'https://rms-backend-v1.vercel.app',
              ),
        );

  final http.Client _httpClient;
  final String baseUrl;

  RiderApiClient withBaseUrl(String nextBaseUrl) {
    final normalized = _normalizeBaseUrl(nextBaseUrl);
    if (normalized.isEmpty || normalized == baseUrl) return this;
    return RiderApiClient(httpClient: _httpClient, baseUrl: normalized);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Map<String, String> _jsonHeaders([String? token]) => {
        'Content-Type': 'application/json',
        if (token != null && token.trim().isNotEmpty)
          'Authorization': 'Bearer ${token.trim()}',
      };

  Future<RiderDriver> loginDriver({
    required String driverId,
    required String password,
    required String branchId,
  }) async {
    final response = await _httpClient
        .post(
          _uri('/api/delivery/driver/login'),
          headers: _jsonHeaders(),
          body: jsonEncode({
            'driverId': driverId,
            'password': password,
            'branchId': branchId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(response);
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('RMS did not return driver profile.');
    }
    return RiderDriver.fromJson(data);
  }

  Future<bool> isDriverLoginBlockedByPosCheckout(RiderDriver driver) async {
    final driverCode = driver.driverId.trim();
    final password = driver.password.trim();
    final branchId = driver.restaurantId.trim();
    if (driverCode.isEmpty || password.isEmpty || branchId.isEmpty) {
      return false;
    }
    try {
      await loginDriver(
        driverId: driverCode,
        password: password,
        branchId: branchId,
      );
      return false;
    } on RmsApiException catch (error) {
      final code = error.code.toUpperCase();
      final message = error.message.toLowerCase();
      if (code == 'CHECK_IN_REQUIRED' ||
          message.contains('check-in first') ||
          message.contains('checked out')) {
        return true;
      }
      rethrow;
    }
  }

  Future<RiderBranch> verifyStoreQr(String qrToken) async {
    final qrApiUrl = RiderBranch.peekApiUrl(qrToken);
    final verifier = qrApiUrl == null ? this : withBaseUrl(qrApiUrl);
    final response = await _httpClient
        .post(
          verifier._uri('/api/delivery/driver/verify-qr'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'qrToken': qrToken}),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(response);
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('RMS did not return restaurant details.');
    }
    final branch = RiderBranch.fromJson(data);
    if (branch.id.isEmpty) {
      throw Exception('RMS did not return restaurant details.');
    }
    return branch;
  }

  Future<RiderDriver> updateDriverStatus(
    RiderDriver driver,
    String status,
  ) async {
    final response = await _httpClient
        .patch(
          _uri('/api/delivery/driver/${driver.id}/status'),
          headers: _jsonHeaders(driver.token),
          body: jsonEncode({'status': status}),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(response);
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('RMS did not return driver profile.');
    }
    return RiderDriver.fromJson(data)
        .withToken(driver.token)
        .withRestaurantId(driver.restaurantId)
        .withPassword(driver.password);
  }

  Future<RiderDriver> fetchDriverProfile(RiderDriver driver) async {
    final response = await _httpClient
        .get(
          _uri('/api/delivery/driver/${driver.id}'),
          headers: _jsonHeaders(driver.token),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(response);
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('RMS did not return driver profile.');
    }
    return RiderDriver.fromJson(data)
        .withToken(driver.token)
        .withRestaurantId(driver.restaurantId)
        .withPassword(driver.password);
  }

  Future<void> updateDriverLocation(
    RiderDriver driver, {
    required double latitude,
    required double longitude,
  }) async {
    final response = await _httpClient
        // iOS app-side call: POST /api/delivery/driver/{driverId}/location sends rider GPS updates.
        .post(
          _uri('/api/delivery/driver/${driver.id}/location'),
          headers: _jsonHeaders(driver.token),
          body: jsonEncode({
            'lat': latitude,
            'lng': longitude,
            'phase': 'available',
          }),
        )
        .timeout(const Duration(seconds: 8));
    _decode(response);
  }

  Future<void> tryUpdateDriverLocation(
    RiderDriver driver, {
    required double latitude,
    required double longitude,
  }) async {
    try {
      await updateDriverLocation(
        driver,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (error) {
      final message = '$error';
      if (message.contains('/api/delivery/driver/${driver.id}/location') &&
          message.contains('returned 404')) {
        return;
      }
      rethrow;
    }
  }

  Future<void> checkInDriverAtPos(
    RiderDriver driver, {
    required String branchId,
  }) async {
    final employeeId = await _resolveDriverEmployeeId(driver, branchId);
    await _postAttendanceAction(
      driver,
      branchId: branchId,
      employeeId: employeeId,
      action: 'check-in',
    );
  }

  Future<void> checkOutDriverAtPos(
    RiderDriver driver, {
    required String branchId,
  }) async {
    final employeeId = await _resolveDriverEmployeeId(driver, branchId);
    await _postAttendanceAction(
      driver,
      branchId: branchId,
      employeeId: employeeId,
      action: 'check-out',
    );
  }

  Future<bool> isDriverCheckedInAtPos(RiderDriver driver) async {
    final branchId = driver.restaurantId.trim();
    final driverCodes = {
      driver.driverId.trim().toUpperCase(),
      driver.id.trim().toUpperCase(),
    }..removeWhere((id) => id.isEmpty);
    if (branchId.isEmpty || driverCodes.isEmpty) return false;

    final response = await _getFirstAvailable([
      _uri('/api/attendance', {'branchId': branchId}),
      _uri('/api/employee/attendance', {'branchId': branchId}),
    ], driver.token);
    final body = _decode(response);
    final data = body['data'];
    final records = _attendanceRecordsFromData(data);
    for (final record in records.whereType<Map<String, dynamic>>()) {
      final employeeId = record['employeeId'];
      final employee = record['employee'];
      final employeeCodes = <String>{
        if (employeeId is Map) ...[
          '${employeeId['employeeId'] ?? ''}',
          '${employeeId['_id'] ?? ''}',
          '${employeeId['id'] ?? ''}',
        ] else
          '${employeeId ?? ''}',
        if (employee is Map) ...[
          '${employee['employeeId'] ?? ''}',
          '${employee['_id'] ?? ''}',
          '${employee['id'] ?? ''}',
        ],
      }.map((id) => id.trim().toUpperCase()).where((id) => id.isNotEmpty);
      if (!employeeCodes.any(driverCodes.contains)) continue;
      final status = '${record['status'] ?? ''}'.trim().toLowerCase();
      return status == 'checked-in' || status == 'on-break';
    }
    return false;
  }

  List<dynamic> _attendanceRecordsFromData(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final records = data['records'];
      if (records is List) return records;
      final attendances = data['attendances'];
      if (attendances is List) return attendances;
      final attendance = data['attendance'];
      if (attendance is List) return attendance;
    }
    return const [];
  }

  Future<void> _postAttendanceAction(
    RiderDriver driver, {
    required String branchId,
    required String employeeId,
    required String action,
  }) async {
    final paths = [
      '/api/attendance/$action',
      '/api/employee/attendance/$action',
    ];
    for (final path in paths) {
      try {
        final response = await _httpClient
            .post(
              _uri(path),
              headers: _jsonHeaders(driver.token),
              body: jsonEncode({
                'branchId': branchId,
                'employeeId': employeeId,
              }),
            )
            .timeout(const Duration(seconds: 15));
        _decode(response);
        return;
      } on RmsApiException catch (error) {
        if (action == 'check-in' &&
            error.message.toLowerCase().contains('already checked in')) {
          return;
        }
        if (error.code == 'ROUTE_UNAVAILABLE' && path != paths.last) {
          continue;
        }
        if (error.code != 'ROUTE_UNAVAILABLE') {
          rethrow;
        }
      }
    }
    throw Exception('RMS attendance route is not available.');
  }

  Future<String> _resolveDriverEmployeeId(
    RiderDriver driver,
    String branchId,
  ) async {
    final search = driver.driverId.trim();
    if (search.isEmpty) {
      throw Exception('Driver employee code is missing.');
    }
    final response = await _getFirstAvailable([
      _uri('/api/employees', {
        'branchId': branchId,
        'search': search,
        'isActive': 'true',
      }),
      _uri('/api/employee/employees', {
        'branchId': branchId,
        'search': search,
        'isActive': 'true',
      }),
    ], driver.token);
    final body = _decode(response);
    final data = body['data'];
    final Iterable<Map<String, dynamic>> employees =
        data is List ? data.whereType<Map<String, dynamic>>() : const [];
    for (final employee in employees) {
      if ('${employee['employeeId'] ?? ''}'.trim().toUpperCase() ==
          search.toUpperCase()) {
        final id = '${employee['_id'] ?? employee['id'] ?? ''}'.trim();
        if (id.isNotEmpty) return id;
      }
    }
    throw Exception('POS employee record was not found for driver $search.');
  }

  Future<http.Response> _getFirstAvailable(
    List<Uri> uris,
    String token,
  ) async {
    RmsApiException? lastRouteError;
    for (final uri in uris) {
      final response = await _httpClient
          .get(uri, headers: _jsonHeaders(token))
          .timeout(const Duration(seconds: 15));
      try {
        _decode(response);
        return response;
      } on RmsApiException catch (error) {
        if (error.code == 'ROUTE_UNAVAILABLE') {
          lastRouteError = error;
          continue;
        }
        rethrow;
      }
    }
    throw lastRouteError ?? Exception('RMS backend route is not available.');
  }

  Future<List<RiderOrder>> fetchDriverAssignments(RiderDriver driver) async {
    // iOS app-side call: GET /driver/:id/assignments fetches this rider's assignments.
    final response = await _httpClient
        .get(
          _uri('/api/delivery/driver/${driver.id}/assignments'),
          headers: _jsonHeaders(driver.token),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(response);
    final data = body['data'];
    final orders = data is List
        ? data
            .whereType<Map<String, dynamic>>()
            .map(RiderOrder.fromAssignmentJson)
            .toList()
        : const <RiderOrder>[];
    return orders;
  }

  Future<RiderActivityReport> fetchDriverActivity(RiderDriver driver) async {
    try {
      final response = await _httpClient.get(
        _uri('/api/delivery/driver-drop/summary', {
          'branchId': driver.restaurantId,
          'restaurantId': driver.restaurantId,
          'driverId': driver.id,
          'date': _todayDateString(),
        }),
        headers: {
          'Content-Type': 'application/json',
          'X-Branch-Id': driver.restaurantId,
        },
      ).timeout(const Duration(seconds: 15));
      final body = _decode(response);
      final data = body['data'];
      if (data is Map<String, dynamic>) {
        final orders = data['orders'] is List
            ? (data['orders'] as List)
                .whereType<Map<String, dynamic>>()
                .map(RiderOrder.fromActivityJson)
                .where((order) => order.countsTowardActivity)
                .toList()
            : const <RiderOrder>[];
        if (orders.isNotEmpty) {
          return RiderActivityReport(
            stats: RiderActivityStats.fromDeliveredOrders(orders),
            orders: orders,
          );
        }
      }
    } catch (_) {
      // Older backends may not expose driver-drop summary to the APK.
    }

    final response = await _httpClient
        .get(
          _uri('/api/delivery/driver/${driver.id}/activity'),
          headers: _jsonHeaders(driver.token),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(response);
    final data = body['data'];
    if (data is! Map<String, dynamic>) return const RiderActivityReport.empty();
    final orders = data['orders'] is List
        ? (data['orders'] as List)
            .whereType<Map<String, dynamic>>()
            .map(RiderOrder.fromActivityJson)
            .where((order) => order.countsTowardActivity)
            .toList()
        : const <RiderOrder>[];

    return RiderActivityReport(
      stats: RiderActivityStats(
        deliveriesToday: (data['deliveriesToday'] as num?)?.toInt() ?? 0,
        totalValue: (data['totalValue'] as num?)?.toDouble() ?? 0,
        averageDeliveryTime: Duration(
          seconds: (data['averageDeliverySeconds'] as num?)?.toInt() ?? 0,
        ),
      ),
      orders: orders,
    );
  }

  String _todayDateString() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  Future<void> completeDriverAssignment(
    String assignmentId, {
    required RiderDriver driver,
  }) async {
    final resolvedAssignmentId = assignmentId.trim();
    if (resolvedAssignmentId.isEmpty) {
      throw Exception('Delivery assignment was not returned by RMS.');
    }
    final response = await _httpClient
        .patch(
          _uri('/api/delivery/driver/complete/$resolvedAssignmentId'),
          headers: _jsonHeaders(driver.token),
        )
        .timeout(const Duration(seconds: 15));
    _decode(response);
  }

  Future<void> updateOrderStatus(
    String orderId,
    String status, {
    required RiderDriver driver,
    String? assignmentId,
  }) async {
    if (status != 'completed' && status != 'delivered') return;
    final resolvedAssignmentId =
        assignmentId == null || assignmentId.trim().isEmpty
            ? orderId
            : assignmentId.trim();
    if (resolvedAssignmentId.isEmpty) {
      throw Exception('Delivery assignment was not returned by RMS.');
    }
    final response = await _httpClient
        .patch(
          _uri('/api/delivery/driver/deliver/$resolvedAssignmentId'),
          headers: _jsonHeaders(driver.token),
        )
        .timeout(const Duration(seconds: 15));
    _decode(response);
  }

  static String _normalizeBaseUrl(String value) {
    var text = value.trim();
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    return text.endsWith('/api') ? text.substring(0, text.length - 4) : text;
  }

  Map<String, dynamic> _decode(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    if (response.body.trimLeft().startsWith('<') ||
        (contentType.isNotEmpty && !contentType.contains('json'))) {
      throw RmsApiException(
        code: 'ROUTE_UNAVAILABLE',
        message: 'RMS backend route is not available: '
            '${response.request?.method ?? 'REQUEST'} ${response.request?.url ?? ''} '
            'returned ${response.statusCode} ${contentType.isEmpty ? 'unknown content' : contentType}.',
      );
    }
    final decoded =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final body =
        decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] == false) {
      throw RmsApiException(
        code: '${body['code'] ?? response.statusCode}',
        message: '${body['message'] ?? 'RMS request failed'}',
      );
    }
    return body;
  }
}

class RmsApiException implements Exception {
  const RmsApiException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => message;
}

class RiderBranch {
  const RiderBranch({
    required this.id,
    required this.name,
    required this.code,
    this.apiUrl,
  });

  factory RiderBranch.fromJson(Map<String, dynamic> json) => RiderBranch(
        id: '${json['branchId'] ?? json['restaurantId'] ?? json['_id'] ?? json['id'] ?? ''}'
            .trim(),
        name:
            '${json['branchName'] ?? json['restaurantName'] ?? json['name'] ?? ''}'
                .trim(),
        code: '${json['branchCode'] ?? json['code'] ?? ''}'.trim(),
        apiUrl: _normalizeApiUrl('${json['apiUrl'] ?? json['baseUrl'] ?? ''}'),
      );

  Map<String, dynamic> toJson() => {
        'branchId': id,
        'branchName': name,
        'branchCode': code,
        if (apiUrl != null && apiUrl!.isNotEmpty) 'apiUrl': apiUrl,
      };

  static RiderBranch? tryParse(String rawValue) {
    for (final text in _qrCandidates(rawValue)) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          final branch = RiderBranch.fromJson(decoded);
          if (branch.id.isNotEmpty) return branch;
        }
      } catch (_) {
        final branch = _tryParseBranchUri(text);
        if (branch != null) return branch;
      }
    }
    return null;
  }

  static RiderBranch? tryParseAny(String rawValue) =>
      tryParse(rawValue) ?? tryParseSignedQr(rawValue);

  static RiderBranch? tryParseSignedQr(String rawValue) {
    for (final text in _qrCandidates(rawValue)) {
      final payload = _tryDecodeSignedQrPayload(text);
      if (payload == null) continue;
      final branch = RiderBranch.fromJson(payload);
      if (branch.id.isNotEmpty) return branch;
    }
    return null;
  }

  static String? peekApiUrl(String rawValue) {
    final parsed = tryParseAny(rawValue);
    if (parsed?.apiUrl != null && parsed!.apiUrl!.trim().isNotEmpty) {
      return parsed.apiUrl;
    }
    for (final text in _qrCandidates(rawValue)) {
      final apiUrl = _normalizeApiUrl(
        _tryDecodeSignedQrPayload(text)?['apiUrl']?.toString() ?? '',
      );
      if (apiUrl != null && apiUrl.isNotEmpty) return apiUrl;
    }
    return null;
  }

  static RiderBranch? _tryParseBranchUri(String text) {
    final uri = Uri.tryParse(text);
    final branchId = uri?.queryParameters['branchId'] ??
        uri?.queryParameters['restaurantId'];
    if (branchId == null || branchId.trim().isEmpty) return null;
    return RiderBranch(
      id: branchId.trim(),
      name: (uri?.queryParameters['branchName'] ??
                  uri?.queryParameters['restaurantName'])
              ?.trim() ??
          '',
      code: uri?.queryParameters['branchCode']?.trim() ?? '',
      apiUrl: _normalizeApiUrl(uri?.queryParameters['apiUrl'] ?? ''),
    );
  }

  static List<String> _qrCandidates(String rawValue) {
    final seen = <String>{};
    final queue = <String>[rawValue];
    final candidates = <String>[];
    while (queue.isNotEmpty && candidates.length < 24) {
      final current = _cleanQrText(queue.removeAt(0));
      if (current.isEmpty || !seen.add(current)) continue;
      candidates.add(current);

      try {
        final decoded = Uri.decodeComponent(current);
        if (decoded != current) queue.add(decoded);
      } catch (_) {}

      try {
        final decodedJson = jsonDecode(current);
        if (decodedJson is Map<String, dynamic>) {
          for (final key in const [
            'data',
            'qr',
            'qrToken',
            'qrCodePayload',
            'token',
            'payload',
            'code',
          ]) {
            final value = decodedJson[key];
            if (value is String && value.trim().isNotEmpty) queue.add(value);
          }
        }
      } catch (_) {}

      final uri = Uri.tryParse(current);
      if (uri != null) {
        for (final key in const [
          'data',
          'qr',
          'qrToken',
          'token',
          'payload',
          'code',
        ]) {
          final value = uri.queryParameters[key];
          if (value != null && value.trim().isNotEmpty) queue.add(value);
        }
      }
    }
    return candidates;
  }

  static String _cleanQrText(String value) {
    var text = value.trim().replaceAll(RegExp(r'[\r\n]+'), '');
    text = text.replaceAll(RegExp(r'''^["']|["']$'''), '');
    return text.trim();
  }

  static Map<String, dynamic>? _tryDecodeSignedQrPayload(String text) {
    final clean = _cleanQrText(text);
    final parts = clean.split('.');
    if (parts.length != 2 || parts.first.isEmpty) return null;
    try {
      final normalized = base64Url.normalize(parts.first);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(decoded);
      return payload is Map<String, dynamic> ? payload : null;
    } catch (_) {
      try {
        final normalized = base64.normalize(parts.first);
        final decoded = utf8.decode(base64.decode(normalized));
        final payload = jsonDecode(decoded);
        return payload is Map<String, dynamic> ? payload : null;
      } catch (_) {
        return null;
      }
    }
  }

  static String? _normalizeApiUrl(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri != null && (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
      final emulatorUri = uri.replace(host: '10.0.2.2');
      final emulatorText = emulatorUri.toString();
      return emulatorText.endsWith('/api')
          ? emulatorText.substring(0, emulatorText.length - 4)
          : emulatorText;
    }
    return text.endsWith('/api') ? text.substring(0, text.length - 4) : text;
  }

  String get label {
    final parts = [name, code.isEmpty ? '' : '($code)']
        .where((part) => part.trim().isNotEmpty)
        .join(' ');
    return parts.isEmpty ? 'Selected restaurant' : parts;
  }

  final String id;
  final String name;
  final String code;
  final String? apiUrl;
}

class RiderLocationFix {
  const RiderLocationFix({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class RiderDriver {
  const RiderDriver({
    required this.id,
    required this.driverId,
    required this.name,
    required this.phone,
    required this.color,
    required this.status,
    required this.restaurantId,
    required this.token,
    this.password = '',
    this.posCheckedIn = true,
    this.vehicleLabel = '',
  });

  factory RiderDriver.fromJson(Map<String, dynamic> json) {
    final vehicle = json['assignedVehicle'];
    String vehicleLabel = '';
    if (vehicle is Map<String, dynamic>) {
      final number = '${vehicle['number'] ?? ''}';
      final label = '${vehicle['label'] ?? ''}';
      vehicleLabel = [label, number.isEmpty ? '' : '#$number']
          .where((part) => part.isNotEmpty)
          .join(' ');
    }
    return RiderDriver(
      id: '${json['_id'] ?? json['id'] ?? ''}',
      driverId: '${json['driverId'] ?? ''}',
      name: '${json['name'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      color: '${json['color'] ?? '#3B82F6'}',
      status: '${json['status'] ?? 'offline'}',
      restaurantId:
          '${json['restaurantId'] ?? json['branchId'] ?? json['branch'] ?? ''}',
      token: '${json['token'] ?? ''}',
      password: '${json['password'] ?? ''}',
      posCheckedIn: json['posCheckedIn'] != false,
      vehicleLabel: vehicleLabel,
    );
  }

  RiderDriver withRestaurantId(String restaurantId) => RiderDriver(
        id: id,
        driverId: driverId,
        name: name,
        phone: phone,
        color: color,
        status: status,
        restaurantId: effectiveRestaurantId(restaurantId),
        token: token,
        password: password,
        posCheckedIn: posCheckedIn,
        vehicleLabel: vehicleLabel,
      );

  String effectiveRestaurantId(String fallbackRestaurantId) {
    final current = restaurantId.trim();
    if (current.isNotEmpty && current.toLowerCase() != 'default') {
      return current;
    }
    final fallback = fallbackRestaurantId.trim();
    return fallback.isEmpty ? current : fallback;
  }

  RiderDriver withToken(String token) => RiderDriver(
        id: id,
        driverId: driverId,
        name: name,
        phone: phone,
        color: color,
        status: status,
        restaurantId: restaurantId,
        token: token,
        password: password,
        posCheckedIn: posCheckedIn,
        vehicleLabel: vehicleLabel,
      );

  RiderDriver withPassword(String password) => RiderDriver(
        id: id,
        driverId: driverId,
        name: name,
        phone: phone,
        color: color,
        status: status,
        restaurantId: restaurantId,
        token: token,
        password: password,
        posCheckedIn: posCheckedIn,
        vehicleLabel: vehicleLabel,
      );

  Map<String, dynamic> toJson() => {
        '_id': id,
        'id': id,
        'driverId': driverId,
        'name': name,
        'phone': phone,
        'color': color,
        'status': status,
        'restaurantId': restaurantId,
        'token': token,
        'password': password,
        'posCheckedIn': posCheckedIn,
        if (vehicleLabel.trim().isNotEmpty)
          'assignedVehicle': {'label': vehicleLabel},
      };

  final String id;
  final String driverId;
  final String name;
  final String phone;
  final String color;
  final String status;
  final String restaurantId;
  final String token;
  final String password;
  final bool posCheckedIn;
  final String vehicleLabel;
}

class RiderActivityReport {
  const RiderActivityReport({
    required this.stats,
    required this.orders,
  });

  const RiderActivityReport.empty()
      : stats = const RiderActivityStats.empty(),
        orders = const <RiderOrder>[];

  factory RiderActivityReport.fromOrders(List<RiderOrder> orders) =>
      RiderActivityReport(
        stats: RiderActivityStats.fromDeliveredOrders(orders),
        orders: orders.where((order) => order.countsTowardActivity).toList(),
      );

  final RiderActivityStats stats;
  final List<RiderOrder> orders;
}

class RiderActivityStats {
  const RiderActivityStats({
    required this.deliveriesToday,
    required this.totalValue,
    required this.averageDeliveryTime,
  });

  const RiderActivityStats.empty()
      : deliveriesToday = 0,
        totalValue = 0,
        averageDeliveryTime = Duration.zero;

  final int deliveriesToday;
  final double totalValue;
  final Duration averageDeliveryTime;

  factory RiderActivityStats.fromDeliveredOrders(List<RiderOrder> orders) {
    final deliveredOrders =
        orders.where((order) => order.countsTowardActivity).toList();
    return RiderActivityStats(
      deliveriesToday: deliveredOrders.length,
      totalValue:
          deliveredOrders.fold<double>(0, (sum, order) => sum + order.total),
      averageDeliveryTime:
          RiderActivityStats.averageDeliveryTimeFor(deliveredOrders),
    );
  }

  RiderActivityStats mergedWith(RiderActivityStats other) {
    return RiderActivityStats(
      deliveriesToday: deliveriesToday > other.deliveriesToday
          ? deliveriesToday
          : other.deliveriesToday,
      totalValue: totalValue > other.totalValue ? totalValue : other.totalValue,
      averageDeliveryTime: averageDeliveryTime == Duration.zero
          ? other.averageDeliveryTime
          : averageDeliveryTime,
    );
  }

  RiderActivityStats addOrder(RiderOrder order) {
    final nextDeliveriesToday = deliveriesToday + 1;
    final orderDeliveryTime =
        RiderActivityStats.averageDeliveryTimeFor([order]);
    final nextAverageDeliveryTime = orderDeliveryTime == Duration.zero
        ? averageDeliveryTime
        : averageDeliveryTime == Duration.zero
            ? orderDeliveryTime
            : Duration(
                seconds: (((averageDeliveryTime.inSeconds * deliveriesToday) +
                            orderDeliveryTime.inSeconds) /
                        nextDeliveriesToday)
                    .round(),
              );
    return RiderActivityStats(
      deliveriesToday: nextDeliveriesToday,
      totalValue: totalValue + order.total,
      averageDeliveryTime: nextAverageDeliveryTime,
    );
  }

  static Duration averageDeliveryTimeFor(List<RiderOrder> orders) {
    final deliveryTimes = orders
        .map((order) {
          final backendDuration = order.deliveryDuration;
          if (backendDuration != null && backendDuration > Duration.zero) {
            return backendDuration;
          }
          final finishedAt = order.deliveredAt ?? DateTime.now();
          if (!finishedAt.isAfter(order.createdAt)) return Duration.zero;
          return finishedAt.difference(order.createdAt);
        })
        .where((duration) => duration > Duration.zero)
        .toList();
    if (deliveryTimes.isEmpty) return Duration.zero;

    final totalSeconds = deliveryTimes.fold<int>(
      0,
      (sum, duration) => sum + duration.inSeconds,
    );
    return Duration(seconds: totalSeconds ~/ deliveryTimes.length);
  }

  static String deliveryTimeLabelFor(RiderOrder order) {
    final finishedAt = order.deliveredAt ?? DateTime.now();
    final backendDuration = order.deliveryDuration;
    if (backendDuration != null && backendDuration > Duration.zero) {
      return _durationLabel(backendDuration);
    }
    if (!finishedAt.isAfter(order.createdAt)) return '--';
    return _durationLabel(finishedAt.difference(order.createdAt));
  }

  static bool isDeliveredToday(RiderOrder order) {
    final deliveredAt = order.deliveredAt;
    if (deliveredAt == null) return false;
    final now = DateTime.now();
    final localDeliveredAt = deliveredAt.toLocal();
    return localDeliveredAt.year == now.year &&
        localDeliveredAt.month == now.month &&
        localDeliveredAt.day == now.day;
  }

  String get totalValueLabel => '\$${totalValue.toStringAsFixed(2)}';

  String get averageDeliveryTimeLabel {
    if (averageDeliveryTime == Duration.zero) return '--';
    return _durationLabel(averageDeliveryTime);
  }

  static String _durationLabel(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class RiderOrder {
  const RiderOrder({
    required this.assignmentId,
    required this.id,
    required this.number,
    required this.status,
    required this.orderType,
    required this.customerName,
    required this.phone,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.total,
    required this.createdAt,
    required this.deliveredAt,
    required this.deliveryDuration,
    required this.items,
  });

  factory RiderOrder.fromAssignmentJson(Map<String, dynamic> json) {
    final order = json['order'] is Map<String, dynamic>
        ? json['order'] as Map<String, dynamic>
        : <String, dynamic>{};
    final customerLocation = json['customerLocation'] is Map<String, dynamic>
        ? json['customerLocation'] as Map<String, dynamic>
        : <String, dynamic>{};
    final orderCoordinates = order['coordinates'] is Map<String, dynamic>
        ? order['coordinates'] as Map<String, dynamic>
        : <String, dynamic>{};
    final items = order['items'];
    final assignmentId = '${json['_id'] ?? json['assignmentId'] ?? ''}'.trim();
    final orderId = '${order['_id'] ?? json['orderId'] ?? ''}'.trim();
    final orderNumber =
        '${order['orderNumber'] ?? json['orderNumber'] ?? ''}'.trim();
    final latitude = _numberFrom(
      customerLocation['lat'] ??
          customerLocation['latitude'] ??
          orderCoordinates['lat'] ??
          orderCoordinates['latitude'] ??
          order['customerLat'] ??
          order['latitude'],
    );
    final longitude = _numberFrom(
      customerLocation['lng'] ??
          customerLocation['longitude'] ??
          orderCoordinates['lng'] ??
          orderCoordinates['longitude'] ??
          order['customerLng'] ??
          order['longitude'],
    );
    return RiderOrder(
      assignmentId: assignmentId,
      id: orderId.isNotEmpty ? orderId : assignmentId,
      number: orderNumber.isNotEmpty ? orderNumber : orderId,
      status: '${json['status'] ?? 'assigned'}',
      orderType: 'delivery',
      customerName: '${order['customerName'] ?? json['customerName'] ?? ''}',
      phone: '${order['customerPhone'] ?? json['customerPhone'] ?? ''}',
      address:
          '${order['deliveryAddress'] ?? customerLocation['address'] ?? ''}',
      latitude: latitude,
      longitude: longitude,
      total: (order['total'] as num?)?.toDouble() ?? 0,
      createdAt:
          DateTime.tryParse('${json['assignedAt'] ?? ''}') ?? DateTime.now(),
      deliveredAt: DateTime.tryParse(
        '${json['deliveredAt'] ?? json['completedAt'] ?? ''}',
      ),
      deliveryDuration: _durationFrom(json),
      items: items is List
          ? items.map(RiderOrderItem.fromDeliveryPayload).toList()
          : const <RiderOrderItem>[],
    );
  }

  factory RiderOrder.fromActivityJson(Map<String, dynamic> json) {
    final orderNumber = '${json['orderNumber'] ?? ''}'.trim();
    final ticketName = '${json['ticketName'] ?? ''}'.trim();
    final number = orderNumber.isNotEmpty
        ? orderNumber
        : ticketName.split(' ').first.trim();
    final deliveredAt = DateTime.tryParse(
      '${json['deliveredAt'] ?? json['completedAt'] ?? ''}',
    );
    final deliveryDuration = _durationFrom(json);
    final rawStatus =
        '${json['assignmentStatus'] ?? json['status'] ?? ''}'.trim();
    final status = rawStatus.isNotEmpty ? rawStatus : 'completed';
    return RiderOrder(
      assignmentId: '${json['assignmentId'] ?? json['_id'] ?? ''}',
      id: '${json['orderId'] ?? json['assignmentId'] ?? json['id'] ?? ''}',
      number: number,
      status: status,
      orderType: 'delivery',
      customerName: '${json['customerName'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      address: '${json['address'] ?? ''}',
      latitude: null,
      longitude: null,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      createdAt:
          DateTime.tryParse('${json['assignedAt'] ?? ''}') ?? DateTime.now(),
      deliveredAt: deliveredAt,
      deliveryDuration: deliveryDuration,
      items: const <RiderOrderItem>[],
    );
  }

  final String assignmentId;
  final String id;
  final String number;
  final String status;
  final String orderType;
  final String customerName;
  final String phone;
  final String address;
  final double? latitude;
  final double? longitude;
  final double total;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final Duration? deliveryDuration;
  final List<RiderOrderItem> items;

  String get normalizedStatus =>
      status.trim().toLowerCase().replaceAll('_', '-').replaceAll(' ', '-');

  bool get isRemovedFromDelivery {
    switch (normalizedStatus) {
      case 'delivered':
      case 'completed':
      case 'returning':
      case 'returned':
      case 'unassigned':
      case 'cancelled':
      case 'canceled':
      case 'void':
      case 'deleted':
        return true;
      default:
        return false;
    }
  }

  static double? _numberFrom(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static Duration? _durationFrom(Map<String, dynamic> json) {
    final seconds = _numberFrom(
      json['deliverySeconds'] ??
          json['deliveryTimeSeconds'] ??
          json['deliveryDurationSeconds'] ??
          json['durationSeconds'] ??
          json['timeTakenSeconds'],
    );
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds.round());
    }
    final minutes = _numberFrom(
      json['deliveryMinutes'] ??
          json['deliveryTimeMinutes'] ??
          json['deliveryDurationMinutes'] ??
          json['durationMinutes'] ??
          json['timeTakenMinutes'],
    );
    if (minutes != null && minutes > 0) {
      return Duration(seconds: (minutes * 60).round());
    }
    return null;
  }

  Map<String, dynamic> toActivityJson() => {
        'assignmentId': assignmentId,
        'orderId': id,
        'orderNumber': number,
        'status': status,
        'total': total,
        'assignedAt': createdAt.toIso8601String(),
        if (deliveredAt != null) 'deliveredAt': deliveredAt!.toIso8601String(),
        if (deliveryDuration != null)
          'deliverySeconds': deliveryDuration!.inSeconds,
      };

  RiderOrder copyWith({
    String? status,
    DateTime? deliveredAt,
    Duration? deliveryDuration,
  }) =>
      RiderOrder(
        assignmentId: assignmentId,
        id: id,
        number: number,
        status: status ?? this.status,
        orderType: orderType,
        customerName: customerName,
        phone: phone,
        address: address,
        latitude: latitude,
        longitude: longitude,
        total: total,
        createdAt: createdAt,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        deliveryDuration: deliveryDuration ?? this.deliveryDuration,
        items: items,
      );

  List<RiderOrderItem> get visibleItems =>
      items.where((item) => item.name.isNotEmpty).toList();

  bool get isDelivery => orderType.toLowerCase() == 'delivery';
  bool get isReady {
    return normalizedStatus == 'en-route' ||
        normalizedStatus == 'assigned' ||
        normalizedStatus == 'accepted' ||
        normalizedStatus == 'picked-up' ||
        normalizedStatus == 'out-for-delivery' ||
        normalizedStatus == 'in-progress';
  }

  bool get isDelivered =>
      normalizedStatus == 'delivered' || normalizedStatus == 'returning';
  bool get isCompleted =>
      normalizedStatus == 'completed' ||
      normalizedStatus == 'complete' ||
      normalizedStatus == 'closed';
  bool get isUnassigned => normalizedStatus == 'unassigned';
  bool get countsTowardActivity => isDelivered || isCompleted;
  bool get isActiveDelivery => isReady;
  bool get shouldShowInDelivery => isReady && !isRemovedFromDelivery;

  String get statusLabel {
    switch (normalizedStatus) {
      case 'assigned':
        return 'Assigned';
      case 'en-route':
        return 'En route';
      case 'delivered':
      case 'returning':
        return 'Returning';
      case 'completed':
        return 'Completed';
      case 'unassigned':
        return 'Unassigned';
      default:
        return status;
    }
  }

  String get activityStatusLabel {
    if (isCompleted) return 'Completed';
    if (isDelivered) return 'Delivered';
    return statusLabel;
  }
}

class RiderOrderItem {
  const RiderOrderItem({required this.name, required this.quantity});

  factory RiderOrderItem.fromJson(Map<String, dynamic> json) => RiderOrderItem(
        name: '${json['name'] ?? ''}',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      );

  factory RiderOrderItem.fromDeliveryPayload(Object? value) {
    if (value is Map<String, dynamic>) return RiderOrderItem.fromJson(value);
    final text = '$value';
    if (text.trim().isEmpty || text == 'null') {
      return const RiderOrderItem(name: '', quantity: 0);
    }
    final match = RegExp(r'^\s*(\d+)x\s+(.+)$').firstMatch(text);
    if (match != null) {
      return RiderOrderItem(
        quantity: int.tryParse(match.group(1)!) ?? 1,
        name: match.group(2) ?? text,
      );
    }
    return RiderOrderItem(name: text, quantity: 1);
  }

  final String name;
  final int quantity;
}

class _RiderHeader extends StatelessWidget {
  const _RiderHeader({
    required this.driver,
    required this.online,
    required this.orderCount,
    required this.onOnlineChanged,
    required this.onRefresh,
  });

  final RiderDriver driver;
  final bool online;
  final int orderCount;
  final ValueChanged<bool> onOnlineChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                child: const Icon(Icons.delivery_dining, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rider',
                        style: Theme.of(context).textTheme.headlineSmall),
                    if (driver.name.trim().isNotEmpty ||
                        driver.driverId.trim().isNotEmpty)
                      Text(
                        [
                          driver.name.trim(),
                          driver.driverId.trim(),
                        ].where((part) => part.isNotEmpty).join(' - '),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    Text('$orderCount RMS orders assigned'),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: .08)),
            ),
            child: Row(
              children: [
                Icon(
                  online ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: online ? Colors.green.shade700 : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    online ? 'Online with RMS' : 'Offline',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Switch(value: online, onChanged: onOnlineChanged),
              ],
            ),
          ),
        ],
      );
}

class RiderOrderCard extends StatelessWidget {
  const RiderOrderCard({
    super.key,
    required this.order,
    required this.selected,
    required this.onTap,
  });

  final RiderOrder order;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        color: selected ? const Color(0xFFFFF0D0) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black.withValues(alpha: .08),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: order.countsTowardActivity
                      ? Colors.green.shade100
                      : order.isReady
                          ? Colors.blue.shade100
                          : Colors.amber.shade100,
                  foregroundColor: order.countsTowardActivity
                      ? Colors.green.shade800
                      : order.isReady
                          ? Colors.blue.shade800
                          : Colors.orange.shade900,
                  child: Icon(order.countsTowardActivity
                      ? Icons.check_circle
                      : order.isReady
                          ? Icons.route
                          : Icons.restaurant_menu),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Order #${order.number}',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(order.customerName,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(order.address,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(order.statusLabel,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    if (!order.countsTowardActivity)
                      _ElapsedTimerText(
                        startedAt: order.createdAt,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    Text('\$${order.total.toStringAsFixed(2)}'),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class ActiveDeliveryPanel extends StatelessWidget {
  const ActiveDeliveryPanel({
    super.key,
    required this.order,
    required this.updating,
    required this.onDelivered,
    required this.onBeAvailable,
  });

  final RiderOrder order;
  final bool updating;
  final VoidCallback onDelivered;
  final Future<void> Function() onBeAvailable;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: .08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Current delivery',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                _StatusPill(order.statusLabel),
              ],
            ),
            const SizedBox(height: 14),
            _DetailRow(icon: Icons.person, text: order.customerName),
            _DetailRow(icon: Icons.phone, text: order.phone),
            _DetailRow(
              icon: Icons.location_on,
              text: order.address,
              trailing: IconButton.filledTonal(
                onPressed: order.address.trim().isEmpty
                    ? null
                    : () => _openDirections(context),
                icon: const Icon(Icons.directions),
                tooltip: 'Directions',
              ),
            ),
            if (!order.countsTowardActivity)
              _DetailRow(
                icon: Icons.timer_outlined,
                text: 'Delivery timer',
                trailing: _ElapsedTimerText(
                  startedAt: order.createdAt,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            const Divider(height: 24),
            ...order.visibleItems.take(4).map(
                  (item) => Text('${item.quantity}x ${item.name}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            if (order.visibleItems.length > 4)
              Text('+${order.visibleItems.length - 4} more items'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        updating || order.countsTowardActivity || !order.isReady
                            ? null
                            : onDelivered,
                    icon: updating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Delivered'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: order.countsTowardActivity && !updating
                    ? onBeAvailable
                    : null,
                icon: const Icon(Icons.person_pin_circle_outlined),
                label: const Text('Be available'),
              ),
            ),
          ],
        ),
      );

  Future<void> _openDirections(BuildContext context) async {
    try {
      await const MethodChannel('com.example.pizza_hut/location')
          .invokeMethod<void>('openDirections', {
        'address': order.address,
        'latitude': order.latitude,
        'longitude': order.longitude,
      });
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'No map app could open directions.'),
        ),
      );
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text, this.trailing});

  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: text.isEmpty
            ? const SizedBox.shrink()
            : Row(
                children: [
                  Icon(icon,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
      );
}

class _ElapsedTimerText extends StatefulWidget {
  const _ElapsedTimerText({required this.startedAt, this.style});

  final DateTime startedAt;
  final TextStyle? style;

  @override
  State<_ElapsedTimerText> createState() => _ElapsedTimerTextState();
}

class _ElapsedTimerTextState extends State<_ElapsedTimerText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt);
    final safeElapsed = elapsed.isNegative ? Duration.zero : elapsed;
    final hours = safeElapsed.inHours;
    final minutes = safeElapsed.inMinutes.remainder(60);
    final seconds = safeElapsed.inSeconds.remainder(60);
    final label = hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:'
            '${seconds.toString().padLeft(2, '0')}'
        : '$minutes:${seconds.toString().padLeft(2, '0')}';

    return Text(label, style: widget.style);
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.text,
    this.isError = false,
  });

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError ? Colors.red.shade50 : Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isError ? Colors.red.shade100 : Colors.amber.shade100,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isError ? Colors.red : Colors.orange.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
}

class _EmptyDeliveries extends StatelessWidget {
  const _EmptyDeliveries();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 90),
        child: Column(
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: Colors.amber.shade100,
              child: Icon(Icons.delivery_dining,
                  size: 46, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text('No active orders',
                style: Theme.of(context).textTheme.titleLarge),
            const Text('Assigned POS delivery orders will appear here.'),
          ],
        ),
      );
}
