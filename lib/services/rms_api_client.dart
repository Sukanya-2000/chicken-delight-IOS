import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'rms_http_client.dart';

class RmsApiException implements Exception {
  RmsApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class RmsApiClient {
  RmsApiClient({http.Client? httpClient, String? baseUrl})
      : _httpClient = httpClient ?? createRmsHttpClient(),
        baseUrl = baseUrl ??
            const String.fromEnvironment('RMS_API_BASE_URL',
                defaultValue: 'https://rms-backend-v1.vercel.app');

  final http.Client _httpClient;
  final String baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<List<MenuCategory>> fetchMenu() async {
    final response = await _httpClient.get(_uri('/api/menu/pos-feed'));
    final body = _decode(response);
    final data = body['data'];
    if (data is! Map<String, dynamic>) return const [];

    final categories = (data['categories'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final items = (data['menuItems'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MenuItem.fromRmsJson)
        .toList();

    return categories
        .map((category) {
          final id = '${category['id'] ?? category['_id'] ?? ''}';
          final categoryItems =
              items.where((item) => item.categoryId == id).toList();
          return MenuCategory('${category['name'] ?? 'Menu'}', categoryItems);
        })
        .where((category) => category.items.isNotEmpty)
        .toList();
  }

  Future<PromoValidation> validatePromo({
    required String code,
    required double subtotal,
  }) async {
    final response = await _httpClient.post(
      _uri('/api/promo/validate'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code.trim().toUpperCase(),
        'subtotal': _money(subtotal),
      }),
    );
    final body = _decode(response);
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw RmsApiException('The RMS backend did not return promo data.');
    }
    return PromoValidation.fromRmsJson(data);
  }

  Future<Order> createOrder({
    required List<CartItem> cart,
    required Store store,
    required OrderType orderType,
    required String customerName,
    required String phone,
    required String email,
    required String address,
    required String postalCode,
    required double subtotal,
    required double tax,
    required double discount,
    required double total,
    required String promoCode,
    required bool payLater,
  }) async {
    final payload = {
      'orderType': orderType == OrderType.delivery ? 'delivery' : 'takeout',
      'orderSource': 'online',
      'items': cart.map((item) => item.toRmsOrderJson()).toList(),
      'subtotal': _money(subtotal),
      'taxRate': subtotal <= 0 ? 0 : _money(tax / subtotal),
      'tax': _money(tax),
      'discount': _money(discount),
      'discountType': discount > 0 ? 'promo' : 'none',
      'promoCode': promoCode,
      'total': _money(total),
      'paymentTiming': payLater ? 'pay-later' : 'pay-now',
      'paymentType': 'one-time',
      'payments': payLater
          ? []
          : [
              {'method': 'card', 'amount': _money(total)}
            ],
      'orderTiming': 'now',
      'customer': {
        'name': customerName,
        'phone': phone,
        'email': email,
        'address': address,
        'postalCode': postalCode,
      },
      'notes': 'Placed from Chicken Delight app. Store: ${store.name}',
    };

    final response = await _httpClient.post(
      _uri('/api/orders'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    final body = _decode(response);
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw RmsApiException('The RMS backend did not return an order.');
    }
    return Order.fromRmsJson(data,
        fallbackItems: cart,
        fallbackStore: store,
        fallbackType: orderType,
        fallbackSubtotal: subtotal,
        fallbackTax: tax,
        fallbackDiscount: discount,
        fallbackDeliveryFee: orderType == OrderType.delivery ? 4.99 : 0,
        fallbackTip: total -
            subtotal +
            discount -
            tax -
            (orderType == OrderType.delivery ? 4.99 : 0));
  }

  Future<Order> fetchOrder({
    required Order order,
  }) async {
    if (order.id.isEmpty) return order;

    final response = await _httpClient.get(_uri('/api/orders/${order.id}'));
    final body = _decode(response);
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw RmsApiException('The RMS backend did not return order data.');
    }
    return Order.fromRmsJson(
      data,
      fallbackItems: order.items,
      fallbackStore: order.store,
      fallbackType: order.orderType,
      fallbackSubtotal: order.subtotal,
      fallbackTax: order.tax,
      fallbackDiscount: order.discount,
      fallbackDeliveryFee: order.deliveryFee,
      fallbackTip: order.tip,
    );
  }

  Map<String, dynamic> _decode(
    http.Response response, {
    String? unavailableMessage,
  }) {
    final contentType = response.headers['content-type'] ?? '';
    if (response.body.trimLeft().startsWith('<') ||
        (contentType.isNotEmpty && !contentType.contains('json'))) {
      throw RmsApiException(
          unavailableMessage ??
              'The RMS API returned a web page instead of menu data. Check the backend URL.');
    }

    final decoded =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final body =
        decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] == false) {
      throw RmsApiException('${body['message'] ?? 'RMS request failed'}');
    }
    return body;
  }

  double _money(double value) => double.parse(value.toStringAsFixed(2));
}
