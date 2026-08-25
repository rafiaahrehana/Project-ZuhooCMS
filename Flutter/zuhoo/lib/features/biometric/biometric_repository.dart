import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'biometric_models.dart';

/// Attendance terminals.
///
/// Enrolling and verifying are not here — see the note at the top of
/// [BiometricPermissions] for why a phone cannot do either.
class BiometricRepository {
  BiometricRepository(this._api);

  final ApiClient _api;

  static const _devices = '/company/biometric/devices';
  static const _data = '/company/biometric';

  /// Every device, one status, or only those reachable right now.
  ///
  /// The filters are path segments rather than query parameters, and
  /// `/online` answers with a bare list rather than a page — `getPaged` reads
  /// either shape.
  Future<PagedResponse<BiometricDevice>> devices({
    String? status,
    int page = 0,
    int size = 30,
  }) {
    // Written out rather than as a switch: a bare identifier in a pattern
    // position binds a variable instead of comparing against the constant.
    final String path;
    if (status == null) {
      path = _devices;
    } else if (status == onlineDevicesFilter) {
      path = '$_devices/online';
    } else {
      path = '$_devices/status/$status';
    }
    return _api.getPaged(path, BiometricDevice.fromJson, page: page, size: size);
  }

  Future<BiometricDevice> createDevice(BiometricDeviceRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_devices, request.toJson());
    return BiometricDevice.fromJson(json);
  }

  /// Sends the whole record — see [BiometricDeviceRequest] for which fields
  /// are assigned without a null check.
  Future<BiometricDevice> updateDevice(
    int id,
    BiometricDeviceRequest request,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_devices/$id',
      request.toJson(),
    );
    return BiometricDevice.fromJson(json);
  }

  /// Query parameter, empty response — the caller applies the change itself.
  Future<void> setDeviceStatus(int id, String status) =>
      _api.patch<dynamic>('$_devices/$id/status?status=$status');

  /// Marks it reachable or not. Normally the device reports this itself; the
  /// app offers it so a terminal known to be down can be taken out of the
  /// rotation without waiting for a health check.
  Future<void> setDeviceOnline(int id, bool online) =>
      _api.patch<dynamic>('$_devices/$id/online-status?online=$online');

  /// Records that it has just synchronised. Empty response.
  Future<void> recordSync(int id) => _api.post<dynamic>('$_devices/$id/sync');

  Future<void> deleteDevice(int id) => _api.delete<dynamic>('$_devices/$id');

  // ── Enrollments ─────────────────────────────────────────────

  /// What one person is enrolled on. A bare list.
  Future<List<BiometricEnrollment>> enrollmentsFor(int employeeId) async {
    final list = await _api.get<List<dynamic>>('$_data/employee/$employeeId');
    return list
        .whereType<Map<String, dynamic>>()
        .map(BiometricEnrollment.fromJson)
        .toList(growable: false);
  }

  /// Revokes one. The person can be enrolled again at the terminal.
  Future<void> deleteEnrollment(int id) => _api.delete<dynamic>('$_data/$id');
}

/// Not a `BiometricDeviceStatus` — a pseudo-status for `/online`, which asks
/// "what is reachable now" rather than "what is in what state".
const onlineDevicesFilter = 'ONLINE_NOW';

final biometricRepositoryProvider = Provider<BiometricRepository>(
  (ref) => BiometricRepository(ref.watch(apiClientProvider)),
);

/// Which slice of the estate is showing. Null is all of it.
class DeviceFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) {
    if (state == status) return;
    state = status;
  }
}

final deviceFilterProvider = NotifierProvider<DeviceFilterController, String?>(
  DeviceFilterController.new,
);

class BiometricDevicesController extends AsyncNotifier<List<BiometricDevice>> {
  @override
  Future<List<BiometricDevice>> build() {
    ref.watch(currentUserProvider);
    ref.watch(deviceFilterProvider);
    return _load();
  }

  Future<List<BiometricDevice>> _load() async {
    final page = await ref
        .read(biometricRepositoryProvider)
        .devices(status: ref.read(deviceFilterProvider));
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(BiometricDevice updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }

  void remove(int id) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current)
        if (row.id != id) row,
    ]);
  }
}

final biometricDevicesProvider =
    AsyncNotifierProvider<BiometricDevicesController, List<BiometricDevice>>(
  BiometricDevicesController.new,
);

/// What one employee is enrolled on. Keyed by employee, and disposed with the
/// screen that asked.
final enrollmentsProvider =
    FutureProvider.autoDispose.family<List<BiometricEnrollment>, int>(
  (ref, employeeId) =>
      ref.read(biometricRepositoryProvider).enrollmentsFor(employeeId),
);
