import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/attachment_picker.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../website/website_screen.dart';
import 'company_models.dart';
import 'company_repository.dart';
import 'public_company_screen.dart';

/// The company as it sees itself.
///
/// Everything here is what a client eventually sees on an invoice or a portal
/// page, which is why it is worth getting right and worth being able to
/// correct from a phone.
class CompanyScreen extends ConsumerWidget {
  const CompanyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(myCompanyProvider);
    final canEdit = ref
        .watch(permissionControllerProvider)
        .hasAny(CompanyPermissions.editAny);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Your company'),
        actions: [
          if (async.value?.subdomain != null) ...[
            IconButton(
              tooltip: 'Your public page',
              icon: const Icon(Icons.public_outlined),
              onPressed: () => PublicCompanyScreen.open(
                context,
                subdomain: async.value!.subdomain!,
              ),
            ),
            IconButton(
              tooltip: 'Your website',
              icon: const Icon(Icons.language_outlined),
              onPressed: () => WebsiteScreen.open(
                context,
                subdomain: async.value!.subdomain!,
              ),
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async => ref.invalidate(myCompanyProvider),
        child: async.when(
          loading: () => const Loader(),
          error: (error, _) => ErrorState(
            // An account with no company — platform staff, typically — gets a
            // refusal rather than an empty record, and the backend says so.
            message: error is ApiException
                ? error.message
                : 'Could not load your company.',
            onRetry: () => ref.invalidate(myCompanyProvider),
          ),
          data: (company) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _Header(company: company),
              if (company.trialExpired) ...[
                const SizedBox(height: 12),
                MessageBanner.warning(
                  'The trial has run out. Some things will stop working until '
                  'a plan is chosen.',
                ),
              ],
              const SizedBox(height: 20),
              _Section(
                title: 'Getting in touch',
                icon: Icons.contact_page_outlined,
                onEdit: canEdit
                    ? () => showCompanySheet(
                          context,
                          company: company,
                          part: CompanyPart.contact,
                        )
                    : null,
                facts: [
                  ('Phone', company.companyPhone),
                  ('Website', company.website),
                  // Neither of these is on the update request at all, so
                  // they are shown as settled facts rather than as fields.
                  ('Email', company.companyEmail),
                  ('Portal address', company.subdomain),
                ],
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'On invoices',
                icon: Icons.receipt_long_outlined,
                onEdit: canEdit
                    ? () => showCompanySheet(
                          context,
                          company: company,
                          part: CompanyPart.money,
                        )
                    : null,
                facts: [
                  ('Tax number', company.taxRegistrationNumber),
                  ('Currency', company.baseCurrency),
                  (
                    'Year starts',
                    company.fiscalYearStartMonth == null
                        ? null
                        : Fmt.monthName(company.fiscalYearStartMonth!)
                  ),
                  ('Bank', company.bankName),
                  ('Account name', company.bankAccountName),
                  ('Account number', company.bankAccountNumber),
                  ('Branch', company.bankBranch),
                ],
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'What clients see',
                icon: Icons.storefront_outlined,
                onEdit: canEdit
                    ? () => showCompanySheet(
                          context,
                          company: company,
                          part: CompanyPart.portal,
                        )
                    : null,
                facts: [
                  ('Tagline', company.tagline),
                  ('About', company.portalAbout),
                ],
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'Your plan',
                icon: Icons.card_membership_outlined,
                // Set by the platform, not by the company. Shown so somebody
                // knows what they are on, never edited here.
                facts: [
                  ('Plan', company.subscriptionPlan),
                  ('Status', Fmt.label(company.status)),
                  ('From', Fmt.dateShort(company.subscriptionStart)),
                  ('Until', Fmt.dateShort(company.subscriptionEnd)),
                  ('Owner', company.ownerName),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerStatefulWidget {
  const _Header({required this.company});

  final CompanyProfile company;

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  bool _busy = false;

  Future<void> _changeLogo() async {
    final picked = await pickAttachment(context);
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // The logo is a URL on the record, not bytes: the file goes to the
      // avatar endpoint first, which checks it really is an image.
      final uploaded = await ref
          .read(apiClientProvider)
          .uploadAvatar(picked.path, picked.name);

      await ref
          .read(companyRepositoryProvider)
          .updateMe(CompanyProfileRequest(logo: uploaded.fileUrl));
      ref.invalidate(myCompanyProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Logo changed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change the logo.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final company = widget.company;
    final canEdit = ref
        .watch(permissionControllerProvider)
        .hasAny(CompanyPermissions.editAny);

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          // Tapping the logo replaces it, which nothing about an avatar
          // says out loud: without this a screen reader announces the
          // company's initial and no action.
          Semantics(
            button: canEdit,
            label: canEdit ? 'Change the company logo' : null,
            child: GestureDetector(
              onTap: canEdit && !_busy ? _changeLogo : null,
              child: _busy
                  ? const SizedBox(
                      height: 56,
                      width: 56,
                      child: Center(
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : Avatar(
                      initials: company.companyName.isEmpty
                          ? '?'
                          : company.companyName[0].toUpperCase(),
                      imageUrl: company.logo,
                      size: 56,
                    ),
            ),
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
                    style: TextStyle(color: bos.muted, fontSize: 12.5),
                  ),
                if (company.location != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      company.location!,
                      style: TextStyle(color: bos.muted, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.facts,
    this.onEdit,
  });

  final String title;
  final IconData icon;
  final List<(String, String?)> facts;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final filled = facts.where((fact) => fact.$2?.trim().isNotEmpty == true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          icon: icon,
          trailing: onEdit == null
              ? null
              : TextButton(onPressed: onEdit, child: const Text('Edit')),
        ),
        AppCard(
          child: filled.isEmpty
              ? Text(
                  'Nothing recorded.',
                  style: TextStyle(color: bos.muted, fontSize: 13),
                )
              : Column(
                  children: [
                    for (final fact in filled)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 108,
                              child: Text(
                                fact.$1,
                                style: TextStyle(
                                  color: bos.muted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                fact.$2!,
                                style: TextStyle(
                                  color: bos.text,
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Which part of the record a sheet is editing.
///
/// Three narrow forms rather than one long one: contact details, banking, and
/// what the portal shows are edited by different people at different times,
/// and a single form of seventeen fields is a form nobody finishes.
enum CompanyPart { contact, money, portal }

Future<void> showCompanySheet(
  BuildContext context, {
  required CompanyProfile company,
  required CompanyPart part,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CompanySheet(company: company, part: part),
    );

class _CompanySheet extends ConsumerStatefulWidget {
  const _CompanySheet({required this.company, required this.part});

  final CompanyProfile company;
  final CompanyPart part;

  @override
  ConsumerState<_CompanySheet> createState() => _CompanySheetState();
}

class _CompanySheetState extends ConsumerState<_CompanySheet> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields = {
    for (final entry in _initialValues.entries)
      entry.key: TextEditingController(text: entry.value ?? ''),
  };
  late int? _fiscalMonth = widget.company.fiscalYearStartMonth;

  String? _error;
  bool _busy = false;

  Map<String, String?> get _initialValues => switch (widget.part) {
        CompanyPart.contact => {
            'companyName': widget.company.companyName,
            'companyPhone': widget.company.companyPhone,
            'website': widget.company.website,
          },
        CompanyPart.money => {
            'taxRegistrationNumber': widget.company.taxRegistrationNumber,
            'baseCurrency': widget.company.baseCurrency,
            'bankName': widget.company.bankName,
            'bankAccountName': widget.company.bankAccountName,
            'bankAccountNumber': widget.company.bankAccountNumber,
            'bankBranch': widget.company.bankBranch,
          },
        CompanyPart.portal => {
            'tagline': widget.company.tagline,
            'portalAbout': widget.company.portalAbout,
          },
      };

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _read(String key) {
    final text = _fields[key]?.text.trim();
    return text == null || text.isEmpty ? null : text;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final request = switch (widget.part) {
      CompanyPart.contact => CompanyProfileRequest(
          companyName: _read('companyName'),
          companyPhone: _read('companyPhone'),
          website: _read('website'),
        ),
      CompanyPart.money => CompanyProfileRequest(
          taxRegistrationNumber: _read('taxRegistrationNumber'),
          baseCurrency: _read('baseCurrency'),
          bankName: _read('bankName'),
          bankAccountName: _read('bankAccountName'),
          bankAccountNumber: _read('bankAccountNumber'),
          bankBranch: _read('bankBranch'),
          fiscalYearStartMonth: _fiscalMonth,
        ),
      CompanyPart.portal => CompanyProfileRequest(
          tagline: _read('tagline'),
          portalAbout: _read('portalAbout'),
        ),
    };

    try {
      await ref.read(companyRepositoryProvider).updateMe(request);
      ref.invalidate(myCompanyProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save that.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: switch (widget.part) {
        CompanyPart.contact => 'Getting in touch',
        CompanyPart.money => 'On invoices',
        CompanyPart.portal => 'What clients see',
      },
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save',
      submitting: _busy,
      onSubmit: _submit,
      children: switch (widget.part) {
        CompanyPart.contact => [
            TextFormField(
              controller: _fields['companyName'],
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? 'A name, please.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fields['companyPhone'],
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fields['website'],
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Website'),
            ),
            const SizedBox(height: 10),
            Text(
              'The registered email and the portal address cannot be changed '
              'here — every link a client already has depends on them.',
              style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
            ),
          ],
        CompanyPart.money => [
            TextFormField(
              controller: _fields['taxRegistrationNumber'],
              decoration: const InputDecoration(labelText: 'Tax number'),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _fields['baseCurrency'],
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Currency'),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      return text.length == 3 ? null : 'Three letters.';
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _fiscalMonth,
                    decoration:
                        const InputDecoration(labelText: 'Year starts'),
                    items: [
                      for (var month = 1; month <= 12; month++)
                        DropdownMenuItem(
                          value: month,
                          child: Text(Fmt.monthName(month)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _fiscalMonth = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fields['bankName'],
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Bank'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fields['bankAccountName'],
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Account name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fields['bankAccountNumber'],
              decoration: const InputDecoration(labelText: 'Account number'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fields['bankBranch'],
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Branch'),
            ),
            const SizedBox(height: 10),
            Text(
              'These appear on every invoice you issue.',
              style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
            ),
          ],
        CompanyPart.portal => [
            TextFormField(
              controller: _fields['tagline'],
              decoration: const InputDecoration(
                labelText: 'Tagline',
                hintText: 'The one line under your name.',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fields['portalAbout'],
              maxLines: 6,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'About'),
            ),
            const SizedBox(height: 10),
            Text(
              'Shown on your client portal, where anybody with the link can '
              'read it.',
              style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
            ),
          ],
      },
    );
  }
}
