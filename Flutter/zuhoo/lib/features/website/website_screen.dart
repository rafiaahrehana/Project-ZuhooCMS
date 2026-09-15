import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';
import 'website_detail_screens.dart';
import 'website_models.dart';
import 'website_repository.dart';

/// A company's full marketing site, as `/api/website/**` serves it for its
/// subdomain — the richer sibling of the plain portal page
/// `PublicCompanyScreen` already previews. Reached the same way that one is:
/// a button on the company screen, not a place in the main nav, because it is
/// a preview of something else rather than a workspace of its own.
class WebsiteScreen extends StatelessWidget {
  const WebsiteScreen({super.key, required this.subdomain});

  final String subdomain;

  static void open(BuildContext context, {required String subdomain}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebsiteScreen(subdomain: subdomain),
      ),
    );
  }

  static const _tabs = [
    Tab(text: 'Overview'),
    Tab(text: 'Services'),
    Tab(text: 'Blog'),
    Tab(text: 'Team'),
    Tab(text: 'Reviews'),
    Tab(text: 'FAQs'),
    Tab(text: 'Projects'),
    Tab(text: 'Pricing'),
    Tab(text: 'Contact'),
  ];

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Website preview'),
          bottom: TabBar(
            tabs: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(subdomain: subdomain),
            _ServicesTab(subdomain: subdomain),
            _BlogTab(subdomain: subdomain),
            _TeamTab(subdomain: subdomain),
            _TestimonialsTab(subdomain: subdomain),
            _FaqsTab(subdomain: subdomain),
            _ProjectsTab(subdomain: subdomain),
            _PricingTab(subdomain: subdomain),
            _ContactTab(subdomain: subdomain),
          ],
        ),
      ),
    );
  }
}

/// Wraps every tab's body the same way: a scrollable list, pull to refresh,
/// and the same three states every other screen in the app draws for a
/// fetch. Takes the already-resolved [async] value and an [onRefresh]
/// callback rather than a provider reference itself — riverpod 3.x no longer
/// exposes a public type for "some provider producing `AsyncValue<T>`", so
/// each call site (already a [ConsumerWidget] with its own `ref`) resolves
/// its own provider and hands the result in.
class _AsyncTab<T> extends StatelessWidget {
  const _AsyncTab({
    required this.async,
    required this.onRefresh,
    required this.builder,
    required this.emptyIcon,
    required this.emptyTitle,
    this.isEmpty,
  });

  final AsyncValue<T> async;
  final VoidCallback onRefresh;
  final List<Widget> Function(T data) builder;
  final IconData emptyIcon;
  final String emptyTitle;
  final bool Function(T data)? isEmpty;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: Theme.of(context).bos.brand,
      onRefresh: () async => onRefresh(),
      child: async.when(
        loading: () => const Loader(padding: 48),
        error: (error, _) => ListView(
          children: [
            ErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Could not load this.',
              onRetry: onRefresh,
            ),
          ],
        ),
        data: (data) {
          if (isEmpty?.call(data) ?? false) {
            return ListView(
              children: [
                EmptyState(icon: emptyIcon, title: emptyTitle),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: builder(data),
          );
        },
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.subdomain});

  final String subdomain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(websiteSettingsProvider(subdomain));

    return RefreshIndicator(
      color: bos.brand,
      onRefresh: () async =>
          ref.invalidate(websiteSettingsProvider(subdomain)),
      child: async.when(
        loading: () => const Loader(padding: 48),
        error: (error, _) => ListView(
          children: [
            ErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Could not load the site settings.',
              onRetry: () => ref.invalidate(websiteSettingsProvider(subdomain)),
            ),
          ],
        ),
        data: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.heroHeading?.trim().isNotEmpty == true
                        ? settings.heroHeading!
                        : (settings.companyName ?? 'Your website'),
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if (settings.heroSubheading?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      settings.heroSubheading!,
                      style: TextStyle(
                        color: bos.textSecondary,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (settings.aboutText?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 16),
              const SectionHeader('About', icon: Icons.info_outline_rounded),
              AppCard(
                child: Text(
                  settings.aboutText!,
                  style: TextStyle(color: bos.text, fontSize: 13.5, height: 1.6),
                ),
              ),
            ],
            if (settings.stats.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionHeader('Numbers', icon: Icons.bar_chart_rounded),
              AppCard(
                child: Wrap(
                  spacing: 20,
                  runSpacing: 14,
                  children: [
                    for (final stat in settings.stats)
                      SizedBox(
                        width: 130,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stat.value ?? '—',
                              style: TextStyle(
                                color: bos.brandInk,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (stat.label != null)
                              Text(
                                stat.label!,
                                style: TextStyle(color: bos.muted, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (settings.email != null ||
                settings.phone != null ||
                settings.address != null) ...[
              const SizedBox(height: 16),
              const SectionHeader('Contact', icon: Icons.call_outlined),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (settings.email != null)
                      _InfoRow(Icons.email_outlined, settings.email!),
                    if (settings.phone != null)
                      _InfoRow(Icons.phone_outlined, settings.phone!),
                    if (settings.address != null)
                      _InfoRow(Icons.place_outlined, settings.address!),
                  ],
                ),
              ),
            ],
            if (settings.socialLinks.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionHeader('Social', icon: Icons.share_outlined),
              AppCard(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final link in settings.socialLinks)
                      if (link.platform != null)
                        Chip(label: Text(link.platform!)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const _PulseCard(),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: bos.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: bos.text, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// A quiet "the site is live" indicator, fed by the same simulated number the
/// public site's particle background animates from. It means nothing on its
/// own — see `WebsiteRepository.pulse` — so it is shown as a pulse, not a
/// metric with a label implying otherwise.
class _PulseCard extends ConsumerWidget {
  const _PulseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(websitePulseProvider);

    return AppCard(
      child: Row(
        children: [
          Icon(Icons.podcasts_rounded, size: 18, color: bos.brandInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Live site pulse',
              style: TextStyle(color: bos.text, fontSize: 13.5),
            ),
          ),
          async.when(
            loading: () => SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: bos.muted,
              ),
            ),
            error: (_, _) => Text('—', style: TextStyle(color: bos.muted)),
            data: (value) => Text(
              '$value',
              style: TextStyle(
                color: bos.brandInk,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicesTab extends ConsumerWidget {
  const _ServicesTab({required this.subdomain});

  final String subdomain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = websiteServicesProvider(subdomain);
    return _AsyncTab<List<WebsiteOffering>>(
      async: ref.watch(provider),
      onRefresh: () => ref.invalidate(provider),
      isEmpty: (data) => data.isEmpty,
      emptyIcon: Icons.local_offer_outlined,
      emptyTitle: 'No services listed',
      builder: (services) => [
        for (final service in services)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Builder(
              builder: (context) {
                final bos = Theme.of(context).bos;
                return AppCard(
                  onTap: () => WebsiteServiceDetailScreen.open(
                    context,
                    subdomain: subdomain,
                    slug: service.slug,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              service.title,
                              style: TextStyle(
                                color: bos.text,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (service.summary != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                service.summary!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: bos.textSecondary,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (service.startingPrice != null) ...[
                        const SizedBox(width: 10),
                        Text(
                          service.startingPrice!,
                          style: TextStyle(
                            color: bos.brandInk,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, color: bos.muted),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _BlogTab extends ConsumerWidget {
  const _BlogTab({required this.subdomain});

  final String subdomain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = websiteBlogProvider(subdomain);
    return _AsyncTab<List<WebsiteContent>>(
      async: ref.watch(provider),
      onRefresh: () => ref.invalidate(provider),
      isEmpty: (data) => data.isEmpty,
      emptyIcon: Icons.article_outlined,
      emptyTitle: 'No posts yet',
      builder: (posts) => [
        for (final post in posts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Builder(
              builder: (context) {
                final bos = Theme.of(context).bos;
                return AppCard(
                  onTap: () => WebsiteBlogDetailScreen.open(
                    context,
                    subdomain: subdomain,
                    slug: post.slug,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.title ?? 'Untitled post',
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (post.excerpt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          post.excerpt!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: bos.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (post.author != null) ...[
                            Text(
                              post.author!,
                              style: TextStyle(color: bos.muted, fontSize: 11.5),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (post.readMinutes != null)
                            Text(
                              '${post.readMinutes} min read',
                              style: TextStyle(color: bos.muted, fontSize: 11.5),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _TeamTab extends ConsumerWidget {
  const _TeamTab({required this.subdomain});

  final String subdomain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = websiteTeamProvider(subdomain);
    return _AsyncTab<List<WebsitePerson>>(
      async: ref.watch(provider),
      onRefresh: () => ref.invalidate(provider),
      isEmpty: (data) => data.isEmpty,
      emptyIcon: Icons.groups_2_outlined,
      emptyTitle: 'No team members listed',
      builder: (team) => [
        for (final person in team)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Builder(
              builder: (context) {
                final bos = Theme.of(context).bos;
                return AppCard(
                  child: Row(
                    children: [
                      Avatar(
                        initials: (person.name?.isNotEmpty ?? false)
                            ? person.name![0].toUpperCase()
                            : '?',
                        imageUrl: person.photoUrl,
                        size: 42,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person.name ?? 'Team member',
                              style: TextStyle(
                                color: bos.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (person.role != null)
                              Text(
                                person.role!,
                                style: TextStyle(color: bos.muted, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _TestimonialsTab extends ConsumerWidget {
  const _TestimonialsTab({required this.subdomain});

  final String subdomain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = websiteTestimonialsProvider(subdomain);
    return _AsyncTab<List<WebsitePerson>>(
      async: ref.watch(provider),
      onRefresh: () => ref.invalidate(provider),
      isEmpty: (data) => data.isEmpty,
      emptyIcon: Icons.rate_review_outlined,
      emptyTitle: 'No reviews yet',
      builder: (testimonials) => [
        for (final t in testimonials)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Builder(
              builder: (context) {
                final bos = Theme.of(context).bos;
                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (t.rating != null)
                        Row(
                          children: [
                            for (var i = 0; i < 5; i++)
                              Icon(
                                i < t.rating! ? Icons.star_rounded : Icons.star_outline_rounded,
                                size: 15,
                                color: bos.warning,
                              ),
                          ],
                        ),
                      if (t.quote != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '"${t.quote}"',
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        [t.name, t.company].whereType<String>().join(' · '),
                        style: TextStyle(
                          color: bos.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _FaqsTab extends ConsumerWidget {
  const _FaqsTab({required this.subdomain});

  final String subdomain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = websiteFaqsProvider(subdomain);
    return _AsyncTab<List<WebsiteFaq>>(
      async: ref.watch(provider),
      onRefresh: () => ref.invalidate(provider),
      isEmpty: (data) => data.isEmpty,
      emptyIcon: Icons.help_outline_rounded,
      emptyTitle: 'No FAQs yet',
      builder: (faqs) => [
        for (final faq in faqs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Builder(
              builder: (context) {
                final bos = Theme.of(context).bos;
                return Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: ExpansionTile(
                      title: Text(
                        faq.question,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      childrenPadding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          faq.answer ?? '',
                          style: TextStyle(
                            color: bos.textSecondary,
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ProjectsTab extends ConsumerWidget {
  const _ProjectsTab({required this.subdomain});

  final String subdomain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = websiteProjectsProvider(subdomain);
    return _AsyncTab<List<WebsiteProject>>(
      async: ref.watch(provider),
      onRefresh: () => ref.invalidate(provider),
      isEmpty: (data) => data.isEmpty,
      emptyIcon: Icons.work_outline_rounded,
      emptyTitle: 'No projects listed',
      builder: (projects) => [
        for (final project in projects)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Builder(
              builder: (context) {
                final bos = Theme.of(context).bos;
                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.title,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (project.summary != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          project.summary!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: bos.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (project.client != null) ...[
                            Text(
                              project.client!,
                              style: TextStyle(color: bos.muted, fontSize: 11.5),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (project.year != null)
                            Text(
                              '${project.year}',
                              style: TextStyle(color: bos.muted, fontSize: 11.5),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _PricingTab extends ConsumerWidget {
  const _PricingTab({required this.subdomain});

  final String subdomain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = websitePricingProvider(subdomain);
    return _AsyncTab<List<WebsitePricingPlan>>(
      async: ref.watch(provider),
      onRefresh: () => ref.invalidate(provider),
      isEmpty: (data) => data.isEmpty,
      emptyIcon: Icons.sell_outlined,
      emptyTitle: 'No pricing plans listed',
      builder: (plans) => [
        for (final plan in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Builder(
              builder: (context) {
                final bos = Theme.of(context).bos;
                return AppCard(
                  color: plan.featured ? bos.brandSoft : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              plan.name,
                              style: TextStyle(
                                color: bos.text,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (plan.price != null)
                            Text(
                              '${plan.price}${plan.period != null ? '/${plan.period}' : ''}',
                              style: TextStyle(
                                color: bos.brandInk,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                        ],
                      ),
                      if (plan.description != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          plan.description!,
                          style: TextStyle(color: bos.textSecondary, fontSize: 12),
                        ),
                      ],
                      if (plan.features.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final feature in plan.features)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              children: [
                                Icon(Icons.check_rounded, size: 14, color: bos.success),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    feature,
                                    style: TextStyle(color: bos.text, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ContactTab extends ConsumerStatefulWidget {
  const _ContactTab({required this.subdomain});

  final String subdomain;

  @override
  ConsumerState<_ContactTab> createState() => _ContactTabState();
}

class _ContactTabState extends ConsumerState<_ContactTab> {
  final _contactName = TextEditingController();
  final _contactEmail = TextEditingController();
  final _contactPhone = TextEditingController();
  final _contactSubject = TextEditingController();
  final _contactMessage = TextEditingController();
  bool _sendingContact = false;

  final _newsletterEmail = TextEditingController();
  bool _sendingNewsletter = false;

  final _requestServiceTitle = TextEditingController();
  final _requestName = TextEditingController();
  final _requestEmail = TextEditingController();
  final _requestPhone = TextEditingController();
  final _requestMessage = TextEditingController();
  bool _sendingRequest = false;
  String? _lastRequestCode;

  final _trackCode = TextEditingController();
  bool _tracking = false;
  WebsiteServiceRequestStatus? _tracked;

  @override
  void dispose() {
    _contactName.dispose();
    _contactEmail.dispose();
    _contactPhone.dispose();
    _contactSubject.dispose();
    _contactMessage.dispose();
    _newsletterEmail.dispose();
    _requestServiceTitle.dispose();
    _requestName.dispose();
    _requestEmail.dispose();
    _requestPhone.dispose();
    _requestMessage.dispose();
    _trackCode.dispose();
    super.dispose();
  }

  Future<void> _sendContact() async {
    if (_contactName.text.trim().isEmpty ||
        _contactEmail.text.trim().isEmpty ||
        _contactMessage.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name, email and message are required.')),
      );
      return;
    }
    setState(() => _sendingContact = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(websiteRepositoryProvider).submitContact(
            widget.subdomain,
            WebsiteContactRequest(
              name: _contactName.text.trim(),
              email: _contactEmail.text.trim(),
              phone: _contactPhone.text.trim().isEmpty
                  ? null
                  : _contactPhone.text.trim(),
              subject: _contactSubject.text.trim().isEmpty
                  ? null
                  : _contactSubject.text.trim(),
              message: _contactMessage.text.trim(),
            ),
          );
      if (!mounted) return;
      _contactName.clear();
      _contactEmail.clear();
      _contactPhone.clear();
      _contactSubject.clear();
      _contactMessage.clear();
      messenger.showSnackBar(const SnackBar(content: Text('Message sent.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send that.')),
      );
    } finally {
      if (mounted) setState(() => _sendingContact = false);
    }
  }

  Future<void> _sendNewsletter() async {
    if (_newsletterEmail.text.trim().isEmpty) return;
    setState(() => _sendingNewsletter = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(websiteRepositoryProvider).subscribeNewsletter(
            widget.subdomain,
            WebsiteNewsletterRequest(email: _newsletterEmail.text.trim()),
          );
      if (!mounted) return;
      _newsletterEmail.clear();
      messenger.showSnackBar(const SnackBar(content: Text('Subscribed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not subscribe.')),
      );
    } finally {
      if (mounted) setState(() => _sendingNewsletter = false);
    }
  }

  Future<void> _sendServiceRequest() async {
    if (_requestName.text.trim().isEmpty ||
        _requestEmail.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and email are required.')),
      );
      return;
    }
    setState(() => _sendingRequest = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final code =
          await ref.read(websiteRepositoryProvider).submitServiceRequest(
                widget.subdomain,
                WebsiteServiceRequestPayload(
                  serviceTitle: _requestServiceTitle.text.trim().isEmpty
                      ? null
                      : _requestServiceTitle.text.trim(),
                  name: _requestName.text.trim(),
                  email: _requestEmail.text.trim(),
                  phone: _requestPhone.text.trim().isEmpty
                      ? null
                      : _requestPhone.text.trim(),
                  message: _requestMessage.text.trim().isEmpty
                      ? null
                      : _requestMessage.text.trim(),
                ),
              );
      if (!mounted) return;
      setState(() => _lastRequestCode = code);
      _requestServiceTitle.clear();
      _requestName.clear();
      _requestEmail.clear();
      _requestPhone.clear();
      _requestMessage.clear();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not submit that request.')),
      );
    } finally {
      if (mounted) setState(() => _sendingRequest = false);
    }
  }

  Future<void> _track() async {
    if (_trackCode.text.trim().isEmpty) return;
    setState(() {
      _tracking = true;
      _tracked = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status = await ref
          .read(websiteRepositoryProvider)
          .trackServiceRequest(widget.subdomain, _trackCode.text.trim());
      if (!mounted) return;
      setState(() => _tracked = status);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not find that code.')),
      );
    } finally {
      if (mounted) setState(() => _tracking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const SectionHeader('Send a message', icon: Icons.mail_outline_rounded),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _contactName,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _contactEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _contactPhone,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: 'Phone (optional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _contactSubject,
                decoration:
                    const InputDecoration(labelText: 'Subject (optional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _contactMessage,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Message'),
              ),
              const SizedBox(height: 14),
              LoadingButton(
                label: 'Send',
                loading: _sendingContact,
                onPressed: _sendContact,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader('Newsletter', icon: Icons.campaign_outlined),
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newsletterEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
              ),
              const SizedBox(width: 10),
              _sendingNewsletter
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : FilledButton(
                      onPressed: _sendNewsletter,
                      child: const Text('Subscribe'),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader('Request a service', icon: Icons.assignment_outlined),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _requestServiceTitle,
                decoration:
                    const InputDecoration(labelText: 'Service (optional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _requestName,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _requestEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _requestPhone,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: 'Phone (optional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _requestMessage,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Message (optional)'),
              ),
              const SizedBox(height: 14),
              LoadingButton(
                label: 'Submit request',
                loading: _sendingRequest,
                onPressed: _sendServiceRequest,
              ),
              if (_lastRequestCode != null) ...[
                const SizedBox(height: 12),
                MessageBanner.success(
                  'Submitted. Tracking code: $_lastRequestCode',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader('Track a request', icon: Icons.search_rounded),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _trackCode,
                      decoration:
                          const InputDecoration(labelText: 'Tracking code'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _tracking
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : FilledButton(
                          onPressed: _track,
                          child: const Text('Track'),
                        ),
                ],
              ),
              if (_tracked != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _tracked!.serviceTitle ?? _tracked!.code,
                        style: TextStyle(color: bos.text, fontSize: 13),
                      ),
                    ),
                    StatusChip(_tracked!.status),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
