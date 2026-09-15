import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../requests/request_models.dart' show CatalogService;
import 'company_models.dart';

/// The company's own record of itself.
///
/// Not the platform's view of a tenant — that lives in the platform module and
/// is gated on platform staff roles. These endpoints answer for whichever
/// company the caller belongs to, and the two public ones answer for anybody.
class CompanyRepository {
  CompanyRepository(this._api);

  final ApiClient _api;

  static const _base = '/companies';

  /// The signed-in user's own company. Refused outright for an account with
  /// no company — a platform staff member, typically.
  Future<CompanyProfile> me() async {
    final json = await _api.get<Map<String, dynamic>>('$_base/me');
    return CompanyProfile.fromJson(json);
  }

  /// Changes it. A genuine patch: every field is null-checked server-side,
  /// so only what changed needs sending.
  Future<CompanyProfile> updateMe(CompanyProfileRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_base/me',
      request.toJson(),
    );
    return CompanyProfile.fromJson(json);
  }

  /// A company's public page, by the name in its portal address.
  ///
  /// Unauthenticated: this is what somebody sees before they have an account,
  /// so it carries only what the company chose to publish.
  Future<PublicCompany> publicProfile(String subdomain) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/public/${Uri.encodeComponent(subdomain)}',
    );
    return PublicCompany.fromJson(json);
  }

  /// What that company offers, as its portal advertises it. Also public, so
  /// it lists only the services marked for the portal.
  Future<List<CatalogService>> publicServices(String subdomain) async {
    final list = await _api.get<List<dynamic>>(
      '$_base/public/${Uri.encodeComponent(subdomain)}/services',
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(CatalogService.fromJson)
        .toList(growable: false);
  }

  /// Starts an online checkout for upgrading the company's plan. The backend
  /// re-checks that the caller owns the company and that the target plan
  /// actually costs more than the current one before it hands back anything —
  /// this only starts that conversation and returns where to send the browser.
  Future<String> initiateSubscriptionUpgrade(
    SubscriptionUpgradeRequest request,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/payments/sslcommerz/initiate',
      request.toJson(),
    );
    return json['gatewayUrl'] as String? ?? '';
  }
}

final companyRepositoryProvider = Provider<CompanyRepository>(
  (ref) => CompanyRepository(ref.watch(apiClientProvider)),
);

final myCompanyProvider = FutureProvider<CompanyProfile>((ref) {
  ref.watch(currentUserProvider);
  return ref.read(companyRepositoryProvider).me();
});

/// A company's public page, keyed on the name in its portal address.
final publicCompanyProvider =
    FutureProvider.autoDispose.family<PublicCompany, String>(
  (ref, subdomain) =>
      ref.read(companyRepositoryProvider).publicProfile(subdomain),
);

/// What a company advertises publicly.
final publicServicesProvider =
    FutureProvider.autoDispose.family<List<CatalogService>, String>(
  (ref, subdomain) =>
      ref.read(companyRepositoryProvider).publicServices(subdomain),
);
