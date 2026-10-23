import 'package:flutter/material.dart';

class ReasoningFoldout extends StatefulWidget {
  final String reasoning;
  final bool isStreaming;

  const ReasoningFoldout({
    super.key,
    required this.reasoning,
    required this.isStreaming,
  });

  @override
  State<ReasoningFoldout> createState() => _ReasoningFoldoutState();
}

class _ReasoningFoldoutState extends State<ReasoningFoldout> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    widget.isStreaming ? Icons.psychology : Icons.check_circle_outline,
                    size: 16,
                    color: widget.isStreaming ? theme.colorScheme.primary : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isStreaming ? 'Thinking...' : 'Reasoning Process',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.isStreaming ? theme.colorScheme.primary : Colors.grey.shade700,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: SelectableText(
                widget.reasoning,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
