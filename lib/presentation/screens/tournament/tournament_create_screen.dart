import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../providers/tournament_provider.dart';

class TournamentCreateScreen extends ConsumerStatefulWidget {
  const TournamentCreateScreen({super.key});

  @override
  ConsumerState<TournamentCreateScreen> createState() =>
      _TournamentCreateScreenState();
}

class _TournamentCreateScreenState
    extends ConsumerState<TournamentCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _feeCtrl = TextEditingController(text: '0');
  final _minCoinsCtrl = TextEditingController(text: '0');

  String _format = '7v7';
  int _maxTeams = 8;
  bool _isPublic = true;
  DateTime? _startsAt;
  bool _submitting = false;

  static const _formats = ['5v5', '7v7', '11v11'];
  static const _formatLabels = ['5 vs 5', '7 vs 7', '11 vs 11'];
  static const _teamOptions = [4, 8, 16, 32];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final notifier = ref.read(tournamentNotifierProvider.notifier);
    final t = await notifier.create(
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      format: _format,
      maxTeams: _maxTeams,
      entryFee: int.tryParse(_feeCtrl.text.trim()) ?? 0,
      minCoins: int.tryParse(_minCoinsCtrl.text.trim()) ?? 0,
      visibility: _isPublic ? 'public' : 'private',
      startsAt: _startsAt?.toUtc().toIso8601String(),
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (t != null) {
      context.pushReplacement('/tournaments/${t.id}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0A1F1A),
          content: Text(
            'Failed to create tournament',
            style: GoogleFonts.dmSans(color: Colors.red),
          ),
        ),
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.black,
              surface: Color(0xFF0A1F1A),
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _startsAt = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Create Tournament',
          style: GoogleFonts.nunito(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name
              _FieldLabel('Tournament Name'),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _nameCtrl,
                hint: 'e.g. Weekend Cup',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 20),

              // Description
              _FieldLabel('Description'),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _descCtrl,
                hint: 'Optional description...',
                maxLines: 3,
              ),
              const SizedBox(height: 20),

              // Format dropdown
              _FieldLabel('Format'),
              const SizedBox(height: 6),
              _buildDropdown<String>(
                value: _format,
                items: List.generate(
                  _formats.length,
                  (i) => DropdownMenuItem(
                    value: _formats[i],
                    child: Text(_formatLabels[i],
                        style: GoogleFonts.dmSans(
                            color: AppColors.textPrimary, fontSize: 14)),
                  ),
                ),
                onChanged: (v) => setState(() => _format = v ?? _format),
              ),
              const SizedBox(height: 20),

              // Max Teams dropdown
              _FieldLabel('Max Teams'),
              const SizedBox(height: 6),
              _buildDropdown<int>(
                value: _maxTeams,
                items: _teamOptions
                    .map((n) => DropdownMenuItem(
                          value: n,
                          child: Text('$n teams',
                              style: GoogleFonts.dmSans(
                                  color: AppColors.textPrimary, fontSize: 14)),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _maxTeams = v ?? _maxTeams),
              ),
              const SizedBox(height: 20),

              // Entry Fee
              _FieldLabel('Entry Fee (coins)'),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _feeCtrl,
                hint: '0 = free',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),

              // Min Coins (team requirement)
              _FieldLabel('Min Team Coins (total across members)'),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _minCoinsCtrl,
                hint: '0 = no requirement',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),

              // Visibility toggle
              _FieldLabel('Visibility'),
              const SizedBox(height: 6),
              Row(
                children: [
                  _VisibilityOption(
                    label: 'Public',
                    selected: _isPublic,
                    onTap: () => setState(() => _isPublic = true),
                  ),
                  const SizedBox(width: 12),
                  _VisibilityOption(
                    label: 'Private',
                    selected: !_isPublic,
                    onTap: () => setState(() => _isPublic = false),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Start Date
              _FieldLabel('Start Date (optional)'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.inputFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.inputStroke),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _startsAt != null
                              ? '${_startsAt!.day}/${_startsAt!.month}/${_startsAt!.year}'
                              : 'Select a date...',
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            color: _startsAt != null
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Icon(Icons.calendar_today_outlined,
                          size: 18, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'Create Tournament',
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.inputStroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.inputStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputStroke),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          dropdownColor: const Color(0xFF0A1F1A),
          icon: const Icon(Icons.keyboard_arrow_down,
              color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.nunito(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  const _VisibilityOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.12)
                : AppColors.inputFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.inputStroke,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color:
                    selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
