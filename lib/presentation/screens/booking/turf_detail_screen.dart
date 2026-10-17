import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/pitch_model.dart';
import '../../../data/models/slot_model.dart';
import '../../providers/pitch_provider.dart';

class TurfDetailScreen extends ConsumerStatefulWidget {
  const TurfDetailScreen({super.key, required this.pitchId, this.pitch});
  final String pitchId;
  final PitchModel? pitch;

  @override
  ConsumerState<TurfDetailScreen> createState() => _TurfDetailScreenState();
}

class _TurfDetailScreenState extends ConsumerState<TurfDetailScreen>
    with SingleTickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();
  SlotModel? _selectedSlot;
  late TabController _tabCtrl;
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pitchAsync = widget.pitch != null
        ? AsyncValue.data(widget.pitch!)
        : ref.watch(pitchDetailProvider(widget.pitchId));
    final slotsAsync =
        ref.watch(pitchSlotsProvider(widget.pitchId, _selectedDate));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: pitchAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const Center(
            child: Text('Could not load turf',
                style: TextStyle(color: Colors.white))),
        data: (pitch) => Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  // ── Hero image with back + pagination dots ──────────────
                  SliverToBoxAdapter(
                    child: Stack(
                      children: [
                        // Image
                        pitch.primaryImage.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: pitch.primaryImage,
                                height: 280,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                    height: 280, color: const Color(0xFF0A1F1A)),
                                errorWidget: (_, __, ___) => Container(
                                    height: 280,
                                    color: const Color(0xFF0A1F1A),
                                    child: const Center(
                                        child: Icon(Icons.sports_soccer,
                                            color: AppColors.primaryMid,
                                            size: 56))),
                              )
                            : Container(
                                height: 280, color: const Color(0xFF0A1F1A)),
                        // Gradient fade at bottom of image
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 80,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  AppColors.background,
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Back button
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 8,
                          left: 16,
                          child: GestureDetector(
                            onTap: () => context.pop(),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.arrow_back_ios_new,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                        // "Turf Details" top label
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Text('Turf Details',
                                style: GoogleFonts.nunito(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                        ),
                        // Dot indicators
                        Positioned(
                          bottom: 14,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(4, (i) {
                              return Container(
                                width: i == _imageIndex ? 20 : 6,
                                height: 6,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  color: i == _imageIndex
                                      ? AppColors.primary
                                      : Colors.white30,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Pitch info header ───────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(pitch.name,
                                              style: GoogleFonts.nunito(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w800,
                                                  color:
                                                      AppColors.textPrimary)),
                                        ),
                                        const SizedBox(width: 6),
                                        // Verified badge
                                        Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: AppColors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.check,
                                              color: Colors.black, size: 10),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.location_on_outlined,
                                            size: 13,
                                            color: AppColors.textSecondary),
                                        const SizedBox(width: 3),
                                        Expanded(
                                          child: Text(
                                              '${pitch.address}, ${pitch.city}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.dmSans(
                                                  fontSize: 12,
                                                  color: AppColors.textSecondary)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${pitch.pricePerHour.toInt()} tk',
                                style: GoogleFonts.nunito(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Action buttons row
                          Row(
                            children: [
                              _ActionPill(
                                  label: 'Book Now',
                                  filled: true,
                                  onTap: () {
                                    // Scroll down to slots section
                                    Scrollable.ensureVisible(
                                      context,
                                      duration: const Duration(milliseconds: 400),
                                    );
                                  }),
                              const SizedBox(width: 10),
                              _ActionPill(
                                  label: 'Get Direction',
                                  filled: false,
                                  onTap: () async {
                                    final lat = pitch?.latitude ?? 0;
                                    final lng = pitch?.longitude ?? 0;
                                    final Uri uri;
                                    if (lat != 0 && lng != 0) {
                                      uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(pitch?.name ?? '')})');
                                    } else {
                                      final q = Uri.encodeComponent(pitch?.address ?? pitch?.name ?? 'turf');
                                      uri = Uri.parse('https://maps.google.com/?q=$q');
                                    }
                                    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Could not open maps', style: GoogleFonts.dmSans(color: Colors.black)), backgroundColor: AppColors.primary),
                                        );
                                      }
                                    }
                                  }),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Tab bar: Facilities / Reviews / Photos / Policies ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TabBar(
                        controller: _tabCtrl,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        labelColor: AppColors.primary,
                        unselectedLabelColor: AppColors.textSecondary,
                        indicatorColor: AppColors.primary,
                        indicatorWeight: 2.5,
                        indicatorSize: TabBarIndicatorSize.label,
                        dividerColor: Colors.transparent,
                        labelStyle: GoogleFonts.dmSans(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        unselectedLabelStyle: GoogleFonts.dmSans(
                            fontSize: 14, fontWeight: FontWeight.w500),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        tabs: const [
                          Tab(text: 'Facilities'),
                          Tab(text: 'Reviews'),
                          Tab(text: 'Photos'),
                          Tab(text: 'Policies'),
                        ],
                      ),
                    ),
                  ),

                  // ── About / Facilities — collapsed below the fold ───────
                  // Booking is the primary action; About + Facilities are
                  // reference material people open if they care. Hidden in
                  // an ExpansionTile so the slot picker is reachable in
                  // one scroll.
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          title: Text('About this pitch',
                              style: GoogleFonts.nunito(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          iconColor: AppColors.textSecondary,
                          collapsedIconColor: AppColors.textSecondary,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                pitch.description.isNotEmpty
                                    ? pitch.description
                                    : 'Premium artificial turf, FIFA-approved.',
                                style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    height: 1.6),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _FacilityChip(
                                    icon: Icons.shower, label: 'Changing Room'),
                                _FacilityChip(
                                    icon: Icons.local_parking,
                                    label: 'Parking'),
                                _FacilityChip(
                                    icon: Icons.lightbulb_outline,
                                    label: 'Flood Lights'),
                                _FacilityChip(
                                    icon: Icons.sports_soccer,
                                    label: 'Match Recording'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Reserve section ──────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Reserve Your Spot',
                              style: GoogleFonts.nunito(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          const SizedBox(height: 4),

                          // Horizontal date strip — 14 days + calendar picker
                          SizedBox(
                            height: 68,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: 15, // 14 days + calendar icon
                              itemBuilder: (context, i) {
                                if (i == 14) {
                                  // Calendar picker button
                                  return GestureDetector(
                                    onTap: _pickDate,
                                    child: Container(
                                      width: 48,
                                      margin: const EdgeInsets.only(left: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0A1F1A),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppColors.primaryDeep),
                                      ),
                                      child: const Icon(Icons.calendar_month_outlined,
                                          size: 20, color: AppColors.textSecondary),
                                    ),
                                  );
                                }
                                final date = DateTime.now().add(Duration(days: i));
                                final isSelected = _selectedDate.year == date.year &&
                                    _selectedDate.month == date.month &&
                                    _selectedDate.day == date.day;
                                final dayLabel = i == 0
                                    ? 'Today'
                                    : i == 1
                                        ? 'Tomorrow'
                                        : _weekdayShort(date.weekday);
                                return GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedDate = date;
                                    _selectedSlot = null;
                                  }),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 56,
                                    margin: EdgeInsets.only(right: 8, left: i == 0 ? 0 : 0),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primary
                                          : const Color(0xFF0A1F1A),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.primaryDeep,
                                        width: isSelected ? 1.5 : 0.5,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          dayLabel,
                                          style: GoogleFonts.dmSans(
                                            fontSize: i < 2 ? 9 : 11,
                                            fontWeight: FontWeight.w600,
                                            color: isSelected
                                                ? Colors.black
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${date.day}',
                                          style: GoogleFonts.nunito(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: isSelected
                                                ? Colors.black
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          _monthShort(date.month),
                                          style: GoogleFonts.dmSans(
                                            fontSize: 9,
                                            color: isSelected
                                                ? Colors.black54
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 18),
                          Text('Available Time Slots',
                              style: GoogleFonts.nunito(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 12),

                          // Slot grid (matching Figma: 4 columns, price in each)
                          slotsAsync.when(
                            loading: () => const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.primary)),
                            ),
                            error: (_, __) => Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text('Could not load slots',
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.textSecondary)),
                            ),
                            data: (slots) => _SlotGrid(
                              slots: slots,
                              selected: _selectedSlot,
                              pricePerHour: pitch.pricePerHour,
                              onSelect: (s) =>
                                  setState(() => _selectedSlot = s),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom CTA ────────────────────────────────────────────────
            // 2-tap target: pick a slot, tap "Book". Skip the local payment
            // method picker — SSLCommerz's gateway handles bKash / Nagad /
            // cards in one screen anyway. Power users who specifically want
            // bKash etc. land on the same gateway.
            _BottomCTA(
              selectedSlot: _selectedSlot,
              pricePerHour: pitch.pricePerHour,
              onTap: () => context.push('/payment', extra: {
                'pitch': pitch,
                'startsAt': _selectedSlot!.startsAt,
                'endsAt': _selectedSlot!.endsAt,
                'method': 'bank',
                'totalCost': pitch.pricePerHour *
                    _selectedSlot!.endsAt
                        .difference(_selectedSlot!.startsAt)
                        .inMinutes /
                    60.0,
              }),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              surface: Color(0xFF0A1F1A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedSlot = null;
      });
    }
  }

  String _formatDateFull(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _weekdayShort(int weekday) =>
      const ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday];

  String _monthShort(int month) =>
      const ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
             'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month];
}

// ─────────────────────────────────────────────────────────────────────────────
// Action pill ("Book Now" / "Get Direction")
// ─────────────────────────────────────────────────────────────────────────────
class _ActionPill extends StatelessWidget {
  const _ActionPill(
      {required this.label, required this.filled, required this.onTap});
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: filled ? AppColors.primary : AppColors.primaryDeep),
        ),
        child: Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: filled ? Colors.black : AppColors.textSecondary)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Facility chip
// ─────────────────────────────────────────────────────────────────────────────
class _FacilityChip extends StatelessWidget {
  const _FacilityChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slot grid — matches Figma: 4 columns, time + price per cell
// ─────────────────────────────────────────────────────────────────────────────
class _SlotGrid extends StatelessWidget {
  const _SlotGrid({
    required this.slots,
    required this.selected,
    required this.pricePerHour,
    required this.onSelect,
  });
  final List<SlotModel> slots;
  final SlotModel? selected;
  final double pricePerHour;
  final void Function(SlotModel) onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.1,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: slots.length,
      itemBuilder: (context, i) {
        final s = slots[i];
        final isPast = s.startsAt.isBefore(DateTime.now().toUtc());
        final isSelectable = s.available && !isPast;
        final isSelected =
            selected != null && s.startsAt == selected!.startsAt;
        final hour = s.startsAt.toLocal().hour;
        final suffix = hour >= 12 ? 'PM' : 'AM';
        final h = hour % 12 == 0 ? 12 : hour % 12;
        final label = '$h:00 $suffix';

        return GestureDetector(
          onTap: isSelectable ? () => onSelect(s) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary
                  : isSelectable
                      ? const Color(0xFF0A1F1A)
                      : const Color(0xFF080E0E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : isSelectable
                        ? AppColors.primaryDeep
                        : const Color(0xFF0E1616),
                width: isSelected ? 1.5 : 0.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? Colors.black
                        : isSelectable
                            ? AppColors.textPrimary
                            : AppColors.textSecondary.withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isPast
                      ? 'Past'
                      : s.available
                          ? '${pricePerHour.toInt()} BDT'
                          : 'Booked',
                  style: GoogleFonts.dmSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? Colors.black54
                        : isSelectable
                            ? AppColors.primary.withValues(alpha: 0.8)
                            : AppColors.textSecondary.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom CTA bar — shows price + "Book Now" or "Select a slot"
// ─────────────────────────────────────────────────────────────────────────────
class _BottomCTA extends StatelessWidget {
  const _BottomCTA({
    required this.selectedSlot,
    required this.pricePerHour,
    required this.onTap,
  });
  final SlotModel? selectedSlot;
  final double pricePerHour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasSlot = selectedSlot != null;
    final hours = hasSlot
        ? selectedSlot!.endsAt.difference(selectedSlot!.startsAt).inMinutes / 60.0
        : 0.0;
    final total = (pricePerHour * hours).round();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF051210),
        border: Border(
            top: BorderSide(
                color: hasSlot
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : AppColors.primaryDeep,
                width: hasSlot ? 1 : 0.5)),
      ),
      child: Row(
        children: [
          if (hasSlot)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$total BDT',
                    style: GoogleFonts.nunito(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                Text('${hours.toStringAsFixed(1)} hr',
                    style: GoogleFonts.dmSans(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          if (hasSlot) const SizedBox(width: 20),
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      hasSlot ? AppColors.primary : const Color(0xFF0A1F1A),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: hasSlot ? 4 : 0,
                  shadowColor: AppColors.primary.withValues(alpha: 0.5),
                ),
                onPressed: hasSlot ? onTap : null,
                icon: hasSlot
                    ? const Icon(Icons.lock_rounded,
                        color: Colors.black, size: 16)
                    : const SizedBox.shrink(),
                label: Text(
                  hasSlot ? 'Book Now' : 'Select a time slot',
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: hasSlot ? Colors.black : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
