import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../mock_data/mock_data.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../widgets/widgets.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.restaurant,
                      color: Colors.white,
                      size: 58,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'CHICKEN DELIGHT',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.primary),
                  ),
                  const Text(
                    'There\'s delight in every bite',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 36),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'How would you like your order?',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 14),
                  OrderTypeToggle(
                    value: state.orderType,
                    onChanged: state.setOrderType,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => context.push('/stores'),
                    child: const Text('Find restaurants near me'),
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

class StoreListScreen extends StatefulWidget {
  const StoreListScreen({super.key});

  @override
  State<StoreListScreen> createState() => _StoreListScreenState();
}

class _StoreListScreenState extends State<StoreListScreen> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby restaurants'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '1 restaurant near ${state.location.isEmpty ? 'you' : state.location}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            state.orderType == OrderType.delivery
                ? 'Choose this location for delivery ordering.'
                : 'Choose this location for pickup ordering.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          StoreCard(
            store: stores.first,
            onTap: () {
              state.selectStore(stores.first);
              context.push('/menu');
            },
          ),
        ],
      ),
    );
  }
}
