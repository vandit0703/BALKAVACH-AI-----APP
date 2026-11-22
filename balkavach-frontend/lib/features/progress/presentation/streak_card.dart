import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../data/progress_repository.dart';

/// A self-contained card presenting the child's streak status, countdown
/// for grace periods, 7-day activity row, and celebration effects.
class StreakCard extends StatefulWidget {
  const StreakCard({
    required this.streakInfo,
    this.activityDays = const [],
    this.onTap,
    this.elevated = true,
    super.key,
  });

  final StreakInfo streakInfo;
  final List<ActivityDay> activityDays;
  final VoidCallback? onTap;
  final bool elevated;

  @override
  State<StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<StreakCard>
    with SingleTickerProviderStateMixin {
  Timer? _countdownTimer;
  Timer? _celebrationTimer;
  int? _localSecondsRemaining;
  int _timerMinutesElapsed = 0;
  bool _showCelebration = false;

  late final AnimationController _celebrationController;
  late final Animation<double> _celebrationScale;
  late final Animation<double> _celebrationOpacity;

  @override
  void initState() {
    super.initState();
    _localSecondsRemaining = widget.streakInfo.secondsUntilExpiry;
    _timerMinutesElapsed = 0;

    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _celebrationScale = CurvedAnimation(
      parent: _celebrationController,
      curve: Curves.elasticOut,
    );

    _celebrationOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _celebrationController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant StreakCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.streakInfo.secondsUntilExpiry !=
            widget.streakInfo.secondsUntilExpiry ||
        oldWidget.streakInfo.streakState != widget.streakInfo.streakState) {
      _localSecondsRemaining = widget.streakInfo.secondsUntilExpiry;
      _timerMinutesElapsed = 0;
      _countdownTimer?.cancel();
      _startTimerIfNeeded();
    }

    final newState = widget.streakInfo.streakState;
    final streakIncreased =
        widget.streakInfo.currentStreak > oldWidget.streakInfo.currentStreak;
    final stateAllowsCelebration =
        newState == 'active' || newState == 'recovered';

    if (streakIncreased && stateAllowsCelebration) {
      _triggerCelebration();
    }
  }

  void _triggerCelebration() {
    _celebrationTimer?.cancel();
    setState(() => _showCelebration = true);
    _celebrationController.forward(from: 0.0).then((_) {
      _celebrationTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        setState(() => _showCelebration = false);
      });
    });
  }

  void _startTimerIfNeeded() {
    if (widget.streakInfo.streakState == 'at_risk' &&
        _localSecondsRemaining != null) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        if (!mounted) return;
        setState(() {
          _timerMinutesElapsed++;
          if (_localSecondsRemaining != null) {
            _localSecondsRemaining = (_localSecondsRemaining! - 60).clamp(
              0,
              999999999,
            );
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _celebrationTimer?.cancel();
    _celebrationController.dispose();
    super.dispose();
  }

  String _stateEmoji(String state) => switch (state) {
    'at_risk' => '⏳',
    'broken' => '💔',
    'recovered' || 'active' => '🔥',
    _ => '🔥',
  };

  String _stateTitle(AppLocalizations l10n, String state) => switch (state) {
    'at_risk' => l10n.streakAtRisk,
    'broken' => l10n.streakBroken,
    'recovered' => l10n.streakRecovered,
    'active' || _ => l10n.streakActive,
  };

  String _motivationalMessage(AppLocalizations l10n, StreakInfo info) {
    if (info.streakState == 'broken') {
      return l10n.streakStartNew;
    }
    if (info.streakState == 'at_risk') {
      return l10n.streakComplete;
    }
    if (info.streakState == 'recovered') {
      return l10n.streakComplete;
    }
    return l10n.streakComplete;
  }

  Color _accentColor(BuildContext context, String state) {
    final colors = context.colors;
    return switch (state) {
      'at_risk' => colors.error,
      'broken' => colors.outline,
      'recovered' => colors.tertiary,
      'active' || _ => colors.secondary,
    };
  }

  Color _badgeBackgroundColor(BuildContext context, String state) {
    final colors = context.colors;
    return switch (state) {
      'at_risk' => colors.errorContainer,
      'broken' => colors.surfaceContainerHigh,
      'recovered' => colors.tertiaryFixed,
      'active' || _ => colors.secondaryContainer,
    };
  }

  String? _countdownString(AppLocalizations l10n, StreakInfo info) {
    if (info.streakState != 'at_risk') return null;

    final seconds = _localSecondsRemaining;
    if (seconds == null) return null;

    // Source of truth is backend; show "refresh to update" if stale (> 5 mins elapsed or timed out)
    if (_timerMinutesElapsed >= 5 || seconds <= 0) {
      return '0h remaining (refresh to update)';
    }

    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;

    if (days > 0) {
      return l10n.streakDaysRemaining(days, hours);
    } else {
      return l10n.streakHoursRemaining(hours > 0 ? hours : 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final info = widget.streakInfo;
    final state = info.streakState;
    final emoji = _stateEmoji(state);
    final title = _stateTitle(l10n, state);
    final motivation = _motivationalMessage(l10n, info);
    final countdown = _countdownString(l10n, info);
    final accent = _accentColor(context, state);
    final badgeBg = _badgeBackgroundColor(context, state);

    return Stack(
      children: [
        AppCard(
          radius: AppRadius.hero,
          elevated: widget.elevated,
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top row: State chip & Longest streak
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm + 4,
                      vertical: AppSpacing.xs + 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          title,
                          style: context.text.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    l10n.streakLongest(info.longestStreak),
                    style: context.text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Streak Count Display
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${info.currentStreak}',
                    style: context.text.displayLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: accent,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      l10n.statStreakValue(info.currentStreak),
                      style: context.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),

              // Motivational message or Grace countdown
              if (countdown != null) ...[
                Container(
                  margin: const EdgeInsets.only(top: AppSpacing.xs),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm + 2,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 16, color: colors.error),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          countdown,
                          style: context.text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],

              Text(
                motivation,
                style: context.text.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),

              // 7-day activity calendar row
              _ActivityDaysRow(activityDays: widget.activityDays),
            ],
          ),
        ),

        // Celebration Animation Overlay
        if (_showCelebration)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _celebrationController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _celebrationOpacity.value,
                    child: Transform.scale(
                      scale: _celebrationScale.value,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.9),
                          borderRadius: AppRadius.hero,
                          border: Border.all(color: colors.primary, width: 3),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '🎉 🔥 🎉',
                              style: TextStyle(fontSize: 40),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '+1 Streak Extended!',
                              style: context.text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// A compact 7-day row of activity dots.
class _ActivityDaysRow extends StatelessWidget {
  const _ActivityDaysRow({required this.activityDays});

  final List<ActivityDay> activityDays;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dayFormat = DateFormat.E(locale);

    final nowUtc = DateTime.now().toUtc();
    final todayMidnight = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);

    final activityMap = {
      for (final day in activityDays)
        DateTime.utc(day.date.year, day.date.month, day.date.day):
            day.completedTasks > 0,
    };

    final days = [
      for (var i = 6; i >= 0; i--) todayMidnight.subtract(Duration(days: i)),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final day in days) ...[
          _DayDot(
            date: day,
            dayLabel: dayFormat.format(day).substring(0, 1),
            isActive: activityMap[day] ?? false,
            isToday: day == todayMidnight,
            activeColor: colors.primary,
            inactiveColor: colors.surfaceContainerHighest,
            todayOutlineColor: colors.secondary,
          ),
        ],
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.date,
    required this.dayLabel,
    required this.isActive,
    required this.isToday,
    required this.activeColor,
    required this.inactiveColor,
    required this.todayOutlineColor,
  });

  final DateTime date;
  final String dayLabel;
  final bool isActive;
  final bool isToday;
  final Color activeColor;
  final Color inactiveColor;
  final Color todayOutlineColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? activeColor : inactiveColor,
            border: isToday
                ? Border.all(color: todayOutlineColor, width: 2)
                : null,
          ),
          child: Center(
            child: isActive
                ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                : (isToday
                      ? Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: todayOutlineColor,
                          ),
                        )
                      : null),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          dayLabel,
          style: context.text.labelSmall?.copyWith(
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
            color: isToday
                ? todayOutlineColor
                : context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
