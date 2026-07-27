package com.example.chicken_delight

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Criteria
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.chicken_delight/location"
    private val permissionRequestCode = 4207
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            if (call.method == "getCurrentLocation") {
                requestCurrentLocation(result)
            } else if (call.method == "openDirections") {
                openDirections(
                    call.argument<String>("address"),
                    call.argument<Double>("latitude"),
                    call.argument<Double>("longitude"),
                    result
                )
            } else {
                result.notImplemented()
            }
        }
    }

    private fun openDirections(
        address: String?,
        latitude: Double?,
        longitude: Double?,
        result: MethodChannel.Result
    ) {
        val destination = address?.trim()
        val hasCoordinates = latitude != null && longitude != null
        if (!hasCoordinates && destination.isNullOrEmpty()) {
            result.error("missing_address", "Delivery address is missing.", null)
            return
        }
        val query = if (hasCoordinates) {
            "$latitude,$longitude"
        } else {
            destination.orEmpty()
        }

        val origin = try {
            val locationManager =
                getSystemService(Context.LOCATION_SERVICE) as LocationManager
            bestLastKnownLocation(locationManager)
        } catch (_: SecurityException) {
            null
        }
        val googleMapsUri = if (origin != null) {
            Uri.parse(
                "https://www.google.com/maps/dir/?api=1" +
                    "&origin=${origin.latitude},${origin.longitude}" +
                    "&destination=${Uri.encode(query)}" +
                    "&travelmode=driving"
            )
        } else {
            Uri.parse("google.navigation:q=${Uri.encode(query)}")
        }
        val googleMapsIntent = Intent(Intent.ACTION_VIEW, googleMapsUri).apply {
            setPackage("com.google.android.apps.maps")
        }
        try {
            startActivity(googleMapsIntent)
            result.success(null)
            return
        } catch (_: ActivityNotFoundException) {
            // Fall back to any installed third-party map app.
        }

        val mapIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("geo:0,0?q=${Uri.encode(query)}")
        )
        val chooser = Intent.createChooser(mapIntent, "Open directions with")
        try {
            startActivity(chooser)
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("no_map_app", "No map app is available on this device.", null)
        }
    }

    private fun requestCurrentLocation(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            pendingResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                permissionRequestCode
            )
            return
        }
        readCurrentLocation(result)
    }

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return

        val result = pendingResult ?: return
        pendingResult = null
        if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
            readCurrentLocation(result)
            return
        }

        val permanentlyDenied = permissions.any {
            !ActivityCompat.shouldShowRequestPermissionRationale(this, it)
        }
        if (permanentlyDenied) {
            result.error(
                "permission_denied_forever",
                "Location permission is blocked.",
                null
            )
        } else {
            result.error("permission_denied", "Location permission denied.", null)
        }
    }

    private fun readCurrentLocation(result: MethodChannel.Result) {
        val locationManager =
            getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val gpsEnabled =
            locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
        val networkEnabled =
            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        if (!gpsEnabled && !networkEnabled) {
            result.error("service_disabled", "Location services are disabled.", null)
            return
        }

        val cached = bestLastKnownLocation(locationManager)
        if (cached != null) {
            result.success(locationPayload(cached))
            return
        }

        val provider = locationManager.getBestProvider(
            Criteria().apply { accuracy = Criteria.ACCURACY_FINE },
            true
        ) ?: if (networkEnabled) {
            LocationManager.NETWORK_PROVIDER
        } else {
            LocationManager.GPS_PROVIDER
        }

        val handler = Handler(Looper.getMainLooper())
        var completed = false
        lateinit var listener: LocationListener
        listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (completed) return
                completed = true
                handler.removeCallbacksAndMessages(null)
                locationManager.removeUpdates(listener)
                result.success(locationPayload(location))
            }

            override fun onProviderDisabled(provider: String) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }

        try {
            locationManager.requestLocationUpdates(provider, 0L, 0f, listener)
            handler.postDelayed({
                if (completed) return@postDelayed
                val fallback = bestLastKnownLocation(locationManager)
                if (fallback != null) {
                    completed = true
                    locationManager.removeUpdates(listener)
                    result.success(locationPayload(fallback))
                    return@postDelayed
                }
                completed = true
                locationManager.removeUpdates(listener)
                result.error("timeout", "Timed out waiting for location.", null)
            }, 20000L)
        } catch (error: SecurityException) {
            result.error("permission_denied", "Location permission denied.", null)
        }
    }

    private fun bestLastKnownLocation(locationManager: LocationManager): Location? {
        val providers = locationManager.getProviders(true)
        return providers
            .mapNotNull { provider ->
                try {
                    locationManager.getLastKnownLocation(provider)
                } catch (_: SecurityException) {
                    null
                }
            }
            .maxByOrNull { it.time }
    }

    private fun locationPayload(location: Location): Map<String, Double> =
        mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude
        )
}
