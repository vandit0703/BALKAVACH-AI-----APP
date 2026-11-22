import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

/// The panel-language text for a server issue code. Unknown codes fall back to
/// the server's (English) message so nothing is hidden.
String missionIssueLabel(AppLocalizations l10n, String code, String fallback) =>
    switch (code) {
      'steps_missing' => l10n.missionIssueStepsMissing,
      'steps_too_few' => l10n.missionIssueStepsTooFew,
      'steps_malformed' => l10n.missionIssueStepsMalformed,
      'placeholder_text' => l10n.missionIssuePlaceholder,
      'materials_missing' => l10n.missionIssueMaterials,
      'submission_missing' => l10n.missionIssueSubmission,
      'safety_missing' => l10n.missionIssueSafety,
      'completion_missing' => l10n.missionIssueCompletion,
      'bands_identical' => l10n.missionIssueBandsIdentical,
      'objective_missing' => l10n.missionIssueObjective,
      'observation_missing' => l10n.missionIssueObservation,
      _ => fallback,
    };

/// A list of `{code, message, age_band?, locale?}` issues from the server.
class MissionIssueList extends StatelessWidget {
  const MissionIssueList({
    required this.title,
    required this.issues,
    this.isError = true,
    super.key,
  });

  final String title;
  final List<Map<String, dynamic>> issues;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : scheme.tertiary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
        ),
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.info_outline,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [
                      if (issue['age_band'] != null || issue['locale'] != null)
                        '${issue['age_band'] ?? ''} ${issue['locale'] ?? ''}'
                            .trim(),
                      missionIssueLabel(
                        l10n,
                        '${issue['code']}',
                        '${issue['message']}',
                      ),
                    ].join(' · '),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Explains why publishing was refused (the server's `problems` list).
Future<void> showPublishProblems(BuildContext context, Object? details) {
  final l10n = AppLocalizations.of(context);
  final raw = details is Map ? details['problems'] : null;
  final problems = raw is List
      ? raw.whereType<Map<String, dynamic>>().toList()
      : <Map<String, dynamic>>[];
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(l10n.missionPublishBlockedTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: problems.isEmpty
              ? Text(l10n.errorTemplateInstructionsIncomplete)
              : MissionIssueList(
                  key: const Key('publish.problems'),
                  title: l10n.missionEditErrors,
                  issues: problems,
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionClose),
        ),
      ],
    ),
  );
}

/// Edit one age band x language version with structured fields: objective,
/// ordered steps, materials, observation, submission, safety and completion,
/// with a child-facing preview and the server's publish checks.
///
/// Saving PATCHes the existing variation (its id, and so every assignment,
/// submission and approval that refers to it, is unchanged).
class VariationEditorDialog extends ConsumerStatefulWidget {
  const VariationEditorDialog({
    required this.templateId,
    required this.variation,
    super.key,
  });

  final String templateId;
  final Map<String, dynamic> variation;

  @override
  ConsumerState<VariationEditorDialog> createState() =>
      _VariationEditorDialogState();
}

class _VariationEditorDialogState extends ConsumerState<VariationEditorDialog> {
  late final TextEditingController _objective;
  late final TextEditingController _observe;
  late final TextEditingController _submit;
  late final TextEditingController _safety;
  late final TextEditingController _completion;
  late final TextEditingController _minutes;
  late final List<TextEditingController> _steps;
  late final List<TextEditingController> _materials;
  List<Map<String, dynamic>> _errors = const [];
  List<Map<String, dynamic>> _warnings = const [];
  bool? _publishable;
  bool _busy = false;

  Map<String, dynamic> get _v => widget.variation;

  @override
  void initState() {
    super.initState();
    TextEditingController c(Object? v) =>
        TextEditingController(text: '${v ?? ''}');
    _objective = c(_v['learning_objective']);
    _observe = c(_v['observation_guidance']);
    _submit = c(_v['submission_requirements']);
    _safety = c(_v['safety_instructions']);
    _completion = c(_v['completion_criteria']);
    _minutes = c(_v['duration_minutes']);
    _steps = [
      for (final s in (_v['steps'] as List<dynamic>? ?? const [])) c(s),
    ];
    _materials = [
      for (final m in (_v['required_materials'] as List<dynamic>? ?? const []))
        c(m),
    ];
  }

  @override
  void dispose() {
    for (final c in [
      _objective,
      _observe,
      _submit,
      _safety,
      _completion,
      _minutes,
      ..._steps,
      ..._materials,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  List<String> _list(List<TextEditingController> cs) => [
    for (final c in cs)
      if (c.text.trim().isNotEmpty) c.text.trim(),
  ];

  /// Body for PATCH (changed fields) and, with the fixed identity fields, for
  /// the preview check. `instructions` is left out on purpose: the server
  /// rebuilds it from the steps so older clients keep working.
  Map<String, Object?> get _fields => {
    'learning_objective': _opt(_objective),
    'steps': _list(_steps),
    'required_materials': _list(_materials),
    'observation_guidance': _opt(_observe),
    'submission_requirements': _opt(_submit),
    'safety_instructions': _safety.text.trim(),
    'completion_criteria': _completion.text.trim(),
    'duration_minutes': int.tryParse(_minutes.text.trim()) ?? 0,
  };

  Future<void> _check() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final body = {
        'age_band': _v['age_band'],
        'locale': _v['locale'],
        'title': _v['title'],
        'description': _v['description'],
        'variation_key': _v['variation_key'] ?? 'v1',
        ..._fields,
      };
      final result = await ref
          .read(adminApiProvider)
          .post('/api/v1/admin/daily-missions/variations/preview', body);
      List<Map<String, dynamic>> list(Object? v) =>
          (v as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _errors = list(result['errors']);
        _warnings = list(result['warnings']);
        _publishable = result['publishable'] == true;
      });
    } on ApiError catch (error) {
      if (mounted) showMessage(context, describeError(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(adminApiProvider)
          .patch(
            '/api/v1/admin/daily-missions/templates/${widget.templateId}/variations/${_v['id']}',
            _fields,
          );
      if (!mounted) return;
      showMessage(context, l10n.missionEditSaved);
      Navigator.of(context).pop(true);
    } on ApiError catch (error) {
      if (!mounted) return;
      if (error.code == 'published_variation_edit_invalid') {
        // Nothing was saved: the mission stays published and unchanged.
        showMessage(context, l10n.errorPublishedEditInvalid);
        await showPublishProblems(context, error.details);
      } else {
        showError(context, error);
      }
    }
  }

  void _move(List<TextEditingController> list, int from, int to) {
    if (to < 0 || to >= list.length) return;
    setState(() => list.insert(to, list.removeAt(from)));
  }

  Widget _stepRow(AppLocalizations l10n, int i) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: Key('editor.step.$i'),
            controller: _steps[i],
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: l10n.missionEditStepN(i + 1),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        IconButton(
          key: Key('editor.step.up.$i'),
          tooltip: l10n.missionEditMoveUp,
          icon: const Icon(Icons.arrow_upward),
          onPressed: i == 0 ? null : () => _move(_steps, i, i - 1),
        ),
        IconButton(
          key: Key('editor.step.down.$i'),
          tooltip: l10n.missionEditMoveDown,
          icon: const Icon(Icons.arrow_downward),
          onPressed: i == _steps.length - 1
              ? null
              : () => _move(_steps, i, i + 1),
        ),
        IconButton(
          key: Key('editor.step.remove.$i'),
          tooltip: l10n.missionEditRemove,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => setState(() => _steps.removeAt(i).dispose()),
        ),
      ],
    ),
  );

  Widget _materialRow(AppLocalizations l10n, int i) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            key: Key('editor.material.$i'),
            controller: _materials[i],
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        IconButton(
          tooltip: l10n.missionEditRemove,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => setState(() => _materials.removeAt(i).dispose()),
        ),
      ],
    ),
  );

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    int lines = 2,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: Key(key),
      controller: controller,
      minLines: 1,
      maxLines: lines,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  /// What the child will see, built from the current form values.
  Widget _preview(AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    final steps = _list(_steps);
    final materials = _list(_materials);
    Widget section(String title, Widget body) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleSmall),
          const SizedBox(height: 4),
          body,
        ],
      ),
    );
    return Card(
      key: const Key('editor.preview'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.missionEditPreview, style: text.labelLarge),
            const SizedBox(height: 8),
            if (_opt(_objective) != null)
              section(l10n.missionEditObjective, Text(_objective.text.trim())),
            if (materials.isNotEmpty)
              section(
                l10n.missionEditMaterials,
                Text(materials.map((m) => '• $m').join('\n')),
              ),
            if (steps.isNotEmpty)
              section(
                l10n.missionEditSteps,
                Text(
                  [
                    for (var i = 0; i < steps.length; i++)
                      '${i + 1}. ${steps[i]}',
                  ].join('\n'),
                ),
              ),
            if (_opt(_observe) != null)
              section(l10n.missionEditObserve, Text(_observe.text.trim())),
            if (_opt(_submit) != null)
              section(l10n.missionEditSubmit, Text(_submit.text.trim())),
            if (_safety.text.trim().isNotEmpty)
              section(l10n.missionEditSafety, Text(_safety.text.trim())),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text('${l10n.missionEditTitle}: ${_v['title']}'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field('editor.objective', l10n.missionEditObjective, _objective),
              Text(
                l10n.missionEditSteps,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _steps.length; i++) _stepRow(l10n, i),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('editor.step.add'),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.missionEditAddStep),
                  onPressed: () =>
                      setState(() => _steps.add(TextEditingController())),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.missionEditMaterials,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _materials.length; i++) _materialRow(l10n, i),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    key: const Key('editor.material.add'),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.missionEditAddMaterial),
                    onPressed: () =>
                        setState(() => _materials.add(TextEditingController())),
                  ),
                  TextButton(
                    key: const Key('editor.material.none'),
                    onPressed: () => setState(() {
                      for (final c in _materials) {
                        c.dispose();
                      }
                      _materials
                        ..clear()
                        ..add(
                          TextEditingController(
                            text: l10n.missionEditNothingNeeded,
                          ),
                        );
                    }),
                    child: Text(l10n.missionEditNothingNeeded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _field(
                'editor.minutes',
                l10n.missionEditMinutes,
                _minutes,
                lines: 1,
                keyboard: TextInputType.number,
              ),
              _field('editor.observe', l10n.missionEditObserve, _observe),
              _field('editor.submit', l10n.missionEditSubmit, _submit),
              _field('editor.safety', l10n.missionEditSafety, _safety),
              _field(
                'editor.completion',
                l10n.missionEditCompletion,
                _completion,
              ),
              _preview(l10n),
              const SizedBox(height: 8),
              MissionIssueList(
                key: const Key('editor.errors'),
                title: l10n.missionEditErrors,
                issues: _errors,
              ),
              MissionIssueList(
                key: const Key('editor.warnings'),
                title: l10n.missionEditWarnings,
                issues: _warnings,
                isError: false,
              ),
              if (_publishable == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.missionEditReady,
                    key: const Key('editor.ready'),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                l10n.missionEditUnpublishNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionClose),
        ),
        OutlinedButton(
          key: const Key('editor.check'),
          onPressed: _busy ? null : _check,
          child: Text(l10n.missionEditCheck),
        ),
        FilledButton(
          key: const Key('editor.save'),
          onPressed: _busy ? null : _save,
          child: Text(l10n.missionEditSave),
        ),
      ],
    );
  }
}
