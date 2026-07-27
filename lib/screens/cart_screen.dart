import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../widgets/widgets.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _promoController = TextEditingController();

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Your cart')),
      body: state.cart.isEmpty ? const _EmptyCart() : _CartContent(state: state, promoController: _promoController),
      bottomNavigationBar: state.cart.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: FilledButton(
                onPressed: () => context.push('/checkout'),
                child: Text('Proceed to checkout  •  ${currency.format(state.total)}'),
              ),
            ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shopping_bag_outlined, size: 76, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('Your cart is empty', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('Add something delicious from the menu.', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.tonal(onPressed: () => context.pop(), child: const Text('Browse menu')),
          ]),
        ),
      );
}

class _CartContent extends StatelessWidget {
  const _CartContent({required this.state, required this.promoController});
  final AppState state;
  final TextEditingController promoController;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Order details', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                OrderTypeToggle(value: state.orderType, onChanged: state.setOrderType),
                const SizedBox(height: 14),
                Row(children: [
                  const Icon(Icons.location_on_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(state.orderType == OrderType.delivery ? 'Deliver to' : 'Pick up at', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(_destination),
                      const Text('ASAP', style: TextStyle(color: Colors.black54)),
                    ]),
                  ),
                  TextButton(onPressed: () => context.go('/'), child: const Text('Edit')),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(children: [
                    Icon(Icons.warning_amber_rounded),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'If you have a food allergy, phone the restaurant before ordering.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Your items', style: Theme.of(context).textTheme.titleLarge),
            Text('${state.itemCount} item${state.itemCount == 1 ? '' : 's'}'),
          ]),
          const SizedBox(height: 8),
          ...state.cart.map((item) => _CartItemTile(item: item)),
          TextButton.icon(onPressed: () => context.pop(), icon: const Icon(Icons.add), label: const Text('Add more items')),
          const SizedBox(height: 12),
          Text('Promo code', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: promoController, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText: 'Enter promo code', prefixIcon: Icon(Icons.local_offer_outlined)))),
            const SizedBox(width: 10),
            FilledButton.tonal(
              onPressed: state.promoLoading ? null : () => _applyPromo(context),
              child: state.promoLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Apply'),
            ),
          ]),
          if (state.promoMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              state.promoMessage!,
              style: TextStyle(
                color: state.promoCode.isEmpty
                    ? Theme.of(context).colorScheme.error
                    : Colors.green.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 22),
          Text('Add a tip', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: <double>[0, .10, .15, .20].map((tip) => ChoiceChip(label: Text(tip == 0 ? 'No tip' : '${(tip * 100).round()}%'), selected: state.tipRate == tip, onSelected: (_) => state.setTip(tip))).toList()),
          const SizedBox(height: 18),
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                PriceRow('Subtotal', currency.format(state.subtotal)),
                if (state.discount > 0) PriceRow('Promo discount', '-${currency.format(state.discount)}'),
                PriceRow('Tax', currency.format(state.tax)),
                if (state.deliveryFee > 0) PriceRow('Delivery fee', currency.format(state.deliveryFee)),
                PriceRow('Tip', currency.format(state.tip)),
                const Divider(height: 22),
                PriceRow('Total', currency.format(state.total), bold: true),
              ]),
            ),
          ),
        ],
      );

  String get _destination {
    if (state.orderType == OrderType.delivery) return state.location.isEmpty ? 'Address required' : state.location;
    return state.selectedStore?.address ?? 'Restaurant selection required';
  }

  Future<void> _applyPromo(BuildContext context) async {
    final valid = await state.applyPromo(promoController.text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(valid ? 'Promo discount applied!' : state.promoMessage ?? 'That promo code is not valid.')));
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({required this.item});
  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(item.item.image, width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 72, height: 72, color: Colors.amber.shade100, child: const Icon(Icons.fastfood))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.item.name, style: Theme.of(context).textTheme.titleMedium),
            if (item.modifiers.isNotEmpty)
              Text(
                item.modifiers
                    .map((modifier) => modifier.price > 0
                        ? '${modifier.optionName} +${currency.format(modifier.price)}'
                        : modifier.optionName)
                    .join(' - '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54),
              ),
            if (item.instructions.isNotEmpty) Text('“${item.instructions}”', style: const TextStyle(fontStyle: FontStyle.italic)),
            const SizedBox(height: 6),
            Text(currency.format(item.total), style: const TextStyle(fontWeight: FontWeight.w900)),
          ])),
          Column(children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(visualDensity: VisualDensity.compact, onPressed: () => state.quantity(item.id, item.quantity - 1), icon: const Icon(Icons.remove_circle_outline)),
              Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w800)),
              IconButton(visualDensity: VisualDensity.compact, onPressed: () => state.quantity(item.id, item.quantity + 1), icon: const Icon(Icons.add_circle_outline)),
            ]),
            TextButton(onPressed: () => state.remove(item.id), child: const Text('Remove')),
          ]),
        ]),
      ),
    );
  }
}
