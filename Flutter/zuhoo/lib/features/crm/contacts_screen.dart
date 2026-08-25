import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'crm_models.dart';
import 'crm_repository.dart';

/// The people at client companies, and the tags used to describe anything in
/// CRM.
///
/// Two tabs because they answer the same kind of question — who and what is
/// this — and because neither is big enough to earn a screen of its own.
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Contacts')),
        body: const Loader(),
      );
    }

    final tabs = <({String label, Widget view, VoidCallback? create})>[
      if (permissions.has(CrmPermissions.contactView))
        (label: 'People', view: const _ContactsTab(), create: null),
      if (permissions.has(CrmPermissions.tagView))
        (
          label: 'Tags',
          view: const _TagsTab(),
          create: permissions.has(CrmPermissions.tagManage)
              ? () => showTagSheet(context)
              : null,
        ),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Contacts')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message: 'Contacts and tags need the CRM permissions.',
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: tabController,
            builder: (context, _) {
              final create = tabs[tabController.index].create;
              return Scaffold(
                backgroundColor: bos.bgPage,
                appBar: AppBar(
                  title: const Text('Contacts'),
                  bottom: TabBar(
                    tabs: [for (final tab in tabs) Tab(text: tab.label)],
                  ),
                ),
                floatingActionButton: create == null
                    ? null
                    : FloatingActionButton.extended(
                        onPressed: create,
                        backgroundColor: bos.brand,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New'),
                      ),
                body: TabBarView(children: [for (final tab in tabs) tab.view]),
              );
            },
          );
        },
      ),
    );
  }
}

/// Free-text search across every contact.
class ContactSearchController extends Notifier<String> {
  @override
  String build() => '';

  void set(String keyword) {
    final trimmed = keyword.trim();
    if (state == trimmed) return;
    state = trimmed;
  }
}

final contactSearchProvider =
    NotifierProvider<ContactSearchController, String>(
  ContactSearchController.new,
);

class AllContactsController extends AsyncNotifier<List<ClientContact>> {
  @override
  Future<List<ClientContact>> build() {
    ref.watch(currentUserProvider);
    ref.watch(contactSearchProvider);
    return _load();
  }

  Future<List<ClientContact>> _load() async {
    final page = await ref
        .read(crmRepositoryProvider)
        .allContacts(keyword: ref.read(contactSearchProvider));
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }
}

final allContactsProvider =
    AsyncNotifierProvider<AllContactsController, List<ClientContact>>(
  AllContactsController.new,
);

/// One client's contacts, for the client's own screen.
final contactsForClientProvider =
    FutureProvider.autoDispose.family<List<ClientContact>, int>(
  (ref, clientId) => ref.read(crmRepositoryProvider).contactsFor(clientId),
);

class TagsController extends AsyncNotifier<List<Tag>> {
  @override
  Future<List<Tag>> build() {
    ref.watch(currentUserProvider);
    return ref.read(crmRepositoryProvider).tags();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(crmRepositoryProvider).tags(),
    );
  }

  void apply(Tag updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }

  void remove(int id) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current)
        if (row.id != id) row,
    ]);
  }
}

final tagsProvider =
    AsyncNotifierProvider<TagsController, List<Tag>>(TagsController.new);

// ── People ────────────────────────────────────────────────────

class _ContactsTab extends ConsumerStatefulWidget {
  const _ContactsTab();

  @override
  ConsumerState<_ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<_ContactsTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConfigList<ClientContact>(
      async: ref.watch(allContactsProvider),
      onRefresh: ref.read(allContactsProvider.notifier).refresh,
      emptyIcon: Icons.contacts_outlined,
      emptyTitle: ref.watch(contactSearchProvider).isEmpty
          ? 'No contacts yet'
          : 'Nobody matches',
      emptyMessage:
          'A contact is a person at a client company. They are added from the '
          'client they belong to.',
      errorMessage: 'Could not load the contacts.',
      header: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search by name, email or company',
            prefixIcon: Icon(Icons.search_rounded),
            isDense: true,
          ),
          onSubmitted: ref.read(contactSearchProvider.notifier).set,
        ),
      ),
      itemBuilder: (context, contact) => ConfigRow(
        title: contact.fullName,
        active: true,
        subtitle: [
          if (contact.clientCompanyName != null) contact.clientCompanyName!,
          if (contact.role.isNotEmpty) contact.role,
          if (contact.email != null) contact.email!,
        ].join(' · '),
        trailingLabel: contact.primaryContact ? 'primary' : null,
      ),
    );
  }
}

/// Everybody at one client, with the actions that only make sense there.
///
/// A contact belongs to a client, so adding and editing one happens from the
/// client rather than from the flat list — the flat list has no client to
/// attach a new person to.
class ClientContactsScreen extends ConsumerStatefulWidget {
  const ClientContactsScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  final int clientId;
  final String clientName;

  static void open(
    BuildContext context, {
    required int clientId,
    required String clientName,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClientContactsScreen(
          clientId: clientId,
          clientName: clientName,
        ),
      ),
    );
  }

  @override
  ConsumerState<ClientContactsScreen> createState() =>
      _ClientContactsScreenState();
}

class _ClientContactsScreenState extends ConsumerState<ClientContactsScreen> {
  int? _busyId;

  Future<void> _act(
    int id,
    Future<void> Function() action,
    String success,
    String failure,
  ) async {
    setState(() => _busyId = id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      ref.invalidate(contactsForClientProvider(widget.clientId));
      await ref.read(allContactsProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(ClientContact contact) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${contact.fullName}?',
      message: contact.primaryContact
          ? 'They are the primary contact for this client, so somebody else '
              'will need promoting afterwards.'
          : 'They stop appearing against this client.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;
    final repo = ref.read(crmRepositoryProvider);
    await _act(
      contact.id,
      () => repo.deleteContact(widget.clientId, contact.id),
      '${contact.fullName} removed.',
      'Could not remove that contact.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);
    final canWrite = permissions.has(CrmPermissions.contactUpdate);
    final canDelete = permissions.has(CrmPermissions.contactDelete);
    final repo = ref.read(crmRepositoryProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: Text(widget.clientName)),
      floatingActionButton: permissions.has(CrmPermissions.contactCreate)
          ? FloatingActionButton.extended(
              onPressed: () =>
                  showContactSheet(context, clientId: widget.clientId),
              backgroundColor: bos.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt_rounded),
              label: const Text('Add'),
            )
          : null,
      body: ConfigList<ClientContact>(
        async: ref.watch(contactsForClientProvider(widget.clientId)),
        onRefresh: () async =>
            ref.invalidate(contactsForClientProvider(widget.clientId)),
        emptyIcon: Icons.contacts_outlined,
        emptyTitle: 'Nobody yet',
        emptyMessage:
            'Add the people you deal with at ${widget.clientName}. One of them '
            'is the primary contact.',
        errorMessage: 'Could not load the contacts.',
        itemBuilder: (context, contact) => ConfigRow(
          title: contact.fullName,
          active: true,
          subtitle: [
            if (contact.role.isNotEmpty) contact.role,
            if (contact.email != null) contact.email!,
            if (contact.phone != null) contact.phone!,
          ].join(' · '),
          trailingLabel: contact.primaryContact ? 'primary' : null,
          busy: _busyId == contact.id,
          onEdit: canWrite
              ? () => showContactSheet(
                    context,
                    clientId: widget.clientId,
                    existing: contact,
                  )
              : null,
          actions: [
            // Promotion only — there is no demoting somebody, because a client
            // always has exactly one primary.
            if (canWrite && !contact.primaryContact)
              RowAction(
                label: 'Make primary',
                onSelected: () => _act(
                  contact.id,
                  () => repo.makePrimaryContact(widget.clientId, contact.id),
                  '${contact.fullName} is now the primary contact.',
                  'Could not change the primary contact.',
                ),
              ),
            if (canDelete)
              RowAction(
                label: 'Remove',
                destructive: true,
                onSelected: () => _delete(contact),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Tags ──────────────────────────────────────────────────────

class _TagsTab extends ConsumerStatefulWidget {
  const _TagsTab();

  @override
  ConsumerState<_TagsTab> createState() => _TagsTabState();
}

class _TagsTabState extends ConsumerState<_TagsTab> {
  int? _busyId;

  Future<void> _delete(Tag tag) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove "${tag.name}"?',
      message:
          'Anything currently tagged with it loses the tag. The records '
          'themselves are untouched.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = tag.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(crmRepositoryProvider).deleteTag(tag.id);
      ref.read(tagsProvider.notifier).remove(tag.id);
      messenger.showSnackBar(SnackBar(content: Text('"${tag.name}" removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that tag.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        ref.watch(permissionControllerProvider).has(CrmPermissions.tagManage);

    return ConfigList<Tag>(
      async: ref.watch(tagsProvider),
      onRefresh: ref.read(tagsProvider.notifier).refresh,
      emptyIcon: Icons.sell_outlined,
      emptyTitle: 'No tags yet',
      emptyMessage:
          'Tags are one shared vocabulary used across leads, clients and '
          'opportunities — rather than free text typed afresh each time.',
      errorMessage: 'Could not load the tags.',
      itemBuilder: (context, tag) => _TagRow(
        tag: tag,
        busy: _busyId == tag.id,
        onEdit: canManage ? () => showTagSheet(context, existing: tag) : null,
        onDelete: canManage ? () => _delete(tag) : null,
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.busy,
    this.onEdit,
    this.onDelete,
  });

  final Tag tag;
  final bool busy;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: [
            // The colour is the point of a tag, so it leads. A value the
            // backend stored that will not parse falls back to neutral rather
            // than crashing the row.
            Container(
              height: 14,
              width: 14,
              decoration: BoxDecoration(
                color: tag.argb == null ? bos.muted : Color(tag.argb!),
                shape: BoxShape.circle,
                border: Border.all(color: bos.borderLight),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tag.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bos.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (onEdit != null || onDelete != null)
              PopupMenuButton<String>(
                onSelected: (value) =>
                    value == 'edit' ? onEdit?.call() : onDelete?.call(),
                itemBuilder: (context) => [
                  if (onEdit != null)
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Remove',
                        style: TextStyle(color: bos.danger),
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

// ── Sheets ────────────────────────────────────────────────────

Future<void> showContactSheet(
  BuildContext context, {
  required int clientId,
  ClientContact? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ContactSheet(clientId: clientId, existing: existing),
  );
}

class _ContactSheet extends ConsumerStatefulWidget {
  const _ContactSheet({required this.clientId, this.existing});

  final int clientId;
  final ClientContact? existing;

  @override
  ConsumerState<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends ConsumerState<_ContactSheet> {
  final _formKey = GlobalKey<FormState>();

  late final _fullName =
      TextEditingController(text: widget.existing?.fullName ?? '');
  late final _email =
      TextEditingController(text: widget.existing?.email ?? '');
  late final _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late final _jobTitle =
      TextEditingController(text: widget.existing?.jobTitle ?? '');
  late final _department =
      TextEditingController(text: widget.existing?.department ?? '');
  late final _notes =
      TextEditingController(text: widget.existing?.notes ?? '');

  /// Only offered when they are not already the primary — there is no
  /// demoting, because a client always has exactly one.
  bool _makePrimary = false;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _email,
      _phone,
      _jobTitle,
      _department,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(crmRepositoryProvider);
    final request = ClientContactRequest(
      fullName: _fullName.text,
      email: _email.text,
      phone: _phone.text,
      jobTitle: _jobTitle.text,
      department: _department.text,
      notes: _notes.text,
      primaryContact: _makePrimary ? true : null,
    );

    try {
      if (_isEdit) {
        await repo.updateContact(widget.clientId, widget.existing!.id, request);
      } else {
        await repo.createContact(widget.clientId, request);
      }
      ref.invalidate(contactsForClientProvider(widget.clientId));
      await ref.read(allContactsProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Contact updated.' : 'Contact added.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that contact.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? Function(String?) _max(int limit) => (value) {
        final trimmed = value?.trim() ?? '';
        return trimmed.length > limit ? '$limit characters at most.' : null;
      };

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final alreadyPrimary = widget.existing?.primaryContact ?? false;

    return FormSheetFrame(
      title: _isEdit ? 'Edit contact' : 'New contact',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add contact',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _fullName,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          maxLength: 150,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.person_outline_rounded),
            counterText: '',
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email (optional)',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
          validator: _max(255),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone (optional)',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          validator: _max(30),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _jobTitle,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Job title'),
                validator: _max(100),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _department,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Department'),
                validator: _max(100),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notes,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            alignLabelWithHint: true,
          ),
        ),
        if (alreadyPrimary) ...[
          const SizedBox(height: 12),
          Text(
            'They are the primary contact for this client.',
            style: TextStyle(color: bos.muted, fontSize: 12.5),
          ),
        ] else ...[
          const SizedBox(height: 4),
          SwitchListTile(
            value: _makePrimary,
            onChanged: (value) => setState(() => _makePrimary = value),
            title: Text(
              'Make them the primary contact',
              style: TextStyle(color: bos.text, fontSize: 14),
            ),
            subtitle: Text(
              'Whoever holds it now loses it — there is only one',
              style: TextStyle(color: bos.muted, fontSize: 11.5),
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ],
    );
  }
}

/// The eight colours a tag can be.
///
/// A fixed set rather than a colour picker: tags are meant to be told apart at
/// a glance, and a free picker produces eight shades of the same blue.
const _tagColours = <String>[
  '#367C2B',
  '#2563EB',
  '#7C3AED',
  '#DB2777',
  '#DC2626',
  '#EA580C',
  '#CA8A04',
  '#0F766E',
];

Future<void> showTagSheet(BuildContext context, {Tag? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TagSheet(existing: existing),
  );
}

class _TagSheet extends ConsumerStatefulWidget {
  const _TagSheet({this.existing});

  final Tag? existing;

  @override
  ConsumerState<_TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends ConsumerState<_TagSheet> {
  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _colour = _seedColour;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  /// Matches the stored colour to one of the eight when it is one of them, so
  /// editing a tag does not silently change its colour.
  String get _seedColour {
    final stored = widget.existing?.color;
    if (stored == null) return _tagColours.first;
    final normalised =
        stored.startsWith('#') ? stored.toUpperCase() : '#${stored.toUpperCase()}';
    return _tagColours.contains(normalised) ? normalised : _tagColours.first;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(crmRepositoryProvider);
    final request = TagRequest(name: _name.text, color: _colour);

    try {
      if (_isEdit) {
        final updated = await repo.updateTag(widget.existing!.id, request);
        ref.read(tagsProvider.notifier).apply(updated);
      } else {
        await repo.createTag(request);
        await ref.read(tagsProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Tag updated.' : 'Tag added.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that tag.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: _isEdit ? 'Edit tag' : 'New tag',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add tag',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.sell_outlined),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        const SizedBox(height: 18),
        Text(
          'Colour',
          style: TextStyle(
            color: bos.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final colour in _tagColours)
              InkWell(
                onTap: () => setState(() => _colour = colour),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: 34,
                  width: 34,
                  decoration: BoxDecoration(
                    color: Color(
                      int.parse(colour.substring(1), radix: 16) | 0xFF000000,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colour == _colour ? bos.text : bos.borderLight,
                      width: colour == _colour ? 2.5 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
