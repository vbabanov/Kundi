import '../../../runtimes/avatar_runtime/contracts/avatar_response_package.dart';

enum AssistantMode {
  tutor,
  generalChat,
}

extension AssistantModeApiValue on AssistantMode {
  String get apiValue {
    switch (this) {
      case AssistantMode.tutor:
        return 'tutor';
      case AssistantMode.generalChat:
        return 'general_chat';
    }
  }
}

class AssistantChatRecord {
  const AssistantChatRecord({
    required this.role,
    required this.text,
  });

  final String role;
  final String text;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role,
        'text': text,
      };
}

class AssistantEntity {
  const AssistantEntity({
    required this.id,
    required this.mode,
    required this.userText,
    required this.responseText,
    required this.avatarPackage,
    required this.createdAt,
    required this.gradeBand,
  });

  final String id;
  final AssistantMode mode;
  final String userText;
  final String responseText;
  final AvatarResponsePackage avatarPackage;
  final DateTime createdAt;
  final String gradeBand;

  List<AssistantChatRecord> toHistory() {
    return <AssistantChatRecord>[
      AssistantChatRecord(role: 'user', text: userText),
      AssistantChatRecord(role: 'assistant', text: responseText),
    ];
  }
}

class AssistantSessionEntity {
  const AssistantSessionEntity({
    required this.id,
    required this.locale,
    required this.gradeLevel,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.lastMessageAt,
  });

  final String id;
  final String locale;
  final int gradeLevel;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastMessageAt;
}

class AssistantMessageEntity {
  const AssistantMessageEntity({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.inputMode,
    required this.responseMode,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String role;
  final String content;
  final String inputMode;
  final String responseMode;
  final DateTime createdAt;

  bool get isUser => role == 'user';
}

class AssistantPageResult<T> {
  const AssistantPageResult({
    required this.items,
    this.nextCursor = '',
  });

  final List<T> items;
  final String nextCursor;
}

class AssistantMessageResult {
  const AssistantMessageResult({
    required this.userMessage,
    required this.assistantMessage,
    required this.responseMode,
    required this.helpLevel,
    required this.emotion,
    required this.animationCue,
    required this.suggestions,
    this.followUpQuestion = '',
  });

  final AssistantMessageEntity userMessage;
  final AssistantMessageEntity assistantMessage;
  final String responseMode;
  final String helpLevel;
  final String followUpQuestion;
  final String emotion;
  final String animationCue;
  final List<String> suggestions;
}
