class LessonsEntity {
  const LessonsEntity({
    required this.id,
    required this.date,
    required this.lessonNumber,
    this.lessonPlace = '',
    this.startTime = '',
    this.endTime = '',
    required this.subjectName,
    required this.topic,
    required this.homeworkText,
    required this.requiresPhoto,
    required this.gradeValue,
    required this.attendanceCode,
  });

  final String id;
  final String date;
  final int lessonNumber;
  final String lessonPlace;
  final String startTime;
  final String endTime;
  final String subjectName;
  final String topic;
  final String homeworkText;
  final bool requiresPhoto;
  final String gradeValue;
  final String attendanceCode;
}
