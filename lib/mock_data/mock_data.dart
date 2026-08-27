import '../models/models.dart';

const pizzaImage =
    'https://images.unsplash.com/photo-1579751626657-72bc17010498?auto=format&fit=crop&w=500&q=80';
const wingsImage =
    'https://images.unsplash.com/photo-1527477396000-e27163b481c2?auto=format&fit=crop&w=500&q=80';
const pastaImage =
    'https://images.unsplash.com/photo-1551183053-bf91a1d81141?auto=format&fit=crop&w=500&q=80';
const dessertImage =
    'https://images.unsplash.com/photo-1606313564200-e75d5e30476c?auto=format&fit=crop&w=500&q=80';

const stores = <Store>[
  Store(
    id: 'pizza-hut-downtown',
    name: 'Pizza Hut Downtown',
    code: 'PHDOWNTOWN',
    address: '300 Main St',
    city: 'Winnipeg',
    distance: '1.8 km',
    isOpen: true,
    eta: '25-35 min',
    phone: '(204) 555-0101',
    deliveryFee: 4.99,
    taxRate: .12,
  ),
  Store(
    id: 'pizza-hut-portage',
    name: 'Pizza Hut Portage',
    code: 'PHPORTAGE',
    address: '1725 Portage Ave',
    city: 'Winnipeg',
    distance: '3.2 km',
    isOpen: true,
    eta: '30-40 min',
    phone: '(204) 555-0134',
    deliveryFee: 5.49,
    taxRate: .12,
  ),
  Store(
    id: 'pizza-hut-st-vital',
    name: 'Pizza Hut St. Vital',
    code: 'PHVITAL',
    address: '1225 St Mary' 's Rd',
    city: 'Winnipeg',
    distance: '5.9 km',
    isOpen: true,
    eta: '35-45 min',
    phone: '(204) 555-0177',
    deliveryFee: 5.99,
    taxRate: .12,
  ),
];

MenuItem m(
  String id,
  String name,
  String desc,
  double price, {
  MenuItemKind kind = MenuItemKind.regular,
  String image = pizzaImage,
}) =>
    MenuItem(
      id: id,
      name: name,
      description: desc,
      price: price,
      kind: kind,
      image: image,
    );

final menuCategories = <MenuCategory>[
  MenuCategory('Melts', [
    m('m1', 'Pepperoni Lover\'s Melt',
        'Crispy folded melt with pepperoni, mozzarella and marinara dip.', 8.99,
        kind: MenuItemKind.pizza),
    m('m2', 'Buffalo Chicken Melt',
        'Chicken, onions and buffalo sauce in a toasted melt.', 9.49,
        kind: MenuItemKind.pizza),
  ]),
  MenuCategory('Large Pizzas', [
    m(
        'p1',
        'Create Your Own Pizza',
        'Hand-tossed crust with sauce, cheese and your favorite toppings.',
        13.99,
        kind: MenuItemKind.pizza),
    m('p2', 'Pepperoni Lover\'s',
        'Extra pepperoni and extra cheese on classic red sauce.', 16.99,
        kind: MenuItemKind.pizza),
    m('p3', 'Supreme Pizza',
        'Pepperoni, beef, mushrooms, green peppers, onions and olives.', 18.49,
        kind: MenuItemKind.pizza),
    m('p4', 'Veggie Lover\'s',
        'Mushrooms, onions, green peppers, tomatoes and black olives.', 17.49,
        kind: MenuItemKind.pizza),
  ]),
  MenuCategory('Specialty Pizzas', [
    m('s1', 'Meat Lover\'s', 'Pepperoni, ham, beef, bacon and Italian sausage.',
        18.99,
        kind: MenuItemKind.pizza),
    m('s2', 'BBQ Chicken',
        'Grilled chicken, bacon, onions and smoky BBQ sauce.', 18.49,
        kind: MenuItemKind.pizza),
    m('s3', 'Hawaiian Chicken', 'Chicken, ham, pineapple and mozzarella.',
        17.99,
        kind: MenuItemKind.pizza),
  ]),
  MenuCategory('Deals', [
    m('d1', 'Big Dinner Box', 'Two medium pizzas, breadsticks and wings.',
        29.99,
        kind: MenuItemKind.combo),
    m('d2', 'Triple Treat Box',
        'Two medium pizzas, breadsticks and dessert for sharing.', 34.99,
        kind: MenuItemKind.combo),
  ]),
  MenuCategory('Wings', [
    m('w1', 'Traditional Wings',
        'Bone-in wings tossed in your choice of sauce.', 10.99,
        image: wingsImage),
    m('w2', 'Boneless Wings', 'Crispy boneless bites with dipping sauce.', 9.99,
        image: wingsImage),
  ]),
  MenuCategory('Pasta', [
    m('pa1', 'Chicken Alfredo Pasta',
        'Creamy Alfredo, grilled chicken and oven-baked cheese.', 11.99,
        image: pastaImage),
    m('pa2', 'Meaty Marinara Pasta',
        'Penne with marinara, beef, sausage and melted cheese.', 11.99,
        image: pastaImage),
  ]),
  MenuCategory('Sides', [
    m('i1', 'Breadsticks', 'Warm breadsticks with marinara dipping sauce.',
        5.99),
    m('i2', 'Cheese Sticks', 'Oven-baked cheese sticks with marinara.', 6.99),
    m('i3', 'Fries', 'Hot, crisp and lightly salted.', 4.49),
  ]),
  MenuCategory('Desserts', [
    m('e1', 'Cinnamon Sticks', 'Sweet cinnamon sticks with icing dip.', 5.99,
        image: dessertImage),
    m('e2', 'Chocolate Chip Cookie', 'Warm shareable cookie cut into slices.',
        6.99,
        image: dessertImage),
  ]),
  MenuCategory('Beverages', [
    m('b1', '2L Pepsi', 'Chilled bottle for sharing.', 3.99),
    m('b2', 'Bottled Water', 'Chilled spring water.', 2.49),
  ]),
];
