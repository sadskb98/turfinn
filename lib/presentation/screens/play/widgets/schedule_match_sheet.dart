import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/pitch_model.dart';
import '../../../../data/sources/remote/feed_remote_source.dart';
import '../../../providers/feed_provider.dart';
import '../../../providers/pitch_provider.dart';
import '../../../widgets/toast.dart';

const _kFormats = ['5v5', '6v6', '7v7', '11v11'];
const _kFormatSpots = {'5v5': 10, '6v6': 12, '7v7': 14, '11v11': 22};

/// 3-step wizard:
///   1. Pick a Turfinn pitch
///   2. Pick date + start time + duration
///   3. Pick format + spots + post-type, confirm
class ScheduleMatchSheet extends ConsumerStatefulWidget {
  const ScheduleMatchSheet({
    super.key,
    required this.userLat,
    required this.userLng,
  });

  final double? userLat;
  final double? userLng;

  @override
  ConsumerState<ScheduleMatchSheet> createState() =>
      _ScheduleMatchSheetState();
}

class _ScheduleMatchSheetState extends ConsumerState<ScheduleMatchSheet> {
  int _step = 0;

  PitchModel? _pitch;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _start = const TimeOfDay(hour: 18, minute: 0);
  int _durationMinutes = 90;
  String _format = '7v7';
  int _spots = 14;
  // post_type is hidden in v1 — always open_match. "Need teammates" is a
  // v2 feature; >90% of demand is "I have a pitch, need more players".
  static const String _postType = 'open_match';

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _spots = _kFormatSpots[_format] ?? 14;
  }

  @override
  void dispose() {
    super.dispose();
  }

  DateTime get _matchDateTime => DateTime(
      _date.year, _date.month, _date.day, _start.hour, _start.minute);

  int? get _perHeadEstimate {
    if (_pitch == null || _spots <= 0) return null;
    final totalCost = _pitch!.pricePerHour * _durationMinutes / 60.0;
    return (totalCost / _spots).round();
  }

  Future<void> _submit() async {
    if (_pitch == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final remote = ref.read(feedRemoteSourceProvider);
      // Auto-title — readable + searchable. Users almost never customise the
      // title and adding a field for it just adds friction.
      final df = DateFormat('EEE');
      final tf = DateFormat('h:mma');
      final autoTitle = '$_format · ${df.format(_matchDateTime)} ${tf.format(_matchDateTime).toLowerCase()}';
      await remote.createPost(
        pitchId: _pitch!.id,
        title: autoTitle,
        matchDate: _matchDateTime,
        spotsTotal: _spots,
        postType: _postType,
        durationMinutes: _durationMinutes,
        format: _format,
      );
      if (!mounted) return;
      ref.invalidate(feedListProvider);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showError(context, _friendlyError(e));
      setState(() => _submitting = false);
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('slot already booked')) {
      return 'That slot is already booked. Pick a different time.';
    }
    if (s.contains('pitch not found') || s.contains('not active')) {
      return 'This pitch is not available for matchmaking.';
    }
    return 'Could not schedule the match. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF033640),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.primaryDeep,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _header(),
            const Divider(height: 1, color: Color(0xFF0E2A24)),
            Expanded(child: _stepBody(ctrl)),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final titles = ['Pick a pitch', 'When?', 'Match details'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Schedule a match',
                  style: GoogleFonts.nunito(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const Spacer(),
              Text('Step ${_step + 1} of 3',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 6),
          Text(titles[_step],
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: List.generate(3, (i) {
              final active = i <= _step;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  height: 3,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary
                        : AppColors.primaryDeep.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _stepBody(ScrollController ctrl) {
    switch (_step) {
      case 0:
        return _PitchPicker(
          userLat: widget.userLat,
          userLng: widget.userLng,
          selected: _pitch,
          scrollController: ctrl,
          onPick: (p) => setState(() => _pitch = p),
        );
      case 1:
        return _SlotPicker(
          scrollController: ctrl,
          date: _date,
          start: _start,
          duration: _durationMinutes,
          onDate: (d) => setState(() => _date = d),
          onStart: (t) => setState(() => _start = t),
          onDuration: (m) => setState(() => _durationMinutes = m),
        );
      case 2:
        return _DetailsForm(
          scrollController: ctrl,
          format: _format,
          spots: _spots,
          pitch: _pitch,
          duration: _durationMinutes,
          perHead: _perHeadEstimate,
          onFormat: (f) => setState(() {
            _format = f;
            _spots = _kFormatSpots[f] ?? _spots;
          }),
          onSpots: (n) => setState(() => _spots = n),
        );
    }
    return const SizedBox.shrink();
  }

  Widget _footer() {
    final canAdvance = _canAdvance();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            if (_step > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _submitting ? null : () => setState(() => _step--),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primaryDeep),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Back',
                      style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            if (_step > 0) const SizedBox(width: 10),
            Expanded(
              flex: _step == 0 ? 1 : 2,
              child: ElevatedButton(
                onPressed: !canAdvance || _submitting
                    ? null
                    : () {
                        if (_step < 2) {
                          setState(() => _step++);
                        } else {
                          _submit();
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primaryDeep.withValues(alpha: 0.5),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : Text(_step == 2 ? 'Post match' : 'Continue',
                        style: GoogleFonts.nunito(
                            fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canAdvance() {
    switch (_step) {
      case 0:
        return _pitch != null;
      case 1:
        return _matchDateTime.isAfter(DateTime.now());
      case 2:
        return _spots >= 2;
    }
    return false;
  }
}

// ── Step 1: Pitch picker ────────────────────────────────────────────────────

class _PitchPicker extends ConsumerWidget {
  const _PitchPicker({
    required this.userLat,
    required this.userLng,
    required this.selected,
    required this.scrollController,
    required this.onPick,
  });

  final double? userLat;
  final double? userLng;
  final PitchModel? selected;
  final ScrollController scrollController;
  final ValueChanged<PitchModel> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pitchListProvider(
      lat: userLat,
      lng: userLng,
    ));
    return async.when(
      data: (pitches) {
        if (pitches.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                'No pitches available right now.',
                style: GoogleFonts.dmSans(color: AppColors.textSecondary),
              ),
            ),
          );
        }
        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          itemCount: pitches.length,
          itemBuilder: (_, i) {
            final p = pitches[i];
            final isSelected = selected?.id == p.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => onPick(p),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.10)
                        : const Color(0xFF0A1F1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.primaryDeep.withValues(alpha: 0.5),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: p.imageUrls.split(',').first.trim().isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: p.imageUrls.split(',').first.trim(),
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                      color: AppColors.primaryDeep),
                                  errorWidget: (_, __, ___) => Container(
                                    color: AppColors.primaryDeep,
                                    child: const Icon(
                                        Icons.sports_soccer_rounded,
                                        color: AppColors.primary),
                                  ),
                                )
                              : Container(
                                  color: AppColors.primaryDeep,
                                  child: const Icon(
                                      Icons.sports_soccer_rounded,
                                      color: AppColors.primary),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: GoogleFonts.nunito(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(p.city,
                                style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text('${p.pricePerHour.toInt()} BDT/hr',
                                    style: GoogleFonts.dmSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary)),
                                if (p.distanceKm != null) ...[
                                  const SizedBox(width: 8),
                                  Text('· ${p.distanceKm!.toStringAsFixed(1)} km',
                                      style: GoogleFonts.dmSans(
                                          fontSize: 12,
                                          color: AppColors.textSecondary)),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded,
                            color: AppColors.primary, size: 22),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load pitches.\n$e',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
        ),
      ),
    );
  }
}

// ── Step 2: Slot picker ─────────────────────────────────────────────────────

class _SlotPicker extends StatelessWidget {
  const _SlotPicker({
    required this.scrollController,
    required this.date,
    required this.start,
    required this.duration,
    required this.onDate,
    required this.onStart,
    required this.onDuration,
  });

  final ScrollController scrollController;
  final DateTime date;
  final TimeOfDay start;
  final int duration;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<TimeOfDay> onStart;
  final ValueChanged<int> onDuration;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEE, MMM d');
    final endTime = TimeOfDay(
      hour: (start.hour + (duration ~/ 60)) % 24,
      minute: (start.minute + duration % 60) % 60,
    );

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _label('Date'),
        _tile(
          icon: Icons.calendar_today_rounded,
          text: dateFmt.format(date),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              firstDate: now,
              lastDate: now.add(const Duration(days: 30)),
              initialDate: date,
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme:
                      const ColorScheme.dark(primary: AppColors.primary),
                ),
                child: child!,
              ),
            );
            if (picked != null) onDate(picked);
          },
        ),
        const SizedBox(height: 16),
        _label('Start time'),
        _tile(
          icon: Icons.schedule_rounded,
          text: start.format(context),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: start,
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme:
                      const ColorScheme.dark(primary: AppColors.primary),
                ),
                child: child!,
              ),
            );
            if (picked != null) onStart(picked);
          },
        ),
        const SizedBox(height: 16),
        _label('Duration'),
        Wrap(
          spacing: 8,
          children: [60, 90, 120].map((m) => _chip(
                label: '$m min',
                selected: duration == m,
                onTap: () => onDuration(m),
              )).toList(),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Match ends at ${endTime.format(context)}. We\'ll check the slot is free when you post.',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s,
            style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.5)),
      );

  Widget _tile({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.primaryDeep.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(text,
                style: GoogleFonts.dmSans(
                    fontSize: 14, color: AppColors.textPrimary)),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.primaryDeep),
        ),
        child: Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.black : AppColors.textPrimary)),
      ),
    );
  }
}

// ── Step 3: Details form ────────────────────────────────────────────────────

class _DetailsForm extends StatelessWidget {
  const _DetailsForm({
    required this.scrollController,
    required this.format,
    required this.spots,
    required this.pitch,
    required this.duration,
    required this.perHead,
    required this.onFormat,
    required this.onSpots,
  });

  final ScrollController scrollController;
  final String format;
  final int spots;
  final PitchModel? pitch;
  final int duration;
  final int? perHead;
  final ValueChanged<String> onFormat;
  final ValueChanged<int> onSpots;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _label('Format'),
        Wrap(
          spacing: 8,
          children: _kFormats
              .map((f) => _chip(
                    label: f,
                    selected: format == f,
                    onTap: () => onFormat(f),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        _label('Spots needed'),
        Row(
          children: [
            _circleBtn(Icons.remove,
                () => onSpots((spots - 1).clamp(2, 30))),
            const SizedBox(width: 16),
            Text('$spots',
                style: GoogleFonts.nunito(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(width: 16),
            _circleBtn(Icons.add,
                () => onSpots((spots + 1).clamp(2, 30))),
            const SizedBox(width: 12),
            Text('(default for $format)',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 18),
        _summary(),
      ],
    );
  }

  Widget _summary() {
    if (pitch == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 6),
              Text('Cost summary',
                  style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          _row('Pitch', pitch!.name),
          _row('Pitch rate', '${pitch!.pricePerHour.toInt()} BDT/hr'),
          _row('Duration', '$duration min'),
          _row('Total cost',
              '${(pitch!.pricePerHour * duration / 60).toInt()} BDT'),
          _row('Per player share',
              perHead == null ? '—' : '~$perHead BDT/head'),
          const Divider(height: 16, color: Color(0xFF0E2A24)),
          Text(
            'Players will pay their share + a 20 BDT commitment fee when they join.',
            style: GoogleFonts.dmSans(
                fontSize: 11, color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(k,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: AppColors.textSecondary)),
          const Spacer(),
          Text(v,
              style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s,
            style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.5)),
      );

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.primaryDeep),
        ),
        child: Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.black : AppColors.textPrimary)),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF0A1F1A),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primaryDeep),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
    );
  }
}
