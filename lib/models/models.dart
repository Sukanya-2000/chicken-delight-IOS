enum OrderType { delivery, pickup }

enum MenuItemKind { regular, pizza, dinner, combo }

class ModifierOption {
  const ModifierOption({
    required this.id,
    required this.name,
    required this.price,
    this.image = '',
    this.isDefault = false,
    this.modifierGroups = const [],
  });

  factory ModifierOption.fromRmsJson(Map<String, dynamic> json) =>
      ModifierOption(
        id: '${json['id'] ?? json['_id'] ?? ''}',
        name: '${json['name'] ?? 'Option'}',
        image: '${json['image'] ?? ''}',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        isDefault: json['isDefault'] == true,
        modifierGroups: (json['modifierGroups'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ModifierGroup.fromRmsJson)
            .toList(),
      );

  final String id, name, image;
  final double price;
  final bool isDefault;
  final List<ModifierGroup> modifierGroups;
}

class ModifierGroup {
  const ModifierGroup({
    required this.id,
    required this.name,
    required this.required,
    required this.minSelection,
    required this.maxSelection,
    required this.displayType,
    required this.options,
  });

  factory ModifierGroup.fromRmsJson(Map<String, dynamic> json) => ModifierGroup(
        id: '${json['id'] ?? json['_id'] ?? ''}',
        name: '${json['name'] ?? 'Choices'}',
        required: json['required'] == true,
        minSelection: (json['minSelection'] as num?)?.toInt() ?? 0,
        maxSelection: (json['maxSelection'] as num?)?.toInt() ?? 1,
        displayType: '${json['displayType'] ?? 'checkbox'}',
        options: (json['options'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ModifierOption.fromRmsJson)
            .toList(),
      );

  final String id, name, displayType;
  final bool required;
  final int minSelection, maxSelection;
  final List<ModifierOption> options;
}

class SelectedModifier {
  const SelectedModifier({
    required this.groupId,
    required this.groupName,
    required this.optionId,
    required this.optionName,
    required this.price,
    required this.isRoot,
  });

  final String groupId, groupName, optionId, optionName;
  final double price;
  final bool isRoot;

  Map<String, dynamic> toRmsJson() => {
        'groupId': groupId,
        'groupName': groupName,
        'optionId': optionId,
        'optionName': optionName,
        'price': price,
        'isRoot': isRoot,
      };
}

class Store {
  const Store(
      {required this.id,
      required this.name,
      required this.address,
      required this.distance,
      required this.isOpen,
      required this.eta,
      required this.phone});

  factory Store.fromRmsJson(Map<String, dynamic> json) => Store(
        id: '${json['restaurantId'] ?? json['id'] ?? json['_id'] ?? ''}',
        name: '${json['name'] ?? 'Restaurant'}',
        address: '${json['address'] ?? ''}',
        distance: '${json['distanceLabel'] ?? json['distance'] ?? ''}',
        isOpen: json['isOpen'] != false,
        eta: '${json['etaLabel'] ?? json['eta'] ?? ''}',
        phone: '${json['phone'] ?? ''}',
      );

  final String id, name, address, distance, eta, phone;
  final bool isOpen;
}

class ItemOption {
  const ItemOption(this.name, {this.extra = 0});
  final String name;
  final double extra;
}

class MenuItem {
  const MenuItem(
      {required this.id,
      required this.name,
      required this.description,
      required this.price,
      required this.image,
      this.kind = MenuItemKind.regular,
      this.categoryId = '',
      this.badge = '',
      this.isPopular = false,
      this.modifierGroups = const []});
  factory MenuItem.fromRmsJson(Map<String, dynamic> json) {
    final itemType = '${json['itemType'] ?? ''}'.toLowerCase();
    final name = '${json['name'] ?? ''}'.toLowerCase();
    return MenuItem(
      id: '${json['id'] ?? json['_id'] ?? ''}',
      categoryId: '${json['categoryId'] ?? ''}',
      name: '${json['name'] ?? 'Menu item'}',
      description: '${json['description'] ?? ''}',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      image: '${json['image'] ?? ''}',
      badge: '${json['badge'] ?? ''}',
      isPopular: json['isPopular'] == true,
      modifierGroups: (json['modifierGroups'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ModifierGroup.fromRmsJson)
          .toList(),
      kind: itemType == 'combo'
          ? MenuItemKind.combo
          : name.contains('pizza')
              ? MenuItemKind.pizza
              : name.contains('dinner')
                  ? MenuItemKind.dinner
                  : MenuItemKind.regular,
    );
  }
  final String id, name, description, image, categoryId, badge;
  final double price;
  final bool isPopular;
  final MenuItemKind kind;
  final List<ModifierGroup> modifierGroups;
}

class MenuCategory {
  const MenuCategory(this.name, this.items);
  final String name;
  final List<MenuItem> items;
}

class CartItem {
  CartItem(
      {required this.id,
      required this.item,
      required this.quantity,
      required this.modifiers,
      required this.instructions,
      required this.unitPrice});
  final String id;
  final MenuItem item;
  int quantity;
  final List<SelectedModifier> modifiers;
  final String instructions;
  final double unitPrice;
  double get total => unitPrice * quantity;
  Map<String, dynamic> toRmsOrderJson() => {
        'menuItemId': item.id,
        'name': item.name,
        'image': item.image,
        'basePrice': unitPrice,
        'selectedModifiers':
            modifiers.map((modifier) => modifier.toRmsJson()).toList(),
        'quantity': quantity,
        'totalPrice': total,
        'note': instructions,
      };
}

class PromoValidation {
  const PromoValidation({
    required this.code,
    required this.discount,
    required this.description,
  });

  factory PromoValidation.fromRmsJson(Map<String, dynamic> json) =>
      PromoValidation(
        code: '${json['code'] ?? ''}',
        discount: (json['discountAmount'] as num?)?.toDouble() ?? 0,
        description: '${json['description'] ?? ''}',
      );

  final String code;
  final double discount;
  final String description;
}

class Order {
  Order(
      {required this.id,
      required this.number,
      required this.items,
      required this.subtotal,
      required this.tax,
      required this.discount,
      required this.deliveryFee,
      required this.tip,
      required this.total,
      required this.store,
      required this.orderType,
      required this.placedAt,
      required this.status});
  factory Order.fromRmsJson(Map<String, dynamic> json,
          {required List<CartItem> fallbackItems,
          required Store fallbackStore,
          required OrderType fallbackType,
          double? fallbackSubtotal,
          double? fallbackTax,
          double? fallbackDiscount,
          double? fallbackDeliveryFee,
          double? fallbackTip}) =>
      Order(
        id: '${json['_id'] ?? json['id'] ?? ''}',
        number: '${json['orderNumber'] ?? json['number'] ?? ''}',
        items: List.of(fallbackItems),
        subtotal: (json['subtotal'] as num?)?.toDouble() ??
            fallbackSubtotal ??
            fallbackItems.fold(0.0, (sum, item) => sum + item.total),
        tax: (json['tax'] as num?)?.toDouble() ?? fallbackTax ?? 0,
        discount:
            (json['discount'] as num?)?.toDouble() ?? fallbackDiscount ?? 0,
        deliveryFee: fallbackDeliveryFee ?? 0,
        tip: fallbackTip ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        store: fallbackStore,
        orderType: fallbackType,
        placedAt:
            DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
        status: '${json['status'] ?? 'pending'}',
      );
  Order copyWith({String? status}) => Order(
        id: id,
        number: number,
        items: items,
        subtotal: subtotal,
        tax: tax,
        discount: discount,
        deliveryFee: deliveryFee,
        tip: tip,
        total: total,
        store: store,
        orderType: orderType,
        placedAt: placedAt,
        status: status ?? this.status,
      );

  final String id;
  final String number;
  final List<CartItem> items;
  final double subtotal;
  final double tax;
  final double discount;
  final double deliveryFee;
  final double tip;
  final double total;
  final Store store;
  final OrderType orderType;
  final DateTime placedAt;
  final String status;
}
