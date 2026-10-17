// Panel-style data table. Designed for the manager + super-admin web
// dashboards. Differences from a raw Flutter DataTable:
//   - Column-aware widths (don't make a 60-char description compete equally
//     with a 4-char status badge for horizontal space)
//   - Optional alignment per column
//   - Subtle alternating row tint + soft divider — busy old version had
//     equal-weight dividers between every row
//   - Real empty state with an icon (was just grey text)
//   - Vertical center for cells so single-line text + multi-line text
//     don't fight in the same row
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

/// Column definition. Pass a list of these for fine-grained control;
/// passing plain strings (legacy ctor) gives every column equal weight.
class TableColumn {
  const TableColumn(this.label, {this.flex = 1, this.alignRight = false});
  final String label;
  final int flex;
  final bool alignRight;
}

class DataTableCard extends StatelessWidget {
  /// Legacy constructor — every column gets flex=1, left-aligned.
  /// Existing call sites keep working unchanged.
  DataTableCard({
    super.key,
    required this.title,
    required List<String> columns,
    required this.rows,
    this.onRefresh,
    this.trailing,
  }) : columns = columns.map((c) => TableColumn(c)).toList();

  /// Rich constructor — supply per-column flex + alignment.
  const DataTableCard.rich({
    super.key,
    required this.title,
    required this.columns,
    required this.rows,
    this.onRefresh,
    this.trailing,
  });

  final String title;
  final List<TableColumn> columns;
  final List<List<Widget>> rows;
  final VoidCallback? onRefresh;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.primaryDeep.withValues(alpha: 0.6), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar — title left, count badge inline, refresh + trailing right
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
            decoration: const BoxDecoration(
              border: Border(
                bottom:
                    BorderSide(color: Color(0xFF143A33), width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (onRefresh != null)
                  IconButton(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppColors.textSecondary, size: 18),
                    tooltip: 'Refresh',
                    splashRadius: 18,
                  ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          // Column headers
          Container(
            color: const Color(0xFF071712),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            child: Row(
              children: columns
                  .map((c) => Expanded(
                        flex: c.flex,
                        child: Align(
                          alignment: c.alignRight
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Text(
                            c.label.toUpperCase(),
                            style: GoogleFonts.dmSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          // Rows
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 56),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 36,
                        color: AppColors.textSecondary.withValues(alpha: 0.6)),
                    const SizedBox(height: 10),
                    Text(
                      'No data yet',
                      style: GoogleFonts.dmSans(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(rows.length, (i) {
              final cells = rows[i];
              final isOdd = i.isOdd;
              return Container(
                color: isOdd
                    ? const Color(0xFF0D2520)
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color:
                            i == rows.length - 1
                                ? Colors.transparent
                                : const Color(0xFF0E2A24),
                        width: 0.5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(cells.length, (j) {
                    final col =
                        j < columns.length ? columns[j] : const TableColumn('');
                    return Expanded(
                      flex: col.flex,
                      child: Align(
                        alignment: col.alignRight
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: cells[j],
                      ),
                    );
                  }),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Status pill — friendlier than ALL-CAPS shouty version. Spaces out the
/// underscores for legibility, picks colors based on common keywords.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final color = switch (s) {
      'confirmed' ||
      'ready' ||
      'matched' ||
      'active' ||
      'success' ||
      'refunded' ||
      'collected' ||
      'super_admin' =>
        AppColors.primary,
      'pending' ||
      'searching' ||
      'forming' ||
      'submitted' ||
      'requested' ||
      'manager' =>
        const Color(0xFFFFC857),
      'cancelled' ||
      'banned' ||
      'failed' ||
      'refund_failed' ||
      'rejected' =>
        const Color(0xFFFF6B6B),
      'completed' || 'admin' => const Color(0xFF6FA8FF),
      _ => AppColors.textSecondary,
    };

    // Title-case + replace underscores. Easier to read than ALL CAPS.
    final pretty = s
        .split('_')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.6),
      ),
      child: Text(
        pretty,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Cell text — single line by default with ellipsis. Tooltip surfaces the
/// full text on hover for desktop users so truncation never hides info.
/// Pass `subtitle` to render a secondary grey line below (great for
/// "name + phone" or "title + venue" patterns).
class CellText extends StatelessWidget {
  const CellText(
    this.text, {
    super.key,
    this.bold = false,
    this.subtitle,
    this.muted = false,
  });
  final String text;
  final bool bold;
  final String? subtitle;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final main = Text(
      text,
      style: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: muted ? AppColors.textSecondary : AppColors.textPrimary,
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
    final body = subtitle == null || subtitle!.isEmpty
        ? main
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              main,
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          );
    return Tooltip(
      message: subtitle == null ? text : '$text\n$subtitle',
      waitDuration: const Duration(milliseconds: 600),
      child: body,
    );
  }
}
