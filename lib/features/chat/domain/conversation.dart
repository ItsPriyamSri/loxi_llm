import 'package:freezed_annotation/freezed_annotation.dart';

part 'conversation.freezed.dart';
part 'conversation.g.dart';

/// Title a chat carries until its first message names it.
const kNewChatTitle = 'New chat';

/// Whether [title] is still a placeholder. Includes 'New conversation', the
/// placeholder before the UI refresh, so chats saved under it still get
/// named by their first message.
bool isPlaceholderChatTitle(String title) =>
    title == kNewChatTitle || title == 'New conversation';

@freezed
class Conversation with _$Conversation {
  const Conversation._();

  const factory Conversation({
    required String id,
    required String title,
    @Default('') String systemPrompt,
    @Default('') String modelId,
    required int createdAtMs,
    required int updatedAtMs,
    @Default(false) bool ragEnabled,
    @Default(false) bool toolsEnabled,
    @Default('') String summary,
    @Default(0) int summarizedCount,
  }) = _Conversation;

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      _$ConversationFromJson(json);
}
