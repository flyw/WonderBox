import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../voice/presentation/widgets/voice_input_button.dart';

class ChatInputBox extends StatefulWidget {
  final bool isStreaming;
  final bool isSpeaking;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  const ChatInputBox({
    super.key,
    required this.isStreaming,
    this.isSpeaking = false,
    required this.onSend,
    required this.onStop,
  });

  @override
  State<ChatInputBox> createState() => _ChatInputBoxState();
}

class _ChatInputBoxState extends State<ChatInputBox> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  String _prefixText = '';

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && !widget.isStreaming) {
      widget.onSend(text);
      _controller.clear();
      _prefixText = '';
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            VoiceInputButton(
              onRecordingStarted: () {
                _prefixText = _controller.text.trim();
              },
              onTextRecognized: (liveText) {
                if (liveText.isNotEmpty) {
                  if (_prefixText.isEmpty) {
                    _controller.text = liveText;
                  } else {
                    _controller.text = '$_prefixText $liveText';
                  }
                  _controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: _controller.text.length),
                  );
                }
              },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: KeyboardListener(
                  focusNode: _keyboardFocusNode,
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _handleSend();
                    }
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(
                      fontSize: 15,
                      color: theme.colorScheme.onSurface,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Type your message or speak...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (widget.isStreaming || widget.isSpeaking)
              IconButton.filled(
                icon: const Icon(Icons.stop_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                tooltip: widget.isSpeaking ? '停止说话' : '停止生成',
                onPressed: widget.onStop,
              )
            else
              IconButton.filled(
                icon: const Icon(Icons.arrow_upward_rounded),
                tooltip: 'Send prompt',
                onPressed: _handleSend,
              ),
          ],
        ),
      ),
    );
  }
}
