import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/models/pitch_model.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/models/gamification_models.dart';
import '../../providers/pitch_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/booking_provider.dart';
import '../../providers/gamification_provider.dart';

// 0 = nearest, 1 = budget, 2 = open now
const _kNearest = 0;
const _kBudget = 1;
const _kOpenNow = 2;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _filterIndex = -1;
  String _city = 'Dhaka';
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    _loadCity();
  }

  Future<void> _loadCity() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('location_mode') ?? '';
    final city = prefs.getString('preferred_city') ?? 'Dhaka';
    if (!mounted) return;
    setState(() => _city = mode == 'city' && city.isNotEmpty ? city : 'Dhaka');
  }

  Future<void> _acquireLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low);
      if (!mounted) return;
      setState(() { _userLat = pos.latitude; _userLng = pos.longitude; });
    } catch (_) {}
  }

  List<PitchModel> _applyFilter(List<PitchModel> pitches) {
    var list = List<PitchModel>.from(pitches);
    switch (_filterIndex) {
      case _kNearest:
        list.sort((a, b) => (a.distanceKm ?? 9999).compareTo(b.distanceKm ?? 9999));
      case _kBudget:
        list.removeWhere((p) => p.pricePerHour >= 2000);
      case _kOpenNow:
        list.retainWhere((p) => p.isActive);
    }
    return list;
  }

  Future<void> _onFilterTap(int i) async {
    final next = _filterIndex == i ? -1 : i;
    if (next == _kNearest && _userLat == null) await _acquireLocation();
    setState(() => _filterIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final useLocation = _filterIndex == _kNearest && _userLat != null;
    final pitchesAsync = ref.watch(pitchListProvider(
      city: useLocation ? null : _city,
      lat: useLocation ? _userLat : null,
      lng: useLocation ? _userLng : null,
    ));
    final profileAsync = ref.watch(profileNotifierProvider);
    final myBookingsAsync = ref.watch(myBookingsProvider);
    final walletAsync = ref.watch(walletBalanceProvider);
    final gameProfileAsync = ref.watch(playerProfileProvider);

    final userName = profileAsync.valueOrNull?.name.isNotEmpty == true
        ? profileAsync.valueOrNull!.name
        : 'Player';

    final upcoming = myBookingsAsync.valueOrNull
        ?.where((b) =>
            (b.status == 'confirmed' || b.status == 'pending') &&
            b.startsAt.isAfter(DateTime.now()))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
          slivers: [
            // ── Top bar ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Row(
                  children: [
                    // Avatar — tap to open profile (Profile is no longer in
                    // the bottom nav after the Teams/Feed swap).
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.profile),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primaryMid,
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF051210),
                            ),
                            child: Center(
                              child: Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : 'T',
                                style: GoogleFonts.nunito(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.profile),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(userName,
                              style: GoogleFonts.nunito(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          Text(
                            gameProfileAsync.valueOrNull?.levelTitle ?? 'Player',
                            style: GoogleFonts.dmSans(
                                fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Wallet chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1F1A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.primaryDeep, width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primaryDeep,
                            ),
                            child: const Center(
                              child: Text('\u09F3',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            walletAsync.when(
                              data: (b) => '$b coins',
                              loading: () => '...',
                              error: (_, __) => '0 coins',
                            ),
                            style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Tournaments Banner ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                child: GestureDetector(
                  onTap: () => context.push(AppRoutes.tournaments),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF062E22), Color(0xFF051A14)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.primaryDeep.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Icon(Icons.emoji_events,
                                size: 24, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tournaments',
                                  style: GoogleFonts.nunito(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary)),
                              const SizedBox(height: 2),
                              Text('Browse & join — Registration Open',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      color: AppColors.primaryMid)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textSecondary, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Your Next Match (if upcoming booking) ───────────────────
            if (upcoming != null && upcoming.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: _NextMatchCard(
                    booking: upcoming.first,
                    streak: gameProfileAsync.valueOrNull?.currentStreak ?? 0,
                  ),
                ),
              ),

            // ── Filter chips ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                child: _FilterChips(
                  selected: _filterIndex,
                  onChanged: _onFilterTap,
                ),
              ),
            ),

            // ── Section header ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
                child: Row(
                  children: [
                    Text(
                      _filterIndex == _kNearest && _userLat != null
                          ? 'Nearest Arenas'
                          : 'Arenas in $_city',
                      style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.explore),
                      child: Text('See all',
                          style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary)),
                    ),
                  ],
                ),
              ),
            ),

            // ── Turf cards ──────────────────────────────────────────────
            pitchesAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary)),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Text('Could not load turfs — check backend',
                        style: GoogleFonts.dmSans(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ),
                ),
              ),
              data: (pitches) {
                final filtered = _applyFilter(pitches);
                if (filtered.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Text('No turfs match this filter',
                            style: GoogleFonts.dmSans(
                                fontSize: 13, color: AppColors.textSecondary)),
                      ),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                      child: TurfCard(
                        pitch: filtered[i],
                        onTap: () => context.push(
                          '/pitches/${filtered[i].id}',
                          extra: filtered[i],
                        ),
                      ),
                    ),
                    childCount: filtered.length,
                  ),
                );
              },
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Daily Check-in Card
// ─────────────────────────────────────────────────────────────────────────────
class DailyCheckinCard extends StatelessWidget {
  const DailyCheckinCard({
    required this.checkinAsync,
    required this.onCheckin,
  });

  final AsyncValue<CheckinStatus> checkinAsync;
  final VoidCallback onCheckin;

  static const _dayRewards = [10, 10, 10, 10, 10, 10, 50];

  @override
  Widget build(BuildContext context) {
    return checkinAsync.when(
      loading: () => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primaryDeep, width: 0.5),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (status) {
        final cycle = status.cycle.isNotEmpty
            ? status.cycle
            : List.filled(7, false);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1F1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primaryDeep, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Daily Check-in',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (status.checkedInToday)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Checked In',
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: onCheckin,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Check In',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (i) {
                  final completed = i < cycle.length && cycle[i];
                  final isToday = i + 1 == status.currentDay;
                  final reward = _dayRewards[i];
                  return CheckinDayCircle(
                    day: i + 1,
                    reward: reward,
                    completed: completed,
                    isToday: isToday,
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CheckinDayCircle extends StatelessWidget {
  const CheckinDayCircle({
    required this.day,
    required this.reward,
    required this.completed,
    required this.isToday,
  });

  final int day;
  final int reward;
  final bool completed;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: completed
                ? AppColors.primary.withValues(alpha: 0.15)
                : isToday
                    ? AppColors.primaryDeep
                    : const Color(0xFF051210),
            border: Border.all(
              color: completed
                  ? AppColors.primary
                  : isToday
                      ? AppColors.primaryMid
                      : AppColors.primaryDeep,
              width: isToday ? 1.5 : 0.5,
            ),
          ),
          child: Center(
            child: completed
                ? const Icon(Icons.check, size: 18, color: AppColors.primary)
                : Text(
                    '$day',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isToday
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '+$reward',
          style: GoogleFonts.dmSans(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: completed ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Weekly Challenges Section
// ─────────────────────────────────────────────────────────────────────────────
class WeeklyChallengesSection extends StatelessWidget {
  const WeeklyChallengesSection({required this.challengesAsync});

  final AsyncValue<List<Challenge>> challengesAsync;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Weekly Challenges',
          style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        challengesAsync.when(
          loading: () => Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1F1A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primaryDeep, width: 0.5),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
          error: (_, __) => Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1F1A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primaryDeep, width: 0.5),
            ),
            child: Center(
              child: Text(
                'Could not load challenges',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          data: (challenges) {
            if (challenges.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1F1A),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: AppColors.primaryDeep, width: 0.5),
                ),
                child: Center(
                  child: Text(
                    'No challenges this week',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            }
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1F1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primaryDeep, width: 0.5),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < challenges.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Divider(
                          height: 1,
                          color: AppColors.primaryDeep.withValues(alpha: 0.5),
                        ),
                      ),
                    ChallengeRow(challenge: challenges[i]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class ChallengeRow extends StatelessWidget {
  const ChallengeRow({required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final progressFraction =
        challenge.target > 0 ? challenge.progress / challenge.target : 0.0;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      challenge.title,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (challenge.completed)
                    Text(
                      'Done',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    )
                  else
                    Text(
                      '${challenge.progress}/${challenge.target}',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progressFraction.clamp(0.0, 1.0),
                        backgroundColor: AppColors.primaryDeep,
                        color: challenge.completed
                            ? AppColors.primary
                            : AppColors.primaryMid,
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '+${challenge.coinReward}',
                    style: GoogleFonts.dmSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Your Next Match card (Figma: Home Screen with Booked Turf)
// ─────────────────────────────────────────────────────────────────────────────
class _NextMatchCard extends StatelessWidget {
  const _NextMatchCard({required this.booking, this.streak = 0});
  final BookingModel booking;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final diff = booking.startsAt.difference(DateTime.now());
    final label = diff.inDays > 0
        ? 'In ${diff.inDays}d'
        : diff.inHours > 0
            ? 'In ${diff.inHours}h'
            : 'Now';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Your Next Match',
                  style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
              if (streak > 0) ...[
                const SizedBox(width: 6),
                Icon(Icons.local_fire_department,
                    size: 14, color: Colors.orange.shade400),
                const SizedBox(width: 2),
                Text(
                  '${streak}w',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade400,
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            booking.pitchName.isNotEmpty
                ? booking.pitchName
                : 'Urban Arena — 7v7 Turf',
            style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.access_time_rounded,
                  size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                '${_fmtTime(booking.startsAt)} — ${_fmtTime(booking.endsAt)}',
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chips
// ─────────────────────────────────────────────────────────────────────────────
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onChanged});
  final int selected;
  final Future<void> Function(int) onChanged;

  static const _filters = [
    (icon: Icons.near_me_rounded, label: 'Nearest'),
    (icon: Icons.savings_outlined, label: 'Budget'),
    (icon: Icons.sports_soccer_rounded, label: 'Open Now'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_filters.length, (i) {
        final active = selected == i;
        final f = _filters[i];
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: active
                        ? AppColors.primary
                        : AppColors.primaryDeep),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(f.icon,
                      size: 13,
                      color:
                          active ? Colors.black : AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(f.label,
                      style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: active
                              ? Colors.black
                              : AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Turf card — matches Figma exactly
// ─────────────────────────────────────────────────────────────────────────────
class TurfCard extends StatelessWidget {
  const TurfCard({super.key, required this.pitch, required this.onTap});
  final PitchModel pitch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primaryDeep, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                children: [
                  pitch.primaryImage.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: pitch.primaryImage,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                              height: 160,
                              color: const Color(0xFF051210),
                              child: const Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.primaryDeep,
                                      strokeWidth: 2))),
                          errorWidget: (_, __, ___) => Container(
                              height: 160,
                              color: const Color(0xFF051210),
                              child: const Center(
                                  child: Icon(Icons.sports_soccer,
                                      color: AppColors.primaryMid,
                                      size: 44))),
                        )
                      : Container(
                          height: 160,
                          color: const Color(0xFF051210)),
                  // Gradient overlay at bottom of image
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 50,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            const Color(0xFF0A1F1A),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Card body
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(pitch.name,
                            style: GoogleFonts.nunito(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text('${pitch.address}, ${pitch.city}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Price
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${pitch.pricePerHour.toInt()} BDT/hr',
                          style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary),
                        ),
                      ),
                      if (pitch.distanceKm != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A1F1A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: AppColors.primaryDeep, width: 0.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.near_me_rounded,
                                  size: 11, color: AppColors.textSecondary),
                              const SizedBox(width: 3),
                              Text(pitch.distanceLabel,
                                  style: GoogleFonts.dmSans(
                                      fontSize: 11,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      // Open/closed dot
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pitch.isActive
                              ? AppColors.primary
                              : Colors.redAccent,
                        ),
                      ),
                      // Book Now
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('Book Now',
                            style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.black)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
