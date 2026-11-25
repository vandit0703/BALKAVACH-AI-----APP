import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/locale.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets.dart';

/// Quizzes children take in the Learn tab: settings, questions, answers, the
/// pass mark and the first-pass reward. Correct answers are stored and graded
/// on the server; the child app never receives them before submitting.
class QuizzesPage extends ConsumerStatefulWidget {
  const QuizzesPage({super.key});

  @override
  ConsumerState<QuizzesPage> createState() => _QuizzesPageState();
}

class _QuizzesPageState extends ConsumerState<QuizzesPage> {
  int _reload = 0;

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final api = ref.read(adminApiProvider);
    Map<String, dynamic>? detail;
    if (row != null) {
      try {
        detail = await api.getMap('/api/v1/admin/quizzes/${row['id']}');
      } on ApiError catch (error) {
        if (mounted) showError(context, error);
        return;
      }
    }
    if (!mounted) return;
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _QuizEditorDialog(initial: detail),
    );
    if (body == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final done = await runAction(
      context,
      () => detail == null
          ? api.post('/api/v1/admin/quizzes', body)
          : api.put('/api/v1/admin/quizzes/${detail['id']}', body),
      success: l10n.quizSaved,
    );
    if (done) setState(() => _reload++);
  }

  Future<void> _preview(Map<String, dynamic> row) async {
    try {
      final detail = await ref
          .read(adminApiProvider)
          .getMap('/api/v1/admin/quizzes/${row['id']}');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _QuizPreviewDialog(quiz: detail),
      );
    } on ApiError catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _setPublished(Map<String, dynamic> row, bool value) async {
    final l10n = AppLocalizations.of(context);
    final done = await runAction(
      context,
      () => ref.read(adminApiProvider).patch(
        '/api/v1/admin/quizzes/${row['id']}/published',
        {'is_published': value},
      ),
      success: value ? l10n.quizPublished : l10n.quizUnpublished,
    );
    if (done) setState(() => _reload++);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final l10n = AppLocalizations.of(context);
    final yes = await confirm(
      context,
      title: l10n.quizActionDelete,
      body: l10n.quizDeleteConfirm,
      confirmLabel: l10n.quizActionDelete,
    );
    if (!yes || !mounted) return;
    final done = await runAction(
      context,
      () => ref
          .read(adminApiProvider)
          .delete('/api/v1/admin/quizzes/${row['id']}'),
      success: l10n.quizDeleted,
    );
    if (done) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canWrite = ref.watch(sessionProvider)?.can('content:write') ?? false;
    return ListView(
      children: [
        PageHeader(
          title: l10n.quizzesTitle,
          subtitle: l10n.quizzesSubtitle,
          actions: [
            if (canWrite)
              FilledButton.icon(
                key: const Key('quizzes.add'),
                onPressed: _edit,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.quizzesNew),
              ),
          ],
        ),
        PagedTable(
          reloadKey: _reload,
          emptyMessage: l10n.quizzesEmpty,
          fetch: (offset, limit) => ref
              .read(adminApiProvider)
              .getList(
                '/api/v1/admin/quizzes',
                query: {'limit': limit, 'offset': offset},
              ),
          columns: [
            l10n.fieldTitle,
            l10n.quizFieldSubject,
            l10n.fieldLanguage,
            l10n.quizColQuestions,
            l10n.quizColReward,
            l10n.colStatus,
            '',
          ],
          cells: (context, row, reload) {
            final published = row['is_published'] == true;
            return [
              Text('${row['title']}'),
              Text('${row['subject']}'),
              Text(
                '${kLanguageNames[row['language_code']] ?? row['language_code']}',
              ),
              Text('${row['question_count']}'),
              Text('${row['star_reward']} ★ · ${row['xp_reward']} XP'),
              StatusPill(
                label: published
                    ? l10n.quizStatusPublished
                    : l10n.quizStatusDraft,
                good: published,
              ),
              PopupMenuButton<String>(
                key: Key('quizzes.menu.${row['id']}'),
                onSelected: (action) => switch (action) {
                  'preview' => _preview(row),
                  'edit' => _edit(row),
                  'publish' => _setPublished(row, !published),
                  _ => _delete(row),
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: Key('quizzes.preview.${row['id']}'),
                    value: 'preview',
                    child: Text(l10n.quizActionPreview),
                  ),
                  if (canWrite) ...[
                    PopupMenuItem(
                      key: Key('quizzes.edit.${row['id']}'),
                      value: 'edit',
                      // A published quiz is locked: it must be unpublished first.
                      enabled: !published,
                      child: Text(
                        published ? l10n.quizEditLocked : l10n.actionEdit,
                      ),
                    ),
                    PopupMenuItem(
                      key: Key('quizzes.publish.${row['id']}'),
                      value: 'publish',
                      child: Text(
                        published
                            ? l10n.quizActionUnpublish
                            : l10n.quizActionPublish,
                      ),
                    ),
                    if (!published)
                      PopupMenuItem(
                        key: Key('quizzes.delete.${row['id']}'),
                        value: 'delete',
                        child: Text(l10n.quizActionDelete),
                      ),
                  ],
                ],
              ),
            ];
          },
        ),
      ],
    );
  }
}

// ---- editor -----------------------------------------------------------------------------

class _OptionDraft {
  _OptionDraft(String text, {this.correct = false})
    : text = TextEditingController(text: text);

  final TextEditingController text;
  bool correct;
}

class _QuestionDraft {
  _QuestionDraft({
    String prompt = '',
    String explanation = '',
    this.type = 'single',
    List<_OptionDraft>? options,
  }) : prompt = TextEditingController(text: prompt),
       explanation = TextEditingController(text: explanation),
       options = options ?? [_OptionDraft('', correct: true), _OptionDraft('')];

  final TextEditingController prompt;
  final TextEditingController explanation;
  String type;
  final List<_OptionDraft> options;

  void dispose() {
    prompt.dispose();
    explanation.dispose();
    for (final option in options) {
      option.text.dispose();
    }
  }

  /// The same rules the server enforces, so a mistake is caught before saving.
  bool get isValid {
    final texts = [for (final o in options) o.text.text.trim().toLowerCase()];
    final correct = options.where((o) => o.correct).length;
    return prompt.text.trim().isNotEmpty &&
        options.length >= 2 &&
        options.length <= 8 &&
        texts.every((t) => t.isNotEmpty) &&
        texts.toSet().length == texts.length &&
        switch (type) {
          'true_false' => options.length == 2 && correct == 1,
          'multiple' => correct >= 1 && correct < options.length,
          _ => correct == 1,
        };
  }

  Map<String, dynamic> toJson() => {
    'prompt': prompt.text.trim(),
    'question_type': type,
    'explanation': explanation.text.trim().isEmpty
        ? null
        : explanation.text.trim(),
    'options': [
      for (final o in options)
        {'text': o.text.text.trim(), 'is_correct': o.correct},
    ],
  };
}

class _QuizEditorDialog extends StatefulWidget {
  const _QuizEditorDialog({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_QuizEditorDialog> createState() => _QuizEditorDialogState();
}

class _QuizEditorDialogState extends State<_QuizEditorDialog> {
  late final _title = TextEditingController(text: _s('title'));
  late final _description = TextEditingController(text: _s('description'));
  late final _subject = TextEditingController(
    text: _s('subject').isEmpty ? 'general' : _s('subject'),
  );
  late final _ageMin = TextEditingController(text: _n('age_min', 4));
  late final _ageMax = TextEditingController(text: _n('age_max', 15));
  late final _pass = TextEditingController(text: _n('pass_percent', 60));
  late final _stars = TextEditingController(text: _n('star_reward', 0));
  late final _xp = TextEditingController(text: _n('xp_reward', 0));
  late String _difficulty = _s('difficulty').isEmpty
      ? 'easy'
      : _s('difficulty');
  late String _language = _s('language_code').isEmpty
      ? 'en'
      : _s('language_code');
  late bool _retry = widget.initial?['allow_retry'] as bool? ?? true;
  late final List<_QuestionDraft> _questions = [
    for (final q
        in (widget.initial?['questions'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>())
      _QuestionDraft(
        prompt: '${q['prompt']}',
        explanation: '${q['explanation'] ?? ''}',
        type: '${q['question_type']}',
        options: [
          for (final o
              in (q['options'] as List<dynamic>).cast<Map<String, dynamic>>())
            _OptionDraft('${o['text']}', correct: o['is_correct'] == true),
        ],
      ),
  ];
  String? _error;

  String _s(String key) => '${widget.initial?[key] ?? ''}';
  String _n(String key, int fallback) => '${widget.initial?[key] ?? fallback}';

  @override
  void dispose() {
    for (final c in [
      _title,
      _description,
      _subject,
      _ageMin,
      _ageMax,
      _pass,
      _stars,
      _xp,
    ]) {
      c.dispose();
    }
    for (final q in _questions) {
      q.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  void _setType(_QuestionDraft q, String type, AppLocalizations l10n) {
    setState(() {
      q.type = type;
      if (type == 'true_false') {
        for (final o in q.options) {
          o.text.dispose();
        }
        q.options
          ..clear()
          ..addAll([
            _OptionDraft(l10n.quizTrue, correct: true),
            _OptionDraft(l10n.quizFalse),
          ]);
      } else if (type == 'single') {
        var seen = false;
        for (final o in q.options) {
          if (o.correct && seen) o.correct = false;
          seen = seen || o.correct;
        }
      }
    });
  }

  void _toggleCorrect(_QuestionDraft q, _OptionDraft option, bool value) {
    setState(() {
      if (q.type == 'multiple') {
        option.correct = value;
      } else {
        for (final o in q.options) {
          o.correct = identical(o, option);
        }
      }
    });
  }

  void _save(AppLocalizations l10n) {
    if (_title.text.trim().length < 2) {
      setState(() => _error = l10n.quizErrorTitle);
      return;
    }
    for (var i = 0; i < _questions.length; i++) {
      if (!_questions[i].isValid) {
        setState(() => _error = l10n.quizErrorQuestion(i + 1));
        return;
      }
    }
    Navigator.pop(context, {
      'title': _title.text.trim(),
      'description': _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      'subject': _subject.text.trim().isEmpty
          ? 'general'
          : _subject.text.trim(),
      'difficulty': _difficulty,
      'language_code': _language,
      'age_min': _int(_ageMin, 4),
      'age_max': _int(_ageMax, 15),
      'pass_percent': _int(_pass, 60),
      'star_reward': _int(_stars, 0),
      'xp_reward': _int(_xp, 0),
      'allow_retry': _retry,
      'questions': [for (final q in _questions) q.toJson()],
    });
  }

  Widget _number(TextEditingController c, String label, {Key? key}) => SizedBox(
    width: 180,
    child: TextField(
      key: key,
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final types = {
      'single': l10n.quizTypeSingle,
      'multiple': l10n.quizTypeMultiple,
      'true_false': l10n.quizTypeTrueFalse,
    };
    return AlertDialog(
      title: Text(
        widget.initial == null ? l10n.quizzesNewTitle : l10n.quizzesEditTitle,
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('quiz.title'),
                controller: _title,
                maxLength: 200,
                decoration: InputDecoration(labelText: l10n.fieldTitle),
              ),
              TextField(
                controller: _description,
                maxLines: 2,
                decoration: InputDecoration(labelText: l10n.fieldDescription),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _subject,
                      decoration: InputDecoration(
                        labelText: l10n.quizFieldSubject,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: _difficulty,
                      decoration: InputDecoration(
                        labelText: l10n.quizFieldDifficulty,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'easy',
                          child: Text(l10n.quizDifficultyEasy),
                        ),
                        DropdownMenuItem(
                          value: 'medium',
                          child: Text(l10n.quizDifficultyMedium),
                        ),
                        DropdownMenuItem(
                          value: 'hard',
                          child: Text(l10n.quizDifficultyHard),
                        ),
                      ],
                      onChanged: (v) => setState(() => _difficulty = v!),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      key: const Key('quiz.language'),
                      initialValue: _language,
                      decoration: InputDecoration(
                        labelText: l10n.fieldLanguage,
                      ),
                      items: [
                        for (final e in kLanguageNames.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => setState(() => _language = v!),
                    ),
                  ),
                  _number(_ageMin, l10n.quizFieldAgeMin),
                  _number(_ageMax, l10n.quizFieldAgeMax),
                  _number(_pass, l10n.quizFieldPassPercent),
                  _number(
                    _stars,
                    l10n.quizFieldStars,
                    key: const Key('quiz.stars'),
                  ),
                  _number(_xp, l10n.quizFieldXp, key: const Key('quiz.xp')),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.quizRewardHelp,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.quizFieldRetry),
                value: _retry,
                onChanged: (v) => setState(() => _retry = v),
              ),
              const Divider(),
              Text(
                l10n.quizQuestionsHeading,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (var i = 0; i < _questions.length; i++)
                _questionCard(context, l10n, i, types),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  key: const Key('quiz.addQuestion'),
                  onPressed: () =>
                      setState(() => _questions.add(_QuestionDraft())),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.quizAddQuestion),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    key: const Key('quiz.error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('quiz.save'),
          onPressed: () => _save(l10n),
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }

  Widget _questionCard(
    BuildContext context,
    AppLocalizations l10n,
    int index,
    Map<String, String> types,
  ) {
    final q = _questions[index];
    final fixed = q.type == 'true_false';
    return Card(
      key: Key('quiz.question.$index'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: Key('quiz.prompt.$index'),
                    controller: q.prompt,
                    maxLength: 1000,
                    decoration: InputDecoration(
                      labelText: '${index + 1}. ${l10n.quizQuestionPrompt}',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.quizRemove,
                  onPressed: () => setState(() {
                    _questions.removeAt(index).dispose();
                  }),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              key: Key('quiz.type.$index'),
              initialValue: q.type,
              decoration: InputDecoration(labelText: l10n.quizQuestionType),
              items: [
                for (final e in types.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => _setType(q, v!, l10n),
            ),
            for (var j = 0; j < q.options.length; j++)
              Row(
                key: Key('quiz.option.$index.$j'),
                children: [
                  Tooltip(
                    message: l10n.quizOptionCorrect,
                    child: Checkbox(
                      key: Key('quiz.correct.$index.$j'),
                      value: q.options[j].correct,
                      onChanged: (v) =>
                          _toggleCorrect(q, q.options[j], v ?? false),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: Key('quiz.optionText.$index.$j'),
                      controller: q.options[j].text,
                      readOnly: fixed,
                      maxLength: 300,
                      decoration: InputDecoration(
                        labelText: l10n.quizOptionText,
                        counterText: '',
                      ),
                    ),
                  ),
                  if (!fixed && q.options.length > 2)
                    IconButton(
                      tooltip: l10n.quizRemove,
                      onPressed: () =>
                          setState(() => q.options.removeAt(j).text.dispose()),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
            if (!fixed && q.options.length < 8)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: Key('quiz.addOption.$index'),
                  onPressed: () =>
                      setState(() => q.options.add(_OptionDraft(''))),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.quizAddOption),
                ),
              ),
            TextField(
              controller: q.explanation,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: l10n.quizQuestionExplanation,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- preview ----------------------------------------------------------------------------

class _QuizPreviewDialog extends StatelessWidget {
  const _QuizPreviewDialog({required this.quiz});

  final Map<String, dynamic> quiz;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final questions = (quiz['questions'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return AlertDialog(
      title: Text('${l10n.quizPreviewTitle}: ${quiz['title']}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final q in questions) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    '${q['position']}. ${q['prompt']}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final o
                    in (q['options'] as List<dynamic>)
                        .cast<Map<String, dynamic>>())
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      o['is_correct'] == true
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: o['is_correct'] == true ? Colors.green : null,
                    ),
                    title: Text('${o['text']}'),
                    subtitle: o['is_correct'] == true
                        ? Text(l10n.quizPreviewCorrect)
                        : null,
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionClose),
        ),
      ],
    );
  }
}
