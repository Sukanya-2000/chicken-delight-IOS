import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/rms_api_client.dart';

class AppState extends ChangeNotifier {
  AppState({RmsApiClient? apiClient})
      : _apiClient = apiClient ?? RmsApiClient();

  final RmsApiClient _apiClient;
  OrderType orderType = OrderType.delivery;
  String location = '';
  Store? selectedStore;
  final List<CartItem> cart = [];
  List<MenuCategory> menuCategories = const [];
  bool menuLoading = false;
  String? menuError;
  String promoCode = '';
  double promoDiscount = 0;
  String? promoMessage;
  bool promoLoading = false;
  double tipRate = 0;
  Order? lastOrder;
  int trackingStep = 0;
  String? trackingError;
  Timer? _statusTimer;

  int get itemCount => cart.fold(0, (sum, e) => sum + e.quantity);
  double get subtotal => cart.fold(0, (sum, e) => sum + e.total);
  double get discount => promoDiscount > subtotal ? subtotal : promoDiscount;
  double get tax => (subtotal - discount) * .12;
  double get deliveryFee => orderType == OrderType.delivery ? 4.99 : 0;
  double get tip => subtotal * tipRate;
  double get total => subtotal - discount + tax + deliveryFee + tip;

  void setOrderType(OrderType value) {
    orderType = value;
    notifyListeners();
  }

  void setLocation(String value) {
    location = value;
    notifyListeners();
  }

  void selectStore(Store value) {
    selectedStore = value;
    notifyListeners();
  }

  void add(MenuItem item, int quantity, List<SelectedModifier> modifiers,
      String instructions, double unitPrice) {
    cart.add(CartItem(
        id: '${item.id}-${DateTime.now().microsecondsSinceEpoch}',
        item: item,
        quantity: quantity,
        modifiers: modifiers,
        instructions: instructions,
        unitPrice: unitPrice));
    _clearPromo();
    notifyListeners();
  }

  void remove(String id) {
    cart.removeWhere((e) => e.id == id);
    if (cart.isEmpty) _clearPromo();
    notifyListeners();
  }

  void quantity(String id, int value) {
    final c = cart.firstWhere((e) => e.id == id);
    if (value <= 0) {
      remove(id);
    } else {
      c.quantity = value;
      _clearPromo();
      notifyListeners();
    }
  }

  Future<bool> applyPromo(String value) async {
    final code = value.trim().toUpperCase();
    if (code.isEmpty || subtotal <= 0) {
      promoCode = '';
      promoDiscount = 0;
      promoMessage = null;
      notifyListeners();
      return false;
    }

    promoLoading = true;
    promoMessage = null;
    notifyListeners();
    try {
      final promo =
          await _apiClient.validatePromo(code: code, subtotal: subtotal);
      promoCode = promo.code;
      promoDiscount = promo.discount;
      promoMessage = promo.description;
      return promoDiscount > 0;
    } catch (error) {
      promoCode = '';
      promoDiscount = 0;
      promoMessage = error.toString();
      return false;
    } finally {
      promoLoading = false;
      notifyListeners();
    }
  }

  void setTip(double value) {
    tipRate = value;
    notifyListeners();
  }

  Future<void> loadMenu({bool force = false}) async {
    if (menuLoading || (menuCategories.isNotEmpty && !force)) return;
    menuLoading = true;
    menuError = null;
    notifyListeners();
    try {
      menuCategories = await _apiClient.fetchMenu();
      if (menuCategories.isEmpty) {
        menuError = 'No active menu items were returned by RMS.';
      }
    } catch (error) {
      menuError = error.toString();
    } finally {
      menuLoading = false;
      notifyListeners();
    }
  }

  Future<bool> placeOrder({
    required String customerName,
    required String phone,
    required String email,
    required String address,
    required String postalCode,
    required bool payLater,
  }) async {
    final store = selectedStore;
    if (store == null || cart.isEmpty) return false;

    final order = await _apiClient.createOrder(
      cart: cart,
      store: store,
      orderType: orderType,
      customerName: customerName,
      phone: phone,
      email: email,
      address: address,
      postalCode: postalCode,
      subtotal: subtotal,
      tax: tax,
      discount: discount,
      total: total,
      promoCode: promoCode,
      payLater: payLater,
    );
    lastOrder = order;
    cart.clear();
    _clearPromo();
    _applyOrderStatus(order);
    _startOrderStatusPolling();
    notifyListeners();
    return true;
  }

  Future<void> refreshLastOrderStatus() async {
    final order = lastOrder;
    if (order == null || order.id.isEmpty) return;

    try {
      final refreshed = await _apiClient.fetchOrder(order: order);
      lastOrder = refreshed;
      trackingError = null;
      _applyOrderStatus(refreshed);
    } catch (error) {
      trackingError = error.toString();
    } finally {
      notifyListeners();
    }
  }

  void _startOrderStatusPolling() {
    _statusTimer?.cancel();
    final order = lastOrder;
    if (order == null || order.id.isEmpty || _isTerminalStatus(order.status)) {
      return;
    }
    _statusTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => refreshLastOrderStatus());
  }

  void _applyOrderStatus(Order order) {
    trackingStep = _trackingStepForStatus(order.status);
    if (_isTerminalStatus(order.status)) {
      _statusTimer?.cancel();
      _statusTimer = null;
    }
  }

  int _trackingStepForStatus(String status) {
    switch (status.toLowerCase()) {
      case 'preparing':
        return 1;
      case 'ready':
        return 2;
      case 'completed':
        return 3;
      case 'cancelled':
        return 3;
      case 'pending':
      default:
        return 0;
    }
  }

  bool _isTerminalStatus(String status) {
    final normalized = status.toLowerCase();
    return normalized == 'completed' || normalized == 'cancelled';
  }

  void _clearPromo() {
    promoCode = '';
    promoDiscount = 0;
    promoMessage = null;
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }
}
