import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/theme/gawago_colors.dart';
import '../../../shared/utils/display_formatters.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/authenticated_shell.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';

const _maxMessageLength = 2000;

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversation,
    this.repository = const ChatRepository(),
    this.pollInterval = const Duration(seconds: 4),
  });

  final ChatConversation conversation;
  final ChatRepository repository;
  final Duration pollInterval;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = const [];
  bool _loaded = false;
  Object? _loadError;
  bool _closed = false;
  bool _polling = false;
  int _localSeq = 0;
  Timer? _timer;

  int get _hireId => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(widget.pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int? get _lastServerId {
    var last = 0;
    for (final message in _messages) {
      if (message.status == ChatMessageStatus.sent && message.id > last) {
        last = message.id;
      }
    }
    return last == 0 ? null : last;
  }

  /// Server messages keyed by id -- a poll and a send response that return
  /// the same message never duplicate it -- followed by local unsent ones.
  List<ChatMessage> _merge(
    List<ChatMessage> existing,
    List<ChatMessage> incoming,
  ) {
    final byId = <int, ChatMessage>{};
    final local = <ChatMessage>[];
    for (final message in existing) {
      if (message.status == ChatMessageStatus.sent) {
        byId[message.id] = message;
      } else {
        local.add(message);
      }
    }
    for (final message in incoming) {
      byId[message.id] = message;
    }
    final sent = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return [...sent, ...local];
  }

  void _chatClosed() {
    _timer?.cancel();
    if (mounted) setState(() => _closed = true);
  }

  Future<void> _poll() async {
    if (_polling || _closed) return;
    _polling = true;
    try {
      final incoming = await widget.repository.getMessages(
        _hireId,
        afterId: _lastServerId,
      );
      if (!mounted) return;
      final before = _messages.length;
      setState(() {
        _messages = _merge(_messages, incoming);
        _loaded = true;
        _loadError = null;
      });
      if (_messages.length > before) _scrollToEnd();
      if (incoming.any((message) => !message.isMine && !message.isRead)) {
        unawaited(widget.repository.markRead(_hireId).catchError((_) {}));
      }
    } on ApiException catch (error) {
      if (error.type == ApiErrorType.forbidden) {
        _chatClosed();
      } else if (mounted && !_loaded) {
        setState(() => _loadError = error);
      }
    } catch (error) {
      if (mounted && !_loaded) setState(() => _loadError = error);
    } finally {
      _polling = false;
    }
  }

  void _send() {
    final content = _draft.text.trim();
    if (content.isEmpty || _closed) return;
    final clientId = 'local-${_localSeq++}';
    setState(() {
      _messages = [
        ..._messages,
        ChatMessage(
          id: 0,
          clientId: clientId,
          content: content,
          isMine: true,
          createdAt: DateTime.now().toUtc().toIso8601String(),
          status: ChatMessageStatus.sending,
        ),
      ];
    });
    _draft.clear();
    _scrollToEnd();
    _deliver(clientId, content);
  }

  Future<void> _deliver(String clientId, String content) async {
    _updateLocal(
      clientId,
      (m) => m.copyWith(status: ChatMessageStatus.sending, error: ''),
    );
    try {
      final saved = await widget.repository.sendMessage(_hireId, content);
      if (!mounted) return;
      setState(() {
        _messages = _merge(
          _messages.where((m) => m.clientId != clientId).toList(),
          [saved],
        );
      });
    } catch (error) {
      if (!mounted) return;
      _updateLocal(
        clientId,
        (m) => m.copyWith(
          status: ChatMessageStatus.failed,
          error: friendlyApiError(error),
        ),
      );
      if (error is ApiException && error.type == ApiErrorType.forbidden) {
        _chatClosed();
      }
    }
  }

  void _updateLocal(String clientId, ChatMessage Function(ChatMessage) update) {
    setState(() {
      _messages = [
        for (final message in _messages)
          message.clientId == clientId ? update(message) : message,
      ];
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    return Theme(
      data: authenticatedTheme(),
      child: AuthenticatedDetailScaffold(
        title: conversation.otherPartyName,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              color: GawaGoColors.surface,
              child: Text(
                [
                  conversation.jobTitle,
                  if (conversation.statusLabel.isNotEmpty)
                    conversation.statusLabel,
                ].join(' • '),
                style: const TextStyle(color: GawaGoColors.textMuted),
              ),
            ),
            Expanded(child: _buildThread()),
            if (_closed)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: const Color(0xFFFBF1D9),
                child: const Text(
                  'This chat is closed because the job is no longer in progress.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              _Composer(controller: _draft, onSend: _send),
          ],
        ),
      ),
    );
  }

  Widget _buildThread() {
    if (!_loaded && _loadError != null) {
      return AppErrorState(error: _loadError, onRetry: _poll);
    }
    if (!_loaded) return const AppLoadingState(message: 'Loading messages...');
    if (_messages.isEmpty) {
      return const AppEmptyState(
        icon: Icons.chat_bubble_outline,
        message: 'No messages yet. Say hello to coordinate the job.',
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _MessageBubble(
          message: message,
          onRetry: message.status == ChatMessageStatus.failed && !_closed
              ? () => _deliver(message.clientId!, message.content)
              : null,
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.onRetry});

  final ChatMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final failed = message.status == ChatMessageStatus.failed;
    final foreground = mine ? Colors.white : GawaGoColors.text;
    final meta = switch (message.status) {
      ChatMessageStatus.sending => 'Sending...',
      ChatMessageStatus.failed => 'Not sent',
      ChatMessageStatus.sent => formatLocalDateTime(
        message.createdAt,
        fallback: '',
      ),
    };
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Opacity(
          opacity: message.status == ChatMessageStatus.sending ? 0.7 : 1,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              color: failed
                  ? GawaGoColors.danger
                  : mine
                  ? GawaGoColors.panelGreen
                  : GawaGoColors.surface,
              border: mine ? null : Border.all(color: GawaGoColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.content,
                  style: TextStyle(color: foreground, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  mine ? meta : '${message.senderName}  $meta',
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.7),
                    fontSize: 11.5,
                  ),
                ),
                if (onRetry != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          message.error,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onRetry,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GawaGoColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('chat-draft'),
                  controller: controller,
                  maxLength: _maxMessageLength,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    counterText: '',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => IconButton.filled(
                  tooltip: 'Send',
                  onPressed: value.text.trim().isEmpty ? null : onSend,
                  icon: const Icon(Icons.send),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
