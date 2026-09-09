import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/widgets/kundi_surface.dart';
import '../application/gamification_controller.dart';
import '../domain/gamification_entity.dart';
import 'achievement_progress.dart';

class GamificationPage extends ConsumerWidget {
  const GamificationPage({this.initialProfile, super.key});

  final GamificationProfile? initialProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gamificationControllerProvider);
    final profile = state.valueOrNull ?? initialProfile;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.profileAllAchievements)),
      body: KundiGradientBackground(
        child: SafeArea(
          top: false,
          child: profile == null
              ? state.when(
                  data: (_) => _GamificationUnavailable(
                    onRetry: () => ref
                        .read(gamificationControllerProvider.notifier)
                        .refresh(),
                  ),
                  loading: () => KundiStateBody.loading(
                    label: context.l10n.gamificationLoading,
                  ),
                  error: (_, __) => _GamificationUnavailable(
                    onRetry: () => ref
                        .read(gamificationControllerProvider.notifier)
                        .refresh(),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await ref
                        .read(gamificationControllerProvider.notifier)
                        .refresh();
                  },
                  child: _AchievementCatalog(profile: profile),
                ),
        ),
      ),
    );
  }
}

class _GamificationUnavailable extends StatelessWidget {
  const _GamificationUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => KundiStateBody.error(
    label: context.l10n.gamificationLoadFailed,
    onRetry: onRetry,
  );
}

class _AchievementCatalog extends StatelessWidget {
  const _AchievementCatalog({required this.profile});

  final GamificationProfile profile;

  @override
  Widget build(BuildContext context) {
    final categories = <String, List<AchievementEntity>>{};
    for (final item in profile.achievements) {
      categories
          .putIfAbsent(item.category, () => <AchievementEntity>[])
          .add(item);
    }
    return ListView(
      key: const Key('gamification-catalog'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _GamificationSummary(profile: profile),
        const SizedBox(height: 18),
        for (final entry in categories.entries) ...[
          Text(
            entry.value.first.categoryTitle.resolve(
              Localizations.localeOf(context).languageCode,
            ),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final item in entry.value) ...[
            _AchievementTile(item: item),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _GamificationSummary extends StatelessWidget {
  const _GamificationSummary({required this.profile});

  final GamificationProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('gamification-summary'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SummaryValue(
                value: '${profile.points}',
                label: context.l10n.profilePoints,
              ),
              _SummaryValue(
                value: '${profile.level}',
                label: context.l10n.profileLevel,
              ),
              _SummaryValue(
                value: '${profile.currentStreak}',
                label: context.l10n.profileStreak,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            context.l10n.gamificationUnlockedSummary(
              profile.achievementsUnlocked,
              profile.achievementsTotal,
            ),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 7),
          LinearProgressIndicator(
            value: profile.levelProgress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 5),
          Text(
            profile.nextLevelPoints > profile.points
                ? context.l10n.gamificationNextLevel(
                    profile.nextLevelPoints - profile.points,
                  )
                : context.l10n.gamificationMaxLevel,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.item});

  final AchievementEntity item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final language = Localizations.localeOf(context).languageCode;
    final date = item.unlockedAt?.toLocal();
    final status = item.unlocked
        ? date == null
              ? context.l10n.gamificationUnlocked
              : context.l10n.gamificationUnlockedOn(
                  MaterialLocalizations.of(context).formatShortDate(date),
                )
        : context.l10n.gamificationLocked;
    return Semantics(
      label: '${item.title.resolve(language)}. $status',
      child: Container(
        key: Key('achievement-${item.code}'),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: item.unlocked ? 0.96 : 0.68),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: item.unlocked ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: item.unlocked
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
              ),
              child: Icon(
                item.unlocked
                    ? Icons.workspace_premium_rounded
                    : Icons.lock_outline_rounded,
                color: item.unlocked
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.resolve(language),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.description.resolve(language),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 9),
                  LinearProgressIndicator(
                    value: item.progress,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(999),
                    color: item.unlocked ? scheme.primary : scheme.secondary,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.gamificationProgress(
                          displayAchievementCurrent(item),
                          item.target,
                        ),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
