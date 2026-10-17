import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/sources/remote/manage_remote_source.dart';

/// Loads /manage/billing once per panel session. Refresh by invalidating
/// the provider. Used by [PremiumGateView] and the Billing sidebar entry.
final billingProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.read(manageRemoteSourceProvider).getMyBilling();
});
