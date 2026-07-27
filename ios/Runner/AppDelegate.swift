import Flutter
import CoreLocation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CLLocationManagerDelegate {
  private let locationChannelName = "com.example.chicken_delight/location"
  private let locationManager = CLLocationManager()
  private var pendingLocationResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: locationChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }

      switch call.method {
      case "getCurrentLocation":
        self.requestCurrentLocation(result: result)
      case "openDirections":
        let arguments = call.arguments as? [String: Any]
        self.openDirections(
          address: arguments?["address"] as? String,
          latitude: self.doubleArgument(arguments?["latitude"]),
          longitude: self.doubleArgument(arguments?["longitude"]),
          result: result
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestCurrentLocation(result: @escaping FlutterResult) {
    guard CLLocationManager.locationServicesEnabled() else {
      result(FlutterError(
        code: "service_disabled",
        message: "Location services are disabled.",
        details: nil
      ))
      return
    }

    switch currentAuthorizationStatus() {
    case .authorizedAlways, .authorizedWhenInUse:
      pendingLocationResult = result
      locationManager.requestLocation()
    case .notDetermined:
      pendingLocationResult = result
      locationManager.requestWhenInUseAuthorization()
    case .denied, .restricted:
      result(FlutterError(
        code: "permission_denied",
        message: "Location permission denied.",
        details: nil
      ))
    @unknown default:
      result(FlutterError(
        code: "permission_denied",
        message: "Location permission denied.",
        details: nil
      ))
    }
  }

  private func openDirections(
    address: String?,
    latitude: Double?,
    longitude: Double?,
    result: FlutterResult
  ) {
    let destination = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hasCoordinates = latitude != nil && longitude != nil
    guard hasCoordinates || !destination.isEmpty else {
      result(FlutterError(
        code: "missing_address",
        message: "Delivery address is missing.",
        details: nil
      ))
      return
    }

    let query = hasCoordinates ? "\(latitude!),\(longitude!)" : destination
    guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
      result(FlutterError(
        code: "invalid_destination",
        message: "Delivery destination could not be encoded.",
        details: nil
      ))
      return
    }

    let app = UIApplication.shared
    if let googleMapsUrl = URL(string: "comgooglemaps://?daddr=\(encodedQuery)&directionsmode=driving"),
       app.canOpenURL(googleMapsUrl) {
      app.open(googleMapsUrl) { success in
        if success {
          result(nil)
        } else {
          result(FlutterError(
            code: "no_map_app",
            message: "No map app is available on this device.",
            details: nil
          ))
        }
      }
      return
    }

    if let appleMapsUrl = URL(string: "http://maps.apple.com/?daddr=\(encodedQuery)&dirflg=d") {
      app.open(appleMapsUrl) { success in
        if success {
          result(nil)
        } else {
          result(FlutterError(
            code: "no_map_app",
            message: "No map app is available on this device.",
            details: nil
          ))
        }
      }
      return
    }

    result(FlutterError(
      code: "no_map_app",
      message: "No map app is available on this device.",
      details: nil
    ))
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard pendingLocationResult != nil else { return }
    switch currentAuthorizationStatus() {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      finishLocationRequest(errorCode: "permission_denied", message: "Location permission denied.")
    case .notDetermined:
      break
    @unknown default:
      finishLocationRequest(errorCode: "permission_denied", message: "Location permission denied.")
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      finishLocationRequest(errorCode: "timeout", message: "Timed out waiting for location.")
      return
    }

    let result = pendingLocationResult
    pendingLocationResult = nil
    result?([
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
    ])
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    finishLocationRequest(errorCode: "timeout", message: "Timed out waiting for location.")
  }

  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    guard pendingLocationResult != nil else { return }
    switch status {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      finishLocationRequest(errorCode: "permission_denied", message: "Location permission denied.")
    case .notDetermined:
      break
    @unknown default:
      finishLocationRequest(errorCode: "permission_denied", message: "Location permission denied.")
    }
  }

  private func finishLocationRequest(errorCode: String, message: String) {
    let result = pendingLocationResult
    pendingLocationResult = nil
    result?(FlutterError(code: errorCode, message: message, details: nil))
  }

  private func doubleArgument(_ value: Any?) -> Double? {
    if let value = value as? Double {
      return value
    }
    if let value = value as? NSNumber {
      return value.doubleValue
    }
    return nil
  }

  private func currentAuthorizationStatus() -> CLAuthorizationStatus {
    if #available(iOS 14.0, *) {
      return locationManager.authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
  }
}
