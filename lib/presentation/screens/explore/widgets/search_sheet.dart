import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/services/geocoding_service.dart';

typedef SearchResult = ({String name, double lat, double lng});

/// Full-width top search overlay — replaces the map top bar when active.
/// Call [MapSearchBar.show] to push it as a route-aware overlay.
class MapSearchBar extends StatefulWidget {
  const MapSearchBar({
    super.key,
    required this.onResult,
    required this.onDismiss,
  });

  final ValueChanged<SearchResult> onResult;
  final VoidCallback onDismiss;

  @override
  State<MapSearchBar> createState() => _MapSearchBarState();
}

class _MapSearchBarState extends State<MapSearchBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<SearchResult> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() { _results = []; _loading = false; });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 420), () async {
      final r = await GeocodingService.suggest(value.trim());
      if (!mounted) return;
      setState(() { _results = r; _loading = false; });
    });
  }

  void _pick(SearchResult r) {
    _focus.unfocus();
    widget.onResult(r);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Search field ────────────────────────────────────────────────────
        Container(
          margin: EdgeInsets.fromLTRB(12, top + 8, 12, 0),
          decoration: BoxDecoration(
            color: const Color(0xF2061512),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primaryDeep),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back,
                    color: AppColors.primary, size: 20),
                onPressed: widget.onDismiss,
              ),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  onChanged: _onChanged,
                  style: GoogleFonts.dmSans(
                      color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search area, street or landmark…',
                    hintStyle: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  ),
                )
              else if (_ctrl.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.textSecondary, size: 18),
                  onPressed: () {
                    _ctrl.clear();
                    setState(() => _results = []);
                    _focus.requestFocus();
                  },
                ),
            ],
          ),
        ),

        // ── Results ─────────────────────────────────────────────────────────
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            decoration: BoxDecoration(
              color: const Color(0xF2061512),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primaryDeep),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _results.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.primaryDeep),
              itemBuilder: (_, i) {
                final r = _results[i];
                final parts = r.name.split(', ');
                final title = parts.first;
                final sub = parts.length > 1
                    ? parts.skip(1).take(2).join(', ')
                    : null;
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on_outlined,
                      color: AppColors.primary, size: 18),
                  title: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  subtitle: sub != null
                      ? Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                              color: AppColors.textSecondary, fontSize: 11))
                      : null,
                  onTap: () => _pick(r),
                );
              },
            ),
          ),
      ],
    );
  }
}
