class HomeworkEntity {
  const HomeworkEntity({
    required this.id,
    required this.description,
    required this.requiresPhoto,
    required this.lessonDate,
    required this.subjectName,
  });

  final String id;
  final String description;
  final bool requiresPhoto;
  final String lessonDate;
  final String subjectName;
}
