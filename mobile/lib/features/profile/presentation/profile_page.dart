import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/kundi_surface.dart';
import '../../auth/application/auth_controller.dart';
import '../../gamification/application/gamification_controller.dart';
import '../../gamification/domain/gamification_entity.dart';
import '../../gamification/presentation/gamification_page.dart';
import '../../gamification/presentation/achievement_progress.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/settings_entity.dart';
import '../application/profile_controller.dart';
import '../domain/profile_entity.dart';
import '../domain/school_shift.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _phone1Controller = TextEditingController();
  final _phone2Controller = TextEditingController();

  String _loadedProfileKey = '';
  ProfileEntity? _cachedProfile;

  @override
  void dispose() {
    _phone1Controller.dispose();
    _phone2Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileControllerProvider);
    final liveProfile = state.asData?.value;
    final profile = liveProfile ?? _cachedProfile;
    final gamification = ref.watch(gamificationControllerProvider).valueOrNull;

    if (liveProfile != null) {
      _cachedProfile = liveProfile;
    }

    return Scaffold(
      body: KundiGradientBackground(
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(child: _ProfileBackdrop()),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _ProfileTopBar(
                    onBack: () => Navigator.of(context).maybePop(),
                    onLogout: _logout,
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        if (profile != null) {
                          _syncForm(profile);
                          return _ProfileContent(
                            profile: profile,
                            gamification: gamification,
                            phone1Controller: _phone1Controller,
                            phone2Controller: _phone2Controller,
                            formKey: _formKey,
                            isSaving: state.isLoading,
                            onSave: _saveProfile,
                            onAddPhoto: _showAddPhotoSoonMessage,
                          );
                        }

                        return state.when(
                          data: (_) => KundiStateBody.empty(
                            label: context.l10n.profileNotLoaded,
                            icon: Icons.person_search_outlined,
                          ),
                          loading: () => KundiStateBody.loading(
                            label: context.l10n.profileLoading,
                          ),
                          error: (error, _) => KundiStateBody.error(
                            label: context.l10n.profileLoadFailed,
                            onRetry: () => ref
                                .read(profileControllerProvider.notifier)
                                .refreshFromCache(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    await ref
        .read(profileControllerProvider.notifier)
        .saveLocalAppProfile(
          parentPhone1: _normalizePhone(_phone1Controller.text),
          parentPhone2: _normalizePhone(_phone2Controller.text),
        );

    if (!mounted) {
      return;
    }

    final nextState = ref.read(profileControllerProvider);
    nextState.whenOrNull(
      data: (_) => _showSnackBar(context.l10n.profileSaved),
      error: (_, __) => _showSnackBar(context.l10n.profileSaveFailed),
    );
  }

  void _syncForm(ProfileEntity profile) {
    final local = profile.localAppProfile;
    final nextKey =
        '${profile.providerIdentity?.studentId}|${local?.parentPhone1}|${local?.parentPhone2}';
    if (_loadedProfileKey == nextKey) {
      return;
    }

    _loadedProfileKey = nextKey;
    _phone1Controller.text = local?.parentPhone1 ?? '';
    _phone2Controller.text = local?.parentPhone2 ?? '';
  }

  void _showAddPhotoSoonMessage() {
    _showSnackBar(context.l10n.profilePhotoSoon);
  }

  Future<void> _logout() async {
    final shouldLogout =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.profileLogoutTitle),
            content: Text(context.l10n.profileLogoutBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(context.l10n.profileLogout),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLogout) {
      return;
    }

    await ref.read(secureStorageProvider).clearAll();
    ref.invalidate(profileControllerProvider);
    ref.invalidate(gamificationControllerProvider);
    ref.invalidate(authControllerProvider);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.profile,
    required this.gamification,
    required this.phone1Controller,
    required this.phone2Controller,
    required this.formKey,
    required this.isSaving,
    required this.onSave,
    required this.onAddPhoto,
  });

  final ProfileEntity profile;
  final GamificationProfile? gamification;
  final TextEditingController phone1Controller;
  final TextEditingController phone2Controller;
  final GlobalKey<FormState> formKey;
  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    final providerIdentity = profile.providerIdentity;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      children: [
        _ProfileHeroCard(
          providerIdentity: providerIdentity,
          gamification: gamification,
          onAddPhoto: onAddPhoto,
        ),
        const SizedBox(height: 10),
        _SectionHeading(
          title: context.l10n.profileStudentData,
          icon: Icons.badge_outlined,
        ),
        const SizedBox(height: 4),
        _StudentDetailsCard(
          providerIdentity: providerIdentity,
          automaticShift: profile.automaticShift,
        ),
        const SizedBox(height: 10),
        _SectionHeading(
          title: context.l10n.profileParentContacts,
          icon: Icons.phone_iphone_outlined,
        ),
        const SizedBox(height: 4),
        _ParentContactsCard(
          formKey: formKey,
          phone1Controller: phone1Controller,
          phone2Controller: phone2Controller,
          isSaving: isSaving,
          onSave: onSave,
        ),
        const SizedBox(height: 10),
        _SectionHeading(
          title: context.l10n.settingsTitle,
          icon: Icons.settings_outlined,
        ),
        const SizedBox(height: 4),
        const _AppSettingsSection(),
        const SizedBox(height: 10),
        _AchievementsSection(profile: gamification),
      ],
    );
  }
}

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({required this.onBack, required this.onLogout});

  final VoidCallback onBack;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Row(
        children: [
          _IconGlassButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: onBack,
          ),
          Expanded(
            child: Text(
              context.l10n.profileTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _IconGlassButton(icon: Icons.logout_rounded, onTap: onLogout),
        ],
      ),
    );
  }
}

class _IconGlassButton extends StatelessWidget {
  const _IconGlassButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Ink(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark
              ? const Color(0x24191343)
              : scheme.surface.withValues(alpha: 0.92),
          border: Border.all(
            color: isDark
                ? const Color(0x55392A69)
                : scheme.primary.withValues(alpha: 0.45),
          ),
        ),
        child: Icon(icon, color: scheme.onSurface, size: 17),
      ),
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.providerIdentity,
    required this.gamification,
    required this.onAddPhoto,
  });

  final ProviderIdentityProfileSection? providerIdentity;
  final GamificationProfile? gamification;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 102,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _AvatarSlot(
                  fullName: providerIdentity?.studentFullName ?? '',
                  onAddPhoto: onAddPhoto,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _orNotSet(
                            context,
                            providerIdentity?.studentFullName ?? '',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFB8AEE2),
                        size: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _orNotSet(context, providerIdentity?.classLabel ?? ''),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.8,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      _PillTag(label: context.l10n.profileStudent),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _GamificationStat(
                          icon: Icons.auto_awesome,
                          value: _pointsValue(gamification),
                          label: context.l10n.profilePoints,
                          iconColor: const Color(0xFFB86DFF),
                        ),
                      ),
                      const _StatDivider(),
                      Expanded(
                        child: _GamificationStat(
                          icon: Icons.local_fire_department_outlined,
                          value: _streakValue(gamification),
                          label: context.l10n.profileStreak,
                          iconColor: const Color(0xFFFF974A),
                        ),
                      ),
                      const _StatDivider(),
                      Expanded(
                        child: _GamificationStat(
                          icon: Icons.shield_moon_outlined,
                          value: _levelValue(gamification),
                          label: context.l10n.profileLevel,
                          iconColor: const Color(0xFFB86DFF),
                        ),
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

class _AvatarSlot extends StatelessWidget {
  const _AvatarSlot({required this.fullName, required this.onAddPhoto});

  final String fullName;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 88,
            height: 88,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF7D47FF), Color(0xFFB15CFF)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x403F23A3),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF171236), Color(0xFF251852)],
                ),
              ),
              child: Center(
                child: Text(
                  _profileInitials(fullName, context.l10n.profileInitials),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 2,
            bottom: 4,
            child: InkWell(
              onTap: onAddPhoto,
              borderRadius: BorderRadius.circular(18),
              child: Ink(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF844BFF), Color(0xFFBD72FF)],
                  ),
                  border: Border.all(color: const Color(0xCCFFFFFF), width: 1),
                ),
                child: const Icon(
                  Icons.add_a_photo_outlined,
                  color: Colors.white,
                  size: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillTag extends StatelessWidget {
  const _PillTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x221C1340),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x55392B68)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFD5CAFF),
          fontSize: 8.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _GamificationStat extends StatelessWidget {
  const _GamificationStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.iconColor,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 0),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8D83B8),
              fontSize: 7.9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 28, color: const Color(0x332C1F55));
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.icon,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF9F6EFF), size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _StudentDetailsCard extends StatelessWidget {
  const _StudentDetailsCard({
    required this.providerIdentity,
    required this.automaticShift,
  });

  final ProviderIdentityProfileSection? providerIdentity;
  final SchoolShift automaticShift;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.person_outline,
            label: context.l10n.profileStudent,
            value: _orNotSet(context, providerIdentity?.studentFullName ?? ''),
          ),
          const _InfoDivider(),
          _InfoRow(
            icon: Icons.apartment_outlined,
            label: context.l10n.profileSchool,
            value: _orNotSet(context, providerIdentity?.schoolName ?? ''),
            multiline: true,
          ),
          const _InfoDivider(),
          _InfoRow(
            icon: Icons.school_outlined,
            label: context.l10n.profileClass,
            value: _orNotSet(context, providerIdentity?.classLabel ?? ''),
            trailing: _ShiftBadge(shift: automaticShift),
          ),
          const _InfoDivider(),
          _InfoRow(
            icon: Icons.support_agent_outlined,
            label: context.l10n.profileTeacher,
            value: _orNotSet(
              context,
              providerIdentity?.classTeacherFullName ?? '',
            ),
            multiline: true,
          ),
        ],
      ),
    );
  }
}

class _ParentContactsCard extends StatelessWidget {
  const _ParentContactsCard({
    required this.formKey,
    required this.phone1Controller,
    required this.phone2Controller,
    required this.isSaving,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController phone1Controller;
  final TextEditingController phone2Controller;
  final bool isSaving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.profileContactsHelp,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFAFA4DA),
                fontSize: 10,
                height: 1.18,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: phone1Controller,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: _profileInputDecoration(
                label: context.l10n.profileParentPhoneOne,
                hint: '+7 771 256 25 25',
              ),
              validator: (value) {
                final normalized = _normalizePhone(value ?? '');
                if (normalized.isEmpty) {
                  return context.l10n.profileParentPhoneOneRequired;
                }
                if (!_isValidPhone(normalized)) {
                  return context.l10n.profilePhoneInvalid;
                }
                return null;
              },
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: phone2Controller,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: _profileInputDecoration(
                label: context.l10n.profileParentPhoneTwo,
                hint: context.l10n.profilePhoneOptionalHint,
              ),
              validator: (value) {
                final normalized = _normalizePhone(value ?? '');
                if (normalized.isEmpty) {
                  return null;
                }
                if (!_isValidPhone(normalized)) {
                  return context.l10n.profilePhoneInvalid;
                }
                return null;
              },
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: isSaving
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  : KundiPrimaryButton(
                      label: context.l10n.profileSaveChanges,
                      icon: Icons.save_outlined,
                      onPressed: onSave,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementsSection extends StatelessWidget {
  const _AchievementsSection({required this.profile});

  final GamificationProfile? profile;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final achievements = profile?.achievements ?? const <AchievementEntity>[];
    final sorted = List<AchievementEntity>.of(achievements)
      ..sort((a, b) {
        if (a.unlocked == b.unlocked) return 0;
        return a.unlocked ? -1 : 1;
      });
    final cards = sorted
        .take(4)
        .map((item) {
          final color = _achievementColor(item.category);
          return _AchievementCardData(
            icon: _achievementIcon(item.category),
            title: item.title.resolve(language),
            subtitle: context.l10n.gamificationProgress(
              displayAchievementCurrent(item),
              item.target,
            ),
            glow: color,
            outline: color,
            unlocked: item.unlocked,
          );
        })
        .toList(growable: false);

    return Column(
      children: [
        _SectionHeading(
          title: context.l10n.profileAchievements,
          icon: Icons.workspace_premium_outlined,
          trailing: _MoreLink(
            onTap: profile == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GamificationPage(initialProfile: profile),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        if (cards.isEmpty)
          SizedBox(
            height: 72,
            child: Center(child: Text(context.l10n.gamificationUnavailable)),
          )
        else
          SizedBox(
            height: 118,
            child: ListView.separated(
              key: const Key('profile-achievement-strip'),
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) =>
                  _AchievementCard(data: cards[index]),
            ),
          ),
      ],
    );
  }
}

class _MoreLink extends StatelessWidget {
  const _MoreLink({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('profile-all-achievements'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.profileAllAchievements,
              style: const TextStyle(
                color: Color(0xFFB56BFF),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFB56BFF),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.data});

  final _AchievementCardData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 96,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surface.withValues(alpha: 0.98),
            scheme.surfaceContainerHigh.withValues(alpha: 0.98),
          ],
        ),
        border: Border.all(
          color: data.unlocked ? data.outline : scheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: data.glow.withValues(alpha: 0.18),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [scheme.surface, scheme.surfaceContainerHigh],
                ),
                border: Border.all(color: data.outline, width: 1.6),
              ),
              child: Icon(
                data.unlocked ? data.icon : Icons.lock_outline_rounded,
                color: data.unlocked ? data.glow : scheme.onSurfaceVariant,
                size: 18,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 9.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Expanded(
            child: Text(
              data.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 7.2,
                fontWeight: FontWeight.w500,
                height: 1.12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementCardData {
  const _AchievementCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.glow,
    required this.outline,
    required this.unlocked,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color glow;
  final Color outline;
  final bool unlocked;
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141132), Color(0xFF20174A)],
        ),
        border: Border.all(color: const Color(0x66372A68)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.multiline = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: multiline ? 2 : 1),
            child: Icon(icon, color: const Color(0xFF9F6EFF), size: 14),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFA39ACB),
                fontSize: 10.4,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: trailing == null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      textAlign: TextAlign.left,
                      maxLines: multiline ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.9,
                        fontWeight: FontWeight.w600,
                        height: 1.18,
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          textAlign: TextAlign.left,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      trailing!,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _AppSettingsSection extends ConsumerWidget {
  const _AppSettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsControllerProvider).valueOrNull ??
        const AppSettings();
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        children: [
          _SettingsRow<AppThemePreference>(
            icon: Icons.contrast_rounded,
            label: context.l10n.settingsTheme,
            value: settings.theme,
            items: [
              DropdownMenuItem(
                value: AppThemePreference.dark,
                child: Text(context.l10n.settingsThemeDark),
              ),
              DropdownMenuItem(
                value: AppThemePreference.light,
                child: Text(context.l10n.settingsThemeLight),
              ),
            ],
            onChanged: (value) => _save(
              context,
              () =>
                  ref.read(settingsControllerProvider.notifier).setTheme(value),
            ),
          ),
          const _InfoDivider(),
          _SettingsRow<AppLanguage>(
            icon: Icons.translate_rounded,
            label: context.l10n.settingsLanguage,
            value: settings.language,
            items: [
              DropdownMenuItem(
                value: AppLanguage.ru,
                child: Text(context.l10n.settingsLanguageRussian),
              ),
              DropdownMenuItem(
                value: AppLanguage.kk,
                child: Text(context.l10n.settingsLanguageKazakh),
              ),
            ],
            onChanged: (value) => _save(
              context,
              () => ref
                  .read(settingsControllerProvider.notifier)
                  .setLanguage(value),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.settingsSaveFailed)));
    }
  }
}

class _SettingsRow<T> extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            borderRadius: BorderRadius.circular(16),
            dropdownColor: const Color(0xFF20174A),
            iconEnabledColor: const Color(0xFFAFA4DA),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            items: items,
            onChanged: (next) {
              if (next != null) onChanged(next);
            },
          ),
        ),
      ],
    );
  }
}

class _ShiftBadge extends StatelessWidget {
  const _ShiftBadge({required this.shift});

  final SchoolShift shift;

  @override
  Widget build(BuildContext context) {
    final label = switch (shift) {
      SchoolShift.first => context.l10n.profileShiftOne,
      SchoolShift.second => context.l10n.profileShiftTwo,
      SchoolShift.unknown => context.l10n.profileShiftUnknown,
    };
    return Container(
      key: const Key('profile-automatic-shift'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoDivider extends StatelessWidget {
  const _InfoDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(color: Color(0x332E2257), thickness: 1, height: 10);
  }
}

class _ProfileBackdrop extends StatelessWidget {
  const _ProfileBackdrop();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(
          top: -110,
          left: -90,
          right: -90,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.0,
                colors: [Color(0x221067FF), Colors.transparent],
              ),
            ),
            child: SizedBox(height: 360),
          ),
        ),
        Positioned(top: 110, left: 108, child: _Sparkle(size: 3)),
        Positioned(top: 148, right: 86, child: _Sparkle(size: 4)),
        Positioned(top: 252, right: 42, child: _Sparkle(size: 3)),
        Positioned(top: 392, left: 38, child: _Sparkle(size: 4)),
      ],
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0x88A96BFF),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0x88A96BFF).withValues(alpha: 0.55),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

InputDecoration _profileInputDecoration({
  required String label,
  required String hint,
}) {
  const borderColor = Color(0x66392C6B);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: borderColor),
  );

  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(color: Color(0xFFA99ED4)),
    hintStyle: const TextStyle(color: Color(0x887A719D)),
    filled: true,
    fillColor: const Color(0x21150F30),
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: Color(0xFF8B54FF), width: 1.1),
    ),
    errorBorder: border.copyWith(
      borderSide: const BorderSide(color: Color(0xFFFF6D91)),
    ),
    focusedErrorBorder: border.copyWith(
      borderSide: const BorderSide(color: Color(0xFFFF6D91), width: 1.1),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
  );
}

String _normalizePhone(String value) {
  return value.replaceAll(RegExp(r'[^0-9+]'), '');
}

bool _isValidPhone(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length >= 10 && digits.length <= 15;
}

String _orNotSet(BuildContext context, String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? context.l10n.commonNotSpecified : trimmed;
}

String _profileInitials(String fullName, String fallback) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return fallback;
  }
  if (parts.length == 1) {
    final safe = parts.first;
    return safe.substring(0, safe.length >= 2 ? 2 : 1).toUpperCase();
  }
  final first = parts.first.substring(0, 1);
  final second = parts.last.substring(0, 1);
  return '$first$second'.toUpperCase();
}

String _pointsValue(GamificationProfile? profile) =>
    profile == null ? '—' : '${profile.points}';

String _streakValue(GamificationProfile? profile) =>
    profile == null ? '—' : '${profile.currentStreak}';

String _levelValue(GamificationProfile? profile) =>
    profile == null ? '—' : '${profile.level}';

IconData _achievementIcon(String category) => switch (category) {
  'activity' => Icons.local_fire_department_outlined,
  'grades' => Icons.star_outline_rounded,
  'learning' => Icons.menu_book_outlined,
  'independence' => Icons.psychology_alt_outlined,
  _ => Icons.workspace_premium_outlined,
};

Color _achievementColor(String category) => switch (category) {
  'activity' => const Color(0xFFFF9F43),
  'grades' => const Color(0xFF7BD95A),
  'learning' => const Color(0xFF65A8FF),
  'independence' => const Color(0xFFCE6BFF),
  _ => const Color(0xFFB56BFF),
};
