import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../belongings/presentation/belongings_screen.dart';
import '../domain/ask_service.dart';

/// Phase 16 UI — Ask KEEPIT.
///
/// A conversational search interface. The user types a natural-language
/// question ("where is my drill?", "what's in the garage?") and gets a
/// grounded answer from local data. All processing is on-device;
/// nothing is sent anywhere.
class AskScreen extends StatefulWidget {
  const AskScreen({super.key, required this.askService});

  static const routePath = '/ask';

  final AskKeepitService askService;

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskMessage {
  _AskMessage({required this.isUser, required this.text, this.answer});

  final bool isUser;
  final String text;
  final AskAnswer? answer;
}

class _AskScreenState extends State<AskScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_AskMessage> _messages = [];
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _busy) return;

    setState(() {
      _messages.add(_AskMessage(isUser: true, text: input));
      _busy = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final answer = await widget.askService.ask(input);
      if (!mounted) return;
      setState(() {
        _messages.add(
          _AskMessage(isUser: false, text: answer.answerText, answer: answer),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _AskMessage(
            isUser: false,
            text: 'Something went wrong looking that up. Try again.',
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask KEEPIT')),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) =>
                        _buildMessage(_messages[i]),
                  ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    const examples = [
      'Where is my drill?',
      "What's in the garage?",
      'When did I buy the TV?',
      'Is the laptop under warranty?',
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.chat_bubble_outline, size: 64),
        const SizedBox(height: 16),
        const Text(
          'Ask about your stuff in plain language.',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Answers come from your inventory on this device. Nothing leaves your phone.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        const Text('Try asking:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...examples.map(
          (e) => Card(
            child: ListTile(
              title: Text(e),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                _controller.text = e;
                _ask();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(_AskMessage message) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text),
            if (message.answer != null)
              _buildAnswerExtras(message.answer!),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerExtras(AskAnswer answer) {
    if (answer.belongings.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        ...answer.belongings.take(5).map(
              (b) => InkWell(
                onTap: () => context.push(
                  '${BelongingsScreen.routePath}/${b.id}',
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          b.name,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Ask about your stuff…',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _ask(),
                enabled: !_busy,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              onPressed: _ask,
            ),
          ],
        ),
      ),
    );
  }
}
