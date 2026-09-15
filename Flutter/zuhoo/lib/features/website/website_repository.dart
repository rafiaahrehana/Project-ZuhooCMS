import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import 'website_models.dart';

/// The public marketing site, read by subdomain rather than by whoever is
/// signed in — `/api/website/**` is `permitAll()` on the backend, the same as
/// the portal endpoints `CompanyRepository` already calls for the simpler
/// preview. Reusing [ApiClient] here is safe for exactly that reason: the
/// auth interceptor only *adds* a bearer token when one is stored, it never
/// requires one, so a signed-in staff member's request looks the same to this
/// controller as an anonymous visitor's.
class WebsiteRepository {
  WebsiteRepository(this._api);

  final ApiClient _api;

  static const _base = '/website';

  Map<String, dynamic> _q(String subdomain, [Map<String, dynamic>? extra]) =>
      {'subdomain': subdomain, ...?extra};

  Future<WebsiteSettings> settings(String subdomain) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/settings',
      query: _q(subdomain),
    );
    return WebsiteSettings.fromJson(json);
  }

  Future<List<WebsiteOffering>> services(
    String subdomain, {
    String? category,
    String? q,
  }) async {
    final list = await _api.get<List<dynamic>>(
      '$_base/services',
      query: _q(subdomain, {'category': category, 'q': q}),
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(WebsiteOffering.fromJson)
        .toList(growable: false);
  }

  Future<WebsiteOffering> service(String subdomain, String slug) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/services/${Uri.encodeComponent(slug)}',
      query: _q(subdomain),
    );
    return WebsiteOffering.fromJson(json);
  }

  Future<List<WebsiteContent>> blog(String subdomain, {String? category}) async {
    final list = await _api.get<List<dynamic>>(
      '$_base/blog',
      query: _q(subdomain, {'category': category}),
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(WebsiteContent.fromJson)
        .toList(growable: false);
  }

  Future<WebsiteContent> blogPost(String subdomain, String slug) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/blog/${Uri.encodeComponent(slug)}',
      query: _q(subdomain),
    );
    return WebsiteContent.fromJson(json);
  }

  Future<WebsiteContent> page(String subdomain, String slug) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/pages/${Uri.encodeComponent(slug)}',
      query: _q(subdomain),
    );
    return WebsiteContent.fromJson(json);
  }

  Future<List<WebsitePerson>> testimonials(String subdomain) async {
    final list = await _api.get<List<dynamic>>(
      '$_base/testimonials',
      query: _q(subdomain),
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map((json) => WebsitePerson.fromJson(json, isTestimonial: true))
        .toList(growable: false);
  }

  Future<List<WebsitePerson>> team(String subdomain) async {
    final list = await _api.get<List<dynamic>>(
      '$_base/team',
      query: _q(subdomain),
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map((json) => WebsitePerson.fromJson(json, isTestimonial: false))
        .toList(growable: false);
  }

  Future<List<WebsiteFaq>> faqs(String subdomain) async {
    final list = await _api.get<List<dynamic>>(
      '$_base/faqs',
      query: _q(subdomain),
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(WebsiteFaq.fromJson)
        .toList(growable: false);
  }

  Future<List<WebsiteProject>> projects(String subdomain) async {
    final list = await _api.get<List<dynamic>>(
      '$_base/projects',
      query: _q(subdomain),
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(WebsiteProject.fromJson)
        .toList(growable: false);
  }

  Future<List<WebsitePricingPlan>> pricing(String subdomain) async {
    final list = await _api.get<List<dynamic>>(
      '$_base/pricing',
      query: _q(subdomain),
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(WebsitePricingPlan.fromJson)
        .toList(growable: false);
  }

  Future<void> submitContact(
    String subdomain,
    WebsiteContactRequest request,
  ) =>
      _api.post<dynamic>(
        '$_base/contact?subdomain=${Uri.encodeComponent(subdomain)}',
        request.toJson(),
      );

  Future<void> subscribeNewsletter(
    String subdomain,
    WebsiteNewsletterRequest request,
  ) =>
      _api.post<dynamic>(
        '$_base/newsletter?subdomain=${Uri.encodeComponent(subdomain)}',
        request.toJson(),
      );

  /// Returns the tracking code the visitor needs to check on it later — the
  /// only place this whole module hands one back, so it must be shown and
  /// not just left in a snackbar that scrolls away.
  Future<String> submitServiceRequest(
    String subdomain,
    WebsiteServiceRequestPayload request,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/service-requests?subdomain=${Uri.encodeComponent(subdomain)}',
      request.toJson(),
    );
    return json['code'] as String? ?? '';
  }

  Future<WebsiteServiceRequestStatus> trackServiceRequest(
    String subdomain,
    String code,
  ) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/service-requests/track/${Uri.encodeComponent(code)}',
      query: _q(subdomain),
    );
    return WebsiteServiceRequestStatus.fromJson(json);
  }

  /// A number every half-second, meant server-side to drive the web site's
  /// particle background rather than to mean anything on its own — see
  /// `MetricsStreamController`. Shown here as a small "site is alive" pulse
  /// rather than dropped, since it is otherwise the one endpoint in the app
  /// with no Flutter caller at all.
  ///
  /// Server-sent events, not JSON — [ApiClient]'s typed methods all assume a
  /// decoded body, so this reaches for the underlying [Dio] instance directly
  /// instead, the one place in the app that does.
  Stream<int> pulse() async* {
    try {
      final response = await _api.dio.get<ResponseBody>(
        '/v1/metrics/stream',
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );

      var buffer = '';
      await for (final chunk in response.data!.stream) {
        buffer += utf8.decode(chunk, allowMalformed: true);
        final lines = buffer.split('\n');
        buffer = lines.removeLast();
        for (final line in lines) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('data:')) continue;
          final value = int.tryParse(trimmed.substring(5).trim());
          if (value != null) yield value;
        }
      }
    } catch (error, stackTrace) {
      throw ApiException.from(error, stackTrace);
    }
  }
}

final websiteRepositoryProvider = Provider<WebsiteRepository>(
  (ref) => WebsiteRepository(ref.watch(apiClientProvider)),
);

final websiteSettingsProvider =
    FutureProvider.autoDispose.family<WebsiteSettings, String>(
  (ref, subdomain) => ref.read(websiteRepositoryProvider).settings(subdomain),
);

final websiteServicesProvider =
    FutureProvider.autoDispose.family<List<WebsiteOffering>, String>(
  (ref, subdomain) => ref.read(websiteRepositoryProvider).services(subdomain),
);

final websiteServiceDetailProvider = FutureProvider.autoDispose
    .family<WebsiteOffering, ({String subdomain, String slug})>(
  (ref, args) =>
      ref.read(websiteRepositoryProvider).service(args.subdomain, args.slug),
);

final websiteBlogProvider =
    FutureProvider.autoDispose.family<List<WebsiteContent>, String>(
  (ref, subdomain) => ref.read(websiteRepositoryProvider).blog(subdomain),
);

final websiteBlogPostProvider = FutureProvider.autoDispose
    .family<WebsiteContent, ({String subdomain, String slug})>(
  (ref, args) => ref
      .read(websiteRepositoryProvider)
      .blogPost(args.subdomain, args.slug),
);

final websiteTeamProvider =
    FutureProvider.autoDispose.family<List<WebsitePerson>, String>(
  (ref, subdomain) => ref.read(websiteRepositoryProvider).team(subdomain),
);

final websiteTestimonialsProvider =
    FutureProvider.autoDispose.family<List<WebsitePerson>, String>(
  (ref, subdomain) =>
      ref.read(websiteRepositoryProvider).testimonials(subdomain),
);

final websiteFaqsProvider =
    FutureProvider.autoDispose.family<List<WebsiteFaq>, String>(
  (ref, subdomain) => ref.read(websiteRepositoryProvider).faqs(subdomain),
);

final websiteProjectsProvider =
    FutureProvider.autoDispose.family<List<WebsiteProject>, String>(
  (ref, subdomain) => ref.read(websiteRepositoryProvider).projects(subdomain),
);

final websitePricingProvider =
    FutureProvider.autoDispose.family<List<WebsitePricingPlan>, String>(
  (ref, subdomain) => ref.read(websiteRepositoryProvider).pricing(subdomain),
);

/// One shared stream rather than one per screen: several widgets on the
/// Overview tab could plausibly want the pulse, and each of them opening its
/// own connection would be a needless multiple of a stream nobody asked to
/// see more than once.
final websitePulseProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.read(websiteRepositoryProvider).pulse(),
);
