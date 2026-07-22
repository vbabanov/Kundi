import '../../lessons/domain/lessons_entity.dart';

bool hasAssignedHomework(LessonsEntity lesson) {
  return lesson.homeworkText.trim().isNotEmpty;
}

bool isHomeworkCompleted(LessonsEntity lesson) {
  return lesson.gradeValue.trim().isNotEmpty;
}

String homeworkIdentity(LessonsEntity lesson) {
  final id = lesson.id.trim();
  if (id.isNotEmpty) {
    return id;
  }
  return '${lesson.date.trim()}|${lesson.lessonNumber}|'
      '${lesson.subjectName.trim().toLowerCase()}';
}
