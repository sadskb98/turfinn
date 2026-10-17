import 'dart:async';
import 'dart:math' show Point, cos, pi;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/match_post_model.dart';
import '../../../data/models/pitch_model.dart';
import '../../providers/feed_provider.dart';
import '../../providers/pitch_provider.dart';
import '../home/home_screen.dart';
import 'widgets/map_top_bar.dart';
import 'widgets/preference_sheet.dart';
import 'widgets/search_sheet.dart';

const _maptilerKey = '5pNDbr41bwoiIH1bFQro';
const _styleUrl =
    'https://api.maptiler.com/maps/streets-v2-dark/style.json?key=$_maptilerKey&language=en';

const _cityCenters = <String, LatLng>{
  'Dhaka': LatLng(23.8103, 90.4125),
  'Chittagong': LatLng(22.3569, 91.7832),
  'Sylhet': LatLng(24.8949, 91.8687),
  'Rajshahi': LatLng(24.3745, 88.6042),
  'Khulna': LatLng(22.8456, 89.5403),
  'Barishal': LatLng(22.7010, 90.3535),
  'Mymensingh': LatLng(24.7471, 90.4203),
  'Comilla': LatLng(23.4607, 91.1809),
  'Narayanganj': LatLng(23.6238, 90.5000),
  'Gazipur': LatLng(23.9999, 90.4203),
  'Bogura': LatLng(24.8510, 89.3697),
  'Rangpur': LatLng(25.7439, 89.2752),
};

const _sheetInitial = 0.45;

class MapExploreScreen extends ConsumerStatefulWidget {
  const MapExploreScreen({super.key});

  @override
  ConsumerState<MapExploreScreen> createState() => _MapExploreScreenState();
}

class _MapExploreScreenState extends ConsumerState<MapExploreScreen> {
  MapLibreMapController? _mapCtrl;
  bool _styleLoaded = false;
  bool _syncingMarkers = false;
  bool _suppressMapTap = false;

  final Map<String, Symbol> _symbols = {};
  // Pin cache key: "<price>_<selected>_<hasMatch>" — keeps the renderer
  // off the hot path even when the underlying matches list mutates.
  final Map<String, Uint8List> _pinCache = {};
  final Set<String> _registeredImages = {};
  // pitch_id → Symbol's current image-key, so we can detect when a pin needs
  // re-rendering because hasMatch flipped without removing/re-adding the symbol.
  final Map<String, String> _symbolImageKey = {};
  Circle? _userCircle;

  String _locationMode = '';
  String _city = '';
  LatLng? _userLocation;
  double _radius = 0.0;
  double _fetchRadius = 0.0;
  Timer? _radiusDebounce;
  String? _selectedPitchId;
  bool _prefChecked = false;
  bool _searching = false;
  bool _showSheet = false;
  bool _hasFitBounds = false;
  LatLng? _searchedLocation;
  String? _searchLabel;
  Offset _footballOffset = const Offset(16, 300);
  bool _footballDragging = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _radiusDebounce?.cancel();
    _mapCtrl?.onSymbolTapped.remove(_onSymbolTapped);
    super.dispose();
  }

  // ── Preferences ──────────────────────────────────────────────────────────────

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('location_mode') ?? '';
    final city = prefs.getString('preferred_city') ?? '';

    if (mode.isEmpty) {
      _locationMode = 'city';
      _city = 'Dhaka';
      setState(() => _prefChecked = true);
      return;
    }
    if (mode == 'nearby') {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        await _clearPreferences();
        setState(() => _prefChecked = true);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _showPreferenceSheet());
        return;
      }
      _locationMode = mode;
      await _acquireLocation();
    } else {
      _locationMode = mode;
      _city = city;
    }
    setState(() => _prefChecked = true);
  }

  Future<void> _clearPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('location_mode');
    await prefs.remove('preferred_city');
    _locationMode = '';
    _city = '';
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('location_mode', _locationMode);
    await prefs.setString('preferred_city', _city);
  }

  void _showPreferenceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      isScrollControlled: true,
      enableDrag: false,
      builder: (_) => PreferenceSheet(
        onNearby: () async {
          setState(() { _locationMode = 'nearby'; _hasFitBounds = false; });
          await _acquireLocation();
          _savePreferences();
        },
        onCity: (city) {
          setState(() {
            _locationMode = 'city';
            _city = city;
            _hasFitBounds = false;
          });
          _moveToCity(city);
          _savePreferences();
        },
        onNearbyRadius: (km) async {
          setState(() {
            _locationMode = 'nearby';
            _radius = km;
            _fetchRadius = km;
            _hasFitBounds = false;
          });
          await _acquireLocation();
          _animateToRadius(km);
          _savePreferences();
        },
      ),
    );
  }

  Future<void> _acquireLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _onLocationFailed();
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.medium));
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() => _userLocation = ll);
      _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(ll, 13));
      if (_styleLoaded) await _updateUserDot(ll);
    } catch (_) {
      _onLocationFailed();
    }
  }

  void _onLocationFailed() {
    if (!mounted) return;
    _clearPreferences();
    setState(() {});
    WidgetsBinding.instance
        .addPostFrameCallback((_) { if (mounted) _showPreferenceSheet(); });
  }

  void _moveToCity(String city) {
    final center = _cityCenters[city] ?? _cityCenters['Chittagong']!;
    _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(center, 12));
  }

  void _animateToRadius(double radiusKm) {
    final ctrl = _mapCtrl;
    final loc = _searchedLocation ?? _userLocation;
    if (ctrl == null || loc == null) return;
    if (radiusKm <= 0) {
      ctrl.animateCamera(CameraUpdate.newLatLngZoom(loc, 9));
      return;
    }
    final latDelta = radiusKm / 111.32;
    final lngDelta = radiusKm / (111.32 * cos(loc.latitude * pi / 180));
    ctrl.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(loc.latitude - latDelta, loc.longitude - lngDelta),
          northeast: LatLng(loc.latitude + latDelta, loc.longitude + lngDelta),
        ),
        left: 24,
        right: 24,
        top: 100,
        bottom: 220,
      ),
    );
  }

  String get _locationLabel {
    if (_searchLabel != null) return _searchLabel!;
    if (_locationMode == 'nearby') return 'Nearby';
    if (_locationMode == 'all') return 'All Bangladesh';
    if (_locationMode == 'city' && _city.isNotEmpty) return _city;
    return 'All Bangladesh';
  }

  // ── Map callbacks ─────────────────────────────────────────────────────────────

  void _onMapCreated(MapLibreMapController ctrl) {
    _mapCtrl = ctrl;
    ctrl.onSymbolTapped.add(_onSymbolTapped);
  }

  Future<void> _onStyleLoaded() async {
    setState(() => _styleLoaded = true);
    if (_userLocation != null) await _updateUserDot(_userLocation!);
  }

  Future<void> _onMapTap(Point<double> _, LatLng __) async {
    if (_suppressMapTap) return;
    await _deselect();
  }

  void _onSymbolTapped(Symbol sym) {
    _suppressMapTap = true;
    Future.microtask(() => _suppressMapTap = false);
    final pitchId = sym.data?['pitch_id'] as String?;
    if (pitchId == null) return;
    _selectPin(pitchId, sym);
    final geo = sym.options.geometry;
    if (geo != null) _mapCtrl?.animateCamera(CameraUpdate.newLatLng(geo));
  }

  // ── Markers ───────────────────────────────────────────────────────────────────

  Future<void> _updateUserDot(LatLng ll) async {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;
    if (_userCircle != null) await ctrl.removeCircle(_userCircle!);
    _userCircle = await ctrl.addCircle(CircleOptions(
      geometry: ll,
      circleRadius: 8,
      circleColor: '#00DF82',
      circleStrokeWidth: 2,
      circleStrokeColor: '#FFFFFF',
    ));
  }

  /// Renders a pin pill with the price. When `hasMatch` is true, draws an
  /// amber soccer-ball badge in the top-right corner so the user can spot
  /// match-bearing pitches at a glance.
  Future<Uint8List> _renderPin(int price,
      {required bool selected, required bool hasMatch}) async {
    // Render at 2x for retina; displayed at iconSize 0.85.
    const scale = 2.0;
    const w = 72.0, h = 30.0, tip = 7.0;
    // Extra height to fit the badge that sits above the pill.
    const badgeR = 10.0;
    final canvasW = w * scale;
    final canvasH = (h + tip) * scale + (hasMatch ? badgeR * scale : 0);

    final bg = selected ? const Color(0xFFE7FF2A) : Colors.white;
    final fg = selected ? Colors.black : const Color(0xFF022026);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final pillTop = hasMatch ? badgeR * scale : 0.0;

    // Drop shadow under the pill.
    canvas.drawRRect(
      RRect.fromLTRBR(
          scale,
          pillTop + scale * 2,
          w * scale - scale,
          pillTop + h * scale,
          const Radius.circular(h * scale / 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, scale * 2),
    );
    // Pill
    canvas.drawRRect(
      RRect.fromLTRBR(0, pillTop, w * scale, pillTop + h * scale,
          const Radius.circular(h * scale / 2)),
      Paint()..color = bg,
    );
    // Pointer triangle
    final mx = w * scale / 2;
    canvas.drawPath(
      Path()
        ..moveTo(mx - 4 * scale, pillTop + h * scale)
        ..lineTo(mx, pillTop + (h + tip) * scale)
        ..lineTo(mx + 4 * scale, pillTop + h * scale)
        ..close(),
      Paint()..color = bg,
    );
    // Price text
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: 12 * scale,
        fontWeight: ui.FontWeight.w700));
    pb.pushStyle(ui.TextStyle(
        color: fg, fontSize: 12 * scale, fontWeight: ui.FontWeight.w700));
    pb.addText('৳$price');
    final para = pb.build()
      ..layout(ui.ParagraphConstraints(width: canvasW));
    canvas.drawParagraph(
        para, Offset(0, pillTop + (h * scale - para.height) / 2));

    if (hasMatch) {
      // Amber circle badge on the top-right corner with a small soccer-ball
      // glyph so it reads instantly as "match here".
      final cx = canvasW - badgeR * scale - 2;
      final cy = badgeR * scale;
      // Badge background
      canvas.drawCircle(Offset(cx, cy), badgeR * scale,
          Paint()..color = const Color(0xFFFFC857));
      canvas.drawCircle(
          Offset(cx, cy),
          badgeR * scale,
          Paint()
            ..color = const Color(0xFF022026)
            ..style = PaintingStyle.stroke
            ..strokeWidth = scale);
      // Inner soccer ball (simplified — single glyph "⚽" via paragraph).
      final bp = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontSize: badgeR * scale * 1.5,
          fontWeight: ui.FontWeight.w800));
      bp.pushStyle(ui.TextStyle(
          color: const Color(0xFF022026),
          fontSize: badgeR * scale * 1.4,
          fontWeight: ui.FontWeight.w800));
      bp.addText('⚽');
      final bpara = bp.build()
        ..layout(ui.ParagraphConstraints(width: badgeR * scale * 2));
      canvas.drawParagraph(
          bpara,
          Offset(
              cx - badgeR * scale, cy - bpara.height / 2));
    }

    final img = await recorder
        .endRecording()
        .toImage(canvasW.round(), canvasH.round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  String _pinCacheKey(int price, {required bool selected, required bool hasMatch}) =>
      'p_${price}_${selected ? 's' : 'n'}_${hasMatch ? 'm' : 'x'}';

  Future<Uint8List> _getPin(int price,
      {required bool selected, required bool hasMatch}) async {
    final key = _pinCacheKey(price, selected: selected, hasMatch: hasMatch);
    if (_pinCache.containsKey(key)) return _pinCache[key]!;
    final bytes = await _renderPin(price, selected: selected, hasMatch: hasMatch);
    _pinCache[key] = bytes;
    return bytes;
  }

  Future<String> _ensureImage(int price,
      {required bool selected, required bool hasMatch}) async {
    final key = _pinCacheKey(price, selected: selected, hasMatch: hasMatch);
    if (!_registeredImages.contains(key)) {
      await _mapCtrl!
          .addImage(key, await _getPin(price, selected: selected, hasMatch: hasMatch));
      _registeredImages.add(key);
    }
    return key;
  }

  void _fitAllPins(List<PitchModel> pitches) {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;
    final valid = pitches.where((p) => p.latitude != 0 || p.longitude != 0).toList();
    if (valid.isEmpty) return;
    if (valid.length == 1) {
      ctrl.animateCamera(CameraUpdate.newLatLngZoom(
          LatLng(valid.first.latitude, valid.first.longitude), 14));
      return;
    }
    double minLat = valid.first.latitude, maxLat = valid.first.latitude;
    double minLng = valid.first.longitude, maxLng = valid.first.longitude;
    for (final p in valid) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    ctrl.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      left: 48, right: 48, top: 120, bottom: 80,
    ));
  }

  Future<void> _syncMarkers(
    List<PitchModel> pitches, {
    Set<String> matchPitchIds = const {},
  }) async {
    if (_syncingMarkers) return;
    final ctrl = _mapCtrl;
    if (ctrl == null || !_styleLoaded) return;
    _syncingMarkers = true;
    try {
      final newIds = {for (final p in pitches) p.id};
      for (final id in _symbols.keys.toList()) {
        if (!newIds.contains(id)) {
          await ctrl.removeSymbol(_symbols.remove(id)!);
          _symbolImageKey.remove(id);
        }
      }
      for (final pitch in pitches) {
        if (pitch.latitude == 0 && pitch.longitude == 0) continue;
        final price = pitch.pricePerHour.round();
        final hasMatch = matchPitchIds.contains(pitch.id);
        final selected = pitch.id == _selectedPitchId;
        final imgKey =
            await _ensureImage(price, selected: selected, hasMatch: hasMatch);

        final existing = _symbols[pitch.id];
        if (existing == null) {
          final sym = await ctrl.addSymbol(
            SymbolOptions(
              geometry: LatLng(pitch.latitude, pitch.longitude),
              iconImage: imgKey,
              iconAnchor: 'bottom',
              iconSize: 0.85,
            ),
            {
              'pitch_id': pitch.id,
              'price': price,
              'has_match': hasMatch,
            },
          );
          _symbols[pitch.id] = sym;
          _symbolImageKey[pitch.id] = imgKey;
        } else if (_symbolImageKey[pitch.id] != imgKey) {
          // Match flag flipped — re-render the existing symbol's icon and
          // refresh its data so subsequent select/deselect picks the right
          // variant.
          await ctrl.updateSymbol(existing, SymbolOptions(iconImage: imgKey));
          existing.data
            ?..['has_match'] = hasMatch;
          _symbolImageKey[pitch.id] = imgKey;
        }
      }
      if (!_hasFitBounds && _symbols.isNotEmpty) {
        _hasFitBounds = true;
        _fitAllPins(pitches);
      }
    } finally {
      _syncingMarkers = false;
    }
  }

  Future<void> _selectPin(String pitchId, Symbol sym) async {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;
    if (_selectedPitchId != null && _selectedPitchId != pitchId) {
      await _deselect(updateState: false);
    }
    final price = (sym.data?['price'] as int?) ?? 0;
    final hasMatch = (sym.data?['has_match'] as bool?) ?? false;
    final imgKey =
        await _ensureImage(price, selected: true, hasMatch: hasMatch);
    await ctrl.updateSymbol(sym, SymbolOptions(iconImage: imgKey));
    _symbolImageKey[pitchId] = imgKey;
    setState(() { _selectedPitchId = pitchId; _showSheet = false; });
  }

  Future<void> _deselect({bool updateState = true}) async {
    final ctrl = _mapCtrl;
    if (ctrl == null || _selectedPitchId == null) return;
    final sym = _symbols[_selectedPitchId!];
    if (sym != null) {
      final price = (sym.data?['price'] as int?) ?? 0;
      final hasMatch = (sym.data?['has_match'] as bool?) ?? false;
      final imgKey =
          await _ensureImage(price, selected: false, hasMatch: hasMatch);
      await ctrl.updateSymbol(sym, SymbolOptions(iconImage: imgKey));
      _symbolImageKey[_selectedPitchId!] = imgKey;
    }
    if (updateState) {
      setState(() => _selectedPitchId = null);
    } else {
      _selectedPitchId = null;
    }
  }

  // ── Floating card ─────────────────────────────────────────────────────────────

  Widget _buildFloatingCard(
    PitchModel pitch,
    double sheetHeight,
    List<MatchPost> matches,
  ) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final hasMatches = matches.isNotEmpty;
    return Positioned(
      bottom: bottomPad + 16,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D2420),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pitch summary — tap to view full pitch details
              InkWell(
                onTap: () => context.push('/pitches/${pitch.id}', extra: pitch),
                borderRadius: BorderRadius.circular(16),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(14)),
                      child: pitch.primaryImage.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: pitch.primaryImage,
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _imgPlaceholder(),
                            )
                          : _imgPlaceholder(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(pitch.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.nunito(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 2),
                            Row(children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 12,
                                  color: AppColors.textSecondary),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(pitch.city,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.dmSans(
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                              ),
                            ]),
                            const SizedBox(height: 6),
                            Text('${pitch.pricePerHour.toInt()} BDT/hr',
                                style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary)),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.chevron_right,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              // Action row — Book always; Join match only when matches > 0.
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFF0E2A24), width: 1),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            context.push('/pitches/${pitch.id}', extra: pitch),
                        icon: const Icon(Icons.event_available_outlined,
                            size: 16),
                        label: Text('Book pitch',
                            style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(
                              color: AppColors.primary, width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    if (hasMatches) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _openMatchListSheet(pitch, matches),
                          icon: const Icon(Icons.sports_soccer_rounded,
                              size: 16),
                          label: Text(
                              matches.length == 1
                                  ? 'Join open match'
                                  : 'Join 1 of ${matches.length} matches',
                              style: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC857),
                            foregroundColor: Colors.black,
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Open a small bottom sheet listing the matches at the selected pitch so
  /// the user can pick which one to join. Single match → push directly.
  Future<void> _openMatchListSheet(
      PitchModel pitch, List<MatchPost> matches) async {
    if (matches.length == 1) {
      context.push('${AppRoutes.matchDetail}/${matches.first.id}');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PitchMatchesSheet(pitch: pitch, matches: matches),
    );
  }

  Widget _imgPlaceholder() => Container(
        width: 88,
        height: 88,
        color: const Color(0xFF051210),
        child: const Center(
            child: Icon(Icons.sports_soccer,
                color: AppColors.primaryDeep, size: 28)),
      );

  Widget _buildTurfList(
      AsyncValue<List<dynamic>> pitchesAsync, ScrollController scrollCtrl) {
    return CustomScrollView(
      controller: scrollCtrl,
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.primaryDeep,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
        pitchesAsync.when(
          loading: () => const SliverFillRemaining(
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary))),
          error: (_, __) => SliverFillRemaining(
              child: Center(
                  child: Text('Could not load turfs',
                      style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary)))),
          data: (pitches) => SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final pitch = pitches[i] as PitchModel;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: _selectedPitchId == pitch.id
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: AppColors.primary, width: 1.5))
                        : null,
                    child: TurfCard(
                        pitch: pitch,
                        onTap: () =>
                            context.push('/pitches/${pitch.id}', extra: pitch)),
                  );
                },
                childCount: pitches.length,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final hasSearch = _searchedLocation != null;
    final pitchesAsync = ref.watch(pitchListProvider(
      city: !hasSearch && _locationMode == 'city' && _city.isNotEmpty ? _city : null,
      lat: hasSearch
          ? _searchedLocation!.latitude
          : _locationMode == 'nearby'
              ? _userLocation?.latitude
              : null,
      lng: hasSearch
          ? _searchedLocation!.longitude
          : _locationMode == 'nearby'
              ? _userLocation?.longitude
              : null,
      radius: hasSearch || (_locationMode == 'nearby' && _fetchRadius > 0)
          ? _fetchRadius
          : null,
    ));

    // Open matches grouped by pitch — drives the soccer-ball badge on pins
    // and the second CTA on the floating card.
    final matchesAsync = ref.watch(openMatchesByPitchProvider(
      lat: _userLocation?.latitude,
      lng: _userLocation?.longitude,
    ));
    final matchesByPitch = matchesAsync.valueOrNull ?? const {};
    final matchPitchIds = matchesByPitch.keys.toSet();

    if (_styleLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && pitchesAsync.hasValue) {
          _syncMarkers(
            pitchesAsync.value!.cast<PitchModel>(),
            matchPitchIds: matchPitchIds,
          );
        }
      });
    }

    final selectedPitch = _selectedPitchId == null
        ? null
        : pitchesAsync.valueOrNull?.cast<PitchModel?>().firstWhere(
            (p) => p?.id == _selectedPitchId,
            orElse: () => null);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: !_prefChecked
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Stack(
              children: [
                // ── Map ──────────────────────────────────────────────────────
                MapLibreMap(
                  styleString: _styleUrl,
                  initialCameraPosition: CameraPosition(
                    target: _locationMode == 'nearby' && _userLocation != null
                        ? _userLocation!
                        : _locationMode == 'city'
                            ? (_cityCenters[_city] ??
                                _cityCenters['Chittagong']!)
                            : const LatLng(23.6850, 90.3563),
                    zoom: _locationMode == 'nearby'
                        ? 13.0
                        : _locationMode == 'city'
                            ? 12.0
                            : 7.0,
                  ),
                  onMapCreated: _onMapCreated,
                  onStyleLoadedCallback: _onStyleLoaded,
                  onMapClick: _onMapTap,
                  rotateGesturesEnabled: true,
                  tiltGesturesEnabled: false,
                  compassEnabled: false,
                  myLocationEnabled: false,
                ),

                // ── Top bar ───────────────────────────────────────────────────
                if (!_searching)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: MapTopBar(
                      locationLabel: _locationLabel,
                      onLocationTap: () {
                        setState(() { _searchedLocation = null; _searchLabel = null; });
                        _showPreferenceSheet();
                      },
                      onSearchTap: () =>
                          setState(() => _searching = true),
                      radiusKm: _locationMode == 'nearby' ? _radius : null,
                      onRadiusChanged: _locationMode == 'nearby'
                          ? (v) {
                              _radiusDebounce?.cancel();
                              setState(() => _radius = v);
                              _animateToRadius(v);
                              _radiusDebounce = Timer(const Duration(milliseconds: 500), () {
                                if (mounted) setState(() => _fetchRadius = v);
                              });
                            }
                          : null,
                    ),
                  ),

                // ── Search overlay ────────────────────────────────────────────
                if (_searching)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: MapSearchBar(
                      onDismiss: () => setState(() => _searching = false),
                      onResult: (r) {
                        final ll = LatLng(r.lat, r.lng);
                        final label = r.name.split(', ').first;
                        setState(() {
                          _searching = false;
                          _searchedLocation = ll;
                          _searchLabel = label;
                        });
                        _animateToRadius(_radius);
                      },
                    ),
                  ),

                // ── Turf list sheet ───────────────────────────────────────────
                if (_locationMode.isNotEmpty && kIsWeb)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: screenHeight * 0.42,
                      decoration: const BoxDecoration(
                        color: AppColors.background,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(16)),
                        border: Border(
                            top: BorderSide(
                                color: AppColors.primaryDeep, width: 0.5)),
                      ),
                      child: _buildTurfList(pitchesAsync, ScrollController()),
                    ),
                  )
                else if (_locationMode.isNotEmpty && _selectedPitchId == null && _showSheet)
                  DraggableScrollableSheet(
                    initialChildSize: _sheetInitial,
                    minChildSize: _sheetInitial,
                    maxChildSize: 1.0,
                    snap: true,
                    snapSizes: const [_sheetInitial, 1.0],
                    builder: (_, scrollCtrl) => DecoratedBox(
                      decoration: const BoxDecoration(
                        color: AppColors.background,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(16)),
                        border: Border(
                            top: BorderSide(
                                color: AppColors.primaryDeep, width: 0.5)),
                      ),
                      child: _buildTurfList(pitchesAsync, scrollCtrl),
                    ),
                  ),

                // ── Football FAB — toggle turf list ──────────────────────────
                if (_locationMode.isNotEmpty && !_searching && selectedPitch == null)
                  AnimatedPositioned(
                    duration: _footballDragging
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    left: _footballOffset.dx,
                    top: _footballOffset.dy,
                    child: GestureDetector(
                      onPanStart: (_) =>
                          setState(() => _footballDragging = true),
                      onPanUpdate: (d) {
                        final size = MediaQuery.of(context).size;
                        setState(() {
                          _footballOffset = Offset(
                            (_footballOffset.dx + d.delta.dx)
                                .clamp(0, size.width - 56),
                            (_footballOffset.dy + d.delta.dy)
                                .clamp(0, size.height - 140),
                          );
                        });
                      },
                      onPanEnd: (_) {
                        final size = MediaQuery.of(context).size;
                        const pad = 16.0;
                        final cx = _footballOffset.dx + 26;
                        setState(() {
                          _footballDragging = false;
                          _footballOffset = Offset(
                            cx < size.width / 2 ? pad : size.width - 56 - pad,
                            _footballOffset.dy
                                .clamp(pad, size.height - 140 - pad),
                          );
                        });
                      },
                      onTap: () =>
                          setState(() => _showSheet = !_showSheet),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _showSheet
                              ? AppColors.primary
                              : const Color(0xFF0D2420),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.primary, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.sports_soccer,
                          color: _showSheet
                              ? AppColors.background
                              : AppColors.primary,
                          size: 24,
                        ),
                      ),
                    ),
                  ),

                // ── Floating pitch card ───────────────────────────────────────
                if (selectedPitch != null && _locationMode.isNotEmpty)
                  _buildFloatingCard(
                    selectedPitch,
                    0,
                    matchesByPitch[selectedPitch.id] ?? const [],
                  ),
              ],
            ),
    );
  }
}

// ── Pitch matches bottom sheet ────────────────────────────────────────────
//
// Shown when the user taps "Join one of N matches" on a pitch with multiple
// open matches. Each row pushes to the standalone Match Detail screen where
// they can see full info + actually join.

class _PitchMatchesSheet extends StatelessWidget {
  const _PitchMatchesSheet({required this.pitch, required this.matches});

  final PitchModel pitch;
  final List<MatchPost> matches;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF033640),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.primaryDeep,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.sports_soccer_rounded,
                      color: Color(0xFFFFC857), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pitch.name,
                            style: GoogleFonts.nunito(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        Text('${matches.length} open matches looking for players',
                            style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF0E2A24)),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: matches.length,
                itemBuilder: (_, i) {
                  final m = matches[i];
                  return _row(context, m);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, MatchPost m) {
    final spotsLeft = m.spotsTotal - m.spotsFilled;
    final perHead = m.perHeadCostBDT ?? 0;
    final fee = m.joinFeeBDT;
    final total = perHead + fee;
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        context.push('${AppRoutes.matchDetail}/${m.id}');
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.primaryDeep.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.title.isEmpty ? 'Match' : m.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                      '${m.matchDate.toLocal().hour.toString().padLeft(2, "0")}:${m.matchDate.toLocal().minute.toString().padLeft(2, "0")}'
                      ' · ${m.format.isEmpty ? "Match" : m.format} · $spotsLeft spots',
                      style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                  total > 0 ? 'Join · $total BDT' : 'Join · $fee BDT',
                  style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }
}
