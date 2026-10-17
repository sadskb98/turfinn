import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/tournament_model.dart';
import '../../../data/models/team_model.dart';
import '../../providers/tournament_provider.dart';
import '../../providers/team_provider.dart';
import '../../providers/profile_provider.dart';

class TournamentDetailScreen extends ConsumerWidget {
  const TournamentDetailScreen({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(tournamentDetailProvider(tournamentId));
    final profileAsync = ref.watch(profileNotifierProvider);

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
          'Tournament',
          style: GoogleFonts.nunito(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: false,
      ),
      body: detailAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48,
                    color: AppColors.textSecondary.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(
                  'Could not load tournament',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => ref.invalidate(
                      tournamentDetailProvider(tournamentId)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Retry',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (detail) {
          final userId = profileAsync.valueOrNull?.id ?? '';
          final isCreator = userId.isNotEmpty && userId == detail.creatorId;
          final isRegistrationOpen = detail.status == 'registration_open';

          return RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.background,
            onRefresh: () async =>
                ref.invalidate(tournamentDetailProvider(tournamentId)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
              children: [
                // ── Header section ──────────────────────────────────────
                _HeaderSection(
                  detail: detail,
                  isCreator: isCreator,
                  isRegistrationOpen: isRegistrationOpen,
                  userId: userId,
                  tournamentId: tournamentId,
                ),
                const SizedBox(height: 20),

                // ── Teams section ───────────────────────────────────────
                _SectionTitle('Teams (${detail.teams.length})'),
                const SizedBox(height: 8),
                if (detail.teams.isEmpty)
                  _EmptyCard('No teams registered yet')
                else
                  ...detail.teams.map((team) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _TeamRow(team: team),
                      )),
                const SizedBox(height: 20),

                // ── Bracket section ─────────────────────────────────────
                if (detail.matches.isNotEmpty) ...[
                  _SectionTitle('Bracket'),
                  const SizedBox(height: 8),
                  _BracketView(
                    matches: detail.matches,
                    userId: userId,
                    tournamentId: tournamentId,
                    teams: detail.teams,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header Section
// ─────────────────────────────────────────────────────────────────────────────
class _HeaderSection extends ConsumerWidget {
  const _HeaderSection({
    required this.detail,
    required this.isCreator,
    required this.isRegistrationOpen,
    required this.userId,
    required this.tournamentId,
  });

  final TournamentDetail detail;
  final bool isCreator;
  final bool isRegistrationOpen;
  final String userId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = _statusColor(detail.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF062E22), Color(0xFF051A14)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.primaryDeep.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status + format badges
          Row(
            children: [
              _Badge(
                label: detail.format.replaceAll('v', ' vs '),
                color: AppColors.primaryMid,
              ),
              const SizedBox(width: 6),
              _Badge(
                label: detail.status.replaceAll('_', ' '),
                color: statusColor,
              ),
              const Spacer(),
              if (detail.visibility == 'private')
                Icon(Icons.lock_outline,
                    size: 16, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 10),

          // Name
          Text(
            detail.name,
            style: GoogleFonts.nunito(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),

          // Creator
          Text(
            'by ${detail.creatorName.isNotEmpty ? detail.creatorName : 'Unknown'}',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),

          // Info row: entry fee, prize, team count
          Row(
            children: [
              if (detail.entryFee > 0)
                _InfoChip(
                  icon: Icons.toll_outlined,
                  label: 'Entry: ${detail.entryFee} coins',
                )
              else
                _InfoChip(
                  icon: Icons.toll_outlined,
                  label: 'Free Entry',
                  highlight: true,
                ),
              const SizedBox(width: 8),
              if (detail.prizePool > 0)
                _InfoChip(
                  icon: Icons.emoji_events_outlined,
                  label: 'Prize: ${detail.prizePool} coins',
                  highlight: true,
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Team count progress
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: detail.maxTeams > 0
                        ? detail.teamCount / detail.maxTeams
                        : 0,
                    backgroundColor: AppColors.primaryDeep,
                    color: AppColors.primary,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${detail.teamCount} / ${detail.maxTeams} teams',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Action buttons
          if (isRegistrationOpen && isCreator)
            _ActionButton(
              label: 'Start Tournament',
              icon: Icons.play_arrow_rounded,
              onTap: () async {
                final error = await ref
                    .read(tournamentNotifierProvider.notifier)
                    .start(tournamentId);
                if (context.mounted && error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFF0A1F1A),
                      content: Text(error,
                          style: GoogleFonts.dmSans(color: Colors.red)),
                    ),
                  );
                }
              },
            ),

          if (isRegistrationOpen && isCreator)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ActionButton(
                label: 'Cancel Tournament',
                icon: Icons.cancel_outlined,
                color: const Color(0xFFFF4444),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF0A1F1A),
                      title: Text('Cancel Tournament?',
                          style: GoogleFonts.nunito(color: AppColors.textPrimary)),
                      content: Text(
                          'This will cancel the tournament and refund all entry fees.',
                          style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('No', style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text('Yes, Cancel', style: GoogleFonts.dmSans(color: const Color(0xFFFF4444))),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    final ok = await ref.read(tournamentNotifierProvider.notifier).cancel(tournamentId);
                    if (context.mounted && ok) {
                      Navigator.pop(context);
                    }
                  }
                },
              ),
            ),

          if (isRegistrationOpen && !isCreator)
            _ActionButton(
              label: 'Join Tournament',
              icon: Icons.group_add_outlined,
              onTap: () => _showJoinDialog(context, ref),
            ),

          // Invite code (private tournaments)
          if (detail.visibility == 'private' &&
              detail.inviteCode != null &&
              detail.inviteCode!.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: detail.inviteCode!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF0A1F1A),
                    content: Text('Invite code copied!',
                        style: GoogleFonts.dmSans(
                            color: AppColors.primary)),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryDeep.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.vpn_key_outlined,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Invite: ${detail.inviteCode}',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.copy,
                        size: 13, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showJoinDialog(BuildContext context, WidgetRef ref) {
    final myTeamsAsync = ref.read(myTeamsProvider);
    myTeamsAsync.when(
      loading: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0A1F1A),
            content: Text('Loading your teams...',
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
        );
      },
      error: (_, __) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0A1F1A),
            content: Text('Could not load your teams',
                style: GoogleFonts.dmSans(color: Colors.red)),
          ),
        );
      },
      data: (teams) {
        if (teams.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0A1F1A),
              content: Text(
                  'You have no teams. Create one first in the Teams tab.',
                  style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
            ),
          );
          return;
        }
        showDialog(
          context: context,
          builder: (_) => _TeamPickerDialog(
            teams: teams,
            tournamentId: tournamentId,
            inviteCode: detail.inviteCode,
          ),
        );
      },
    );
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'registration_open':
        return AppColors.primary;
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return AppColors.primaryMid;
      case 'cancelled':
        return Colors.red;
      default:
        return AppColors.textSecondary;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Team Picker Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _TeamPickerDialog extends ConsumerStatefulWidget {
  const _TeamPickerDialog({
    required this.teams,
    required this.tournamentId,
    this.inviteCode,
  });

  final List<TeamModel> teams;
  final String tournamentId;
  final String? inviteCode;

  @override
  ConsumerState<_TeamPickerDialog> createState() => _TeamPickerDialogState();
}

class _TeamPickerDialogState extends ConsumerState<_TeamPickerDialog> {
  String? _selectedTeamId;
  bool _joining = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0A1F1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select a Team',
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose which team to register',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.teams.length,
                itemBuilder: (context, i) {
                  final team = widget.teams[i];
                  final selected = _selectedTeamId == team.id;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selectedTeamId = team.id),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : AppColors.primaryDeep.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : AppColors.primaryDeep,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  team.name,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${team.format} - ${team.playerCount}/${team.maxPlayers} players',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            const Icon(Icons.check_circle,
                                size: 20, color: AppColors.primary),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppColors.primaryDeep),
                      ),
                      child: Center(
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _selectedTeamId == null || _joining
                        ? null
                        : () async {
                            setState(() => _joining = true);
                            final ok = await ref
                                .read(
                                    tournamentNotifierProvider.notifier)
                                .join(
                                  widget.tournamentId,
                                  _selectedTeamId!,
                                  inviteCode: widget.inviteCode,
                                );
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            if (!ok) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor:
                                      const Color(0xFF0A1F1A),
                                  content: Text(
                                      'Failed to join tournament',
                                      style: GoogleFonts.dmSans(
                                          color: Colors.red)),
                                ),
                              );
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _selectedTeamId != null
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: _joining
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Join',
                                style: GoogleFonts.dmSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Team Row
// ─────────────────────────────────────────────────────────────────────────────
class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team});

  final TournamentTeam team;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Row(
        children: [
          // Seed circle
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryDeep.withValues(alpha: 0.5),
            ),
            child: Center(
              child: Text(
                team.seed != null ? '${team.seed}' : '-',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              team.teamName.isNotEmpty ? team.teamName : 'Unknown Team',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (team.eliminated)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Eliminated',
                style: GoogleFonts.dmSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bracket View — rounds flowing left-to-right
// ─────────────────────────────────────────────────────────────────────────────
class _BracketView extends StatelessWidget {
  const _BracketView({
    required this.matches,
    required this.userId,
    required this.tournamentId,
    required this.teams,
  });

  final List<TournamentMatch> matches;
  final String userId;
  final String tournamentId;
  final List<TournamentTeam> teams;

  @override
  Widget build(BuildContext context) {
    // Group matches by round
    final roundMap = <int, List<TournamentMatch>>{};
    for (final m in matches) {
      roundMap.putIfAbsent(m.round, () => []).add(m);
    }

    // Sort rounds
    final rounds = roundMap.keys.toList()..sort();

    // Sort matches within each round by match_order
    for (final r in rounds) {
      roundMap[r]!.sort((a, b) => a.matchOrder.compareTo(b.matchOrder));
    }

    // Check if user is a captain of any team in this tournament
    final userTeamIds = <String>{};
    for (final t in teams) {
      if (t.captainId == userId) {
        userTeamIds.add(t.teamId);
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int ri = 0; ri < rounds.length; ri++) ...[
              _RoundColumn(
                round: rounds[ri],
                totalRounds: rounds.length,
                matches: roundMap[rounds[ri]]!,
                userId: userId,
                userTeamIds: userTeamIds,
                tournamentId: tournamentId,
              ),
              if (ri < rounds.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: SizedBox(
                    width: 24,
                    child: Center(
                      child: Icon(Icons.chevron_right,
                          size: 20, color: AppColors.primaryDeep),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoundColumn extends StatelessWidget {
  const _RoundColumn({
    required this.round,
    required this.totalRounds,
    required this.matches,
    required this.userId,
    required this.userTeamIds,
    required this.tournamentId,
  });

  final int round;
  final int totalRounds;
  final List<TournamentMatch> matches;
  final String userId;
  final Set<String> userTeamIds;
  final String tournamentId;

  String get _roundLabel {
    final fromFinal = totalRounds - round + 1;
    if (fromFinal == 1) return 'Final';
    if (fromFinal == 2) return 'Semi-Finals';
    if (fromFinal == 3) return 'Quarter-Finals';
    return 'Round $round';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Round label
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryDeep.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _roundLabel,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Match cards
        ...matches.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MatchCard(
                match: m,
                userId: userId,
                userTeamIds: userTeamIds,
                tournamentId: tournamentId,
              ),
            )),
      ],
    );
  }
}

class _MatchCard extends ConsumerWidget {
  const _MatchCard({
    required this.match,
    required this.userId,
    required this.userTeamIds,
    required this.tournamentId,
  });

  final TournamentMatch match;
  final String userId;
  final Set<String> userTeamIds;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeName = match.homeTeamName ?? (match.homeTeamId == null ? 'BYE' : 'TBD');
    final awayName = match.awayTeamName ?? (match.awayTeamId == null ? 'BYE' : 'TBD');

    final isReady = match.status == 'ready';
    final isReported = match.status == 'reported';

    // Check if user is captain of home or away team
    final isHomeCaptain =
        match.homeTeamId != null && userTeamIds.contains(match.homeTeamId);
    final isAwayCaptain =
        match.awayTeamId != null && userTeamIds.contains(match.awayTeamId);
    final isCaptain = isHomeCaptain || isAwayCaptain;

    // Can report score: match is ready and user is a captain
    final canReport = isReady && isCaptain;

    // Can confirm/dispute: match is reported and user is the opposing captain
    // (the one who did NOT report)
    final canConfirmDispute = isReported && isCaptain;

    final statusColor = _matchStatusColor(match.status);

    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: match.winnerId != null
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.primaryDeep,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Home team line
          _TeamScoreLine(
            name: homeName,
            score: match.homeScore,
            isWinner: match.winnerId != null &&
                match.winnerId == match.homeTeamId,
            isBye: homeName == 'BYE',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  'vs',
                  style: GoogleFonts.dmSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    match.status.replaceAll('_', ' '),
                    style: GoogleFonts.dmSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Away team line
          _TeamScoreLine(
            name: awayName,
            score: match.awayScore,
            isWinner: match.winnerId != null &&
                match.winnerId == match.awayTeamId,
            isBye: awayName == 'BYE',
          ),

          // Action buttons
          if (canReport) ...[
            const SizedBox(height: 8),
            _SmallActionButton(
              label: 'Report Score',
              onTap: () => _showReportDialog(context, ref),
            ),
          ],
          if (canConfirmDispute) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SmallActionButton(
                    label: 'Confirm',
                    onTap: () async {
                      final ok = await ref
                          .read(tournamentNotifierProvider.notifier)
                          .confirmScore(tournamentId, match.id);
                      if (context.mounted && !ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF0A1F1A),
                            content: Text('Failed to confirm score',
                                style:
                                    GoogleFonts.dmSans(color: Colors.red)),
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SmallActionButton(
                    label: 'Dispute',
                    isDestructive: true,
                    onTap: () => _showDisputeDialog(context, ref),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context, WidgetRef ref) {
    final homeCtrl = TextEditingController();
    final awayCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0A1F1A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report Score',
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _ScoreField(
                label: match.homeTeamName ?? 'Home',
                controller: homeCtrl,
              ),
              const SizedBox(height: 12),
              _ScoreField(
                label: match.awayTeamName ?? 'Away',
                controller: awayCtrl,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: AppColors.primaryDeep),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final h = int.tryParse(homeCtrl.text) ?? 0;
                        final a = int.tryParse(awayCtrl.text) ?? 0;
                        Navigator.pop(ctx);
                        final ok = await ref
                            .read(tournamentNotifierProvider.notifier)
                            .reportScore(
                                tournamentId, match.id, h, a);
                        if (context.mounted && !ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor:
                                  const Color(0xFF0A1F1A),
                              content: Text(
                                  'Failed to report score',
                                  style: GoogleFonts.dmSans(
                                      color: Colors.red)),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            'Submit',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDisputeDialog(BuildContext context, WidgetRef ref) {
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0A1F1A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dispute Score',
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Explain why the reported score is incorrect',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                style: GoogleFonts.dmSans(
                    fontSize: 14, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Reason for dispute...',
                  hintStyle: GoogleFonts.dmSans(
                      fontSize: 14, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: AppColors.inputStroke),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: AppColors.inputStroke),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: AppColors.primaryDeep),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final reason = reasonCtrl.text.trim();
                        if (reason.isEmpty) return;
                        Navigator.pop(ctx);
                        final ok = await ref
                            .read(tournamentNotifierProvider.notifier)
                            .disputeScore(
                                tournamentId, match.id, reason);
                        if (context.mounted && !ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor:
                                  const Color(0xFF0A1F1A),
                              content: Text(
                                  'Failed to submit dispute',
                                  style: GoogleFonts.dmSans(
                                      color: Colors.red)),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            'Dispute',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _matchStatusColor(String status) {
    switch (status) {
      case 'ready':
        return AppColors.primary;
      case 'reported':
        return Colors.orange;
      case 'confirmed':
        return AppColors.primaryMid;
      case 'disputed':
        return Colors.red;
      case 'bye':
        return AppColors.textSecondary;
      default: // pending
        return AppColors.textSecondary;
    }
  }
}

class _TeamScoreLine extends StatelessWidget {
  const _TeamScoreLine({
    required this.name,
    required this.score,
    required this.isWinner,
    this.isBye = false,
  });

  final String name;
  final int? score;
  final bool isWinner;
  final bool isBye;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isWinner)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.emoji_events,
                size: 12, color: AppColors.primary),
          ),
        Expanded(
          child: Text(
            name,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: isWinner ? FontWeight.w700 : FontWeight.w500,
              color: isBye
                  ? AppColors.textSecondary
                  : isWinner
                      ? AppColors.primary
                      : AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (score != null)
          Text(
            '$score',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isWinner ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
      ],
    );
  }
}

class _ScoreField extends StatelessWidget {
  const _ScoreField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 60,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: GoogleFonts.dmSans(
                  fontSize: 16, color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.inputFill,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.inputStroke),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.inputStroke),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final btnColor = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: btnColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.black),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isDestructive
              ? Colors.red.withValues(alpha: 0.15)
              : AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDestructive ? Colors.red : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.1)
            : AppColors.primaryDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 13,
              color:
                  highlight ? AppColors.primary : AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color:
                  highlight ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
