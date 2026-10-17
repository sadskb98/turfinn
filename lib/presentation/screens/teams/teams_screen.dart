import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/team_model.dart';
import '../../../data/sources/remote/team_remote_source.dart';
import '../../providers/team_provider.dart';

class TeamsScreen extends ConsumerStatefulWidget {
  const TeamsScreen({super.key});

  @override
  ConsumerState<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends ConsumerState<TeamsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  // Back button only when this screen was pushed (e.g. from
                  // Play "My Teams" pill). When reached as a bottom-nav tab,
                  // there's nothing to pop — just hide it.
                  if (Navigator.of(context).canPop()) ...[
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new,
                            color: AppColors.primary, size: 15),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text('Teams',
                      style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Tabs: Create / Join ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1F1A),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.primaryDeep, width: 0.5),
                ),
                child: TabBar(
                  controller: _tabCtrl,
                  indicator: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelStyle: GoogleFonts.dmSans(
                      fontSize: 14, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: GoogleFonts.dmSans(
                      fontSize: 14, fontWeight: FontWeight.w500),
                  labelColor: Colors.black,
                  unselectedLabelColor: AppColors.textSecondary,
                  tabs: const [
                    Tab(text: 'Create Team'),
                    Tab(text: 'Join Team'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Tab content ─────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _CreateTeamTab(ref: ref),
                  _JoinTeamTab(ref: ref),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Team tab
// ─────────────────────────────────────────────────────────────────────────────
class _CreateTeamTab extends StatefulWidget {
  const _CreateTeamTab({required this.ref});
  final WidgetRef ref;

  @override
  State<_CreateTeamTab> createState() => _CreateTeamTabState();
}

class _CreateTeamTabState extends State<_CreateTeamTab> {
  final _nameCtrl = TextEditingController(text: 'Team A');
  String? _matchFormat;
  bool _loading = false;

  static const _formats = [
    '5 vs 5', '6 vs 6', '7 vs 7', '8 vs 8',
    '9 vs 9', '10 vs 10', '11 vs 11',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty || _matchFormat == null) return;
    setState(() => _loading = true);
    try {
      final team = await widget.ref
          .read(teamRemoteSourceProvider)
          .createTeam(name: _nameCtrl.text.trim(), format: _matchFormat!);
      if (mounted) {
        widget.ref.invalidate(myTeamsProvider);
        context.push('/teams/manage', extra: {
          'team': team.name,
          'format': team.format,
          'teamId': team.id,
          'teamCode': team.code,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to create team: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _nameCtrl.text.trim().isNotEmpty && _matchFormat != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Build Your Teams',
              style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Create your squad and invite an opponent captain.',
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 24),

          Text('Team Name',
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          _InputField(controller: _nameCtrl, hint: 'Enter team name'),

          const SizedBox(height: 20),

          Text('Match Format',
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          _DropdownField(
            hint: 'Choose Team Size',
            value: _matchFormat,
            items: _formats,
            onChanged: (v) => setState(() => _matchFormat = v),
          ),

          const Spacer(),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    ready ? AppColors.primary : const Color(0xFF0A1F1A),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: (ready && !_loading) ? _create : null,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text(
                      ready ? 'Build Team' : 'Confirm',
                      style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color:
                              ready ? Colors.black : AppColors.textSecondary),
                    ),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Join Team tab
// ─────────────────────────────────────────────────────────────────────────────
class _JoinTeamTab extends StatefulWidget {
  const _JoinTeamTab({required this.ref});
  final WidgetRef ref;

  @override
  State<_JoinTeamTab> createState() => _JoinTeamTabState();
}

class _JoinTeamTabState extends State<_JoinTeamTab> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter a 6-digit team code');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final team =
          await widget.ref.read(teamRemoteSourceProvider).joinTeam(code);
      if (mounted) {
        widget.ref.invalidate(myTeamsProvider);
        context.push('/teams/manage', extra: {
          'team': team.name,
          'format': team.format,
          'teamId': team.id,
          'teamCode': team.code,
        });
      }
    } catch (e) {
      setState(() => _error = 'Invalid code or team is full');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Join a Team',
              style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(
              'Got a team code from your captain? Enter it below to join the squad.',
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 28),

          Text('Team Code',
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),

          // Code input — 6 characters
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF051210),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                  color: _error != null
                      ? Colors.redAccent
                      : AppColors.primaryDeep),
            ),
            child: TextField(
              controller: _codeCtrl,
              maxLength: 6,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: 10),
              decoration: InputDecoration(
                hintText: '000000',
                hintStyle: GoogleFonts.nunito(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                    letterSpacing: 10),
                border: InputBorder.none,
                counterText: '',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!,
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: Colors.redAccent)),
          ],

          const Spacer(),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _loading ? null : _join,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text('Join Team',
                      style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black)),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────
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
      padding: const EdgeInsets.symmetric(horizontal: 18),
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
          dropdownColor: const Color(0xFF0A1F1A),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary),
          isExpanded: true,
          style:
              GoogleFonts.dmSans(fontSize: 15, color: AppColors.textPrimary),
          onChanged: onChanged,
          items: items
              .map((i) => DropdownMenuItem(value: i, child: Text(i)))
              .toList(),
        ),
      ),
    );
  }
}
