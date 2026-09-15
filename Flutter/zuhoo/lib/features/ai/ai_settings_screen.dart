import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../../shared/widgets/stat_card.dart';
import 'ai_admin_models.dart';
import 'ai_repository.dart';

final aiConfigsProvider =
    FutureProvider.autoDispose<List<AiProviderConfig>>((ref) {
  return ref.read(aiRepositoryProvider).configs();
});

final aiTemplatesProvider =
    FutureProvider.autoDispose<List<AiPromptTemplate>>((ref) async {
  final page = await ref.read(aiRepositoryProvider).templates();
  return page.content;
});

final aiUsageProvider = FutureProvider.autoDispose<AiUsageSummary>((ref) {
  return ref.read(aiRepositoryProvider).usage();
});

/// Configuring the assistant rather than talking to it.
///
/// Everything here is `AI_ADMIN`. Whoever holds it decides which provider the
/// whole company's assistant runs on and what it is told to say, which is why
/// it lives well away from the chat screen.
class AiSettingsScreen extends StatelessWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Assistant settings'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Providers'),
              Tab(text: 'Prompts'),
              Tab(text: 'Usage'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_ProvidersTab(), _TemplatesTab(), _UsageTab()],
        ),
      ),
    );
  }
}

// ── Providers ─────────────────────────────────────────────────

class _ProvidersTab extends ConsumerWidget {
  const _ProvidersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        ConfigList<AiProviderConfig>(
          async: ref.watch(aiConfigsProvider),
          onRefresh: () async => ref.invalidate(aiConfigsProvider),
          emptyIcon: Icons.smart_toy_outlined,
          emptyTitle: 'No provider saved',
          emptyMessage:
              'The assistant needs somewhere to send its questions. Save a '
              'provider and its key to switch it on.',
          errorMessage: 'Could not load the providers.',
          itemBuilder: (context, config) => _ConfigRow(config: config),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => showProviderSheet(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a provider'),
          ),
        ),
      ],
    );
  }
}

class _ConfigRow extends ConsumerStatefulWidget {
  const _ConfigRow({required this.config});

  final AiProviderConfig config;

  @override
  ConsumerState<_ConfigRow> createState() => _ConfigRowState();
}

class _ConfigRowState extends ConsumerState<_ConfigRow> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(AiRepository) action,
    String done,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(aiRepositoryProvider));
      ref.invalidate(aiConfigsProvider);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That did not go through.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${AiProviderType.label(widget.config.provider)}?',
      message: widget.config.active
          ? 'This is the provider in use. Removing it leaves the assistant '
              'with nowhere to send questions until another is made active.'
          : 'The saved key goes with it. Adding the provider again means '
              'entering the key again.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;
    await _run((repo) => repo.deleteConfig(widget.config.id), 'Removed.');
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;

    final facts = <String>[
      Fmt.label(config.model),
      if (config.temperature != null) 'temperature ${config.temperature}',
      if (config.maxTokens > 0) '${config.maxTokens} tokens',
    ];

    return ConfigRow(
      title: AiProviderType.label(config.provider),
      subtitle: facts.join(' · '),
      active: config.active,
      inactiveLabel: 'Standby',
      busy: _busy,
      onEdit: () => showProviderSheet(context, config: config),
      actions: [
        if (!config.active)
          RowAction(
            label: 'Use this one',
            onSelected: () => _run(
              (repo) => repo.activateConfig(config.id),
              'The assistant now uses '
              '${AiProviderType.label(config.provider)}.',
            ),
          ),
        RowAction(label: 'Remove', destructive: true, onSelected: _delete),
      ],
    );
  }
}

/// Saving a provider.
///
/// The key field is left blank on an edit and only sent when something is
/// typed into it: the stored key is encrypted and never returned, so there is
/// nothing to prefill, and a blank one is understood as "keep what you have".
Future<void> showProviderSheet(
  BuildContext context, {
  AiProviderConfig? config,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProviderSheet(config: config),
    );

class _ProviderSheet extends ConsumerStatefulWidget {
  const _ProviderSheet({this.config});

  final AiProviderConfig? config;

  @override
  ConsumerState<_ProviderSheet> createState() => _ProviderSheetState();
}

class _ProviderSheetState extends ConsumerState<_ProviderSheet> {
  final _formKey = GlobalKey<FormState>();
  final _apiKey = TextEditingController();
  late final TextEditingController _temperature = TextEditingController(
    text: widget.config?.temperature?.toString() ?? '',
  );
  late final TextEditingController _maxTokens = TextEditingController(
    text: (widget.config?.maxTokens ?? 0) > 0
        ? widget.config!.maxTokens.toString()
        : '',
  );

  late String _provider = widget.config?.provider ?? AiProviderType.gemini;
  late String _model =
      widget.config?.model ?? AiProviderType.modelsFor(_provider).first;

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _apiKey.dispose();
    _temperature.dispose();
    _maxTokens.dispose();
    super.dispose();
  }

  void _setProvider(String? provider) {
    if (provider == null || provider == _provider) return;
    setState(() {
      _provider = provider;
      // The model list is provider-specific, so the old choice is almost
      // certainly not in it any more.
      _model = AiProviderType.modelsFor(provider).first;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // A brand-new provider with no key would save and then fail on the first
    // question, with an error from the provider rather than from here.
    if (widget.config == null && _apiKey.text.trim().isEmpty &&
        _provider != AiProviderType.mock) {
      setState(() => _error = 'A new provider needs its key.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(aiRepositoryProvider).saveConfig(
            AiProviderConfigRequest(
              provider: _provider,
              model: _model,
              apiKey: _apiKey.text,
              temperature: double.tryParse(_temperature.text.trim()),
              maxTokens: int.tryParse(_maxTokens.text.trim()),
            ),
          );
      ref.invalidate(aiConfigsProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save that provider.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: widget.config == null ? 'Add a provider' : 'Edit provider',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save and use it',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _provider,
          decoration: const InputDecoration(labelText: 'Provider'),
          items: [
            for (final value in AiProviderType.all)
              DropdownMenuItem(
                value: value,
                child: Text(AiProviderType.label(value)),
              ),
          ],
          onChanged: _setProvider,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _model,
          decoration: const InputDecoration(labelText: 'Model'),
          items: [
            for (final value in AiProviderType.modelsFor(_provider))
              DropdownMenuItem(value: value, child: Text(Fmt.label(value))),
          ],
          onChanged: (value) => setState(() => _model = value ?? _model),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _apiKey,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'API key',
            hintText: widget.config == null
                ? 'From the provider'
                : 'Leave blank to keep the saved one',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _temperature,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Temperature'),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null;
                  final number = double.tryParse(text);
                  if (number == null || number < 0 || number > 2) {
                    return 'Between 0 and 2.';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _maxTokens,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max tokens'),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null;
                  final number = int.tryParse(text);
                  return number == null || number <= 0
                      ? 'A whole number.'
                      : null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Saving makes this the provider the whole company’s assistant '
          'uses. Leaving temperature or max tokens blank keeps whatever is '
          'already set.',
          style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
        ),
      ],
    );
  }
}

// ── Prompts ───────────────────────────────────────────────────

class _TemplatesTab extends ConsumerWidget {
  const _TemplatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        ConfigList<AiPromptTemplate>(
          async: ref.watch(aiTemplatesProvider),
          onRefresh: () async => ref.invalidate(aiTemplatesProvider),
          emptyIcon: Icons.description_outlined,
          emptyTitle: 'No prompts of your own',
          emptyMessage:
              'Without one, each feature uses the prompt built into the '
              'product. Write your own to change how the assistant sounds.',
          errorMessage: 'Could not load the prompts.',
          itemBuilder: (context, template) => _TemplateRow(template: template),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => showTemplateSheet(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Write one'),
          ),
        ),
      ],
    );
  }
}

class _TemplateRow extends ConsumerStatefulWidget {
  const _TemplateRow({required this.template});

  final AiPromptTemplate template;

  @override
  ConsumerState<_TemplateRow> createState() => _TemplateRowState();
}

class _TemplateRowState extends ConsumerState<_TemplateRow> {
  bool _busy = false;

  Future<void> _delete() async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete this prompt?',
      message: 'The feature goes back to the prompt built into the product.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(aiRepositoryProvider).deleteTemplate(widget.template.id);
      ref.invalidate(aiTemplatesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that prompt.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;

    final facts = <String>[
      Fmt.label(template.feature),
      'v${template.version}',
      if (template.updatedByName != null) template.updatedByName!,
      if (template.updatedAt != null) Fmt.relative(template.updatedAt),
    ];

    return ConfigRow(
      title: template.name,
      subtitle: facts.join(' · '),
      active: template.active,
      inactiveLabel: 'Superseded',
      busy: _busy,
      onEdit: () => showTemplateSheet(context, template: template),
      actions: [
        RowAction(label: 'Delete', destructive: true, onSelected: _delete),
      ],
    );
  }
}

/// Writing a prompt.
///
/// There is no update endpoint. Saving against a feature supersedes whatever
/// was there and starts a new version, so editing one is really writing the
/// next one — the sheet says so rather than pretending otherwise.
Future<void> showTemplateSheet(
  BuildContext context, {
  AiPromptTemplate? template,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TemplateSheet(template: template),
    );

class _TemplateSheet extends ConsumerStatefulWidget {
  const _TemplateSheet({this.template});

  final AiPromptTemplate? template;

  @override
  ConsumerState<_TemplateSheet> createState() => _TemplateSheetState();
}

class _TemplateSheetState extends ConsumerState<_TemplateSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.template?.name ?? '');
  late final TextEditingController _template =
      TextEditingController(text: widget.template?.template ?? '');
  final _changeNotes = TextEditingController();

  late String _feature = widget.template?.feature ?? AiFeature.general;

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _template.dispose();
    _changeNotes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(aiRepositoryProvider).saveTemplate(
            AiPromptTemplateRequest(
              feature: _feature,
              name: _name.text.trim(),
              template: _template.text.trim(),
              changeNotes: _changeNotes.text,
            ),
          );
      ref.invalidate(aiTemplatesProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save that prompt.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: widget.template == null ? 'New prompt' : 'New version',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _feature,
          decoration: const InputDecoration(labelText: 'For which feature'),
          items: [
            for (final value in AiFeature.all)
              DropdownMenuItem(value: value, child: Text(Fmt.label(value))),
          ],
          onChanged: (value) => setState(() => _feature = value ?? _feature),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _name,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name, please.' : null,
        ),
        TextFormField(
          controller: _template,
          maxLines: 10,
          minLines: 6,
          decoration: const InputDecoration(
            labelText: 'The prompt',
            hintText: 'What the assistant is told before the request.',
          ),
          validator: (value) => (value?.trim().isEmpty ?? true)
              ? 'A prompt needs something in it.'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _changeNotes,
          maxLength: 500,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What changed',
            hintText: 'The only record of why this version exists.',
          ),
        ),
        Text(
          widget.template == null
              ? 'A prompt is saved against one feature. If that feature '
                  'already has one, this supersedes it.'
              : 'This saves as a new version and supersedes '
                  'v${widget.template!.version}. The old text stays on record.',
          style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
        ),
      ],
    );
  }
}

// ── Usage ─────────────────────────────────────────────────────

class _UsageTab extends ConsumerWidget {
  const _UsageTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(aiUsageProvider);

    return RefreshIndicator(
      color: bos.brand,
      backgroundColor: bos.bgCard,
      onRefresh: () async => ref.invalidate(aiUsageProvider),
      child: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load the usage figures.',
          onRetry: () => ref.invalidate(aiUsageProvider),
        ),
        data: (usage) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text(
              usage.date == null ? 'Today' : Fmt.dayDate(usage.date),
              style: TextStyle(color: bos.muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    label: 'Questions',
                    value: usage.totalRequests.toString(),
                    icon: Icons.forum_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatCard(
                    label: 'Tokens',
                    value: usage.totalTokens.toString(),
                    icon: Icons.data_usage_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            StatCard(
              label: 'Average answer time',
              value: (usage.avgResponseTimeMs / 1000).toStringAsFixed(1),
              suffix: 's',
              icon: Icons.timer_outlined,
            ),
            if (usage.requestsByFeature.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionHeader(
                'By feature',
                icon: Icons.pie_chart_outline_rounded,
              ),
              AppCard(
                child: Column(
                  children: [
                    for (final entry in usage.requestsByFeature.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                Fmt.label(entry.key),
                                style: TextStyle(
                                  color: bos.text,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              '${entry.value}',
                              style: TextStyle(color: bos.text, fontSize: 13),
                            ),
                            if (usage.tokensByFeature[entry.key] != null) ...[
                              const SizedBox(width: 10),
                              Text(
                                '${usage.tokensByFeature[entry.key]} tokens',
                                style: TextStyle(
                                  color: bos.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
