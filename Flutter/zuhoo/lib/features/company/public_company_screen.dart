import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'company_repository.dart';

/// A company's portal page, as anybody with the link sees it.
///
/// Reached from your own company's screen as a preview: what is on this page
/// is exactly what an unauthenticated visitor gets, so it is the honest way to
/// check that the tagline, the about text and the service list read the way
/// they were meant to.
class PublicCompanyScreen extends ConsumerWidget {
  const PublicCompanyScreen({super.key, required this.subdomain});

  final String subdomain;

  static void open(BuildContext context, {required String subdomain}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicCompanyScreen(subdomain: subdomain),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(publicCompanyProvider(subdomain));

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Your public page')),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load that page.',
          onRetry: () => ref.invalidate(publicCompanyProvider(subdomain)),
        ),
        data: (company) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            MessageBanner.info(
              'This is what somebody sees before they sign in. Nothing on it '
              'is private.',
            ),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Avatar(
                        initials: company.companyName.isEmpty
                            ? '?'
                            : company.companyName[0].toUpperCase(),
                        imageUrl: company.logo,
                        size: 52,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              company.companyName,
                              style: TextStyle(
                                color: bos.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (company.tagline != null)
                              Text(
                                company.tagline!,
                                style: TextStyle(
                                  color: bos.muted,
                                  fontSize: 12.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (company.portalAbout != null &&
                      company.portalAbout!.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      company.portalAbout!,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 13.5,
                        height: 1.6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(
              'What you offer',
              icon: Icons.sell_outlined,
            ),
            _PublicServices(subdomain: subdomain),
          ],
        ),
      ),
    );
  }
}

class _PublicServices extends ConsumerWidget {
  const _PublicServices({required this.subdomain});

  final String subdomain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(publicServicesProvider(subdomain));

    return AppCard(
      child: async.when(
        loading: () => const Loader(padding: 12),
        error: (error, _) => MessageBanner.error(
          error is ApiException
              ? error.message
              : 'Could not load the service list.',
        ),
        data: (services) => services.isEmpty
            ? Text(
                'Nothing is listed publicly. Services only appear here once '
                'they are marked for the portal.',
                style: TextStyle(color: bos.muted, fontSize: 13, height: 1.5),
              )
            : Column(
                children: [
                  for (final service in services)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  service.name,
                                  style: TextStyle(
                                    color: bos.text,
                                    fontSize: 13.5,
                                  ),
                                ),
                                if (service.description != null)
                                  Text(
                                    service.description!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: bos.muted,
                                      fontSize: 11.5,
                                      height: 1.4,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (service.price != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              Fmt.money(service.price),
                              style: TextStyle(
                                color: bos.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
