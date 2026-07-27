# Chicken Delight ordering demo

A frontend-only Flutter ordering experience with local mock data and in-memory Provider state.

## Run

```sh
flutter pub get
flutter run
```

If platform folders are not already present in your checkout, generate them once with:

```sh
flutter create --platforms=android,ios .
```

The demo promo code is `DELIGHT10`. Location, payment, authentication, store loading, and order tracking are simulated; no data leaves the device.

## Structure

- `lib/models` — domain models
- `lib/mock_data` — stores and complete menu seed
- `lib/providers` — cart, pricing, order, and tracking state
- `lib/screens` — location, stores, menu, cart, checkout, confirmation, tracking, and account
- `lib/widgets` — reusable cards, toggles, price rows, and loading placeholders
