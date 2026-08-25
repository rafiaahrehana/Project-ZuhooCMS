import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/primitives.dart';
import 'application_detail_screen.dart';
import 'candidate_detail_screen.dart';
import 'candidate_form_sheet.dart';
import 'interview_feedback_sheet.dart';
import 'job_posting_form_sheet.dart';
import 'recruitment_kpi_screen.dart';
import 'recruitment_models.dart';
import 'recruitment_repository.dart';

/// Hiring.
///
/// Postings and applications are separate entitlements — somebody may manage
/// job adverts without reviewing candidates, or the reverse — so each tab is
/// gated on its own and disappears rather than erroring.
class RecruitmentScreen extends ConsumerWidget {
  const RecruitmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Hiring')),
        body: const Loader(),
      );
    }

    final canJobs = permissions.has(RecruitmentPermissions.jobView);
    final canApplications =
        permissions.has(RecruitmentPermissions.applicationView);

    final tabs = <({String label, Widget view})>[
      if (canJobs) (label: 'Jobs', view: const _JobsTab()),
      if (canApplications) ...[
        (label: 'Applicants', view: const _ApplicationsTab()),
        // Interviews, candidates and the talent pool are all gated on the
        // application permissions too, rather than each carrying its own —
        // they are different views onto the same pipeline, not separate
        // entitlements. This matches the talent pool endpoints' own gate
        // (APPLICATION_VIEW/APPLICATION_UPDATE); the candidates endpoint is
        // actually role-only server-side, so gating it here too is only ever
        // more conservative than the backend, never less.
        (label: 'Interviews', view: const _InterviewsTab()),
        (label: 'Candidates', view: const _CandidatesTab()),
        (label: 'Talent pool', view: const _TalentPoolTab()),
      ],
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Hiring')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Job postings and applications each need their own permission. '
              'Your HR team can grant them.',
        ),
      );
    }

    // Two of the five tabs have something to create. Both are keyed on the
    // tab's label rather than its index, because which tabs exist depends on
    // what the reader is allowed to see.
    final createOn = <String, ({String label, IconData icon, Future<void> Function(BuildContext) open})>{
      if (permissions.has(RecruitmentPermissions.jobCreate))
        'Jobs': (
          label: 'New posting',
          icon: Icons.post_add_rounded,
          open: showNewJobPostingSheet,
        ),
      if (permissions.has(RecruitmentPermissions.applicationUpdate))
        'Talent pool': (
          label: 'Add to pool',
          icon: Icons.person_add_alt_rounded,
          open: showAddToTalentPoolSheet,
        ),
    };

    return DefaultTabController(
      length: tabs.length,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: tabController,
            builder: (context, _) {
              final action = createOn[tabs[tabController.index].label];
              return Scaffold(
                backgroundColor: bos.bgPage,
                appBar: AppBar(
                  title: const Text('Hiring'),
                  actions: [
                    IconButton(
                      onPressed: () => RecruitmentKpiScreen.open(context),
                      tooltip: 'How hiring is going',
                      icon: const Icon(Icons.insights_outlined),
                    ),
                  ],
                  bottom: TabBar(
                    // Five tabs' worth of labels do not fit a phone width
                    // evenly; scrolling beats truncating "Talent pool" into
                    // nothing useful.
                    isScrollable: tabs.length > 3,
                    tabAlignment: tabs.length > 3 ? TabAlignment.start : null,
                    tabs: [for (final t in tabs) Tab(text: t.label)],
                  ),
                ),
                floatingActionButton: action == null
                    ? null
                    : FloatingActionButton.extended(
                        onPressed: () => action.open(context),
                        backgroundColor: bos.brand,
                        foregroundColor: Colors.white,
                        icon: Icon(action.icon),
                        label: Text(action.label),
                      ),
                body: TabBarView(children: [for (final t in tabs) t.view]),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Jobs ──────────────────────────────────────────────────────

class _JobsTab extends ConsumerWidget {
  const _JobsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PagedListView<JobPosting>(
      async: ref.watch(jobsProvider),
      onRefresh: () => ref.read(jobsProvider.notifier).refresh(),
      onLoadMore: () => ref.read(jobsProvider.notifier).loadMore(),
      emptyTitle: 'No job postings',
      emptyMessage: 'Roles your team is hiring for appear here.',
      emptyIcon: Icons.work_outline_rounded,
      errorMessage: 'Could not load job postings.',
      itemBuilder: (context, job) => _JobCard(job: job),
    );
  }
}

class _JobCard extends ConsumerStatefulWidget {
  const _JobCard({required this.job});

  final JobPosting job;

  @override
  ConsumerState<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends ConsumerState<_JobCard> {
  bool _busy = false;

  Future<void> _run(Future<JobPosting> Function() action, String success) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await action();
      ref.read(jobsProvider.notifier).apply(updated);
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that posting.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Puts a recruiter on the posting.
  ///
  /// The backend takes the id in a body rather than a path segment, which is
  /// why the repository wraps it — see `assignRecruiter`.
  Future<void> _assignRecruiter() async {
    final person = await EmployeePicker.show(
      context,
      title: 'Who is recruiting for this?',
    );
    if (person == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(jobsProvider.notifier)
          .assignRecruiter(widget.job.id, person.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${person.fullName} is recruiting for this.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not assign that recruiter.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close ${widget.job.title}?'),
        content: const Text(
          'It stops accepting applications and comes off the careers page. '
          'Applications already in the pipeline are unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close posting'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(recruitmentRepositoryProvider).closeJob(widget.job.id),
      '${widget.job.title} is closed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final job = widget.job;
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(RecruitmentPermissions.jobUpdate);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (job.departmentName != null)
                        Text(
                          job.departmentName!,
                          style: TextStyle(
                            color: bos.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(job.status, dense: true),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (job.whereLabel != null)
                  _Meta(icon: Icons.place_outlined, text: job.whereLabel!),
                if (job.employmentType != null)
                  _Meta(
                    icon: Icons.schedule_outlined,
                    text: Fmt.label(job.employmentType),
                  ),
                _Meta(
                  icon: Icons.groups_outlined,
                  text: job.vacancies == 1
                      ? '1 vacancy'
                      : '${job.vacancies} vacancies',
                ),
              ],
            ),
            if (job.deadlinePassed) ...[
              const SizedBox(height: 10),
              MessageBanner.warning(
                'The deadline passed on ${Fmt.date(job.deadline)} but this '
                'posting is still open.',
              ),
            ],
            if (canUpdate) ...[
              const SizedBox(height: 12),
              if (_busy)
                const Loader(padding: 6)
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Editing stays open at every stage — the wording of a
                    // live posting is the thing most often wrong.
                    OutlinedButton.icon(
                      onPressed: () =>
                          showNewJobPostingSheet(context, existing: job),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _assignRecruiter,
                      icon: const Icon(Icons.person_add_alt_rounded, size: 16),
                      label: Text(
                        job.assignedRecruiterName == null
                            ? 'Assign a recruiter'
                            : 'Change recruiter',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                      ),
                    ),
                    if (job.canPublish)
                      FilledButton.icon(
                        onPressed: () => _run(
                          () => ref
                              .read(recruitmentRepositoryProvider)
                              .publishJob(job.id),
                          '${job.title} is live.',
                        ),
                        icon: const Icon(Icons.publish_rounded, size: 16),
                        label: Text(job.isDraft ? 'Publish' : 'Reopen'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                    if (job.canClose)
                      OutlinedButton.icon(
                        onPressed: _close,
                        icon: const Icon(Icons.block_rounded, size: 16),
                        label: const Text('Close'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: bos.danger,
                          side: BorderSide(
                            color: bos.danger.withValues(alpha: 0.4),
                          ),
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: bos.muted),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: bos.muted, fontSize: 11.5)),
      ],
    );
  }
}

// ── Applications ──────────────────────────────────────────────

class _ApplicationsTab extends ConsumerWidget {
  const _ApplicationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const _StageFilter(),
        Expanded(
          child: PagedListView<JobApplication>(
            async: ref.watch(applicationsProvider),
            onRefresh: () => ref.read(applicationsProvider.notifier).refresh(),
            onLoadMore: () => ref.read(applicationsProvider.notifier).loadMore(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            emptyTitle: 'No applicants',
            emptyMessage: 'Nobody has applied at this stage yet.',
            emptyIcon: Icons.person_search_outlined,
            errorMessage: 'Could not load applications.',
            itemBuilder: (context, application) =>
                _ApplicationRow(application: application),
          ),
        ),
      ],
    );
  }
}

class _StageFilter extends ConsumerWidget {
  const _StageFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(applicationFilterProvider);
    const stages = ApplicationStatus.pipeline;

    return SizedBox(
      height: scaledStripHeight(context, 44),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: stages.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final status = i == 0 ? null : stages[i - 1];
          return _FilterChip(
            label: status == null ? 'All' : Fmt.label(status),
            active: selected == status,
            onTap: () => ref
                .read(applicationFilterProvider.notifier)
                .set(selected == status ? null : status),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: active ? bos.brand : bos.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? bos.brand : bos.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : bos.textSecondary,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ApplicationRow extends StatelessWidget {
  const _ApplicationRow({required this.application});

  final JobApplication application;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => ApplicationDetailScreen.open(context, id: application.id),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          application.personLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (application.jobPostingTitle != null)
                          Text(
                            application.jobPostingTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: bos.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(application.status, dense: true),
                ],
              ),
              if (application.overallScore != null ||
                  application.atsScore != null) ...[
                const SizedBox(height: 9),
                Row(
                  children: [
                    if (application.overallScore != null)
                      _Meta(
                        icon: Icons.star_outline_rounded,
                        text:
                            'Scored ${application.overallScore!.toStringAsFixed(1)}',
                      ),
                    if (application.overallScore != null &&
                        application.atsScore != null)
                      const SizedBox(width: 12),
                    if (application.atsScore != null)
                      _Meta(
                        icon: Icons.auto_awesome_outlined,
                        text: 'CV match ${application.atsScore}',
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Interviews ────────────────────────────────────────────────

class _InterviewsTab extends ConsumerWidget {
  const _InterviewsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PagedListView<Interview>(
      async: ref.watch(upcomingInterviewsProvider),
      onRefresh: () => ref.read(upcomingInterviewsProvider.notifier).refresh(),
      onLoadMore: () => ref.read(upcomingInterviewsProvider.notifier).loadMore(),
      emptyTitle: 'Nothing scheduled',
      emptyMessage: 'Interviews still to happen appear here, soonest first.',
      emptyIcon: Icons.event_available_outlined,
      errorMessage: 'Could not load interviews.',
      itemBuilder: (context, interview) =>
          InterviewCard(interview: interview, showApplicant: true),
    );
  }
}

// ── Candidates ────────────────────────────────────────────────

class _CandidatesTab extends ConsumerWidget {
  const _CandidatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _SearchField(
          hint: 'Search candidates',
          onChanged: (v) => ref.read(candidateSearchProvider.notifier).set(v),
        ),
        Expanded(
          child: PagedListView<Candidate>(
            async: ref.watch(candidatesProvider),
            onRefresh: () => ref.read(candidatesProvider.notifier).refresh(),
            onLoadMore: () => ref.read(candidatesProvider.notifier).loadMore(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            emptyTitle: 'No candidates',
            emptyMessage: 'Everyone who has ever applied appears here.',
            emptyIcon: Icons.people_outline_rounded,
            errorMessage: 'Could not load candidates.',
            itemBuilder: (context, candidate) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () =>
                    CandidateDetailScreen.open(context, id: candidate.id),
                child: AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              candidate.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (candidate.currentTitle?.trim().isNotEmpty ==
                                true)
                              Text(
                                candidate.currentTitle!.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context).bos.textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Meta(
                        icon: Icons.assignment_outlined,
                        text: '${candidate.applicationCount}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Talent pool ───────────────────────────────────────────────

class _TalentPoolTab extends ConsumerWidget {
  const _TalentPoolTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(RecruitmentPermissions.applicationUpdate);

    return Column(
      children: [
        _SearchField(
          hint: 'Search the talent pool',
          onChanged: (v) => ref.read(talentPoolSearchProvider.notifier).set(v),
        ),
        Expanded(
          child: PagedListView<TalentPoolCandidate>(
            async: ref.watch(talentPoolProvider),
            onRefresh: () => ref.read(talentPoolProvider.notifier).refresh(),
            onLoadMore: () => ref.read(talentPoolProvider.notifier).loadMore(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            emptyTitle: 'Nobody pooled yet',
            emptyMessage:
                'A rejected or withdrawn applicant worth keeping warm for '
                'next time can be pooled from their application.',
            emptyIcon: Icons.star_outline_rounded,
            errorMessage: 'Could not load the talent pool.',
            itemBuilder: (context, candidate) =>
                _PoolCard(candidate: candidate, canUpdate: canUpdate),
          ),
        ),
      ],
    );
  }
}

class _PoolCard extends ConsumerStatefulWidget {
  const _PoolCard({required this.candidate, required this.canUpdate});

  final TalentPoolCandidate candidate;
  final bool canUpdate;

  @override
  ConsumerState<_PoolCard> createState() => _PoolCardState();
}

class _PoolCardState extends ConsumerState<_PoolCard> {
  bool _busy = false;

  Future<void> _call(BuildContext context, String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await launchUrl(
        Uri(scheme: 'tel', path: phone),
        mode: LaunchMode.externalApplication,
      )) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No app on this device can place a call.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No app on this device can place a call.')),
      );
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${widget.candidate.name}?'),
        content: const Text('They come out of the talent pool. This does not '
            'affect any application on file for them.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(recruitmentRepositoryProvider)
          .removeFromTalentPool(widget.candidate.id);
      ref.read(talentPoolProvider.notifier).removeCandidate(widget.candidate.id);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that candidate.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final candidate = widget.candidate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (candidate.desiredRole?.trim().isNotEmpty == true)
                        Text(
                          candidate.desiredRole!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: bos.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                    ],
                  ),
                ),
                if (candidate.rating != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.star_rounded, size: 15, color: bos.warning),
                  const SizedBox(width: 2),
                  Text(
                    '${candidate.rating}',
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
            if (candidate.sourceJobTitle != null ||
                candidate.reason != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (candidate.sourceJobTitle != null)
                    _Meta(
                      icon: Icons.work_outline_rounded,
                      text: 'From ${candidate.sourceJobTitle}',
                    ),
                  if (candidate.reason != null)
                    _Meta(icon: Icons.info_outline_rounded, text: Fmt.label(candidate.reason)),
                ],
              ),
            ],
            if (candidate.notes?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                candidate.notes!.trim(),
                style: TextStyle(color: bos.textSecondary, fontSize: 12.5, height: 1.35),
              ),
            ],
            const SizedBox(height: 10),
            if (_busy)
              const Loader(padding: 6)
            else
              Row(
                children: [
                  if (candidate.phone?.trim().isNotEmpty == true)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _call(context, candidate.phone!),
                        icon: const Icon(Icons.call_outlined, size: 15),
                        label: const Text('Call'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                    ),
                  if (candidate.phone?.trim().isNotEmpty == true &&
                      widget.canUpdate)
                    const SizedBox(width: 8),
                  if (widget.canUpdate) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            showEditTalentPoolSheet(context, candidate),
                        icon: const Icon(Icons.edit_outlined, size: 15),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _remove,
                        icon: const Icon(Icons.delete_outline_rounded, size: 15),
                        label: const Text('Remove'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: bos.danger,
                          side: BorderSide(color: bos.danger.withValues(alpha: 0.4)),
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 400), () => widget.onChanged(value));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _controller,
        onChanged: _onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Clear',
                  onPressed: () {
                    _controller.clear();
                    _debounce?.cancel();
                    widget.onChanged('');
                    setState(() {});
                  },
                ),
        ),
      ),
    );
  }
}
