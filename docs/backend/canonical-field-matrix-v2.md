# Canonical Academic Contract v2 Field Matrix

## Legend
- Source: Kundelik JSON/UI or local app form.
- Canonical: ingest v2 field.
- DB: target persistence field.
- API DTO: backend typed read DTO field.
- Mobile Local: sqlite cache field.

| Source | Canonical | DB | API DTO | Mobile Local |
|---|---|---|---|---|
| `links.context.personId` | `identity.provider_person_id` | `provider_identity_snapshots.provider_person_id` | `identity.providerPersonId` | `canonical_identity_cache.provider_person_id` |
| `links.context.schoolId` | `identity.provider_school_id` | `provider_identity_snapshots.provider_school_id` | `identity.providerSchoolId` | `canonical_identity_cache.provider_school_id` |
| `links.context.groupId` | `identity.provider_group_id` | `provider_identity_snapshots.provider_group_id` | `identity.providerGroupId` | `canonical_identity_cache.provider_group_id` |
| `closecontacts.schoolName` | `identity.school_name` | `provider_identity_snapshots.school_name` | `identity.schoolName` | `canonical_identity_cache.school_name` |
| `closecontacts.groups[groupId].name` | `identity.class_label` | `provider_identity_snapshots.class_label` | `identity.classLabel` | `canonical_identity_cache.class_label` |
| `enrich(user_jid).name` | `identity.student_full_name` | `provider_identity_snapshots.student_full_name` | `identity.studentFullName` | `canonical_identity_cache.student_full_name` |
| `enrich(classTeacher_jid).name` | `identity.class_teacher_full_name` | `provider_identity_snapshots.class_teacher_full_name` | `identity.classTeacherFullName` | `canonical_identity_cache.class_teacher_full_name` |
| `diary.days[].lessons[].id` | `lessons[].provider_lesson_id` | `lessons.provider_lesson_id` | `lessons[].providerLessonId` | `canonical_lessons_cache.provider_lesson_id` |
| `diary.days[].date` | `lessons[].lesson_date` | `lessons.lesson_date` | `lessons[].lessonDate` | `canonical_lessons_cache.lesson_date` |
| `diary.days[].lessons[].number` | `lessons[].lesson_number` | `lessons.lesson_number` | `lessons[].lessonNumber` | `canonical_lessons_cache.lesson_number` |
| `diary.days[].lessons[].subject.id` | `lessons[].provider_subject_id` | `lessons.provider_subject_id` | `lessons[].providerSubjectId` | `canonical_lessons_cache.provider_subject_id` |
| `diary.days[].lessons[].subject.name` | `lessons[].subject_name` | `lessons.subject_name` | `lessons[].subjectName` | `canonical_lessons_cache.subject_name` |
| `diary.days[].lessons[].theme` | `lessons[].theme` | `lesson_topics.title` | `lessons[].theme` | `canonical_lessons_cache.theme` |
| `diary.days[].lessons[].homework.text` | `lessons[].homework_text` | `homeworks.description` | `lessons[].homeworkText` | `canonical_lessons_cache.homework_text` |
| `diary.days[].lessons[].homework.isCompleted` | `lessons[].homework_completed` | `homework_completions.status` | `lessons[].homeworkStatus` | `canonical_homework_cache.status` |
| `diary.workMarks[].value` | `results[].value_text` | `academic_results.value_text` | `results[].valueText` | `canonical_results_cache.value_text` |
| `diary.workMarks[].mood` | `results[].resolved_mood` | `academic_results.resolved_mood` | `results[].resolvedMood` | `canonical_results_cache.resolved_mood` |
| `diary.workMarks[].mood` | `evidence[].source_mood_raw` | `academic_result_evidence.source_mood_raw` | `results[].evidence[].sourceMoodRaw` | `canonical_result_evidence_cache.source_mood_raw` |
| `diary/period mark id` | `results[].provider_mark_id` | `academic_results.provider_mark_id` | `results[].providerMarkId` | `canonical_results_cache.provider_mark_id` |
| `period works[].workId` | `results[].provider_work_id` | `academic_results.provider_work_id` | `results[].providerWorkId` | `canonical_results_cache.provider_work_id` |
| `period type -> FormativeWork` | `results[].result_kind=regular` | `academic_results.result_kind` | `results[].resultKind` | `canonical_results_cache.result_kind` |
| `diary.days[].sorSochs[] (SOR)` | `results[].result_kind=sor` | `academic_results.result_kind` | `results[].resultKind` | `canonical_results_cache.result_kind` |
| `diary.days[].sorSochs[] (SOCH)` | `results[].result_kind=soch` | `academic_results.result_kind` | `results[].resultKind` | `canonical_results_cache.result_kind` |
| `marks/school/... subjects[].periodSection / term mark` | `aggregates[].result_kind=term` | `academic_aggregates.result_kind` | `aggregates[].resultKind` | `canonical_aggregates_cache.result_kind` |
| `marks/final/... subjects[].finalWorks[].marks[]` | `aggregates[].result_kind=year` | `academic_aggregates.result_kind` | `aggregates[].resultKind` | `canonical_aggregates_cache.result_kind` |
| `diary.logEntry.lessonLogEntryValue` | `attendance[].raw_code` | `attendance_events.raw_code` | `attendance[].rawCode` | `canonical_attendance_cache.raw_code` |
| normalized from raw code | `attendance[].normalized_status` | `attendance_events.normalized_status` | `attendance[].normalizedStatus` | `canonical_attendance_cache.normalized_status` |
| `diary.logEntry.id` | `attendance[].provider_event_key` | `attendance_events.provider_event_key` | `attendance[].providerEventKey` | `canonical_attendance_cache.provider_event_key` |
| local profile form: shift | `local_app_profile.shift` | `student_app_profiles.shift` | `localProfile.shift` | `local_app_profile_cache.shift` |
| local profile form: parent_phone_1 | `local_app_profile.parent_phone_1` | `student_app_profiles.parent_phone_1` | `localProfile.parentPhone1` | `local_app_profile_cache.parent_phone_1` |
| local profile form: parent_phone_2 | `local_app_profile.parent_phone_2` | `student_app_profiles.parent_phone_2` | `localProfile.parentPhone2` | `local_app_profile_cache.parent_phone_2` |
