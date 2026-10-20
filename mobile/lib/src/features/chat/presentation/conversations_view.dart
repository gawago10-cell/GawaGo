import 'package:flutter/material.dart';

import '../../../core/theme/gawago_colors.dart';
import '../../../shared/widgets/async_state.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';
import 'chat_screen.dart';

/// The Messages page: one row per active hire the signed-in user is part of.
class ConversationsView extends StatefulWidget {
  const ConversationsView({
    super.key,
    required this.role,
    this.repository = const ChatRepository(),
  });

  /// 'household' or 'worker' -- only changes the empty-state wording.
  final String role;
  final ChatRepository repository;

  @override
  State<ConversationsView> createState() => _ConversationsViewState();
}

class _ConversationsViewState extends State<ConversationsView> {
  late Future<List<ChatConversation>> _conversations;

  @override
  void initState() {
    super.initState();
    _conversations = widget.repository.getConversations();
  }

  Future<void> _reload() async {
    final next = widget.repository.getConversations();
    setState(() => _conversations = next);
    await next.catchError((_) => <ChatConversation>[]);
  }

  Future<void> _open(ChatConversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversation: conversation,
          repository: widget.repository,
        ),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ChatConversation>>(
      future: _conversations,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error, onRetry: _reload);
        }
        if (!snapshot.hasData) {
          return const AppLoadingState(message: 'Loading conversations...');
        }
        final conversations = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _reload,
          child: conversations.isEmpty
              ? ListView(
                  children: [
                    AppEmptyState(
                      icon: Icons.forum_outlined,
                      title: 'No conversations yet',
                      message: widget.role == 'household'
                          ? 'Chat becomes available once you hire a worker.'
                          : 'Chat becomes available once you get hired.',
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: conversations.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _ConversationTile(
                    conversation: conversations[index],
                    onTap: () => _open(conversations[index]),
                  ),
                ),
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final ChatConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = conversation.unreadCount;
    final last = conversation.lastMessage;
    final preview = last == null
        ? conversation.jobTitle
        : '${last.isMine ? 'You: ' : ''}${last.content}';
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: ChatAvatar(
          name: conversation.otherPartyName,
          photoUrl: conversation.otherPartyPhotoUrl,
        ),
        title: Text(
          conversation.otherPartyName,
          style: TextStyle(
            fontWeight: unread > 0 ? FontWeight.w900 : FontWeight.w700,
            color: GawaGoColors.ink,
          ),
        ),
        subtitle: Text(
          preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: unread > 0 ? GawaGoColors.ink : GawaGoColors.textMuted,
            fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        trailing: unread > 0
            ? Badge(
                label: Text(unread > 99 ? '99+' : '$unread'),
                backgroundColor: GawaGoColors.panelGreen,
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.name, this.photoUrl = ''});

  final String name;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return CircleAvatar(
      backgroundColor: GawaGoColors.panelGreen,
      foregroundColor: Colors.white,
      foregroundImage: photoUrl.isEmpty ? null : NetworkImage(photoUrl),
      // A photo that fails to load falls back to the initials underneath.
      onForegroundImageError: photoUrl.isEmpty ? null : (_, _) {},
      child: Text(initials.isEmpty ? '?' : initials),
    );
  }
}
