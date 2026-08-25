import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'application_detail_screen.dart';
import 'candidate_form_sheet.dart';
import 'recruitment_models.dart';
import 'recruitment_repository.dart';

/// One person, across every job they have ever applied for — `JobApplication`
/// is the per-posting pipeline state, this is what stays true regardless of
/// which posting it was.
class CandidateDetailScreen extends ConsumerStatefulWidget {
  const CandidateDetailScreen({super.key, required this.id});

  final int id;

  static void open(BuildContext context, {required int id}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CandidateDetailScreen(id: id)),
    );
  }

  @override
  ConsumerState<CandidateDetailScreen> createState() =>
      _CandidateDetailScreenState();
}

class _CandidateDetailScreenState extends ConsumerState<CandidateDetailScreen> {
  Candidate? _candidate;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final candidate =
          await ref.read(recruitmentRepositoryProvider).candidate(widget.id);
      if (!mounted) return;
      setState(() {
        _candidate = candidate;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _edit(Candidate candidate) async {
    final updated = await showEditCandidateSheet(context, candidate);
    if (updated == null || !mounted) return;
    // The sheet already told the list; this screen holds its own copy.
    setState(() => _candidate = updated);
  }

  Future<void> _delete(Candidate candidate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${candidate.name}?'),
        content: const Text(
          'They stop appearing in the candidate list. Applications already on '
          'file for them are not removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(candidatesProvider.notifier).delete(candidate.id);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Candidate deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that candidate.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final candidate = _candidate;
    final permissions = ref.watch(permissionControllerProvider);
    final canEdit = permissions.has(RecruitmentPermissions.applicationUpdate);
    final canDelete = permissions.has(RecruitmentPermissions.applicationDelete);

    if (_error != null && candidate == null) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Candidate')),
        body: ErrorState(
          message: _error is ApiException
              ? (_error! as ApiException).message
              : 'Could not load this candidate.',
          onRetry: _load,
        ),
      );
    }

    if (candidate == null) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Candidate')),
        body: const Loader(),
      );
    }

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: Text(candidate.name),
        actions: [
          if (canEdit || canDelete)
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (value) {
                if (value == 'edit') {
                  _edit(candidate);
                } else if (value == 'delete') {
                  _delete(candidate);
                }
              },
              itemBuilder: (context) => [
                if (canEdit)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit candidate'),
                  ),
                if (canDelete)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _Header(candidate: candidate),
            const SizedBox(height: 14),
            _Contact(candidate: candidate),
            const SizedBox(height: 20),
            _Applications(candidateId: candidate.id),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            candidate.name,
            style: TextStyle(
              color: bos.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (candidate.currentTitle?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 2),
            Text(
              candidate.currentTitle!.trim(),
              style: TextStyle(color: bos.textSecondary, fontSize: 13.5),
            ),
          ],
          if (candidate.skills?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              candidate.skills!.trim(),
              style: TextStyle(color: bos.muted, fontSize: 12.5, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: bos.borderLight),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.assignment_outlined, size: 14, color: bos.muted),
              const SizedBox(width: 5),
              Text(
                candidate.applicationCount == 1
                    ? '1 application'
                    : '${candidate.applicationCount} applications',
                style: TextStyle(color: bos.muted, fontSize: 12),
              ),
              if (candidate.source != null) ...[
                const Spacer(),
                Icon(Icons.input_rounded, size: 14, color: bos.muted),
                const SizedBox(width: 5),
                Text(
                  'Via ${Fmt.label(candidate.source).toLowerCase()}',
                  style: TextStyle(color: bos.muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact({required this.candidate});

  final Candidate candidate;

  Future<void> _open(BuildContext context, Uri uri, String failure) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        messenger.showSnackBar(SnackBar(content: Text(failure)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = candidate.phone?.trim();
    final email = candidate.email?.trim();
    final resume = candidate.resumeUrl?.trim();

    final actions = <Widget>[
      if (phone != null && phone.isNotEmpty)
        _Action(
          icon: Icons.call_rounded,
          label: 'Call',
          onTap: () => _open(
            context,
            Uri(scheme: 'tel', path: phone),
            'No app on this device can place a call.',
          ),
        ),
      if (email != null && email.isNotEmpty)
        _Action(
          icon: Icons.mail_outline_rounded,
          label: 'Email',
          onTap: () => _open(
            context,
            Uri(scheme: 'mailto', path: email),
            'No mail app is set up on this device.',
          ),
        ),
      if (resume != null && resume.isNotEmpty)
        _Action(
          icon: Icons.description_outlined,
          label: 'CV',
          onTap: () => _open(context, Uri.parse(resume), 'Could not open that CV.'),
        ),
    ];

    if (actions.isEmpty) {
      return const AppCard(
        child: MessageBanner.info('No contact details on file.'),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: actions[i]),
        ],
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
    );
  }
}

class _Applications extends ConsumerWidget {
  const _Applications({required this.candidateId});

  final int candidateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(candidateApplicationsProvider(candidateId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Applications', icon: Icons.work_history_outlined),
        async.when(
          loading: () => const Loader(padding: 8),
          error: (_, _) => const AppCard(
            child: MessageBanner.info('Could not load their applications.'),
          ),
          data: (applications) {
            if (applications.isEmpty) {
              return const AppCard(
                child: MessageBanner.info('No applications on file.'),
              );
            }
            return Column(
              children: [
                for (final application in applications)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => ApplicationDetailScreen.open(
                        context,
                        id: application.id,
                      ),
                      child: AppCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                application.jobPostingTitle ?? 'Application',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: bos.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            StatusChip(application.status, dense: true),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
