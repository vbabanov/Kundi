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
