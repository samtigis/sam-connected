import 'package:flutter/material.dart';
import '../gallery/gallery_controller.dart';

/// Utilitarian / Swiss Minimalist transfer notification banner.
/// Conforms to @samdesain guidelines:
/// - Monochromatic zinc scale
/// - 1px low-contrast border
/// - 6px border radius
/// - Zero emojis (crisp vector icons only)
/// - Real-time speed metrics in MB/s
/// - Non-blocking: minimized top banner that lets the user interact with the entire app
class TransferNotificationBanner extends StatelessWidget {
  final ActiveTaskState task;
  final VoidCallback onToggleMinimized;
  final VoidCallback onCancel;

  const TransferNotificationBanner({
    super.key,
    required this.task,
    required this.onToggleMinimized,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (!task.isActive) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5);
    final borderColor = isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);
    final textPrimary = isDark ? const Color(0xFFFAFAFA) : const Color(0xFF09090B);
    final textMuted = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
    final speedBadgeBg = isDark ? const Color(0xFF09090B) : const Color(0xFFFFFFFF);

    final overallPct = (task.overallProgress * 100).clamp(0, 100).toInt();
    final itemPct = (task.itemProgress * 100).clamp(0, 100).toInt();
    final actionLabel = task.isBackup ? 'Mencadangkan' : 'Menarik';
    final actionIcon = task.isBackup ? Icons.cloud_upload_outlined : Icons.download_outlined;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: task.isMinimized
            ? _buildMinimizedView(
                context,
                actionLabel: actionLabel,
                actionIcon: actionIcon,
                overallPct: overallPct,
                speedBadgeBg: speedBadgeBg,
                borderColor: borderColor,
                textPrimary: textPrimary,
                textMuted: textMuted,
              )
            : _buildExpandedView(
                context,
                actionLabel: actionLabel,
                actionIcon: actionIcon,
                overallPct: overallPct,
                itemPct: itemPct,
                speedBadgeBg: speedBadgeBg,
                borderColor: borderColor,
                textPrimary: textPrimary,
                textMuted: textMuted,
              ),
      ),
    );
  }

  Widget _buildMinimizedView(
    BuildContext context, {
    required String actionLabel,
    required IconData actionIcon,
    required int overallPct,
    required Color speedBadgeBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textMuted,
  }) {
    return InkWell(
      onTap: onToggleMinimized,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(actionIcon, size: 15, color: const Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(fontSize: 12, color: textPrimary, fontFamily: 'Inter'),
                      children: [
                        TextSpan(
                          text: '$actionLabel ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: '${task.current}/${task.total} ',
                          style: TextStyle(color: textMuted),
                        ),
                        TextSpan(
                          text: '($overallPct%)',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Real-time Transfer Speed Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: speedBadgeBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: borderColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.speed_rounded, size: 11, color: textMuted),
                      const SizedBox(width: 4),
                      Text(
                        task.speed,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                // Expand Icon
                IconButton(
                  icon: const Icon(Icons.expand_more_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  tooltip: 'Perluas tampilan progress',
                  onPressed: onToggleMinimized,
                ),
                // Cancel Icon
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  tooltip: 'Hentikan proses',
                  onPressed: onCancel,
                ),
              ],
            ),
          ),
          // Micro progress line at bottom of minimized bar
          LinearProgressIndicator(
            value: task.overallProgress > 0 ? task.overallProgress : null,
            minHeight: 2,
            backgroundColor: Colors.transparent,
            color: const Color(0xFF2563EB),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedView(
    BuildContext context, {
    required String actionLabel,
    required IconData actionIcon,
    required int overallPct,
    required int itemPct,
    required Color speedBadgeBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textMuted,
  }) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Icon(actionIcon, size: 16, color: const Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$actionLabel ke ${task.isBackup ? 'Server' : 'Galeri'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      '${task.current} dari ${task.total} media ($overallPct%)',
                      style: TextStyle(fontSize: 11, color: textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // Real-time Transfer Speed Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: speedBadgeBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.speed_rounded, size: 12, color: textMuted),
                    const SizedBox(width: 4),
                    Text(
                      task.speed,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Minimize button
              IconButton(
                icon: const Icon(Icons.expand_less_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                tooltip: 'Minimalkan',
                onPressed: onToggleMinimized,
              ),
              // Cancel button
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                tooltip: 'Hentikan',
                onPressed: onCancel,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Total Batch Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: task.overallProgress > 0 ? task.overallProgress : null,
              minHeight: 5,
              backgroundColor: borderColor,
              color: const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(height: 8),

          // Current Item Detail Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  task.title.isNotEmpty ? task.title : 'Menyiapkan berkas...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$itemPct%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Current Item File Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: task.itemProgress > 0 ? task.itemProgress : null,
              minHeight: 3,
              backgroundColor: borderColor.withOpacity(0.5),
              color: const Color(0xFF60A5FA),
            ),
          ),
        ],
      ),
    );
  }
}
