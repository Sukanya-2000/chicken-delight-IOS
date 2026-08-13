import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

import 'services/rms_http_client.dart';

void main() => runApp(const ChickenDelightRiderApp());

class ChickenDelightRiderApp extends StatelessWidget {
  const ChickenDelightRiderApp({super.key});

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
  RiderDriver? _driver;
  RiderBranch? _branch;

  RiderApiClient get _activeApiClient {
    final apiUrl = _branch?.apiUrl;
    if (apiUrl == null || apiUrl.trim().isEmpty) return widget.apiClient;
    return widget.apiClient.withBaseUrl(apiUrl);
  }

  @override
  Widget build(BuildContext context) {
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
        onAuthenticated: (value) => setState(() => _driver = value),
      );
    }
    return RiderHomeScreen(
      apiClient: _activeApiClient,
      driver: driver,
      onDriverChanged: (value) => setState(() => _driver = value),
      onLogout: () => setState(() {
        _driver = null;
        _branch = null;
      }),
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
      MethodChannel('com.example.chicken_delight/rider_storage');
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
      MethodChannel('com.example.chicken_delight/location');
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
      final driver = await widget.apiClient.loginDriver(
        driverId: driverId.text.trim(),
        password: password.text,
        branchId: widget.branch.id,
      );
      try {
        final location = await _requestLocation().timeout(
          const Duration(seconds: 8),
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
    required this.driver,
    required this.onDriverChanged,
    required this.onLogout,
  });

  final RiderApiClient apiClient;
  final RiderDriver driver;
  final ValueChanged<RiderDriver> onDriverChanged;
  final VoidCallback onLogout;

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  final List<RiderOrder> _orders = [];
  final List<RiderOrder> _activityOrders = [];
  final Set<String> _countedActivityOrderIds = {};
  Timer? _refreshTimer;
  RiderOrder? _selectedOrder;
  RiderActivityStats _activityStats = const RiderActivityStats.empty();
  int _tabIndex = 0;
  bool _loading = true;
  late bool _online;
  bool _updating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _online = widget.driver.status != 'offline';
    _loadOrders();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _loadOrders());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    if (!_online) return;
    if (mounted && _orders.isEmpty) setState(() => _loading = true);

    try {
      final orders =
          await widget.apiClient.fetchDriverAssignments(widget.driver);
      final activity = await widget.apiClient
          .fetchDriverActivity(widget.driver)
          .catchError((_) => RiderActivityReport.fromOrders(orders));
      final localStats = RiderActivityStats.fromDeliveredOrders(orders);
      if (!mounted) return;
      setState(() {
        _orders
          ..clear()
          ..addAll(orders);
        _rememberActivityOrders(activity.orders);
        _rememberActivityOrders(orders);
        _activityStats =
            _activityStats.mergedWith(activity.stats).mergedWith(localStats);
        _selectedOrder = _syncSelectedOrder(orders);
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
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
      );
      if (status == 'completed' || status == 'delivered') {
        setState(() => _rememberActivityOrder(order));
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

  void _rememberActivityOrders(List<RiderOrder> orders) {
    for (final order in orders) {
      if (order.countsTowardActivity) _rememberActivityOrder(order);
    }
  }

  void _rememberActivityOrder(RiderOrder order) {
    final activityId = order.id.trim().isEmpty
        ? '${order.number}-${order.createdAt.toIso8601String()}'
        : order.id;
    if (!_countedActivityOrderIds.add(activityId)) return;
    _activityOrders.insert(0, order);
    _activityStats = _activityStats.addOrder(order);
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
              error: _error,
              online: _online,
              orders: _orders,
              selectedOrder: _selectedOrder,
              updating: _updating,
              onRefresh: _loadOrders,
              onOnlineChanged: _setOnline,
              onSelectOrder: (order) => setState(() => _selectedOrder = order),
              onDelivered: (order) => _updateStatus(order, 'completed'),
            ),
            _ActivityTab(
              stats: _activityStats,
              orders: _activityOrders,
              onRefresh: _loadOrders,
            ),
            _SettingsTab(
              online: _online,
              driver: widget.driver,
              onOnlineChanged: _setOnline,
              onLogout: widget.onLogout,
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

  Future<void> _setOnline(bool value) async {
    setState(() => _online = value);
    try {
      final updated = await widget.apiClient.updateDriverStatus(
        widget.driver,
        value ? 'available' : 'offline',
      );
      widget.onDriverChanged(updated);
      if (value) _loadOrders();
    } catch (error) {
      if (!mounted) return;
      setState(() => _online = !value);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _DeliveryTab extends StatelessWidget {
  const _DeliveryTab({
    required this.driver,
    required this.loading,
    required this.error,
    required this.online,
    required this.orders,
    required this.selectedOrder,
    required this.updating,
    required this.onRefresh,
    required this.onOnlineChanged,
    required this.onSelectOrder,
    required this.onDelivered,
  });

  final RiderDriver driver;
  final bool loading;
  final String? error;
  final bool online;
  final List<RiderOrder> orders;
  final RiderOrder? selectedOrder;
  final bool updating;
  final Future<void> Function() onRefresh;
  final ValueChanged<bool> onOnlineChanged;
  final ValueChanged<RiderOrder> onSelectOrder;
  final ValueChanged<RiderOrder> onDelivered;

  @override
  Widget build(BuildContext context) {
    final selected = selectedOrder;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _RiderHeader(
            driver: driver,
            online: online,
            orderCount: orders.length,
            onOnlineChanged: onOnlineChanged,
            onRefresh: onRefresh,
          ),
          const SizedBox(height: 18),
          if (error != null)
            const _InlineNotice(
              icon: Icons.cloud_off,
              text: 'RMS refresh failed. Showing last loaded deliveries.',
              isError: true,
            ),
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
          else if (orders.isEmpty)
            const _EmptyDeliveries()
          else ...[
            Text(
              'Assigned orders',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            ...orders.map(
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
    required this.onRefresh,
  });

  final RiderActivityStats stats;
  final List<RiderOrder> orders;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final countedOrders =
        orders.where((order) => order.countsTowardActivity).toList();
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
            value: stats.averageDeliveryTimeLabel,
          ),
          const SizedBox(height: 14),
          _ActivityCard(
            icon: Icons.delivery_dining,
            label: 'Deliveries today',
            value: '${stats.deliveriesToday}',
          ),
          const SizedBox(height: 14),
          _ActivityCard(
            icon: Icons.payments,
            label: 'Total value',
            value: stats.totalValueLabel,
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
                                    'Order #${order.number} - ${order.statusLabel}',
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
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.online,
    required this.driver,
    required this.onOnlineChanged,
    required this.onLogout,
  });

  final bool online;
  final RiderDriver driver;
  final ValueChanged<bool> onOnlineChanged;
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

class RiderApiClient {
  RiderApiClient({http.Client? httpClient, String? baseUrl})
      : _httpClient = httpClient ?? createRmsHttpClient(),
        baseUrl = baseUrl ??
            const String.fromEnvironment('RMS_API_BASE_URL',
                defaultValue: 'https://rms-backend-v1.vercel.app');

  final http.Client _httpClient;
  final String baseUrl;

  RiderApiClient withBaseUrl(String nextBaseUrl) {
    final normalized = nextBaseUrl.trim();
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
    return RiderDriver.fromJson(data).withToken(driver.token);
  }

  Future<void> updateDriverLocation(
    RiderDriver driver, {
    required double latitude,
    required double longitude,
  }) async {
    final response = await _httpClient
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

  Future<List<RiderOrder>> fetchDriverAssignments(RiderDriver driver) async {
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

  Future<void> updateOrderStatus(
    String orderId,
    String status, {
    required RiderDriver driver,
  }) async {
    if (status != 'completed' && status != 'delivered') return;
    final trackingResponse = await _httpClient
        .get(
          _uri('/api/delivery/track/$orderId'),
        )
        .timeout(const Duration(seconds: 15));
    final trackingBody = _decode(trackingResponse);
    final tracking = trackingBody['data'];
    if (tracking is! Map<String, dynamic> || tracking['assigned'] != true) {
      throw Exception(
          'Assign a driver from POS delivery before marking delivered.');
    }
    final assignmentId = '${tracking['assignmentId'] ?? ''}';
    if (assignmentId.isEmpty) {
      throw Exception('Delivery assignment was not returned by RMS.');
    }
    final response = await _httpClient
        .patch(
          _uri('/api/delivery/driver/deliver/$assignmentId'),
          headers: _jsonHeaders(driver.token),
        )
        .timeout(const Duration(seconds: 15));
    _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    if (response.body.trimLeft().startsWith('<') ||
        (contentType.isNotEmpty && !contentType.contains('json'))) {
      throw Exception(
        'RMS backend route is not available: '
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
      throw Exception('${body['message'] ?? 'RMS request failed'}');
    }
    return body;
  }
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
      restaurantId: '${json['restaurantId'] ?? 'default'}',
      token: '${json['token'] ?? ''}',
      vehicleLabel: vehicleLabel,
    );
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
        vehicleLabel: vehicleLabel,
      );

  final String id;
  final String driverId;
  final String name;
  final String phone;
  final String color;
  final String status;
  final String restaurantId;
  final String token;
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
    required this.items,
  });

  factory RiderOrder.fromAssignmentJson(Map<String, dynamic> json) {
    final order = json['order'] is Map<String, dynamic>
        ? json['order'] as Map<String, dynamic>
        : <String, dynamic>{};
    final customerLocation = json['customerLocation'] is Map<String, dynamic>
        ? json['customerLocation'] as Map<String, dynamic>
        : <String, dynamic>{};
    final items = order['items'];
    return RiderOrder(
      id: '${order['_id'] ?? json['orderId'] ?? ''}',
      number: '${order['orderNumber'] ?? ''}',
      status: '${json['status'] ?? 'assigned'}',
      orderType: 'delivery',
      customerName: '${order['customerName'] ?? ''}',
      phone: '${order['customerPhone'] ?? ''}',
      address: '${order['deliveryAddress'] ?? ''}',
      latitude: (customerLocation['lat'] as num?)?.toDouble(),
      longitude: (customerLocation['lng'] as num?)?.toDouble(),
      total: (order['total'] as num?)?.toDouble() ?? 0,
      createdAt:
          DateTime.tryParse('${json['assignedAt'] ?? ''}') ?? DateTime.now(),
      deliveredAt: DateTime.tryParse(
        '${json['deliveredAt'] ?? json['completedAt'] ?? ''}',
      ),
      items: items is List
          ? items.map(RiderOrderItem.fromDeliveryPayload).toList()
          : const <RiderOrderItem>[],
    );
  }

  factory RiderOrder.fromActivityJson(Map<String, dynamic> json) {
    return RiderOrder(
      id: '${json['orderId'] ?? json['assignmentId'] ?? ''}',
      number: '${json['orderNumber'] ?? ''}',
      status: '${json['status'] ?? 'completed'}',
      orderType: 'delivery',
      customerName: '',
      phone: '',
      address: '',
      latitude: null,
      longitude: null,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      createdAt:
          DateTime.tryParse('${json['assignedAt'] ?? ''}') ?? DateTime.now(),
      deliveredAt: DateTime.tryParse(
        '${json['deliveredAt'] ?? json['completedAt'] ?? ''}',
      ),
      items: const <RiderOrderItem>[],
    );
  }

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
  final List<RiderOrderItem> items;

  List<RiderOrderItem> get visibleItems =>
      items.where((item) => item.name.isNotEmpty).toList();

  bool get isDelivery => orderType.toLowerCase() == 'delivery';
  bool get isReady {
    final normalized = status.toLowerCase();
    return normalized == 'en-route' || normalized == 'assigned';
  }

  bool get isDelivered => status.toLowerCase() == 'delivered';
  bool get isCompleted => status.toLowerCase() == 'completed';
  bool get countsTowardActivity => isDelivered || isCompleted;

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'assigned':
        return 'Assigned';
      case 'en-route':
        return 'En route';
      case 'delivered':
        return 'Returning';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
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
  });

  final RiderOrder order;
  final bool updating;
  final VoidCallback onDelivered;

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
            if (!order.countsTowardActivity)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          updating || !order.isReady ? null : onDelivered,
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
              )
            else
              const _InlineNotice(
                icon: Icons.check_circle,
                text:
                    'Delivered. POS can mark the driver available after return.',
              ),
          ],
        ),
      );

  Future<void> _openDirections(BuildContext context) async {
    try {
      await const MethodChannel('com.example.chicken_delight/location')
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
