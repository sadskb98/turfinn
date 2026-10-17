import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart' show Share;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/pitch_model.dart';
import '../../../data/models/team_model.dart';
import '../../../data/sources/remote/pitch_remote_source.dart';
import '../../../data/sources/remote/team_remote_source.dart';
import 'match_chat_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Player data model for the formation
// ─────────────────────────────────────────────────────────────────────────────
class _Player {
  final String name;
  final String number;
  final bool isGk;
  final bool isEmpty;
  bool isSelected;

  _Player({
    required this.name,
    required this.number,
    this.isGk = false,
    this.isEmpty = false,
    this.isSelected = false,
  });
}

class TeamManagementScreen extends ConsumerStatefulWidget {
  const TeamManagementScreen({
    super.key,
    required this.team,
    required this.format,
    this.teamId,
    this.teamCode,
  });
  final String team;
  final String format;
  final String? teamId;
  final String? teamCode;

  @override
  ConsumerState<TeamManagementScreen> createState() =>
      _TeamManagementScreenState();
}

class _TeamManagementScreenState extends ConsumerState<TeamManagementScreen> {
  bool _findingMatch = false;
  MatchModel? _activeMatch;
  late int _count;
  late String _currentFormation;
  int? _selectedPlayerIndex;
  int? _selectedSubIndex;

  // Formation options per team size
  static const _formationOptions = {
    5: ['1-2-1', '2-1-1', '1-1-2'],
    6: ['2-2-1', '1-3-1', '2-1-2'],
    7: ['2-3-1', '3-2-1', '2-2-2'],
    8: ['3-3-1', '2-4-1', '3-2-2'],
    9: ['3-3-2', '3-4-1', '4-3-1'],
    10: ['4-3-2', '4-4-1', '3-4-2'],
    11: ['4-3-3', '4-4-2', '3-5-2'],
  };

  // Named players
  late List<_Player> _starters;
  late List<_Player> _subs;
  bool _loadingMembers = false;

  @override
  void initState() {
    super.initState();
    _count = int.tryParse(widget.format.split(' ').first) ?? 7;
    final options = _formationOptions[_count] ?? ['2-3-1'];
    _currentFormation = options.first;
    _buildEmptyPlayers();
    _fetchTeamMembers();
    _fetchActiveMatch();
  }

  void _buildEmptyPlayers() {
    _starters = List.generate(
      _count,
      (i) => _Player(
        name: 'Empty Slot',
        number: '${i + 1}',
        isGk: i == 0,
        isEmpty: true,
      ),
    );
    _subs = List.generate(
      5,
      (i) => _Player(
        name: 'Empty Slot',
        number: '${_count + i + 1}',
        isEmpty: true,
      ),
    );
  }

  Future<void> _fetchTeamMembers() async {
    if (widget.teamId == null) return;
    setState(() => _loadingMembers = true);
    try {
      final team =
          await ref.read(teamRemoteSourceProvider).getTeam(widget.teamId!);
      if (mounted && team.members.isNotEmpty) {
        setState(() {
          // Fill starters first, then subs
          for (int i = 0; i < _count && i < team.members.length; i++) {
            final m = team.members[i];
            _starters[i] = _Player(
              name: m.displayName,
              number: '${m.number}',
              isGk: i == 0,
            );
          }
          // Remaining members become subs
          for (int i = _count; i < team.members.length && (i - _count) < 5; i++) {
            final m = team.members[i];
            _subs[i - _count] = _Player(
              name: m.displayName,
              number: '${m.number}',
            );
          }
        });
      }
    } catch (_) {
      // Silently keep empty slots on error
    }
    if (mounted) setState(() => _loadingMembers = false);
  }

  Future<void> _fetchActiveMatch() async {
    if (widget.teamId == null) return;
    final match =
        await ref.read(teamRemoteSourceProvider).getActiveMatch(widget.teamId!);
    if (mounted && match != null) setState(() => _activeMatch = match);
  }

  void _swapPlayers(int starterIdx, int subIdx) {
    setState(() {
      final temp = _starters[starterIdx];
      _starters[starterIdx] = _Player(
        name: _subs[subIdx].name,
        number: _subs[subIdx].number,
        isGk: temp.isGk,
      );
      _subs[subIdx] = _Player(
        name: temp.name,
        number: temp.number,
      );
      _selectedPlayerIndex = null;
      _selectedSubIndex = null;
    });
  }

  void _onStarterTap(int idx) {
    setState(() {
      if (_selectedSubIndex != null) {
        _swapPlayers(idx, _selectedSubIndex!);
      } else {
        _selectedPlayerIndex = _selectedPlayerIndex == idx ? null : idx;
        // If both selected, swap
        if (_selectedPlayerIndex != null && _selectedSubIndex != null) {
          _swapPlayers(_selectedPlayerIndex!, _selectedSubIndex!);
        }
      }
    });
  }

  void _onSubTap(int idx) {
    setState(() {
      if (_selectedPlayerIndex != null) {
        _swapPlayers(_selectedPlayerIndex!, idx);
      } else {
        _selectedSubIndex = _selectedSubIndex == idx ? null : idx;
      }
    });
  }

  Future<void> _startMatchmaking() async {
    if (widget.teamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Create a team first to find matches',
              style: GoogleFonts.dmSans(color: Colors.black)),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final pick = await _pickFormatAndCity();
    if (pick == null || !mounted) return;

    setState(() => _findingMatch = true);
    try {
      final match = await ref
          .read(teamRemoteSourceProvider)
          .findMatch(widget.teamId!,
              wantedFormat: pick.$1,
              city: pick.$2,
              latitude: pick.$3,
              longitude: pick.$4);
      if (mounted) {
        setState(() => _activeMatch = match);
        if (match.isMatched) {
          _showMatchFound(match);
        } else {
          _showSearchingDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Matchmaking failed: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
    if (mounted) setState(() => _findingMatch = false);
  }

  Future<(String, String, double, double)?> _pickFormatAndCity() {
    return showModalBottomSheet<(String, String, double, double)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1F1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _FormatCityPicker(),
    );
  }

  void _showMatchFound(MatchModel match) {
    final opponentTeam =
        match.awayTeam ?? match.homeTeam; // show whichever is the opponent
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.sports_esports,
                  color: AppColors.primary, size: 36),
            ),
            const SizedBox(height: 16),
            Text('Match Found!',
                style: GoogleFonts.nunito(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
            const SizedBox(height: 6),
            if (opponentTeam != null)
              Text('vs ${opponentTeam.name}',
                  style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('Set the venue to confirm the match.',
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openVenuePicker(match.id);
                },
                child: Text('Set Venue',
                    style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openMatchChat(match);
                },
                icon: const Icon(Icons.chat_bubble_outline,
                    color: AppColors.primary, size: 16),
                label: Text('Chat with opponent',
                    style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Later',
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMatchChat(MatchModel match) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    if (token.isEmpty || !mounted) return;
    // Decode user ID from JWT payload (middle segment)
    final parts = token.split('.');
    String myUserId = '';
    if (parts.length == 3) {
      try {
        final payload = parts[1];
        final normalized = base64Url.normalize(payload);
        final decoded = utf8.decode(base64Url.decode(normalized));
        final map = jsonDecode(decoded) as Map<String, dynamic>;
        myUserId = (map['user_id'] ?? map['sub'] ?? '') as String;
      } catch (_) {}
    }
    final opponent = _opponentName(match);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MatchChatScreen(
        matchId: match.id,
        myUserId: myUserId,
        opponentTeamName: opponent,
      ),
    ));
  }

  String _opponentName(MatchModel match) {
    // We are the home or away team; return the other one's name
    final home = match.homeTeam;
    final away = match.awayTeam;
    if (widget.teamId == null) return away?.name ?? home?.name ?? 'Opponent';
    if (home?.id == widget.teamId) return away?.name ?? 'Opponent';
    return home?.name ?? 'Opponent';
  }

  void _openVenuePicker(String matchId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VenuePickerSheet(
        matchId: matchId,
        onConfirmed: (updated) {
          if (mounted) setState(() => _activeMatch = updated);
        },
      ),
    );
  }

  void _showSearchingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            Text('Searching for Opponents...',
                style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(
                'Your team is in the matchmaking queue.\nWe\'ll notify you when an opponent is found.',
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('OK',
                  style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formations = _formationOptions[_count] ?? ['2-3-1'];

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
                  Text('Teams Management',
                      style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Info row: Team Code | Formation | Match Type ────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1F1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryDeep, width: 0.5),
                ),
                child: Row(
                  children: [
                    _InfoChip(
                      label: 'Team Code',
                      value: widget.teamCode ?? '------',
                      trailing: GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(
                              text: widget.teamCode ?? ''));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Code copied!',
                                  style: GoogleFonts.dmSans(color: Colors.black)),
                              backgroundColor: AppColors.primary,
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        child: const Icon(Icons.copy_rounded,
                            size: 12, color: AppColors.primary),
                      ),
                    ),
                    _VertDivider(),
                    _InfoChip(label: 'Formation', value: widget.format),
                    _VertDivider(),
                    _InfoChip(label: 'Match Type', value: 'Friendly'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Formation picker chips ──────────────────────────────
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: formations.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final f = formations[i];
                  final active = f == _currentFormation;
                  return GestureDetector(
                    onTap: () => setState(() => _currentFormation = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? AppColors.primary
                              : AppColors.primaryDeep,
                          width: 0.5,
                        ),
                      ),
                      child: Text(f,
                          style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: active
                                  ? Colors.black
                                  : AppColors.textSecondary)),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 10),

            // ── Pitch with formation ────────────────────────────────
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primaryDeep, width: 0.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Pitch background
                      CustomPaint(
                        painter: _PitchPainter(),
                      ),
                      // Formation overlay
                      _FormationOverlay(
                        formation: _currentFormation,
                        players: _starters,
                        selectedIndex: _selectedPlayerIndex,
                        onPlayerTap: _onStarterTap,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Substitutes ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Substitutions',
                          style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                      const SizedBox(width: 6),
                      if (_selectedPlayerIndex != null)
                        Text('← Tap a sub to swap',
                            style: GoogleFonts.dmSans(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 68,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _subs.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final sub = _subs[i];
                        final selected = _selectedSubIndex == i;
                        return GestureDetector(
                          onTap: () => _onSubTap(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 56,
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.redAccent.withValues(alpha: 0.25)
                                  : Colors.redAccent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? Colors.redAccent
                                    : Colors.redAccent.withValues(alpha: 0.3),
                                width: selected ? 2 : 0.5,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: sub.isEmpty
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.redAccent.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                        sub.isEmpty ? '+' : sub.number,
                                        style: GoogleFonts.nunito(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: sub.isEmpty
                                                ? AppColors.textSecondary
                                                    .withValues(alpha: 0.5)
                                                : Colors.redAccent)),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  sub.isEmpty
                                      ? 'Open'
                                      : sub.name.split(' ').first,
                                  style: GoogleFonts.dmSans(
                                      fontSize: 9,
                                      color: sub.isEmpty
                                          ? AppColors.textSecondary
                                              .withValues(alpha: 0.5)
                                          : AppColors.textSecondary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Action buttons ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: Row(
                children: [
                  // Share Team Code
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primaryDeep),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          final code = widget.teamCode ?? '';
                          Share.share(
                              'Join my team on Turfinn! Use code: $code');
                        },
                        icon: const Icon(Icons.share_outlined,
                            color: AppColors.primary, size: 18),
                        label: Text('Share Code',
                            style: GoogleFonts.dmSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Find Match / Active Match button
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: _activeMatch != null && (_activeMatch!.isMatched || _activeMatch!.isSearching)
                          ? ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _activeMatch!.isMatched
                                    ? AppColors.primary
                                    : const Color(0xFF1A3A32),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                              onPressed: _activeMatch!.isMatched
                                  ? () => _openVenuePicker(_activeMatch!.id)
                                  : null,
                              icon: Icon(
                                _activeMatch!.isMatched
                                    ? Icons.location_on
                                    : Icons.hourglass_top,
                                color: _activeMatch!.isMatched
                                    ? Colors.black
                                    : AppColors.primary,
                                size: 18,
                              ),
                              label: Text(
                                _activeMatch!.isMatched
                                    ? 'Set Venue'
                                    : 'Searching...',
                                style: GoogleFonts.dmSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _activeMatch!.isMatched
                                        ? Colors.black
                                        : AppColors.primary),
                              ),
                            )
                          : ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                              onPressed: _findingMatch ? null : _startMatchmaking,
                              icon: _findingMatch
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.black))
                                  : const Icon(Icons.sports_esports,
                                      color: Colors.black, size: 18),
                              label: Text(
                                  _findingMatch ? 'Searching...' : 'Find Match',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black)),
                            ),
                    ),
                  ),
                if (_activeMatch != null && _activeMatch!.isMatched) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 54,
                    width: 54,
                    child: IconButton.outlined(
                      style: IconButton.styleFrom(
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline,
                          color: AppColors.primary, size: 20),
                      tooltip: 'Chat with opponent',
                      onPressed: () => _openMatchChat(_activeMatch!),
                    ),
                  ),
                ],
                ],
              ),
            ),
            // Active match confirmed banner
            if (_activeMatch != null && _activeMatch!.isConfirmed) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Match Confirmed!',
                                style: GoogleFonts.nunito(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary)),
                            if (_activeMatch!.scheduledAt != null)
                              Text(
                                _activeMatch!.scheduledAt!
                                    .replaceFirst('T', ' ')
                                    .substring(0, 16),
                                style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    color: AppColors.textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Venue Picker Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _VenuePickerSheet extends ConsumerStatefulWidget {
  const _VenuePickerSheet({
    required this.matchId,
    required this.onConfirmed,
  });
  final String matchId;
  final void Function(MatchModel) onConfirmed;

  @override
  ConsumerState<_VenuePickerSheet> createState() => _VenuePickerSheetState();
}

class _VenuePickerSheetState extends ConsumerState<_VenuePickerSheet> {
  int _selectedDayIndex = 1; // default: tomorrow
  int _selectedHour = 19; // default: 7 PM
  String? _selectedPitchId;
  String? _selectedPitchName;
  List<PitchModel> _pitches = [];
  bool _loadingPitches = true;
  bool _confirming = false;

  static const _timeOptions = [17, 18, 19, 20, 21, 22];
  static const _timeLabels = ['5 PM', '6 PM', '7 PM', '8 PM', '9 PM', '10 PM'];

  @override
  void initState() {
    super.initState();
    _loadPitches();
  }

  Future<void> _loadPitches() async {
    try {
      final pitches =
          await ref.read(pitchRemoteSourceProvider).listPitches(limit: 30);
      if (mounted) setState(() { _pitches = pitches; _loadingPitches = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingPitches = false);
    }
  }

  DateTime get _selectedDateTime {
    final now = DateTime.now();
    final day = now.add(Duration(days: _selectedDayIndex));
    return DateTime(day.year, day.month, day.day, _selectedHour);
  }

  Future<void> _confirm() async {
    if (_selectedPitchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a pitch')),
      );
      return;
    }
    setState(() => _confirming = true);
    try {
      final match = await ref.read(teamRemoteSourceProvider).setVenue(
            matchId: widget.matchId,
            pitchId: _selectedPitchId!,
            scheduledAt: _selectedDateTime.toUtc(),
          );
      if (mounted) {
        Navigator.pop(context);
        widget.onConfirmed(match);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Venue set! Match confirmed at $_selectedPitchName.'),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to set venue: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
    if (mounted) setState(() => _confirming = false);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A1F1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.primaryDeep,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Set Venue',
                style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ),
          const SizedBox(height: 16),

          // Date chips
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 8),
            child: Text('Date',
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: 8,
              itemBuilder: (_, i) {
                final d = now.add(Duration(days: i));
                final label = i == 0
                    ? 'Today'
                    : i == 1
                        ? 'Tomorrow'
                        : '${_weekday(d.weekday)} ${d.day}';
                final sel = _selectedDayIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _selectedDayIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: sel
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: sel
                              ? AppColors.primary
                              : AppColors.primaryDeep,
                          width: 0.5),
                    ),
                    child: Center(
                      child: Text(label,
                          style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.black : AppColors.textSecondary)),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // Time chips
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 8),
            child: Text('Kick-off Time',
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: _timeOptions.length,
              itemBuilder: (_, i) {
                final sel = _selectedHour == _timeOptions[i];
                return GestureDetector(
                  onTap: () => setState(() => _selectedHour = _timeOptions[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: sel
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: sel
                              ? AppColors.primary
                              : AppColors.primaryDeep,
                          width: 0.5),
                    ),
                    child: Center(
                      child: Text(_timeLabels[i],
                          style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.black : AppColors.textSecondary)),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Pitch selection
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 8),
            child: Text('Pitch',
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
          if (_loadingPitches)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: _pitches.length,
                itemBuilder: (_, i) {
                  final p = _pitches[i];
                  final sel = _selectedPitchId == p.id;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _selectedPitchId = p.id;
                      _selectedPitchName = p.name;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : const Color(0xFF033640),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                sel ? AppColors.primary : AppColors.primaryDeep,
                            width: 0.7),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.sports_soccer,
                              size: 16,
                              color: sel
                                  ? AppColors.primary
                                  : AppColors.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    style: GoogleFonts.dmSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary)),
                                Text(p.address,
                                    style: GoogleFonts.dmSans(
                                        fontSize: 11,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          if (sel)
                            const Icon(Icons.check_circle,
                                color: AppColors.primary, size: 16),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: _confirming ? null : _confirm,
                child: _confirming
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : Text('Confirm Venue',
                        style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.black)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _weekday(int d) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(d - 1) % 7];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Formation overlay — positions players on the pitch
// ─────────────────────────────────────────────────────────────────────────────
class _FormationOverlay extends StatelessWidget {
  const _FormationOverlay({
    required this.formation,
    required this.players,
    required this.selectedIndex,
    required this.onPlayerTap,
  });
  final String formation;
  final List<_Player> players;
  final int? selectedIndex;
  final void Function(int) onPlayerTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;

      // Parse formation string like "2-3-1" into rows
      final rows = formation.split('-').map((s) => int.parse(s)).toList();

      // Calculate card width based on the widest row to prevent overlap
      final maxInRow = rows.reduce((a, b) => a > b ? a : b);
      // Card width = available width / (maxInRow + 1) with padding, capped at 40px
      final cardW = ((w - 24) / (maxInRow + 1)).clamp(30.0, 40.0);

      // Build positioned players
      final widgets = <Widget>[];
      int playerIdx = 0;

      // Goalkeeper at top (defending)
      if (playerIdx < players.length) {
        widgets.add(_buildPlayer(
          players[playerIdx],
          playerIdx,
          w / 2,
          h * 0.06,
          cardW,
        ));
        playerIdx++;
      }

      // Each row of the formation, evenly spaced vertically
      final totalRows = rows.length;
      for (int r = 0; r < totalRows; r++) {
        final rowCount = rows[r];
        final yFrac = 0.15 + (r / totalRows) * 0.72;
        final y = h * yFrac;

        for (int c = 0; c < rowCount && playerIdx < players.length; c++) {
          final xFrac = (c + 1) / (rowCount + 1);
          final x = w * xFrac;
          widgets.add(_buildPlayer(players[playerIdx], playerIdx, x, y, cardW));
          playerIdx++;
        }
      }

      return Stack(children: widgets);
    });
  }

  Widget _buildPlayer(_Player player, int idx, double x, double y, double cardW) {
    final isSelected = selectedIndex == idx;
    final isGk = player.isGk;
    final isEmpty = player.isEmpty;
    final baseColor = isGk ? Colors.redAccent : AppColors.primary;
    final halfW = cardW / 2;

    return Positioned(
      left: x - halfW,
      top: y - 16,
      child: GestureDetector(
        onTap: () => onPlayerTap(idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: cardW,
          padding: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: isEmpty
                ? Colors.white.withValues(alpha: 0.05)
                : isSelected
                    ? baseColor.withValues(alpha: 0.35)
                    : baseColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isEmpty
                  ? Colors.white.withValues(alpha: 0.15)
                  : isSelected
                      ? baseColor
                      : baseColor.withValues(alpha: 0.4),
              width: isSelected ? 2 : 0.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: baseColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Jersey number circle
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isEmpty
                      ? Colors.white.withValues(alpha: 0.08)
                      : (isGk ? Colors.redAccent : AppColors.primary)
                          .withValues(alpha: 0.2),
                ),
                child: Center(
                  child: Text(
                    player.number,
                    style: GoogleFonts.nunito(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: isEmpty
                          ? AppColors.textSecondary.withValues(alpha: 0.5)
                          : (isGk ? Colors.redAccent : AppColors.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              // Name
              Text(
                isEmpty ? '+' : player.name.split(' ').first,
                style: GoogleFonts.dmSans(
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                  color: isEmpty
                      ? AppColors.textSecondary.withValues(alpha: 0.5)
                      : AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info chip for header row
// ─────────────────────────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value, this.trailing});
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w400)),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              if (trailing != null) ...[const SizedBox(width: 4), trailing!],
            ],
          ),
        ],
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 0.5, height: 30, color: AppColors.primaryDeep.withValues(alpha: 0.5));
}

// ─────────────────────────────────────────────────────────────────────────────
// Pitch painter — realistic football field markings
// ─────────────────────────────────────────────────────────────────────────────
class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background gradient
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF0A2E1E),
          const Color(0xFF0D3A26),
          const Color(0xFF0A2E1E),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    // Pitch stripe pattern (subtle)
    final stripePaint = Paint()..color = const Color(0x08FFFFFF);
    const stripeH = 40.0;
    for (double y = 0; y < h; y += stripeH * 2) {
      canvas.drawRect(Rect.fromLTWH(0, y, w, stripeH), stripePaint);
    }

    // Line paint
    final linePaint = Paint()
      ..color = AppColors.primaryDeep.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final margin = 12.0;

    // Boundary
    canvas.drawRect(
        Rect.fromLTWH(margin, margin, w - margin * 2, h - margin * 2),
        linePaint);

    // Center line
    canvas.drawLine(
        Offset(margin, h / 2), Offset(w - margin, h / 2), linePaint);

    // Center circle
    canvas.drawCircle(Offset(w / 2, h / 2), 36, linePaint);

    // Center dot
    final dotPaint = Paint()
      ..color = AppColors.primaryDeep.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w / 2, h / 2), 3, dotPaint);

    // Top penalty box
    final boxW = w * 0.45;
    final boxH = h * 0.12;
    canvas.drawRect(
        Rect.fromLTWH((w - boxW) / 2, margin, boxW, boxH), linePaint);

    // Top goal area (smaller)
    final goalW = w * 0.25;
    final goalH = h * 0.05;
    canvas.drawRect(
        Rect.fromLTWH((w - goalW) / 2, margin, goalW, goalH), linePaint);

    // Bottom penalty box
    canvas.drawRect(
        Rect.fromLTWH((w - boxW) / 2, h - margin - boxH, boxW, boxH),
        linePaint);

    // Bottom goal area
    canvas.drawRect(
        Rect.fromLTWH(
            (w - goalW) / 2, h - margin - goalH, goalW, goalH),
        linePaint);

    // Corner arcs
    final arcPaint = Paint()
      ..color = AppColors.primaryDeep.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    const cornerR = 12.0;
    // Top-left
    canvas.drawArc(
        Rect.fromCircle(center: Offset(margin, margin), radius: cornerR),
        0, 1.5708, false, arcPaint);
    // Top-right
    canvas.drawArc(
        Rect.fromCircle(center: Offset(w - margin, margin), radius: cornerR),
        1.5708, 1.5708, false, arcPaint);
    // Bottom-left
    canvas.drawArc(
        Rect.fromCircle(center: Offset(margin, h - margin), radius: cornerR),
        -1.5708, 1.5708, false, arcPaint);
    // Bottom-right
    canvas.drawArc(
        Rect.fromCircle(
            center: Offset(w - margin, h - margin), radius: cornerR),
        3.1416, 1.5708, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Format + location picker — mirrors the turf-explore PreferenceSheet UX.
// User picks format chips, then either "Use my location" or a city chip.
// Returns (format, city, lat, lng).
// ─────────────────────────────────────────────────────────────────────────────
class _FormatCityPicker extends StatefulWidget {
  const _FormatCityPicker();

  @override
  State<_FormatCityPicker> createState() => _FormatCityPickerState();
}

class _FormatCityPickerState extends State<_FormatCityPicker> {
  static const _formats = ['5v5', '6v6', '7v7', '8v8', '11v11', 'Open'];
  static const _cities = ['Chittagong', 'Dhaka', 'Sylhet', 'Rajshahi'];

  String? _selectedFormat;
  bool _locating = false;

  Future<void> _queueNearby() async {
    if (_selectedFormat == null) return;
    setState(() => _locating = true);

    double lat = 0, lng = 0;
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.deniedForever &&
          perm != LocationPermission.denied) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {
      // silently fall through — backend will do global search
    }

    if (!mounted) return;
    Navigator.of(context).pop((_selectedFormat!, '', lat, lng));
  }

  void _queueCity(String city) {
    Navigator.of(context).pop((_selectedFormat!, city, 0.0, 0.0));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final formatSelected = _selectedFormat != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 32 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Find a Match',
            style: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),

          // ── Format ──────────────────────────────────────────────────────────
          Text(
            'Format',
            style: GoogleFonts.dmSans(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _formats.map((f) {
              final selected = _selectedFormat == f;
              return GestureDetector(
                onTap: () => setState(() => _selectedFormat = f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.primaryDeep,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : AppColors.primaryDeep,
                    ),
                  ),
                  child: Text(
                    f,
                    style: GoogleFonts.dmSans(
                      color: selected ? AppColors.background : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          // ── Location (only after format chosen) ─────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: formatSelected
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Text(
                        'Where do you want to play?',
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Use my location tile
                      GestureDetector(
                        onTap: _locating ? null : _queueNearby,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.primaryDeep.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: AppColors.primaryDeep),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: _locating
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.primary),
                                      )
                                    : const Icon(Icons.my_location_rounded,
                                        color: AppColors.primary, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Use my location',
                                      style: GoogleFonts.nunito(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Find teams near you within 30 km',
                                      style: GoogleFonts.dmSans(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: AppColors.textSecondary, size: 20),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Text(
                        'Or choose your city',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _cities
                            .map(
                              (c) => GestureDetector(
                                onTap: () => _queueCity(c),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: AppColors.primaryDeep),
                                  ),
                                  child: Text(
                                    c,
                                    style: GoogleFonts.dmSans(
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
