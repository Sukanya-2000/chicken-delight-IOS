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

## iOS Internal Testing

The iOS project is checked in under `ios/` and is configured for App Store Connect/TestFlight archives with automatic signing.

Customer app:

```sh
flutter build ipa --release -t lib/main.dart
```

Rider app:

```sh
flutter build ipa --release -t lib/rider_main.dart
```

The customer iOS bundle ID is `com.chickendelight.customer`. Before uploading, open `ios/Runner.xcworkspace` in Xcode on macOS and select your Apple Developer team for the `Runner` target. If you want the rider app to be listed as a separate app in App Store Connect, assign it its own bundle ID in Xcode before archiving, for example `com.chickendelight.rider`.

## Structure

- `lib/models` - domain models
- `lib/mock_data` - stores and complete menu seed
- `lib/providers` - cart, pricing, order, and tracking state
- `lib/screens` - location, stores, menu, cart, checkout, confirmation, tracking, and account
- `lib/widgets` - reusable cards, toggles, price rows, and loading placeholders
