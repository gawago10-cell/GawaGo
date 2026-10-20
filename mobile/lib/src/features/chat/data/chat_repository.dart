import '../../../core/api/gawago_api.dart';
import 'chat_models.dart';

class ChatRepository {
  const ChatRepository();

  /// Active hires the signed-in user is part of.
  Future<List<ChatConversation>> getConversations() async {
    final data = await GawaGoApi.getList('/conversations/');
    return data
        .map((item) => ChatConversation.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Full recent history, or only messages newer than [afterId] when polling.
  Future<List<ChatMessage>> getMessages(int hireId, {int? afterId}) async {
    final query = afterId == null ? '' : '?after=$afterId';
    final data = await GawaGoApi.getList(
      '/conversations/$hireId/messages/$query',
    );
    return data
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> sendMessage(int hireId, String content) async {
    final data = await GawaGoApi.post(
      '/conversations/$hireId/messages/',
      body: {'content': content},
    );
    return ChatMessage.fromJson(data);
  }

  Future<void> markRead(int hireId) async {
    await GawaGoApi.post('/conversations/$hireId/read/');
  }
}
