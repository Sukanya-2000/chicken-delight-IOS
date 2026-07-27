import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'services/rms_http_client.dart';

void main() => runApp(const ChickenDelightRiderApp());

class ChickenDelightRiderApp extends StatelessWidget {
  const ChickenDelightRiderApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Chicken Delight Rider',
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

  @override
  Widget build(BuildContext context) {
    final driver = _driver;
    if (driver == null) {
      return RiderAuthScreen(
        apiClient: widget.apiClient,
        onAuthenticated: (value) => setState(() => _driver = value),
      );
    }
    return RiderHomeScreen(
      apiClient: widget.apiClient,
      driver: driver,
      onDriverChanged: (value) => setState(() => _driver = value),
      onLogout: () => setState(() => _driver = null),
    );
  }
}

class RiderAuthScreen extends StatefulWidget {
  const RiderAuthScreen({
    super.key,
    required this.apiClient,
    required this.onAuthenticated,
  });

  final RiderApiClient apiClient;
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
                        'Chicken Delight Rider',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Login to receive RMS delivery assignments',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w700),
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
      );
      try {
        final location = await _requestLocation().timeout(
          const Duration(seconds: 8),
        );
        await widget.apiClient.tryUpdateDriverLocation(
          driver.id,
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
          await widget.apiClient.fetchDriverAssignments(widget.driver.id);
      final activity = await widget.apiClient
          .fetchDriverActivity(widget.driver.id)
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
      await widget.apiClient.updateOrderStatus(order.id, status);
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
        widget.driver.id,
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

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Future<RiderDriver> loginDriver({
    required String driverId,
    required String password,
  }) async {
    final response = await _httpClient.post(
      _uri('/api/delivery/driver/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'driverId': driverId, 'password': password}),
    ).timeout(const Duration(seconds: 15));
    final body = _decode(response);
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('RMS did not return driver profile.');
    }
    return RiderDriver.fromJson(data);
  }

  Future<RiderDriver> updateDriverStatus(String id, String status) async {
    final response = await _httpClient.patch(
      _uri('/api/delivery/driver/$id/status'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'status': status}),
    ).timeout(const Duration(seconds: 15));
    final body = _decode(response);
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('RMS did not return driver profile.');
    }
    return RiderDriver.fromJson(data);
  }

  Future<void> updateDriverLocation(
    String id, {
    required double latitude,
    required double longitude,
  }) async {
    final response = await _httpClient.post(
      _uri('/api/delivery/driver/$id/location'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'lat': latitude,
        'lng': longitude,
        'phase': 'available',
      }),
    ).timeout(const Duration(seconds: 8));
    _decode(response);
  }

  Future<void> tryUpdateDriverLocation(
    String id, {
    required double latitude,
    required double longitude,
  }) async {
    try {
      await updateDriverLocation(
        id,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (error) {
      final message = '$error';
      if (message.contains('/api/delivery/driver/$id/location') &&
          message.contains('returned 404')) {
        return;
      }
      rethrow;
    }
  }

  Future<List<RiderOrder>> fetchDriverAssignments(String driverId) async {
    final response = await _httpClient.get(
      _uri('/api/delivery/driver/$driverId/assignments'),
    ).timeout(const Duration(seconds: 15));
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

  Future<RiderActivityReport> fetchDriverActivity(String driverId) async {
    final response = await _httpClient.get(
      _uri('/api/delivery/driver/$driverId/activity'),
    ).timeout(const Duration(seconds: 15));
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

  Future<void> updateOrderStatus(String orderId, String status) async {
    if (status != 'completed' && status != 'delivered') return;
    final trackingResponse = await _httpClient.get(
      _uri('/api/delivery/track/$orderId'),
    ).timeout(const Duration(seconds: 15));
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
    final response = await _httpClient.patch(
      _uri('/api/delivery/driver/deliver/$assignmentId'),
    ).timeout(const Duration(seconds: 15));
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
      vehicleLabel: vehicleLabel,
    );
  }

  final String id;
  final String driverId;
  final String name;
  final String phone;
  final String color;
  final String status;
  final String restaurantId;
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
    final deliveredOrders = orders
        .where((order) => order.countsTowardActivity)
        .toList();
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
    final orderDeliveryTime = RiderActivityStats.averageDeliveryTimeFor([order]);
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
                    Text('Chicken Delight Rider',
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
