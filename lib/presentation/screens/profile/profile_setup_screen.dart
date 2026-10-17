import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../providers/profile_provider.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  String? _position;
  String? _skillLevel;
  bool _loading = false;

  static const _positions = [
    'Goalkeeper', 'Defender', 'Midfielder', 'Winger', 'Striker', 'Flexible'
  ];
  static const _skills = ['Beginner', 'Intermediate', 'Advanced', 'Pro'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(profileNotifierProvider.notifier).updateProfile(
            name: _nameCtrl.text.trim(),
            position: _position,
            skillLevel: _skillLevel,
          );
    } catch (e) {
      debugPrint('Profile update failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save profile. Continuing anyway...'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
    if (mounted) {
      setState(() => _loading = false);
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: const Icon(Icons.arrow_back,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(height: 28),

              Text('Build Your Player Profile',
                  style: GoogleFonts.nunito(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Tell us about your game and how you play.',
                style: GoogleFonts.dmSans(
                    fontSize: 14, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Avatar placeholder
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.primaryDeep, width: 2),
                        color: const Color(0xFF0A1F1A),
                      ),
                      child: const Icon(Icons.person,
                          color: AppColors.primaryMid, size: 44),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit,
                            color: Colors.black, size: 14),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              _Label('Full Name'),
              const SizedBox(height: 8),
              _InputField(
                controller: _nameCtrl,
                hint: 'Enter your name',
              ),

              const SizedBox(height: 18),
              _Label('Playing Position'),
              const SizedBox(height: 8),
              _DropdownField(
                hint: 'Choose your position',
                value: _position,
                items: _positions,
                onChanged: (v) => setState(() => _position = v),
              ),

              const SizedBox(height: 18),
              _Label('Skill Level'),
              const SizedBox(height: 8),
              _DropdownField(
                hint: 'Choose your level',
                value: _skillLevel,
                items: _skills,
                onChanged: (v) => setState(() => _skillLevel = v),
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : Text('Set Up Profile',
                          style: GoogleFonts.dmSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary));
}

class _InputField extends StatelessWidget {
  const _InputField({required this.controller, required this.hint});
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF051210),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: TextField(
        controller: controller,
        style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.dmSans(
              fontSize: 15, color: AppColors.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String hint;
  final String? value;
  final List<String> items;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF051210),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint,
              style: GoogleFonts.dmSans(
                  fontSize: 15, color: AppColors.textSecondary)),
          dropdownColor: const Color(0xFF051F18),
          icon: const Icon(Icons.keyboard_arrow_down,
              color: AppColors.textSecondary),
          isExpanded: true,
          style: GoogleFonts.dmSans(
              fontSize: 15, color: AppColors.textPrimary),
          onChanged: onChanged,
          items: items
              .map((i) => DropdownMenuItem(value: i, child: Text(i)))
              .toList(),
        ),
      ),
    );
  }
}
