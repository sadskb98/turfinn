import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

class PanelScaffold extends StatefulWidget {
  const PanelScaffold({
    super.key,
    required this.title,
    required this.items,
    required this.selectedIndex,
    required this.onItemTap,
    required this.body,
  });
  final String title;
  final List<PanelNavItem> items;
  final int selectedIndex;
  final void Function(int) onItemTap;
  final Widget body;

  @override
  State<PanelScaffold> createState() => _PanelScaffoldState();
}

class _PanelScaffoldState extends State<PanelScaffold> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final sideW = _collapsed ? 72.0 : 240.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: sideW,
            decoration: const BoxDecoration(
              color: Color(0xFF033640),
              border: Border(right: BorderSide(color: AppColors.primaryDeep, width: 0.5)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Logo / title
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: _collapsed ? 8 : 20),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.sports_soccer, color: Colors.black, size: 20),
                      ),
                      if (!_collapsed) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                // Nav items
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: widget.items.length,
                    itemBuilder: (_, i) {
                      final item = widget.items[i];
                      final active = i == widget.selectedIndex;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => widget.onItemTap(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: EdgeInsets.symmetric(
                                horizontal: _collapsed ? 10 : 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppColors.primary.withValues(alpha: 0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: active
                                    ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.icon,
                                    size: 20,
                                    color: active
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                  ),
                                  if (!_collapsed) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        item.label,
                                        style: GoogleFonts.dmSans(
                                          fontSize: 14,
                                          fontWeight: active
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: active
                                              ? AppColors.primary
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                    if (item.badge != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '${item.badge}',
                                          style: GoogleFonts.dmSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Collapse toggle
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton(
                    onPressed: () => setState(() => _collapsed = !_collapsed),
                    icon: Icon(
                      _collapsed
                          ? Icons.chevron_right_rounded
                          : Icons.chevron_left_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Body ─────────────────────────────────────────────────
          Expanded(child: widget.body),
        ],
      ),
    );
  }
}

class PanelNavItem {
  const PanelNavItem({required this.icon, required this.label, this.badge});
  final IconData icon;
  final String label;
  final int? badge;
}
