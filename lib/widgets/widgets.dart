import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';

final currency = NumberFormat.currency(symbol: r'$');

class OrderTypeToggle extends StatelessWidget {
  const OrderTypeToggle(
      {super.key, required this.value, required this.onChanged});
  final OrderType value;
  final ValueChanged<OrderType> onChanged;
  @override
  Widget build(BuildContext context) =>
      SegmentedButton<OrderType>(segments: const [
        ButtonSegment(
            value: OrderType.delivery,
            icon: Icon(Icons.delivery_dining),
            label: Text('Delivery')),
        ButtonSegment(
            value: OrderType.pickup,
            icon: Icon(Icons.shopping_bag_outlined),
            label: Text('Pickup'))
      ], selected: {
        value
      }, onSelectionChanged: (v) => onChanged(v.first));
}

class StoreCard extends StatelessWidget {
  const StoreCard({super.key, required this.store, required this.onTap});
  final Store store;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: store.isOpen ? onTap : null,
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    child: const Icon(Icons.storefront, size: 30)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(store.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 5),
                      Text(store.address),
                      const SizedBox(height: 5),
                      Row(children: [
                        const Icon(Icons.phone_outlined, size: 16),
                        const SizedBox(width: 5),
                        Text(store.phone,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Text(store.isOpen ? 'Open now' : 'Closed',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    store.isOpen ? Colors.green : Colors.red)),
                        Expanded(
                            child: Text(
                                '  •  ${store.distance}  •  ${store.eta}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)))
                      ])
                    ])),
                const Icon(Icons.chevron_right)
              ]))));
}

class MenuItemCard extends StatelessWidget {
  const MenuItemCard({super.key, required this.item, required this.onAdd});
  final MenuItem item;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: MenuItemImage(imageUrl: item.image, itemName: item.name),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(item.description,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 10),
                    Text('From ${currency.format(item.price)}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              IconButton.filled(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                tooltip: 'Customize and add',
              ),
            ],
          ),
        ),
      );
}

class MenuItemImage extends StatelessWidget {
  const MenuItemImage({
    super.key,
    required this.imageUrl,
    required this.itemName,
    this.size = 96,
  });

  final String imageUrl;
  final String itemName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.hasAbsolutePath) {
      return _MenuImagePlaceholder(size: size);
    }

    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          width: size,
          height: size,
          color: Colors.amber.shade50,
          alignment: Alignment.center,
          child: const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (_, error, __) {
        debugPrint('Menu image failed for "$itemName": $url ($error)');
        return _MenuImagePlaceholder(size: size);
      },
    );
  }
}

class _MenuImagePlaceholder extends StatelessWidget {
  const _MenuImagePlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        color: Colors.amber.shade100,
        child: const Icon(Icons.fastfood, size: 42),
      );
}

class PriceRow extends StatelessWidget {
  const PriceRow(this.label, this.value, {super.key, this.bold = false});
  final String label, value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(fontWeight: bold ? FontWeight.w800 : null)),
        Text(value,
            style: TextStyle(
                fontWeight: bold ? FontWeight.w900 : null,
                fontSize: bold ? 18 : null))
      ]));
}

class LoadingCards extends StatelessWidget {
  const LoadingCards({super.key});
  @override
  Widget build(BuildContext context) => ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 5,
      itemBuilder: (_, i) => Container(
          height: 115,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(18))));
}
