import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/permission_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../../shared/widgets/stat_card.dart';
import 'itam_models.dart';
import 'itam_repository.dart';
import 'license_form_sheet.dart';

/// Who holds a seat on a licence.
class LicenceSeat {
  const LicenceSeat({
    required this.id,
    required this.employeeId,
    this.employeeName,
    this.softwareName,
    this.assignedAt,
  });

  final int id;
  final int employeeId;
  final String? employeeName;
  final String? softwareName;
  final String? assignedAt;

  factory LicenceSeat.fromJson(Map<String, dynamic> json) => LicenceSeat(
        id: (json['id'] as num?)?.toInt() ?? 0,
        employeeId: (json['employeeId'] as num?)?.toInt() ?? 0,
        employeeName: json['employeeName'] as String?,
        softwareName: json['softwareName'] as String?,
        assignedAt: json['assignedAt'] as String?,
      );
}

/// The parts of the software register the list screen does not cover: one
/// licence in full, who is on it, and what is running out.
class SoftwareRepository {
  SoftwareRepository(this._api);

  final ApiClient _api;

  static const _base = '/v1/itam/software';

  Future<SoftwareLicense> licence(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_base/$id');
    return SoftwareLicense.fromJson(json);
  }

  /// Running out soon. A bare list — the backend decides what "soon" means.
  Future<List<SoftwareLicense>> expiring() async {
    final list = await _api.get<List<dynamic>>('$_base/expiring');
    return list
        .whereType<Map<String, dynamic>>()
        .map(SoftwareLicense.fromJson)
        .toList(growable: false);
  }

  /// Already run out.
  Future<List<SoftwareLicense>> expired() async {
    final list = await _api.get<List<dynamic>>('$_base/expired');
    return list
        .whereType<Map<String, dynamic>>()
        .map(SoftwareLicense.fromJson)
        .toList(growable: false);
  }

  /// Editing a licence.
  ///
  /// The DTO also carries a `passwordHash` for the vendor account. It is
  /// deliberately not sent or collected: the response never returns it, so an
  /// edit form has nothing to seed it from, and a shared vendor password typed
  /// into a phone is not something this app should be asking for.
  Future<SoftwareLicense> update(
    int id,
    SoftwareLicenseRequest request,
  ) async {
    final json =
        await _api.patch<Map<String, dynamic>>('$_base/$id', request.toJson());
    return SoftwareLicense.fromJson(json);
  }

  Future<void> delete(int id) => _api.delete<dynamic>('$_base/$id');

  /// Who currently holds a seat.
  Future<List<LicenceSeat>> seats(int id) async {
    final list = await _api.get<List<dynamic>>('$_base/$id/seats');
    return list
        .whereType<Map<String, dynamic>>()
        .map(LicenceSeat.fromJson)
        .toList(growable: false);
  }

  /// Everything one person holds. What offboarding reads to know what to
  /// revoke.
  Future<List<LicenceSeat>> forEmployee(int employeeId) async {
    final list = await _api.get<List<dynamic>>('$_base/employee/$employeeId');
    return list
        .whereType<Map<String, dynamic>>()
        .map(LicenceSeat.fromJson)
        .toList(growable: false);
  }

}

final softwareRepositoryProvider = Provider<SoftwareRepository>(
  (ref) => SoftwareRepository(ref.watch(apiClientProvider)),
);

final licenceProvider =
    FutureProvider.autoDispose.family<SoftwareLicense, int>(
  (ref, id) => ref.read(softwareRepositoryProvider).licence(id),
);

/// What one person holds, for the offboarding checklist.
final licencesHeldProvider =
    FutureProvider.autoDispose.family<List<LicenceSeat>, int>(
  (ref, employeeId) =>
      ref.read(softwareRepositoryProvider).forEmployee(employeeId),
);

final licenceSeatsProvider =
    FutureProvider.autoDispose.family<List<LicenceSeat>, int>(
  (ref, id) => ref.read(softwareRepositoryProvider).seats(id),
);

/// What is running out, and what already has.
final expiringLicencesProvider =
    FutureProvider.autoDispose<List<SoftwareLicense>>((ref) {
  ref.watch(currentUserProvider);
  return ref.read(softwareRepositoryProvider).expiring();
});

final expiredLicencesProvider =
    FutureProvider.autoDispose<List<SoftwareLicense>>((ref) {
  ref.watch(currentUserProvider);
  return ref.read(softwareRepositoryProvider).expired();
});

/// One licence: what it is, what it costs, and who is on it.
class SoftwareDetailScreen extends ConsumerStatefulWidget {
  const SoftwareDetailScreen({super.key, required this.licence});

  final SoftwareLicense licence;

  static void open(BuildContext context, {required SoftwareLicense licence}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SoftwareDetailScreen(licence: licence),
      ),
    );
  }

  @override
  ConsumerState<SoftwareDetailScreen> createState() =>
      _SoftwareDetailScreenState();
}

class _SoftwareDetailScreenState extends ConsumerState<SoftwareDetailScreen> {
  bool _busy = false;

  Future<void> _act(
    Future<void> Function(ItamRepository repo) action,
    String success,
    String failure,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(itamRepositoryProvider));
      // Seats and the licence's own counts both move.
      ref.invalidate(licenceSeatsProvider(widget.licence.id));
      ref.invalidate(licenceProvider(widget.licence.id));
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      // "No seats available" lands here — a real answer, not a fault.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(SoftwareLicense licence) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${licence.softwareName}?',
      message: licence.seatsUsed > 0
          ? '${licence.seatsUsed} people are on it. They lose their seats and '
              'the licence goes from the register.'
          : 'It goes from the register. Nothing else is affected.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(softwareRepositoryProvider).delete(licence.id);
      await ref.read(licensesProvider.notifier).refresh();
      messenger.showSnackBar(
        SnackBar(content: Text('${licence.softwareName} removed.')),
      );
      if (mounted) navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that licence.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign() async {
    final person = await EmployeePicker.show(
      context,
      title: 'Who needs a seat?',
    );
    if (person == null || !mounted) return;
    await _act(
      (repo) => repo.assignSeat(widget.licence.id, person.id),
      '${person.fullName} has a seat.',
      'Could not assign that seat.',
    );
  }

  Future<void> _release(LicenceSeat seat) async {
    final who = seat.employeeName ?? 'that person';
    final confirmed = await confirmAction(
      context,
      title: 'Take the seat back?',
      message:
          '$who loses access to this software. The seat becomes free for '
          'somebody else.',
      action: 'Release it',
    );
    if (!confirmed || !mounted) return;
    await _act(
      (repo) => repo.releaseSeat(widget.licence.id, seat.employeeId),
      'Seat released.',
      'Could not release that seat.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    // Seeded from the row that opened this, and replaced by the fresh copy as
    // soon as it lands, so seat counts stay honest after an assignment.
    final licence =
        ref.watch(licenceProvider(widget.licence.id)).value ?? widget.licence;
    // Seats have their own code — assigning one is not the same right as
    // adding a licence to the register.
    // Seats have their own code — assigning one is not the same right as
    // adding a licence to the register.
    final permissions = ref.watch(permissionControllerProvider);
    final canManage = permissions.has(ItamPermissions.softwareAssign);
    final canRegister = permissions.has(ItamPermissions.softwareCreate);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: Text(licence.softwareName),
        actions: [
          if (canRegister)
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (value) => value == 'edit'
                  ? showNewLicenseSheet(context, existing: licence)
                  : _delete(licence),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Remove from the register',
                    style: TextStyle(color: bos.danger),
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: canManage && licence.hasSeatsFree
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _assign,
              backgroundColor: bos.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt_rounded),
              label: const Text('Assign a seat'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Seats used',
                  value: '${licence.seatsUsed}',
                  suffix: 'of ${licence.totalSeatsLicensed}',
                  icon: Icons.event_seat_outlined,
                  // No seats left is worth flagging: the next person who asks
                  // cannot be given one.
                  tone: licence.hasSeatsFree ? null : bos.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: licence.expired ? 'Expired' : 'Expires',
                  value: licence.licenseExpiryDate == null
                      ? null
                      : Fmt.dateShort(licence.licenseExpiryDate),
                  suffix: licence.daysUntilExpiry == null
                      ? null
                      : licence.expired
                          ? '${licence.daysUntilExpiry!.abs()} days ago'
                          : 'in ${licence.daysUntilExpiry} days',
                  icon: Icons.event_busy_outlined,
                  tone: licence.expired
                      ? bos.danger
                      : licence.expiringSoon
                          ? bos.warning
                          : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          if (licence.publisher != null) licence.publisher!,
                          if (licence.version != null) licence.version!,
                        ].join(' · '),
                        style: TextStyle(color: bos.muted, fontSize: 12.5),
                      ),
                    ),
                    if (licence.licenseStatus != null)
                      StatusChip(licence.licenseStatus!, dense: true),
                  ],
                ),
                if (licence.licenseType != null ||
                    licence.vendor != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (licence.licenseType != null)
                        Fmt.label(licence.licenseType),
                      if (licence.vendor != null)
                        'bought from ${licence.vendor}',
                    ].join(' · '),
                    style: TextStyle(color: bos.text, fontSize: 13),
                  ),
                ],
                if (licence.notes != null && licence.notes!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    licence.notes!,
                    style:
                        TextStyle(color: bos.muted, fontSize: 12.5, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionHeader('Who is on it', icon: Icons.people_outline_rounded),
          const SizedBox(height: 10),
          if (_busy)
            const Loader(padding: 12)
          else
            ref.watch(licenceSeatsProvider(licence.id)).when(
                  loading: () => const Loader(padding: 12),
                  error: (error, _) => ErrorState(
                    message: error is ApiException
                        ? error.message
                        : 'Could not load the seat holders.',
                    onRetry: () =>
                        ref.invalidate(licenceSeatsProvider(licence.id)),
                  ),
                  data: (seats) {
                    if (seats.isEmpty) {
                      return const EmptyState(
                        icon: Icons.event_seat_outlined,
                        title: 'Nobody yet',
                        message:
                            'Assign a seat and whoever holds it appears here.',
                      );
                    }
                    return Column(
                      children: [
                        for (final seat in seats)
                          ConfigRow(
                            title: seat.employeeName ??
                                'Employee ${seat.employeeId}',
                            active: true,
                            subtitle: seat.assignedAt == null
                                ? null
                                : 'since ${Fmt.date(seat.assignedAt)}',
                            actions: [
                              if (canManage)
                                RowAction(
                                  label: 'Take the seat back',
                                  destructive: true,
                                  onSelected: () => _release(seat),
                                ),
                            ],
                          ),
                      ],
                    );
                  },
                ),
        ],
      ),
    );
  }
}

/// What is running out, and what already has.
///
/// Its own screen rather than a filter on the register: renewals are a job
/// somebody does on a particular day, not a way of browsing software.
class LicenceRenewalsScreen extends ConsumerWidget {
  const LicenceRenewalsScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LicenceRenewalsScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Renewals'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Running out'), Tab(text: 'Expired')],
          ),
        ),
        body: TabBarView(
          children: [
            _LicenceList(
              provider: expiringLicencesProvider,
              emptyTitle: 'Nothing running out',
              emptyMessage:
                  'No licence is close enough to its expiry date to need '
                  'attention yet.',
            ),
            _LicenceList(
              provider: expiredLicencesProvider,
              emptyTitle: 'Nothing expired',
              emptyMessage:
                  'Every licence on the register is still in date.',
            ),
          ],
        ),
      ),
    );
  }
}

class _LicenceList extends ConsumerWidget {
  const _LicenceList({
    required this.provider,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final FutureProvider<List<SoftwareLicense>> provider;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ConfigList<SoftwareLicense>(
      async: ref.watch(provider),
      onRefresh: () async => ref.invalidate(provider),
      emptyIcon: Icons.event_available_outlined,
      emptyTitle: emptyTitle,
      emptyMessage: emptyMessage,
      errorMessage: 'Could not load the licences.',
      itemBuilder: (context, licence) => ConfigRow(
        title: licence.softwareName,
        // An expired licence is drawn muted — it is not in force.
        active: !licence.expired,
        inactiveLabel: 'Expired',
        subtitle: [
          if (licence.publisher != null) licence.publisher!,
          '${licence.seatsUsed} of ${licence.totalSeatsLicensed} seats',
          if (licence.licenseExpiryDate != null)
            Fmt.date(licence.licenseExpiryDate),
        ].join(' · '),
        trailingLabel: licence.daysUntilExpiry == null
            ? null
            : licence.expired
                ? '${licence.daysUntilExpiry!.abs()} days ago'
                : 'in ${licence.daysUntilExpiry}d',
        onEdit: () => SoftwareDetailScreen.open(context, licence: licence),
      ),
    );
  }
}
