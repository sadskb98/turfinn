// Package phone normalizes phone numbers to a canonical E.164 form
// (+CCXXXXXXXXXX) using Google's libphonenumber. Storing the canonical
// form everywhere prevents the "second account silently created" bug
// from differently-formatted inputs of the same person.
//
// Default region is BD (Bangladesh) so bare-local numbers like
// "01715034282" parse correctly. International numbers (Bangladeshis
// abroad, foreign students, etc.) are also accepted via the +CC prefix.
package phone

import (
	"strings"

	"github.com/nyaruka/phonenumbers"
)

// defaultRegion is the ISO-3166-1 alpha-2 region used when the input
// has no explicit country code. We're a Bangladesh-first product;
// override per-call if/when we expand.
const defaultRegion = "BD"

// Normalize returns the E.164 form ("+8801715034282") for any input
// libphonenumber can recognize as a valid mobile or fixed line, or
// empty string for invalid input.
//
// Examples:
//   - "01715034282"           ->  "+8801715034282"
//   - "1715034282"            ->  "+8801715034282"
//   - "+8801715034282"        ->  "+8801715034282"
//   - " (017) 1503-4282 "     ->  "+8801715034282"  (formatting stripped)
//   - "+44 20 7123 4567"      ->  "+442071234567"   (UK number stays UK)
//   - "abc"                   ->  ""
func Normalize(raw string) string {
	if strings.TrimSpace(raw) == "" {
		return ""
	}
	num, err := phonenumbers.Parse(raw, defaultRegion)
	if err != nil {
		return ""
	}
	if !phonenumbers.IsValidNumber(num) {
		return ""
	}
	return phonenumbers.Format(num, phonenumbers.E164)
}

// IsValid is a quick "would Normalize succeed?" check without alloc.
func IsValid(raw string) bool {
	return Normalize(raw) != ""
}
