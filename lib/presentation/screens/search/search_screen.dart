import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<String> _history = [];

  static const _popular = [
    'Gulshan', 'Banani', 'Banasree', '300 ft', 'Dhanmondi', 'Mirpur', 'Narayanganj'
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _history = prefs.getStringList('search_history') ?? [];
    });
  }

  Future<void> _addToHistory(String term) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = [term, ..._history.where((h) => h != term)].take(8).toList();
    await prefs.setStringList('search_history', updated);
    setState(() => _history = updated);
  }

  void _submitSearch(String term) {
    if (term.trim().isEmpty) return;
    _addToHistory(term.trim());
    context.pop(term.trim());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.arrow_back,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1F1A),
                        borderRadius: BorderRadius.circular(22),
                        border:
                            Border.all(color: AppColors.primaryDeep, width: 1),
                      ),
                      child: TextField(
                        controller: _ctrl,
                        autofocus: true,
                        style: GoogleFonts.dmSans(
                            fontSize: 14, color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search for turfs by location',
                          hintStyle: GoogleFonts.dmSans(
                              fontSize: 14, color: AppColors.textSecondary),
                          prefixIcon: const Icon(Icons.search,
                              color: AppColors.textSecondary, size: 18),
                          suffixIcon: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _ctrl,
                            builder: (_, val, __) => val.text.isNotEmpty
                                ? GestureDetector(
                                    onTap: () => _ctrl.clear(),
                                    child: const Icon(Icons.close,
                                        color: AppColors.textSecondary, size: 18),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: _submitSearch,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              Text('Popular Searches in Turfinn',
                  style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              _ChipWrap(
                  chips: _popular,
                  onTap: _submitSearch),

              if (_history.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Search History',
                    style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                _ChipWrap(
                    chips: _history,
                    onTap: _submitSearch),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.chips, required this.onTap});
  final List<String> chips;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips
          .map((c) => GestureDetector(
                onTap: () => onTap(c),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primaryDeep),
                  ),
                  child: Text(c,
                      style: GoogleFonts.dmSans(
                          fontSize: 13, color: AppColors.textPrimary)),
                ),
              ))
          .toList(),
    );
  }
}
