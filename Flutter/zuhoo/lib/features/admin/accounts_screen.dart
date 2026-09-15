
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/paged_controller.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/search_field.dart';

/// Somebody with a login to this company.
///
/// Not the same thing as an employee: a company's users are its owner, its
/// employees and its portal clients, and the same person can be more than one
/// of those. The list keeps only the strongest membership per person rather
/// than showing them twice.
class CompanyUser {
  const CompanyUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.active,
    required this.emailVerified,
    this.email,
    this.phone,
    this.image,
    this.role,
    this.customRoleName,
    this.membership,
    this.createdAt,
  });

  final int id;
  final String firstName;
  final String lastName;
  final bool active;

  /// Somebody who has never confirmed their email cannot sign in, which is
  /// the usual explanation for "the account you set up does not work".
  final bool emailVerified;

  final String? email;
  final String? phone;
  final String? image;

  /// The built-in role their account carries.
  final String? role;

  /// The custom role on top of it, when they have one. That is what actually
  /// decides their permissions.
  final String? customRoleName;

  /// OWNER, EMPLOYEE or CLIENT.
  final String? membership;

  final String? createdAt;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final first = firstName.trim();
    final last = lastName.trim();
    if (first.isEmpty && last.isEmpty) return '?';
    if (last.isEmpty) return first[0].toUpperCase();
    return '${first.isEmpty ? "" : first[0]}${last[0]}'.toUpperCase();
  }

  factory CompanyUser.fromJson(Map<String, dynamic> json) => CompanyUser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        active: json['active'] as bool? ?? false,
        emailVerified: json['emailVerified'] as bool? ?? false,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        image: json['image'] as String?,
        role: json['role'] as String?,
        customRoleName: json['customRoleName'] as String?,
        membership: json['membership'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

class AccountsRepository {
  AccountsRepository(this._api);

  final ApiClient _api;

  /// Everybody with a login to this company.
  ///
  /// Refused for an account with no company — platform staff, who have their
  /// own screens for this.
  Future<PagedResponse<CompanyUser>> users({
    String? keyword,
    String? membership,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '/users',
        CompanyUser.fromJson,
        page: page,
        size: size,
        query: {'keyword': keyword, 'membership': membership},
      );
}

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => AccountsRepository(ref.watch(apiClientProvider)),
);

class AccountSearchController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? keyword) {
    final trimmed = keyword?.trim();
    final next = trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (state == next) return;
    state = next;
  }
}

final accountSearchProvider =
    NotifierProvider<AccountSearchController, String?>(
  AccountSearchController.new,
);

class AccountMembershipController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? membership) {
    if (state == membership) return;
    state = membership;
  }
}

final accountMembershipProvider =
    NotifierProvider<AccountMembershipController, String?>(
  AccountMembershipController.new,
);

class AccountsController extends AsyncNotifier<PagedState<CompanyUser>>
    with PagedLoader<CompanyUser> {
  @override
  Future<PagedState<CompanyUser>> build() {
    ref.watch(currentUserProvider);
    ref.watch(accountSearchProvider);
    ref.watch(accountMembershipProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<CompanyUser>> fetchPage(int page) =>
      ref.read(accountsRepositoryProvider).users(
            keyword: ref.read(accountSearchProvider),
            membership: ref.read(accountMembershipProvider),
            page: page,
          );
}

final accountsProvider =
    AsyncNotifierProvider<AccountsController, PagedState<CompanyUser>>(
  AccountsController.new,
);

/// Who can sign in.
///
/// A different question from the People directory, which is about employment.
/// This is about access: who has a login, what it lets them do, and whether it
/// works at all.
class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
    );
  }

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final controller = ref.read(accountsProvider.notifier);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Who can sign in')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AppSearchField(
              hint: 'A name or an email',
              onChanged: (value) =>
                  ref.read(accountSearchProvider.notifier).set(value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: FilterBar(
              selected: ref.watch(accountMembershipProvider),
              onSelected: ref.read(accountMembershipProvider.notifier).set,
              options: const [
                (value: null, label: 'Everyone'),
                (value: 'OWNER', label: 'Owner'),
                (value: 'EMPLOYEE', label: 'Staff'),
                (value: 'CLIENT', label: 'Clients'),
              ],
            ),
          ),
          Expanded(
            child: PagedListView<CompanyUser>(
              async: ref.watch(accountsProvider),
              onRefresh: controller.refresh,
              onLoadMore: controller.loadMore,
              emptyIcon: Icons.person_outline_rounded,
              emptyTitle: 'Nobody here',
              emptyMessage: 'No account matches that.',
              errorMessage: 'Could not load the accounts.',
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemBuilder: (context, user) => _AccountRow(user: user),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.user});

  final CompanyUser user;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: [
            Avatar(
              initials: user.initials,
              imageUrl: user.image,
              size: 38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (user.email != null)
                    Text(
                      user.email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (user.membership != null) Fmt.label(user.membership),
                      // The custom role is what actually decides what they
                      // can do; the built-in one is only a fallback.
                      if (user.customRoleName != null)
                        user.customRoleName!
                      else if (user.role != null)
                        Fmt.label(user.role),
                    ].join('  ·  '),
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusChip(
                  user.active ? 'ACTIVE' : 'INACTIVE',
                  label: user.active ? 'Active' : 'Disabled',
                  dense: true,
                ),
                if (!user.emailVerified)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      // Worth calling out: this is the usual reason an
                      // account somebody set up does not work.
                      'not verified',
                      style: TextStyle(color: bos.warning, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
