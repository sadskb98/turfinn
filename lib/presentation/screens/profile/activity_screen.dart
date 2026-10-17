import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/booking_model.dart';
import '../../providers/booking_provider.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: const Icon(Icons.arrow_back,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Text('My Activity',
                    style: GoogleFonts.nunito(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ]),
            ),

            TabBar(
              controller: _tab,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2,
              labelStyle: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Upcoming'),
                Tab(text: 'Past'),
                Tab(text: 'Cancelled'),
              ],
            ),

            Expanded(
              child: bookingsAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
                error: (_, __) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Could not load bookings',
                          style: GoogleFonts.dmSans(
                              fontSize: 14, color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(myBookingsProvider),
                        child: Text('Retry',
                            style: GoogleFonts.dmSans(
                                color: AppColors.primary)),
                      ),
                    ],
                  ),
                ),
                data: (bookings) => TabBarView(
                  controller: _tab,
                  children: [
                    _BookingList(
                      bookings: bookings
                          .where((b) =>
                              (b.status == 'confirmed' ||
                                  b.status == 'pending') &&
                              b.startsAt.isAfter(DateTime.now()))
                          .toList(),
                      showCancel: true,
                      ref: ref,
                    ),
                    _BookingList(
                      bookings: bookings
                          .where((b) =>
                              b.status == 'completed' ||
                              b.endsAt.isBefore(DateTime.now()))
                          .toList(),
                      showCancel: false,
                      ref: ref,
                    ),
                    _BookingList(
                      bookings: bookings
                          .where((b) => b.status == 'cancelled')
                          .toList(),
                      showCancel: false,
                      ref: ref,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingList extends StatelessWidget {
  const _BookingList({
    required this.bookings,
    required this.showCancel,
    required this.ref,
  });
  final List<BookingModel> bookings;
  final bool showCancel;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sports_soccer, size: 48, color: AppColors.primaryDeep),
              const SizedBox(height: 12),
              Text('No bookings yet',
                  style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Book a pitch to see your activity here',
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: bookings.length,
      itemBuilder: (context, i) => _BookingCard(
        booking: bookings[i],
        showCancel: showCancel,
        onCancel: () =>
            ref.read(bookingNotifierProvider.notifier).cancel(bookings[i].id),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.showCancel,
    required this.onCancel,
  });
  final BookingModel booking;
  final bool showCancel;
  final VoidCallback onCancel;

  String _fmtDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month]} ${dt.day}, ${dt.year} at ${_fmtTime(dt)}';
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:${m} ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  String get _countdown {
    final diff = booking.startsAt.difference(DateTime.now());
    if (diff.inDays > 0) return 'In ${diff.inDays} Day${diff.inDays > 1 ? 's' : ''}';
    if (diff.inHours > 0) return 'In ${diff.inHours} hrs';
    return 'Soon';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF051210),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(booking.pitchName.isNotEmpty
                    ? booking.pitchName
                    : 'Green Valley Sports Complex',
                    style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: booking.status == 'cancelled'
                      ? const Color(0xFFFF4444).withValues(alpha: 0.2)
                      : AppColors.primaryMid.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  booking.status[0].toUpperCase() + booking.status.substring(1),
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: booking.status == 'confirmed'
                        ? AppColors.primary
                        : booking.status == 'cancelled'
                            ? const Color(0xFFFF4444)
                            : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_fmtDate(booking.startsAt),
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: AppColors.textSecondary)),
          if (booking.startsAt.isAfter(DateTime.now())) ...[
            const SizedBox(height: 2),
            Text(_countdown,
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: AppColors.primary)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: const StadiumBorder(),
                elevation: 0,
              ),
              onPressed: () {},
              child: Text('View Details',
                  style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black)),
            ),
          ),
          if (showCancel) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primaryDeep),
                  shape: const StadiumBorder(),
                ),
                onPressed: onCancel,
                child: Text('Cancel Booking',
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
