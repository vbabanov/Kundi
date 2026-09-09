class LocalizedGamificationText {
  const LocalizedGamificationText({required this.ru, required this.kk});

  final String ru;
  final String kk;

  String resolve(String languageCode) => languageCode == 'kk' ? kk : ru;

  factory LocalizedGamificationText.fromJson(Map<String, dynamic> json) {
    return LocalizedGamificationText(
      ru: (json['ru'] ?? '').toString(),
      kk: (json['kk'] ?? '').toString(),
    );
  }
}

class AchievementEntity {
  const AchievementEntity({
    required this.code,
    required this.category,
    required this.categoryTitle,
    required this.title,
    required this.description,
    required this.current,
    required this.target,
    required this.unlocked,
    required this.unlockedAt,
    required this.seen,
  });

  final String code;
  final String category;
  final LocalizedGamificationText categoryTitle;
  final LocalizedGamificationText title;
  final LocalizedGamificationText description;
  final int current;
  final int target;
  final bool unlocked;
  final DateTime? unlockedAt;
  final bool seen;

  double get progress => target <= 0 ? 0 : (current / target).clamp(0, 1);

  AchievementEntity copyWith({bool? seen}) => AchievementEntity(
    code: code,
    category: category,
    categoryTitle: categoryTitle,
    title: title,
    description: description,
    current: current,
    target: target,
    unlocked: unlocked,
    unlockedAt: unlockedAt,
    seen: seen ?? this.seen,
  );

  factory AchievementEntity.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> mapAt(String key) => json[key] is Map
        ? Map<String, dynamic>.from(json[key] as Map)
        : <String, dynamic>{};
    return AchievementEntity(
      code: (json['code'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      categoryTitle: LocalizedGamificationText.fromJson(
        mapAt('category_title'),
      ),
      title: LocalizedGamificationText.fromJson(mapAt('title')),
      description: LocalizedGamificationText.fromJson(mapAt('description')),
      current: int.tryParse((json['current'] ?? '0').toString()) ?? 0,
      target: int.tryParse((json['target'] ?? '0').toString()) ?? 0,
      unlocked: json['unlocked'] == true,
      unlockedAt: DateTime.tryParse((json['unlocked_at'] ?? '').toString()),
      seen: json['seen'] == true,
    );
  }
}

class GamificationProfile {
  const GamificationProfile({
    required this.catalogVersion,
    required this.points,
    required this.level,
    required this.levelFloorPoints,
    required this.nextLevelPoints,
    required this.currentStreak,
    required this.longestStreak,
    required this.lastActiveDate,
    required this.achievementsUnlocked,
    required this.achievementsTotal,
    required this.achievements,
    required this.pendingUnlocks,
  });

  final int catalogVersion;
  final int points;
  final int level;
  final int levelFloorPoints;
  final int nextLevelPoints;
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastActiveDate;
  final int achievementsUnlocked;
  final int achievementsTotal;
  final List<AchievementEntity> achievements;
  final List<AchievementEntity> pendingUnlocks;

  double get levelProgress {
    final span = nextLevelPoints - levelFloorPoints;
    if (span <= 0) return 1;
    return ((points - levelFloorPoints) / span).clamp(0, 1);
  }

  GamificationProfile markPendingSeen() => GamificationProfile(
    catalogVersion: catalogVersion,
    points: points,
    level: level,
    levelFloorPoints: levelFloorPoints,
    nextLevelPoints: nextLevelPoints,
    currentStreak: currentStreak,
    longestStreak: longestStreak,
    lastActiveDate: lastActiveDate,
    achievementsUnlocked: achievementsUnlocked,
    achievementsTotal: achievementsTotal,
    achievements: achievements
        .map(
          (item) => pendingUnlocks.any((p) => p.code == item.code)
              ? item.copyWith(seen: true)
              : item,
        )
        .toList(growable: false),
    pendingUnlocks: const <AchievementEntity>[],
  );

  factory GamificationProfile.fromJson(Map<String, dynamic> json) {
    List<AchievementEntity> itemsAt(String key) => json[key] is List
        ? (json[key] as List)
              .whereType<Map>()
              .map(
                (item) =>
                    AchievementEntity.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList(growable: false)
        : const <AchievementEntity>[];
    return GamificationProfile(
      catalogVersion:
          int.tryParse((json['catalog_version'] ?? '0').toString()) ?? 0,
      points: int.tryParse((json['points'] ?? '0').toString()) ?? 0,
      level: int.tryParse((json['level'] ?? '1').toString()) ?? 1,
      levelFloorPoints:
          int.tryParse((json['level_floor_points'] ?? '0').toString()) ?? 0,
      nextLevelPoints:
          int.tryParse((json['next_level_points'] ?? '0').toString()) ?? 0,
      currentStreak:
          int.tryParse((json['current_streak'] ?? '0').toString()) ?? 0,
      longestStreak:
          int.tryParse((json['longest_streak'] ?? '0').toString()) ?? 0,
      lastActiveDate: DateTime.tryParse(
        (json['last_active_date'] ?? '').toString(),
      ),
      achievementsUnlocked:
          int.tryParse((json['achievements_unlocked'] ?? '0').toString()) ?? 0,
      achievementsTotal:
          int.tryParse((json['achievements_total'] ?? '0').toString()) ?? 0,
      achievements: itemsAt('achievements'),
      pendingUnlocks: itemsAt('pending_unlocks'),
    );
  }
}
