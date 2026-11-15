import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config.dart';
import '../services/api.dart';
import '../services/athena.dart';
import '../theme.dart';

/// Athena's line icon, used in headers and next to her messages.
const athenaIcon = Icons.forum_outlined;

/// The Athena chat: messages, quick questions, and a text box.
/// Used full screen on phones and as a side panel on the web pages.
class AthenaChat extends StatefulWidget {
  const AthenaChat({
    super.key,
    required this.conversation,
    required this.api,
    this.workerId,
    this.header = false,
    this.onClose,
  });

  final AthenaConversation conversation;
  final Api api;
  final String? workerId;

  /// Show Athena's name at the top (the web panel; phones use the app bar).
  final bool header;
  final VoidCallback? onClose;

  @override
  State<AthenaChat> createState() => _AthenaChatState();
}

class _AthenaChatState extends State<AthenaChat> {
  final _text = TextEditingController();
  final _scroll = ScrollController();

  AthenaConversation get _chat => widget.conversation;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_scrollToEnd);
  }

  @override
  void dispose() {
    _chat.removeListener(_scrollToEnd);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send([String? text]) {
    final question = text ?? _text.text;
    if (question.trim().isEmpty) return;
    _text.clear();
    _chat.ask(widget.api, question, workerId: widget.workerId);
  }

  /// Opens Athena Live: a video call inside the app where Athena looks through the camera.
  /// The person starts it themselves; the camera is never used in the background.
  void _startLiveCall() =>
      context.push('/athena/live?role=${_chat.role}', extra: widget.api);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _chat,
    builder: (context, _) => Column(
      children: [
        if (widget.header) _header(),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              if (_chat.turns.isEmpty) _intro(),
              for (final turn in _chat.turns) _bubble(turn),
              if (_chat.thinking)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Athena is thinking…',
                    style: body(14, color: BB.muted),
                  ),
                ),
            ],
          ),
        ),
        _suggestions(),
        _inputBar(),
      ],
    ),
  );

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
    decoration: const BoxDecoration(
      color: BB.white,
      border: Border(bottom: BorderSide(color: BB.line)),
    ),
    child: Row(
      children: [
        _avatar(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Athena', style: heading(18)),
              Text(
                'Cycl0ps site assistant',
                semanticsLabel: 'Cyclops site assistant',
                style: body(12, color: BB.muted),
              ),
            ],
          ),
        ),
        if (widget.onClose != null)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close Athena',
            onPressed: widget.onClose,
          ),
      ],
    ),
  );

  Widget _avatar() => Container(
    width: 36,
    height: 36,
    decoration: const BoxDecoration(color: BB.ink, shape: BoxShape.circle),
    child: const Icon(athenaIcon, color: BB.white, size: 20),
  );

  Widget _intro() => Container(
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: cardBox(),
    child: Text(switch (_chat.role) {
      'worker' =>
        'Ask Athena about safety on your floor. She can see your floor, '
            'your zone, and the hazards there. Never other workers.',
      'rescuer' =>
        'Ask Athena who is missing, where they were last seen, '
            'and the nearest stairs.',
      _ =>
        'Ask Athena about the site: who is where, who needs help, '
            'and today\'s hazards. She answers from the live data.',
    }, style: body(15, color: BB.muted)),
  );

  Widget _bubble(AthenaTurn turn) {
    final user = turn.fromUser;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: user ? BB.ink : BB.white,
        border: user ? null : Border.all(color: BB.line),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(user ? 16 : 4),
          bottomRight: Radius.circular(user ? 4 : 16),
        ),
      ),
      child: turn.offline
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 18, color: BB.muted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(turn.text, style: body(15, color: BB.muted)),
                ),
              ],
            )
          : SelectableText(
              turn.text,
              style: body(15, color: user ? BB.white : BB.ink),
            ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: user
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!user) ...[
            Semantics(label: 'Athena', child: _avatar()),
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }

  Widget _suggestions() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        for (final question in _chat.suggestions)
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 8),
            child: OutlinedButton(
              onPressed: _chat.thinking ? null : () => _send(question),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: BB.ink,
                backgroundColor: BB.white,
                side: const BorderSide(color: BB.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Text(question, style: body(14)),
            ),
          ),
      ],
    ),
  );

  Widget _inputBar() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    decoration: const BoxDecoration(
      color: BB.white,
      border: Border(top: BorderSide(color: BB.line)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Ask Athena about the site',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            if (Config.featureAthenaLive) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                height: 52,
                child: IconButton.filled(
                  onPressed: _startLiveCall,
                  tooltip: 'Video call Athena',
                  style: IconButton.styleFrom(
                    backgroundColor: BB.ink,
                    foregroundColor: BB.white,
                  ),
                  icon: const Icon(Icons.videocam_outlined),
                ),
              ),
            ],
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              height: 52,
              child: IconButton.filled(
                onPressed: _chat.thinking ? null : _send,
                tooltip: 'Send',
                style: IconButton.styleFrom(
                  backgroundColor: BB.accent,
                  foregroundColor: BB.white,
                ),
                icon: const Icon(Icons.send_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Athena can be wrong. In an emergency, call 911.',
          style: body(12, color: BB.muted),
        ),
      ],
    ),
  );
}
