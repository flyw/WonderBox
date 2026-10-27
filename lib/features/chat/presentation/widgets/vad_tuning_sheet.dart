import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/ambient_assistant_controller.dart';

class VadTuningSheet extends ConsumerWidget {
  const VadTuningSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const VadTuningSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(ambientAssistantProvider);
    final notifier = ref.read(ambientAssistantProvider.notifier);

    final currentRms = state.currentRms;
    final minRms = state.minRmsThreshold;
    final vadThresh = state.vadThreshold;
    final minSpeech = state.minSpeechDuration;
    final isSufficient = state.isEnergySufficient;
    final isSpeechActive = state.isSpeechActive;
    final isListening = state.isListening;

    // Normalize RMS to 0.0 - 1.0 on a 0.040 scale for visual gauge
    final gaugeValue = (currentRms / 0.040).clamp(0.0, 1.0);
    final thresholdPosition = (minRms / 0.040).clamp(0.0, 1.0);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.tune_rounded,
                      color: theme.colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VAD 拾音远近与灵敏度排查',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '实时声学能量检测 · 快速定位远近问题',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // Real-time Acoustic Energy HUD Gauge Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isListening
                        ? (isSufficient
                            ? Colors.green.withValues(alpha: 0.12)
                            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45))
                        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isListening
                          ? (isSufficient ? Colors.green.withValues(alpha: 0.5) : theme.colorScheme.outlineVariant.withValues(alpha: 0.4))
                          : theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                      width: isSufficient ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isSpeechActive
                                    ? Icons.graphic_eq_rounded
                                    : (isListening ? Icons.mic : Icons.mic_off),
                                size: 16,
                                color: isSpeechActive
                                    ? Colors.blue.shade700
                                    : (isSufficient ? Colors.green.shade700 : Colors.grey),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                '实时声学能量 (RMS)',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Text(
                            '当前: ${currentRms.toStringAsFixed(4)} / 门限: ${minRms.toStringAsFixed(4)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: isSufficient ? Colors.green.shade700 : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Gauge Visual Bar with Threshold Marker
                      Stack(
                        children: [
                          Container(
                            height: 14,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                          AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 90),
                            widthFactor: gaugeValue,
                            child: Container(
                              height: 14,
                              decoration: BoxDecoration(
                                color: isSufficient ? Colors.green.shade500 : Colors.amber.shade700,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                          // Threshold Indicator Line
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final left = constraints.maxWidth * thresholdPosition;
                                return Stack(
                                  children: [
                                    Positioned(
                                      left: left - 1,
                                      top: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 2.5,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('0.0 (极静)', style: TextStyle(fontSize: 9, color: Colors.grey)),
                          Text(
                            '门限标线 (${minRms.toStringAsFixed(3)})',
                            style: const TextStyle(fontSize: 9, color: Colors.redAccent, fontWeight: FontWeight.bold),
                          ),
                          const Text('0.040 (大声)', style: TextStyle(fontSize: 9, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Status Diagnosis Row
                      Row(
                        children: [
                          _buildMiniBadge(
                            label: isSufficient ? '✅ 能量达标 (放行)' : '🛑 能量未达 (丢弃远声)',
                            color: isSufficient ? Colors.green : Colors.amber.shade900,
                          ),
                          const SizedBox(width: 8),
                          _buildMiniBadge(
                            label: isSpeechActive
                                ? '🎙️ TEN VAD 触发中'
                                : '待命 (VAD门限 ${(vadThresh * 100).toInt()}%)',
                            color: isSpeechActive ? Colors.blue : Colors.grey.shade700,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Master Distance Slider Axis Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.social_distance_rounded, size: 16, color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                              const Text('拾音距离主调节轴', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Text(
                            _getDistanceText(state.distanceRatio),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Slider(
                        value: state.distanceRatio,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        onChanged: (val) {
                          notifier.setDistanceRatio(val);
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('🎯 贴近 (10cm)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Text('🛋️ 桌面 (45cm 推荐)', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                          Text('🌐 远场 (2.5m+)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Quick Presets
                const Text(
                  '一键距离场景预设',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: _buildPresetCard(
                        context,
                        title: '🛋️ 桌面/近身',
                        distance: '30~60 厘米 (推荐)',
                        subtitle: 'RMS 0.008 · VAD 0.40',
                        isSelected: (minRms - 0.008).abs() < 0.001 && (vadThresh - 0.40).abs() < 0.01,
                        onTap: () {
                          notifier.updateVadConfig(
                            minRmsThreshold: 0.008,
                            vadThreshold: 0.40,
                            minSpeechDuration: 0.18,
                            distanceRatio: 0.45,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPresetCard(
                        context,
                        title: '🎯 贴身专注',
                        distance: '10~20 厘米',
                        subtitle: 'RMS 0.020 · VAD 0.50',
                        isSelected: (minRms - 0.020).abs() < 0.001 && (vadThresh - 0.50).abs() < 0.01,
                        onTap: () {
                          notifier.updateVadConfig(
                            minRmsThreshold: 0.020,
                            vadThreshold: 0.50,
                            minSpeechDuration: 0.25,
                            distanceRatio: 0.10,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildPresetCard(
                  context,
                  title: '🌐 远场开阔',
                  distance: '1~3 米 (空旷大房间)',
                  subtitle: 'RMS 0.003 · VAD 0.35 · MinSpeech 0.12s',
                  isSelected: (minRms - 0.003).abs() < 0.001 && (vadThresh - 0.35).abs() < 0.01,
                  onTap: () {
                    notifier.updateVadConfig(
                      minRmsThreshold: 0.003,
                      vadThreshold: 0.35,
                      minSpeechDuration: 0.12,
                      distanceRatio: 0.85,
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Fine Tuning Sliders
                const Text(
                  '细致滑块调节 (即调即生效)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // RMS Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('物理能量门限 (RMS Gate)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(
                            minRms.toStringAsFixed(3),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                          ),
                        ],
                      ),
                      Slider(
                        value: minRms.clamp(0.002, 0.035),
                        min: 0.002,
                        max: 0.035,
                        divisions: 33,
                        onChanged: (val) {
                          notifier.updateVadConfig(minRmsThreshold: val);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          '数值越小拾音越远；数值越大需凑得越近 (30~50cm 建议 0.008 左右)',
                          style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: 8),

                      // VAD Threshold Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TEN VAD 置信度阈值', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(
                            vadThresh.toStringAsFixed(2),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                          ),
                        ],
                      ),
                      Slider(
                        value: vadThresh.clamp(0.25, 0.65),
                        min: 0.25,
                        max: 0.65,
                        divisions: 8,
                        onChanged: (val) {
                          notifier.updateVadConfig(vadThreshold: val);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          '低于门限的人声判定为静音。建议 0.38~0.45，过高（如 0.55）容易吞字',
                          style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: 8),

                      // Min Speech Duration Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('最短起嗓时长 (Min Speech)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(
                            '${(minSpeech * 1000).toInt()} ms',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                          ),
                        ],
                      ),
                      Slider(
                        value: minSpeech.clamp(0.10, 0.40),
                        min: 0.10,
                        max: 0.40,
                        divisions: 6,
                        onChanged: (val) {
                          notifier.updateVadConfig(minSpeechDuration: val);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '人声需持续该时长才判定开始，可有效过滤轻声咳嗽和碰桌杂音',
                          style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getDistanceText(double r) {
    if (r < 0.15) return '🎯 贴身 10cm';
    if (r < 0.35) return '🎯 近身 25cm';
    if (r < 0.60) return '🛋️ 桌面 45cm (推荐)';
    if (r < 0.85) return '🌐 房间 1.2m';
    return '🌐 远场 2.5m';
  }

  Widget _buildMiniBadge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPresetCard(
    BuildContext context, {
    required String title,
    required String distance,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600)),
                if (isSelected)
                  Icon(Icons.check_circle, size: 14, color: theme.colorScheme.primary),
              ],
            ),
            const SizedBox(height: 2),
            Text(distance, style: TextStyle(fontSize: 11, color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 9, color: theme.colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}
