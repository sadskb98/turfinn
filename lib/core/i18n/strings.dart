// Lightweight i18n. Skips ARB / code-gen because we have ~30 strings and
// no professional translator yet — a simple Map keyed by locale is faster
// to maintain at this stage. When we cross ~100 strings or hire a
// translator, migrate to flutter_localizations + ARB.
//
// Usage:
//   final t = Strings.of(context);
//   Text(t('book.cta'))
//
// Defaults to English when the key is missing for the current locale.
import 'package:flutter/material.dart';

class Strings {
  Strings(this.locale);
  final Locale locale;

  static Strings of(BuildContext context) =>
      Strings(Localizations.localeOf(context));

  // First 30 strings — focused on the booking + match flow + navigation.
  // Bangla strings reviewed for readability over formality (target audience
  // skews young, casual, mixed-script comfortable).
  static const _en = <String, String>{
    'nav.home': 'Home',
    'nav.explore': 'Explore',
    'nav.teams': 'Teams',
    'nav.play': 'Play',
    'nav.feed': 'News',
    'nav.profile': 'Profile',
    'nav.bookings': 'Bookings',

    'book.cta': 'Book',
    'book.cta_pay': 'Pay',
    'book.cta_pay_online': 'Pay {amt} BDT online',
    'book.cash_due': 'Pay cash at venue',
    'book.total': 'Total',
    'book.confirmed': 'Confirmed!',
    'book.refund_policy_short':
        'Cancel 6+ hours before kickoff = full refund.',

    'common.cancel': 'Cancel',
    'common.confirm': 'Confirm',
    'common.back': 'Back',
    'common.retry': 'Retry',
    'common.continue': 'Continue',
    'common.loading': 'Loading…',
    'common.connection_issue': 'Connection issue',
    'common.try_again': 'Check your network and try again.',

    'match.post_cta': 'Post match',
    'match.find_players': 'Find players',
    'match.spots_left': '{n} spots left',
    'match.full': 'Match full',
    'match.confirmed_banner': "You're in!",
    'match.cancel_my_spot': 'Cancel my spot · request refund',

    'pay.refund_queued': 'Refund queued — 3-7 business days',
    'pay.refunded': 'Refund completed — money returned',
    'pay.refund_failed': 'Refund failed — support is on it',

    'support.whatsapp': 'WhatsApp Support',
    'support.email': 'Email Support',
    'support.call': 'Call us',
  };

  // Bangla — Bangladesh (bn-BD). Numerals deliberately stay Latin (240 BDT,
  // not ২৪০) because that's how prices are read aloud in BD.
  static const _bn = <String, String>{
    'nav.home': 'হোম',
    'nav.explore': 'খুঁজুন',
    'nav.teams': 'টিম',
    'nav.play': 'খেলা',
    'nav.feed': 'খবর',
    'nav.profile': 'প্রোফাইল',
    'nav.bookings': 'বুকিং',

    'book.cta': 'বুক করুন',
    'book.cta_pay': 'পরিশোধ',
    'book.cta_pay_online': 'অনলাইনে {amt} BDT দিন',
    'book.cash_due': 'মাঠে নগদ দিন',
    'book.total': 'মোট',
    'book.confirmed': 'কনফার্ম!',
    'book.refund_policy_short':
        'কিকঅফের ৬+ ঘন্টা আগে বাতিল করলে পুরো রিফান্ড।',

    'common.cancel': 'বাতিল',
    'common.confirm': 'নিশ্চিত',
    'common.back': 'ফিরে যান',
    'common.retry': 'আবার চেষ্টা',
    'common.continue': 'চালিয়ে যান',
    'common.loading': 'লোড হচ্ছে…',
    'common.connection_issue': 'নেটওয়ার্ক সমস্যা',
    'common.try_again': 'আপনার ইন্টারনেট দেখে আবার চেষ্টা করুন।',

    'match.post_cta': 'ম্যাচ পোস্ট',
    'match.find_players': 'খেলোয়াড় খুঁজুন',
    'match.spots_left': '{n}টি স্পট বাকি',
    'match.full': 'ম্যাচ ফুল',
    'match.confirmed_banner': 'আপনি ইন!',
    'match.cancel_my_spot': 'আমার স্পট বাতিল · রিফান্ড চাই',

    'pay.refund_queued': 'রিফান্ড অপেক্ষমান — ৩-৭ কর্মদিবস',
    'pay.refunded': 'রিফান্ড সম্পন্ন — টাকা ফেরত দেওয়া হয়েছে',
    'pay.refund_failed': 'রিফান্ড ব্যর্থ — সাপোর্ট দেখছে',

    'support.whatsapp': 'WhatsApp সাপোর্ট',
    'support.email': 'ইমেইল সাপোর্ট',
    'support.call': 'কল করুন',
  };

  /// Translate a key. Substitutes `{name}` placeholders with the supplied
  /// args map. Falls back to English on missing keys; falls back to the key
  /// itself if both English and the active locale are missing.
  String t(String key, [Map<String, String>? args]) {
    final dict = locale.languageCode == 'bn' ? _bn : _en;
    var s = dict[key] ?? _en[key] ?? key;
    if (args != null) {
      args.forEach((k, v) {
        s = s.replaceAll('{$k}', v);
      });
    }
    return s;
  }

  /// Shorthand: t('foo.bar')
  String call(String key, [Map<String, String>? args]) => t(key, args);
}

/// Lookup helper that reads the active locale from BuildContext.
String tr(BuildContext context, String key, [Map<String, String>? args]) =>
    Strings.of(context).t(key, args);
