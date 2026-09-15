import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import 'recruitment_models.dart';
import 'recruitment_repository.dart';
import 'refer_candidate_sheet.dart';

/// The public careers page a company advertises jobs on.
///
/// Its own settings record rather than part of the company profile: the slug
/// is a separate public address from the client portal's subdomain, and the
/// page can be unpublished without touching anything else.
class CareerPageSettings {
  const CareerPageSettings({
    required this.slug,
    required this.published,
    this.headline,
    this.about,
    this.brandColor,
  });

  /// The name in the page's address. Lowercase letters, digits and hyphens,
  /// 1 to 60 characters, no hyphen at either end — the backend checks exactly
  /// that and refuses anything else with a message saying so.
  ///
  /// Seeded from the company name the first time the page is opened, so it
  /// works before anybody configures it.
  final String slug;

  /// Whether anybody outside the company can see it at all.
  final bool published;

  final String? headline;
  final String? about;
  final String? brandColor;

  factory CareerPageSettings.fromJson(Map<String, dynamic> json) =>
      CareerPageSettings(
        slug: json['slug'] as String? ?? '',
        published: json['published'] as bool? ?? false,
        headline: json['headline'] as String?,
        about: json['about'] as String?,
        brandColor: json['brandColor'] as String?,
      );

  /// The PUT takes the same shape it gives, and assigns every field without a
  /// null check — so a save always sends the lot.
  Map<String, dynamic> toJson() => {
        'slug': slug,
        'published': published,
        'headline': headline,
        'about': about,
        'brandColor': brandColor,
      };

  CareerPageSettings copyWith({
    String? slug,
    bool? published,
    String? headline,
    String? about,
    String? brandColor,
  }) =>
      CareerPageSettings(
        slug: slug ?? this.slug,
        published: published ?? this.published,
        headline: headline ?? this.headline,
        about: about ?? this.about,
        brandColor: brandColor ?? this.brandColor,
      );
}

class CareerPageRepository {
  CareerPageRepository(this._api);

  final ApiClient _api;

  static const _base = '/hr/career-page';

  /// Reading it creates it if it does not exist, seeded from the company
  /// name — so there is no such thing as a company without one.
  Future<CareerPageSettings> settings() async {
    final json = await _api.get<Map<String, dynamic>>(_base);
    return CareerPageSettings.fromJson(json);
  }

  /// Saving needs JOB_POSTING_CREATE, while reading only needs
  /// JOB_POSTING_VIEW — a recruiter can look at the page without being able
  /// to change what it says.
  Future<CareerPageSettings> save(CareerPageSettings settings) async {
    final json =
        await _api.put<Map<String, dynamic>>(_base, settings.toJson());
    return CareerPageSettings.fromJson(json);
  }
}

final careerPageRepositoryProvider = Provider<CareerPageRepository>(
  (ref) => CareerPageRepository(ref.watch(apiClientProvider)),
);

final careerPageProvider = FutureProvider.autoDispose<CareerPageSettings>(
  (ref) => ref.read(careerPageRepositoryProvider).settings(),
);

class CareerPageScreen extends ConsumerWidget {
  const CareerPageScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CareerPageScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(careerPageProvider);
    final canEdit = ref
        .watch(permissionControllerProvider)
        .has(RecruitmentPermissions.jobCreate);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Careers page')),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async => ref.invalidate(careerPageProvider),
        child: async.when(
          loading: () => const Loader(),
          error: (error, _) => ErrorState(
            message: error is ApiException
                ? error.message
                : 'Could not load the careers page.',
            onRetry: () => ref.invalidate(careerPageProvider),
          ),
          data: (settings) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              if (!settings.published)
                MessageBanner.warning(
                  'The page is not published. Nobody outside the company can '
                  'see it, and open jobs are not advertised anywhere.',
                )
              else
                MessageBanner.info(
                  'The page is live. Anybody with the address can read it and '
                  'apply to whatever is open.',
                ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.headline ?? 'Join our team',
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (settings.about != null &&
                        settings.about!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        settings.about!,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13.5,
                          height: 1.6,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.link_rounded, size: 15, color: bos.muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SelectableText(
                            '/careers/${settings.slug}',
                            style:
                                TextStyle(color: bos.muted, fontSize: 12.5),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy',
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: '/careers/${settings.slug}'),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied.')),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (canEdit) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        showCareerPageSheet(context, settings: settings),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('Edit the page'),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const SectionHeader(
                'What is advertised',
                icon: Icons.work_outline_rounded,
              ),
              const _OpenJobs(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The jobs the page is currently advertising.
///
/// Its own endpoint rather than filtering the full list: what counts as open
/// is the backend's judgement — published, not closed, not past its closing
/// date — and duplicating that rule here would let the two disagree.
class _OpenJobs extends ConsumerWidget {
  const _OpenJobs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(openJobsProvider);
    // Recording an application is a different entitlement from writing the
    // page — a recruiter who cannot edit the page still refers candidates.
    final canRefer = ref
        .watch(permissionControllerProvider)
        .has(RecruitmentPermissions.applicationCreate);

    return AppCard(
      child: async.when(
        loading: () => const Loader(padding: 12),
        error: (error, _) => MessageBanner.error(
          error is ApiException
              ? error.message
              : 'Could not load the open jobs.',
        ),
        data: (jobs) => jobs.isEmpty
            ? Text(
                'Nothing is open. The page will show as having no vacancies '
                'until a job is published.',
                style: TextStyle(color: bos.muted, fontSize: 13, height: 1.5),
              )
            : Column(
                children: [
                  for (final job in jobs)
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
                                  job.title,
                                  style: TextStyle(
                                    color: bos.text,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  [
                                    if (job.departmentName != null)
                                      job.departmentName!,
                                    if (job.location != null) job.location!,
                                  ].join('  ·  '),
                                  style: TextStyle(
                                    color: bos.muted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            job.vacancies == 1
                                ? '1 post'
                                : '${job.vacancies} posts',
                            style: TextStyle(color: bos.muted, fontSize: 11.5),
                          ),
                          if (canRefer)
                            IconButton(
                              tooltip: 'Put somebody forward',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              icon: Icon(
                                Icons.person_add_alt_rounded,
                                size: 17,
                                color: bos.muted,
                              ),
                              onPressed: () =>
                                  showReferCandidateSheet(context, job: job),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

Future<void> showCareerPageSheet(
  BuildContext context, {
  required CareerPageSettings settings,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CareerPageSheet(settings: settings),
    );

class _CareerPageSheet extends ConsumerStatefulWidget {
  const _CareerPageSheet({required this.settings});

  final CareerPageSettings settings;

  @override
  ConsumerState<_CareerPageSheet> createState() => _CareerPageSheetState();
}

class _CareerPageSheetState extends ConsumerState<_CareerPageSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _slug = TextEditingController(text: widget.settings.slug);
  late final _headline =
      TextEditingController(text: widget.settings.headline ?? '');
  late final _about = TextEditingController(text: widget.settings.about ?? '');
  late bool _published = widget.settings.published;

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _slug.dispose();
    _headline.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(careerPageRepositoryProvider).save(
            widget.settings.copyWith(
              slug: _slug.text.trim().toLowerCase(),
              headline: _headline.text.trim(),
              about: _about.text.trim(),
              published: _published,
            ),
          );
      ref.invalidate(careerPageProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      // Two refusals worth passing on as written: a slug that breaks the
      // pattern, and one another company already has.
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save the careers page.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Careers page',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _slug,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Address',
            prefixText: '/careers/',
            helperText: 'Lowercase letters, digits and hyphens.',
          ),
          validator: (value) {
            final slug = value?.trim().toLowerCase() ?? '';
            // The same pattern the backend enforces, checked here so an
            // obvious mistake does not cost a round trip.
            final pattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{1,58}[a-z0-9])?$');
            if (slug.isEmpty) return 'An address, please.';
            if (!pattern.hasMatch(slug)) {
              return 'Lowercase letters, digits and hyphens, not starting or '
                  'ending with one.';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _headline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Headline',
            hintText: 'Join our team',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _about,
          maxLines: 6,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'About',
            hintText: 'What it is like to work here.',
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile.adaptive(
          value: _published,
          onChanged: (value) => setState(() => _published = value),
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Published',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          subtitle: Text(
            'Off takes the page down. Open jobs stay open; they simply stop '
            'being advertised.',
            style: TextStyle(color: bos.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
