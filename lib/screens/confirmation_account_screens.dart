import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../widgets/widgets.dart';

class ConfirmationScreen extends StatelessWidget {
  const ConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final order = context.watch<AppState>().lastOrder;
    if (order == null) {
      return const Scaffold(body: Center(child: Text('No recent order.')));
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 30),
            CircleAvatar(
              radius: 42,
              backgroundColor: Colors.green.shade100,
              child: const Icon(Icons.check, color: Colors.green, size: 52),
            ),
            const SizedBox(height: 18),
            Text(
              'Order confirmed!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              'Order #${order.number}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimated ${order.orderType.name} time',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      '25-35 minutes',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const Divider(),
                    Text(order.store.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(order.store.address),
                    Text(order.store.phone),
                  ],
                ),
              ),
            ),
            Text('Receipt', style: Theme.of(context).textTheme.titleLarge),
            ...order.items.map((item) => PriceRow(
                '${item.quantity}x ${item.item.name}',
                currency.format(item.total))),
            const Divider(),
            PriceRow('Subtotal', currency.format(order.subtotal)),
            if (order.discount > 0)
              PriceRow('Promo discount', '-${currency.format(order.discount)}'),
            PriceRow('Tax', currency.format(order.tax)),
            if (order.deliveryFee > 0)
              PriceRow('Delivery fee', currency.format(order.deliveryFee)),
            if (order.tip > 0) PriceRow('Tip', currency.format(order.tip)),
            const Divider(),
            PriceRow('Total paid', currency.format(order.total), bold: true),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => context.push('/tracking'),
              icon: const Icon(Icons.route),
              label: const Text('Track order'),
            ),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Start another order'),
            ),
          ],
        ),
      ),
    );
  }
}

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  Timer? _driverTimer;
  double _driverProgress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().refreshLastOrderStatus();
    });
    if (context.read<AppState>().lastOrder?.orderType == OrderType.delivery) {
      _driverTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
        if (!mounted) return;
        setState(() {
          _driverProgress = math.min(1, _driverProgress + .025);
        });
      });
    }
  }

  @override
  void dispose() {
    _driverTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final order = state.lastOrder;
    if (order == null) {
      return const Scaffold(body: Center(child: Text('No recent order.')));
    }

    final step = state.trackingStep;
    final isDelivery = order.orderType == OrderType.delivery;
    final labels = order.orderType == OrderType.delivery
        ? const [
            'Order received',
            'Preparing your order',
            'Out for delivery',
            'Delivered',
          ]
        : const [
            'Order received',
            'Preparing your order',
            'Ready for pickup',
            'Picked up',
          ];
    final heading = isDelivery ? 'Delivery tracking' : 'Pickup tracking';
    final activeStep = step.clamp(0, labels.length - 1).toInt();
    final backendStatus = order.status.toLowerCase();
    final statusText = _trackingStatusLabel(backendStatus, labels[activeStep]);
    final trackingError = state.trackingError;

    return Scaffold(
      appBar: AppBar(title: const Text('Track your order')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading,
                style: Theme.of(context).textTheme.headlineMedium),
            Text('Live order status: $statusText'),
            if (trackingError != null) ...[
              const SizedBox(height: 8),
              Text(
                'Could not refresh RMS status. Showing last known status.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            if (isDelivery) ...[
              LiveOrderMap(
                progress: _driverProgress,
                isDelivery: isDelivery,
                status: statusText,
                storeName: order.store.name,
                destination:
                    state.location.isEmpty ? 'Your address' : state.location,
              ),
              const SizedBox(height: 28),
            ],
            ...List.generate(
              labels.length,
              (index) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      CircleAvatar(
                        backgroundColor: index <= step
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
                        child: Icon(
                          index < step
                              ? Icons.check
                              : index == step
                                  ? Icons.restaurant
                                  : Icons.circle_outlined,
                          color: index <= step ? Colors.white : Colors.grey,
                        ),
                      ),
                      if (index < labels.length - 1)
                        Container(
                          width: 3,
                          height: 58,
                          color: index < step
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade300,
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Padding(
                    padding: const EdgeInsets.only(top: 11),
                    child: Text(
                      labels[index],
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight:
                            index == step ? FontWeight.w900 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _trackingStatusLabel(String status, String fallback) {
  switch (status) {
    case 'pending':
      return 'Order received';
    case 'preparing':
      return 'Preparing your order';
    case 'ready':
      return fallback;
    case 'completed':
      return fallback;
    case 'cancelled':
      return 'Order cancelled';
    default:
      return fallback;
  }
}

class LiveOrderMap extends StatelessWidget {
  const LiveOrderMap({
    super.key,
    required this.progress,
    required this.isDelivery,
    required this.status,
    required this.storeName,
    required this.destination,
  });

  final double progress;
  final bool isDelivery;
  final String status;
  final String storeName;
  final String destination;

  @override
  Widget build(BuildContext context) {
    final eta = math.max(1, ((1 - progress) * 18).ceil());
    final rider = SampleRiderRoute.locationAt(progress);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 220,
            width: double.infinity,
            child: CustomPaint(
              painter: _LiveMapPainter(
                progress: progress,
                colorScheme: Theme.of(context).colorScheme,
                isDelivery: isDelivery,
                rider: rider,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      child: Icon(isDelivery
                          ? Icons.delivery_dining
                          : Icons.shopping_bag_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isDelivery
                                ? 'Rider moving live'
                                : 'Pickup route ready',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            isDelivery
                                ? '$eta min away from $destination'
                                : 'Head to $storeName when your order is ready',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _MapInfoChip(
                        icon: Icons.receipt_long,
                        label: status,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MapInfoChip(
                        icon: Icons.near_me,
                        label: isDelivery
                            ? '${rider.label} area'
                            : 'Store location',
                      ),
                    ),
                  ],
                ),
                if (isDelivery) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sample live input: ${rider.latitude.toStringAsFixed(4)}, ${rider.longitude.toStringAsFixed(4)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapInfoChip extends StatelessWidget {
  const _MapInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: .08)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
}

class RiderLocation {
  const RiderLocation(this.latitude, this.longitude, this.label);

  final double latitude;
  final double longitude;
  final String label;
}

class SampleRiderRoute {
  static const locations = [
    RiderLocation(49.8798, -97.1988, 'Restaurant'),
    RiderLocation(49.8821, -97.1917, 'Portage'),
    RiderLocation(49.8848, -97.1846, 'Midtown'),
    RiderLocation(49.8875, -97.1769, 'Broadway'),
    RiderLocation(49.8911, -97.1692, 'Downtown'),
    RiderLocation(49.8950, -97.1603, 'Destination'),
  ];

  static RiderLocation locationAt(double progress) {
    final clamped = progress.clamp(0.0, 1.0).toDouble();
    final scaled = clamped * (locations.length - 1);
    final index = scaled.floor().clamp(0, locations.length - 2).toInt();
    final nextIndex = math.min(index + 1, locations.length - 1);
    final segmentProgress = scaled - index;
    final start = locations[index];
    final end = locations[nextIndex];
    return RiderLocation(
      _lerp(start.latitude, end.latitude, segmentProgress),
      _lerp(start.longitude, end.longitude, segmentProgress),
      end.label,
    );
  }

  static double _lerp(double start, double end, double progress) =>
      start + ((end - start) * progress);
}

class _LiveMapPainter extends CustomPainter {
  _LiveMapPainter({
    required this.progress,
    required this.colorScheme,
    required this.isDelivery,
    required this.rider,
  });

  final double progress;
  final ColorScheme colorScheme;
  final bool isDelivery;
  final RiderLocation rider;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFF7F4EF);
    canvas.drawRect(Offset.zero & size, background);

    final roadPaint = Paint()
      ..color = const Color(0xFFD7D0C8)
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final activePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * .12, size.height * .78)
      ..cubicTo(size.width * .27, size.height * .35, size.width * .48,
          size.height * .92, size.width * .61, size.height * .46)
      ..cubicTo(size.width * .70, size.height * .15, size.width * .83,
          size.height * .32, size.width * .90, size.height * .18);

    _drawMapGrid(canvas, size);
    _drawNeighbourhoodLabels(canvas, size);
    canvas.drawPath(path, roadPaint);
    _drawProgressPath(canvas, path, activePaint);

    final store = Offset(size.width * .12, size.height * .78);
    final customer = Offset(size.width * .90, size.height * .18);
    _drawPin(canvas, store, Icons.restaurant, colorScheme.primary);
    _drawPin(canvas, customer, isDelivery ? Icons.home : Icons.storefront,
        const Color(0xFF222222));

    final driver = _pointOnPath(path, progress);
    if (isDelivery) {
      _drawDriver(canvas, driver, rider);
    } else {
      _drawPickupBadge(canvas, size);
    }
  }

  void _drawMapGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE7E0D9)
      ..strokeWidth = 2;
    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 18), paint);
    }
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x - 24, size.height), paint);
    }
  }

  void _drawNeighbourhoodLabels(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: .78);
    final labels = [
      (Offset(size.width * .16, size.height * .22), 'Portage Ave'),
      (Offset(size.width * .55, size.height * .20), 'Broadway'),
      (Offset(size.width * .44, size.height * .74), 'Main St'),
    ];
    for (final item in labels) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: item.$2,
          style: const TextStyle(
            color: Color(0xFF6B625A),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(item.$1.dx - 8, item.$1.dy - 5,
            textPainter.width + 16, textPainter.height + 10),
        const Radius.circular(12),
      );
      canvas.drawRRect(rect, paint);
      textPainter.paint(canvas, item.$1);
    }
  }

  void _drawProgressPath(Canvas canvas, Path path, Paint paint) {
    final metric = path.computeMetrics().first;
    final visiblePath = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(visiblePath, paint);
  }

  Offset _pointOnPath(Path path, double value) {
    final metric = path.computeMetrics().first;
    final tangent = metric.getTangentForOffset(metric.length * value);
    return tangent?.position ?? Offset.zero;
  }

  void _drawPin(Canvas canvas, Offset offset, IconData icon, Color color) {
    final pinPaint = Paint()..color = color;
    canvas.drawCircle(offset, 17, pinPaint);
    canvas.drawCircle(offset, 11, Paint()..color = Colors.white);
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas,
        offset - Offset(textPainter.width / 2, textPainter.height / 2));
  }

  void _drawDriver(Canvas canvas, Offset offset, RiderLocation location) {
    final pulse = 28 + (math.sin(progress * math.pi * 12) * 3);
    canvas.drawCircle(
      offset,
      pulse,
      Paint()..color = colorScheme.secondary.withValues(alpha: .20),
    );
    canvas.drawCircle(offset, 22, Paint()..color = Colors.white);
    canvas.drawCircle(offset, 18, Paint()..color = colorScheme.secondary);
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.delivery_dining.codePoint),
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontFamily: Icons.delivery_dining.fontFamily,
          package: Icons.delivery_dining.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas,
        offset - Offset(textPainter.width / 2, textPainter.height / 2));

    final labelPainter = TextPainter(
      text: TextSpan(
        text: location.label,
        style: const TextStyle(
          color: Color(0xFF222222),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 100);
    final labelOffset = Offset(
      (offset.dx - labelPainter.width / 2).clamp(8.0, 2000.0),
      (offset.dy + 28).clamp(8.0, 2000.0),
    );
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(labelOffset.dx - 8, labelOffset.dy - 5,
          labelPainter.width + 16, labelPainter.height + 10),
      const Radius.circular(12),
    );
    canvas.drawRRect(labelRect, Paint()..color = Colors.white);
    labelPainter.paint(canvas, labelOffset);
  }

  void _drawPickupBadge(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * .30, size.height * .38, size.width * .42, 40),
      const Radius.circular(20),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.white);
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Ready at store',
        style: TextStyle(
          color: Color(0xFF222222),
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * .38);
    textPainter.paint(
      canvas,
      Offset(
        rect.outerRect.center.dx - textPainter.width / 2,
        rect.outerRect.center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _LiveMapPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.isDelivery != isDelivery ||
      oldDelegate.rider != rider;
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool signedIn = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My account')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: signedIn
              ? [
                  const ListTile(
                    leading: CircleAvatar(child: Icon(Icons.person)),
                    title: Text('Delight Guest'),
                    subtitle: Text('guest@example.com'),
                  ),
                  const Divider(),
                  const ListTile(
                    leading: Icon(Icons.receipt_long),
                    title: Text('Past order #CD1024'),
                    subtitle: Text('May 18 - 8 Piece Chicken - \$32.18'),
                  ),
                  const ListTile(
                    leading: Icon(Icons.location_on_outlined),
                    title: Text('Saved address'),
                    subtitle: Text('1725 Portage Ave, Winnipeg'),
                  ),
                ]
              : [
                  Text('Welcome back',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 18),
                  const TextField(
                      decoration: InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 12),
                  const TextField(
                      obscureText: true,
                      decoration: InputDecoration(labelText: 'Password')),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() => signedIn = true),
                    child: const Text('Log in'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => signedIn = true),
                    child: const Text('Create an account (demo)'),
                  ),
                ],
        ),
      );
}
