package sslcommerz

import (
	"crypto/md5" //nolint:gosec // SSLCommerz IPN verification requires MD5 per their spec
	"fmt"
	"io"
	"sort"
	"strings"
)

// md5Hex returns the lowercase hex MD5 digest of s.
func md5Hex(s string) string {
	h := md5.New() //nolint:gosec
	_, _ = io.WriteString(h, s)
	return fmt.Sprintf("%x", h.Sum(nil))
}

// DebugSignString returns the canonical hash input string and the computed
// MD5, for diagnostics only. Mirrors VerifySign exactly except it doesn't
// short-circuit on missing verify_key/sign.
func DebugSignString(params map[string]string, storePasswd string) (input, computed string) {
	verifyKey := params["verify_key"]
	hashable := make(map[string]string)
	for _, k := range strings.Split(verifyKey, ",") {
		k = strings.TrimSpace(k)
		if v, present := params[k]; present {
			hashable[k] = v
		}
	}
	hashable["store_passwd"] = md5Hex(storePasswd)
	keys := make([]string, 0, len(hashable))
	for k := range hashable {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var sb strings.Builder
	for i, k := range keys {
		if i > 0 {
			sb.WriteString("&")
		}
		sb.WriteString(k)
		sb.WriteString("=")
		sb.WriteString(hashable[k])
	}
	input = sb.String()
	computed = md5Hex(input)
	return
}

// VerifySign validates an SSLCommerz IPN/success callback signature.
//
// Mirrors SSLCommerz's official PHP sample (validateOrder.php) line-for-line:
//
//	$store_passwd = md5($store_passwd);
//	foreach (explode(',', $verify_key) as $k)
//	    if (isset($post[$k])) $hash[$k] = $post[$k];   // SKIP missing
//	$hash['store_passwd'] = $store_passwd;
//	ksort($hash);
//	$str = '';
//	foreach ($hash as $k => $v) $str .= $k.'='.$v.'&';
//	$str = rtrim($str, '&');
//	if (md5($str) == $post['verify_sign']) /* valid */
//
// Two subtleties we got wrong before:
//   - Values are NOT url-encoded; they go in raw.
//   - Fields listed in verify_key but absent from the form are SKIPPED,
//     not treated as empty strings.
func VerifySign(params map[string]string, storePasswd string) bool {
	verifyKey, ok := params["verify_key"]
	if !ok || verifyKey == "" {
		return false
	}
	verifySign, ok := params["verify_sign"]
	if !ok || verifySign == "" {
		return false
	}

	hashable := make(map[string]string)
	for _, k := range strings.Split(verifyKey, ",") {
		k = strings.TrimSpace(k)
		if v, present := params[k]; present {
			hashable[k] = v
		}
	}
	hashable["store_passwd"] = md5Hex(storePasswd)

	keys := make([]string, 0, len(hashable))
	for k := range hashable {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	var sb strings.Builder
	for i, k := range keys {
		if i > 0 {
			sb.WriteString("&")
		}
		sb.WriteString(k)
		sb.WriteString("=")
		sb.WriteString(hashable[k])
	}

	computed := md5Hex(sb.String())
	return strings.EqualFold(computed, verifySign)
}
