import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

/// Where a check-in or check-out is happening, best-effort.
///
/// The backend has carried `AttendanceMethod.GPS` and a
/// latitude/longitude/location triple on both punch endpoints since before
/// either client existed — Angular never wired it (a browser tab is not
/// where "were you actually at the office" is a question worth asking), and
/// this is the one place a phone can answer it that a desktop cannot.
///
/// Every failure here — permission denied, location services off, no
/// signal, no geocoder on this platform — is silent: a punch that could not
/// be tagged with a place still has to work as a punch. [current] returns
/// null rather than throwing, and the caller falls back to a plain manual
/// check-in exactly as it did before this existed.
class AttendanceLocation {
  const AttendanceLocation({
    required this.latitude,
    required this.longitude,
    this.label,
  });

  final double latitude;
  final double longitude;

  /// A short human-readable place, when the platform's own geocoder resolved
  /// one. Null does not mean the coordinates are wrong — just unlabelled.
  final String? label;

  static Future<AttendanceLocation?> current() async {
    try {
      // The 8-second limit on the explicit getCurrentPosition call below only
      // covers that one call. On web specifically, geolocator_web's own
      // requestPermission() first makes its *own*, un-timed, internal
      // getCurrentPosition() call to trigger the browser's permission
      // prompt — if that one hangs (a weak fix, a browser that never settles
      // the permission promise), nothing downstream saves it. Bounding the
      // whole operation here is the only place that can actually guarantee
      // a punch never waits forever on a place tag it may never get.
      return await _resolve().timeout(const Duration(seconds: 12));
    } catch (_) {
      // Missing GPS hardware, a platform this plugin does not cover, denied
      // permission, or a timeout can all land here — none of it should block
      // the punch itself.
      return null;
    }
  }

  static Future<AttendanceLocation?> _resolve() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 8),
      ),
    );

    return AttendanceLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      label: await _reverseGeocode(position.latitude, position.longitude),
    );
  }

  static Future<String?> _reverseGeocode(double lat, double lng) async {
    try {
      final places = await geocoding.Geocoding().placemarkFromCoordinates(lat, lng);
      if (places.isEmpty) return null;
      final place = places.first;
      final parts = [place.subLocality, place.locality]
          .whereType<String>()
          .where((part) => part.trim().isNotEmpty)
          .toList();
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      // Not every platform ships a geocoder (web, some desktop targets) —
      // the coordinates alone are still worth sending.
      return null;
    }
  }
}
