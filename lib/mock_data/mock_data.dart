import '../models/models.dart';

const foodImage = 'https://images.unsplash.com/photo-1562967914-608f82629710?auto=format&fit=crop&w=500&q=80';
const pizzaImage = 'https://images.unsplash.com/photo-1579751626657-72bc17010498?auto=format&fit=crop&w=500&q=80';

const stores = <Store>[
  Store(
    id: 'default',
    name: 'Chicken Delight',
    address: 'RMS POS menu location',
    distance: 'Near you',
    isOpen: true,
    eta: 'Browse menu',
    phone: '',
  ),
];

MenuItem m(String id, String name, String desc, double price, {MenuItemKind kind = MenuItemKind.regular, String image = foodImage}) => MenuItem(id: id, name: name, description: desc, price: price, kind: kind, image: image);

final menuCategories = <MenuCategory>[
  MenuCategory('Create Your Own One-Topping Pizzas', [m('p1','One-Topping Pizza','Your favourite topping, sauce and mozzarella.',12.99,kind: MenuItemKind.pizza,image:pizzaImage)]),
  MenuCategory('Gourmet Pizzas', [m('p2','Deluxe Pizza','Pepperoni, mushrooms, green peppers and bacon.',16.49,kind:MenuItemKind.pizza,image:pizzaImage),m('p3','Chicken Bacon Ranch','Chicken, bacon, onion and ranch drizzle.',17.99,kind:MenuItemKind.pizza,image:pizzaImage)]),
  MenuCategory('Simply Chicken', [m('c1','8 Piece Chicken','Our famous pressure-fried chicken.',24.99),m('c2','12 Piece Chicken','Golden, crispy and made fresh.',34.99)]),
  MenuCategory('Individual Dinners', [m('d1','2 Piece Dinner','Chicken, fries, salad and a dinner roll.',14.49,kind:MenuItemKind.dinner),m('d2','3 Piece Dinner','Three pieces with fries, salad and roll.',16.99,kind:MenuItemKind.dinner)]),
  MenuCategory('Family Dinners', [m('f1','18 Piece Value Bucket','Feeds 6–8. Chicken, family fries and salads.',49.99,kind:MenuItemKind.dinner),m('f2','24 Piece Family Feast','Feeds 8–10. Chicken, fries, salads and rolls.',64.99,kind:MenuItemKind.dinner),m('f3','30 Piece Celebration Bucket','Feeds 12–15 with generous family sides.',79.99,kind:MenuItemKind.dinner)]),
  MenuCategory('Pizza & Chicken Combos', [m('x1','Family Combo','Large pizza, 8 pieces chicken, fries and salad.',49.49,kind:MenuItemKind.combo,image:pizzaImage)]),
  MenuCategory('Chicken Sandwiches', [m('s1','Classic Chicken Sandwich','Crispy chicken, lettuce and signature sauce.',9.49),m('s2','Spicy Chicken Sandwich','Crispy spicy fillet with pickles.',9.99)]),
  MenuCategory('Chicken Snacks', [m('n1','Chicken Fingers','Five all-white-meat fingers with dip.',11.99),m('n2','Cajun Bites','Seasoned bite-sized chicken.',9.49),m('n3','Chicken Poppers','Crispy poppable chicken bites.',8.99),m('n4','Breaded Pickles','Tangy pickle spears, golden fried.',7.49)]),
  MenuCategory('Ribs & Wings', [m('r1','Honey Garlic Wings','Ten wings tossed in honey garlic sauce.',15.99),m('r2','BBQ Rib Dinner','Tender ribs, fries and salad.',19.99,kind:MenuItemKind.dinner)]),
  MenuCategory('Sides', [m('i1','French Fries','Hot, crisp and lightly salted.',4.49),m('i2','Poutine','Fries, cheese curds and rich gravy.',7.99),m('i3','Coleslaw','Creamy house-made slaw.',3.49),m('i4','Macaroni Salad','Classic creamy macaroni salad.',3.49),m('i5','Potato Salad','Homestyle creamy potato salad.',3.49)]),
  MenuCategory('Dipping Sauces', [m('a1','Honey Dill','Creamy Manitoba favourite.',1.25),m('a2','BBQ Sauce','Smoky and sweet.',1.25)]),
  MenuCategory('Beverages', [m('b1','2L Soft Drink','Choose from available Pepsi products.',4.49),m('b2','Bottled Water','Chilled spring water.',2.49)]),
  MenuCategory('Desserts', [m('e1','New York Cheesecake','Rich and creamy cheesecake slice.',6.49),m('e2','Chocolate Brownie','Fudgy chocolate brownie.',4.49)]),
];
