import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/providers.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/attachment_launcher.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/attachment_picker.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../../shared/widgets/timeline.dart';
import 'performance_models.dart';
import 'performance_repository.dart';
import 'review_form_sheet.dart';

/// One appraisal in full.
class ReviewDetailScreen extends ConsumerStatefulWidget {
  const ReviewDetailScreen({super.key, required this.review});

  final PerformanceReview review;

  static void open(BuildContext context, {required PerformanceReview review}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewDetailScreen(review: review),
      ),
    );
  }

  @override
  ConsumerState<ReviewDetailScreen> createState() => _ReviewDetailScreenState();
}

class _ReviewDetailScreenState extends ConsumerState<ReviewDetailScreen> {
  late PerformanceReview _review = widget.review;
  bool _busy = false;

  Future<void> _edit(PerformanceReview review) async {
    final updated = await showEditReviewSheet(context, review);
    if (updated == null || !mounted) return;
    // The sheet already told the list; this screen holds its own copy, and the
    // overall score it now shows is the one the server recomputed.
    setState(() => _review = updated);
  }

  Future<void> _run(
    Future<PerformanceReview> Function() action,
    String success,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await action();
      ref.read(teamReviewsProvider.notifier).apply(updated);
      ref.invalidate(myReviewsProvider);
      if (!mounted) return;
      setState(() => _review = updated);
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update this review.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finalise() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalise this review?'),
        content: Text(
          'It becomes a signed record for ${_review.personLabel} and cannot be '
          'changed or reopened afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finalise'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _run(
      () => ref.read(performanceRepositoryProvider).finalise(_review.id),
      'Review finalised.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final review = _review;
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(PerformancePermissions.update);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: Text(review.personLabel),
        actions: [
          // A finalised review is a signed record; the backend refuses to edit
          // one, so the action disappears rather than failing.
          if (canUpdate && !review.finalised)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit review',
              onPressed: _busy ? null : () => _edit(review),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Header(review: review),
          if (canUpdate && (review.canAdvance || review.canFinalise)) ...[
            const SizedBox(height: 16),
            if (_busy)
              const Loader(padding: 8)
            else
              Row(
                children: [
                  if (review.canAdvance)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _run(
                          () => ref
                              .read(performanceRepositoryProvider)
                              .advance(review.id),
                          'Moved on.',
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                        label: const Text('Advance stage'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ),
                  if (review.canFinalise)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _finalise,
                        icon: const Icon(Icons.lock_outline_rounded, size: 17),
                        label: const Text('Finalise'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ),
                ],
              ),
          ],
          if (review.hasScores) ...[
            const SizedBox(height: 20),
            _Scores(review: review),
          ],
          if (review.goalCompletionPercent != null) ...[
            const SizedBox(height: 16),
            _Goals(percent: review.goalCompletionPercent!),
          ],
          for (final section in review.narrative) ...[
            const SizedBox(height: 18),
            SectionHeader(section.title, icon: Icons.notes_rounded),
            AppCard(
              child: Text(
                section.body,
                style: TextStyle(color: bos.text, fontSize: 13.5, height: 1.45),
              ),
            ),
          ],
          if (review.aiSummary?.trim().isNotEmpty != true && !review.finalised)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'No summary yet. The assistant can draft one from the '
                      'scores and the notes above.',
                      style: TextStyle(
                        color: bos.muted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LoadingButton(
                      label: 'Draft a summary',
                      icon: Icons.auto_awesome_outlined,
                      loading: _busy,
                      onPressed: () => _run(
                        () => ref
                            .read(performanceRepositoryProvider)
                            .summarise(_review.id),
                        'Summary drafted.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (review.aiSummary?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 18),
            const SectionHeader('Summary', icon: Icons.auto_awesome_outlined),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Labelled every time it is shown. A machine's précis of
                  // somebody's year must never be mistaken for their manager's
                  // words.
                  Text(
                    'Written by the assistant, not by a person.',
                    style: TextStyle(
                      color: bos.muted,
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    review.aiSummary!.trim(),
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          _Kpis(review: review),
          const SizedBox(height: 18),
          _Attachments(review: review, editable: !review.finalised),
          const SizedBox(height: 18),
          _Trail(review: review),
        ],
      ),
    );
  }
}

/// The objective figures for the period the review covers.
///
/// Recomputed on every read from attendance, leave, tasks and client ratings
/// rather than stored on the review, so it agrees with those modules rather
/// than with whatever was true when the review was written.
class _Kpis extends ConsumerWidget {
  const _Kpis({required this.review});

  final PerformanceReview review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final employeeId = review.employeeId;
    final from = review.reviewPeriodStart;
    final to = review.reviewPeriodEnd;

    // All three are required by the endpoint, and a review without a period is
    // not unusual - there is simply nothing to compute over.
    if (employeeId == null || from == null || to == null) {
      return const SizedBox.shrink();
    }

    final async = ref.watch(
      reviewKpisProvider((employeeId: employeeId, from: from, to: to)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('The figures', icon: Icons.query_stats_rounded),
        AppCard(
          child: async.when(
            loading: () => const Loader(padding: 16),
            error: (error, _) => MessageBanner.error(
              error is ApiException
                  ? error.message
                  : 'Could not work out the figures for this period.',
            ),
            data: (kpis) => !kpis.hasAnything
                ? Text(
                    'Nothing was recorded over this period, so there are no '
                    'figures to show.',
                    style: TextStyle(
                      color: bos.muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  )
                : Column(
                    children: [
                      _Kpi(
                        'Attendance',
                        // A dash, not a zero: null means nothing was recorded,
                        // which is not the same as never turning up.
                        kpis.attendancePercent == null
                            ? null
                            : Fmt.percent(kpis.attendancePercent),
                      ),
                      _Kpi(
                        'Days present',
                        '${kpis.daysPresent} of ${kpis.workingDaysRecorded}',
                      ),
                      if (kpis.daysAbsent > 0)
                        _Kpi('Days absent', '${kpis.daysAbsent}'),
                      if (kpis.lateArrivals > 0)
                        _Kpi('Late arrivals', '${kpis.lateArrivals}'),
                      _Kpi('Leave taken', '${kpis.leaveDaysTaken} days'),
                      _Kpi('Tasks completed', '${kpis.tasksCompleted}'),
                      _Kpi('Projects completed', '${kpis.projectsCompleted}'),
                      _Kpi(
                        'Client rating',
                        kpis.customerSatisfaction == null
                            ? null
                            : '${kpis.customerSatisfaction!.toStringAsFixed(1)} '
                                  'out of 5',
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value);

  final String label;

  /// Null renders as a dash, and deliberately so - see [PerformanceKpis].
  final String? value;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: bos.muted, fontSize: 12.5),
            ),
          ),
          Text(
            value ?? Fmt.dash,
            style: TextStyle(
              color: value == null ? bos.muted : bos.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Files kept with the review.
class _Attachments extends ConsumerStatefulWidget {
  const _Attachments({required this.review, required this.editable});

  final PerformanceReview review;
  final bool editable;

  @override
  ConsumerState<_Attachments> createState() => _AttachmentsState();
}

class _AttachmentsState extends ConsumerState<_Attachments> {
  bool _busy = false;

  Future<void> _add() async {
    final picked = await pickAttachment(context);
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Two steps, as the backend intends: the file goes to the generic
      // upload endpoint, and only the URL it answers with is recorded here.
      final uploaded = await ref
          .read(apiClientProvider)
          .uploadDocument(picked.path, picked.name);

      await ref
          .read(performanceRepositoryProvider)
          .addAttachment(
            widget.review.id,
            ReviewAttachmentRequest(
              fileName: uploaded.fileName,
              fileUrl: uploaded.fileUrl,
            ),
          );
      ref.invalidate(reviewAttachmentsProvider(widget.review.id));
      messenger.showSnackBar(const SnackBar(content: Text('Added.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not attach that file.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ReviewAttachment attachment) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${attachment.fileName}?',
      message: 'It stops being part of this review.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(performanceRepositoryProvider)
          .deleteAttachment(widget.review.id, attachment.id);
      ref.invalidate(reviewAttachmentsProvider(widget.review.id));
      messenger.showSnackBar(const SnackBar(content: Text('Removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that file.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(reviewAttachmentsProvider(widget.review.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Files',
          icon: Icons.attach_file_rounded,
          trailing: widget.editable && !_busy
              ? TextButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Attach'),
                )
              : null,
        ),
        AppCard(
          child: _busy
              ? const Loader(padding: 12)
              : async.when(
                  loading: () => const Loader(padding: 12),
                  error: (error, _) => MessageBanner.error(
                    error is ApiException
                        ? error.message
                        : 'Could not load the files.',
                  ),
                  data: (attachments) => attachments.isEmpty
                      ? Text(
                          'Nothing attached.',
                          style: TextStyle(color: bos.muted, fontSize: 13),
                        )
                      : Column(
                          children: [
                            for (final attachment in attachments)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => openAttachmentUrl(
                                    context,
                                    attachment.fileUrl,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.insert_drive_file_outlined,
                                        size: 16,
                                        color: bos.muted,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              attachment.label ??
                                                  attachment.fileName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: bos.brandInk,
                                                fontSize: 13,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                            if (attachment.uploadedByName !=
                                                null)
                                              Text(
                                                attachment.uploadedByName!,
                                                style: TextStyle(
                                                  color: bos.muted,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (widget.editable)
                                        IconButton(
                                          // Named, because a row of bare
                                          // crosses tells a screen reader
                                          // nothing about which one it is on.
                                          tooltip:
                                              'Remove '
                                              '${attachment.label ?? attachment.fileName}',
                                          onPressed: () => _remove(attachment),
                                          icon: Icon(
                                            Icons.close_rounded,
                                            size: 17,
                                            color: bos.muted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.review});

  final PerformanceReview review;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      padding: const EdgeInsets.all(18),
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
                      review.period == null
                          ? 'Review'
                          : '${Fmt.date(review.reviewPeriodStart)} – '
                                '${Fmt.date(review.reviewPeriodEnd)}',
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (review.reviewedByName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Reviewed by ${review.reviewedByName}',
                        style: TextStyle(
                          color: bos.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (review.overallScore != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      review.overallScore!.toStringAsFixed(1),
                      style: TextStyle(
                        color: bos.brand,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    Text(
                      'overall',
                      style: TextStyle(color: bos.muted, fontSize: 11),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              StatusChip(
                review.finalised ? 'COMPLETED' : review.stage,
                label: review.finalised ? 'Finalised' : review.stageLabel,
                dense: true,
              ),
              if (review.performanceLevel != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    Fmt.label(review.performanceLevel),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bos.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (review.promotionRecommendation != null ||
              review.promotionReadiness != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: bos.borderLight),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.trending_up_rounded, size: 15, color: bos.muted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    [
                      if (review.promotionRecommendation != null)
                        Fmt.label(review.promotionRecommendation),
                      if (review.promotionReadiness != null)
                        Fmt.label(review.promotionReadiness),
                    ].join(' · '),
                    style: TextStyle(color: bos.textSecondary, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Scores extends StatelessWidget {
  const _Scores({required this.review});

  final PerformanceReview review;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final scores = review.filledScores;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Scores', icon: Icons.equalizer_rounded),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < scores.length; i++) ...[
                if (i > 0) const SizedBox(height: 13),
                Row(
                  children: [
                    SizedBox(
                      width: 118,
                      child: Text(
                        scores[i].label,
                        style: TextStyle(
                          color: bos.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          // Scores are out of 10 throughout the appraisal form.
                          value: (scores[i].value! / 10).clamp(0, 1).toDouble(),
                          minHeight: 5,
                          backgroundColor: bos.neutralSoft,
                          valueColor: AlwaysStoppedAnimation(bos.brand),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${scores[i].value}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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

class _Goals extends StatelessWidget {
  const _Goals({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Goals completed',
              style: TextStyle(color: bos.textSecondary, fontSize: 13),
            ),
          ),
          Text(
            '$percent%',
            style: TextStyle(
              color: percent >= 80
                  ? bos.success
                  : percent >= 50
                  ? bos.brandInk
                  : bos.warning,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Who signed off which stage and when. `POST /{id}/advance` stamps a
/// timestamp and an actor name for the stage it just moved past, so this
/// renders every one the review has actually cleared plus when the review
/// itself was opened — the full audit trail of an appraisal, not just its
/// creation date.
class _Trail extends StatelessWidget {
  const _Trail({required this.review});

  final PerformanceReview review;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    if (review.createdAt == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('History', icon: Icons.history_rounded),
        AppCard(
          child: Timeline(
            railColor: bos.border,
            tiles: [
              TimelineTile(
                dotColor: bos.muted,
                child: _TrailEntry(
                  title: 'Review opened',
                  at: review.createdAt,
                ),
              ),
              for (final stage in review.stageHistory)
                TimelineTile(
                  // Clearing final approval is what finalises the review, so
                  // that one stage gets the "done" colour instead of the
                  // plain in-progress one every other cleared stage gets.
                  dotColor: stage.stage == PerformanceStage.finalApproval
                      ? bos.success
                      : bos.statusColors(stage.stage).fg,
                  child: _TrailEntry(
                    title: stage.stage == PerformanceStage.finalApproval
                        ? 'Finalised'
                        : PerformanceStage.labels[stage.stage] ?? stage.stage,
                    at: stage.at,
                    by: stage.by,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrailEntry extends StatelessWidget {
  const _TrailEntry({required this.title, this.at, this.by});

  final String title;
  final String? at;
  final String? by;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: bos.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              Fmt.relative(at),
              style: TextStyle(color: bos.muted, fontSize: 11),
            ),
          ],
        ),
        if (by != null && by!.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text('by $by', style: TextStyle(color: bos.muted, fontSize: 11.5)),
        ],
      ],
    );
  }
}
