import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/booking_model.dart';
import '../../data/sources/remote/booking_remote_source.dart';
import 'gamification_provider.dart';

part 'booking_provider.g.dart';

@riverpod
Future<List<BookingModel>> myBookings(MyBookingsRef ref) async {
  return ref.watch(bookingRemoteSourceProvider).listMyBookings();
}

// Booking creation state
sealed class BookingState {}
class BookingIdle extends BookingState {}
class BookingLoading extends BookingState {}
class BookingSuccess extends BookingState {
  BookingSuccess(this.booking);
  final BookingModel booking;
}
class BookingError extends BookingState {
  BookingError(this.message);
  final String message;
}

@riverpod
class BookingNotifier extends _$BookingNotifier {
  @override
  BookingState build() => BookingIdle();

  Future<void> create({
    required String pitchId,
    required DateTime startsAt,
    required DateTime endsAt,
    String notes = '',
    String? paymentMode,
  }) async {
    state = BookingLoading();
    try {
      final booking = await ref.read(bookingRemoteSourceProvider).createBooking(
            pitchId: pitchId,
            startsAt: startsAt,
            endsAt: endsAt,
            notes: notes,
            paymentMode: paymentMode,
          );
      state = BookingSuccess(booking);
      ref.invalidate(myBookingsProvider);
      ref.invalidate(playerProfileProvider);
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(weeklyChallengesProvider);
    } catch (e) {
      state = BookingError('Failed to create booking. Try again.');
    }
  }

  Future<bool> cancel(String id) async {
    try {
      await ref.read(bookingRemoteSourceProvider).cancelBooking(id);
      ref.invalidate(myBookingsProvider);
      return true;
    } catch (e) {
      state = BookingError('Failed to cancel booking. Try again.');
      return false;
    }
  }

  void reset() => state = BookingIdle();
}
