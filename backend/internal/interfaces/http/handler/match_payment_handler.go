package handler

import (
	"errors"
	"net/url"
	"strconv"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/rs/zerolog/log"

	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/config"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type MatchPaymentHandler struct {
	svc   *service.MatchJoinPaymentService
	audit *service.AuditService
}

func NewMatchPaymentHandler(svc *service.MatchJoinPaymentService, audit *service.AuditService) *MatchPaymentHandler {
	return &MatchPaymentHandler{svc: svc, audit: audit}
}

func (h *MatchPaymentHandler) recordAudit(c echo.Context, action, entityType, entityID string, oldVal, newVal any) {
	if h.audit == nil {
		return
	}
	actorID, _ := c.Get(authmw.UserIDKey).(uuid.UUID)
	role, _ := c.Get(authmw.UserRoleKey).(string)
	_ = h.audit.Record(c.Request().Context(), actorID, role, action, entityType, entityID,
		oldVal, newVal,
		c.RealIP(), c.Request().UserAgent())
}

// POST /api/v1/feed/:id/initiate-payment — opens an SSL gateway session for
// joining the match. Returns the redirect URL the client opens in a WebView.
func (h *MatchPaymentHandler) Initiate(c echo.Context) error {
	matchID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)

	gateway, payID, err := h.svc.InitiatePayment(c.Request().Context(), matchID, userID)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrJoinMatchNotFound):
			return response.NotFound(c, "match not found")
		case errors.Is(err, service.ErrMatchClosed):
			return response.Conflict(c, "match is full or no longer accepting players")
		case errors.Is(err, service.ErrAlreadyJoined):
			return response.Conflict(c, "you've already joined this match")
		default:
			return response.BadRequest(c, err.Error())
		}
	}
	return response.OK(c, map[string]any{
		"redirect_url":   gateway,
		"transaction_id": payID.String(),
	})
}

// POST /api/v1/feed/:id/cancel — host cancels their match. Triggers
// automatic SSL refunds to every joiner who paid.
func (h *MatchPaymentHandler) HostCancel(c echo.Context) error {
	matchID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)

	var req struct {
		Reason string `json:"reason" validate:"max=60"`
	}
	_ = c.Bind(&req)
	if req.Reason == "" {
		req.Reason = "host_cancelled"
	}

	n, err := h.svc.CancelMatchByHost(c.Request().Context(), matchID, userID, req.Reason)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrJoinMatchNotFound):
			return response.NotFound(c, "match not found")
		default:
			return response.BadRequest(c, err.Error())
		}
	}
	h.recordAudit(c, "match.host_cancel", "match_post", matchID.String(), nil,
		map[string]any{"reason": req.Reason, "refunds_requested": n})
	return response.OK(c, map[string]any{
		"status":            "cancelled",
		"refunds_requested": n,
	})
}

// POST /api/v1/feed/:id/leave — joiner pulls out of a match they joined.
// Refund is queued automatically if outside the cancellation window
// (default: > 60 min before kickoff). Past the window, the seat is still
// released but the payment is held for the host's discretion.
func (h *MatchPaymentHandler) JoinerCancel(c echo.Context) error {
	matchID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)

	cutoff := config.LoadMatchConfig().JoinerCancelMinMinutesBeforeKickoff
	refunded, err := h.svc.LeaveMatchByJoiner(c.Request().Context(), matchID, userID, cutoff)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrJoinMatchNotFound):
			return response.NotFound(c, "match not found")
		default:
			return response.BadRequest(c, err.Error())
		}
	}
	return response.OK(c, map[string]any{
		"status":          "left",
		"refund_queued":   refunded,
		"cutoff_minutes":  cutoff,
	})
}

// ── Super-Admin payment / refund tooling ───────────────────────────────────

// GET /super-admin/match-payments
//
// Query params:
//   status         — payment status filter ("" = all)
//   refund_status  — refund status filter ("any" = has any refund, "" = all)
//   q              — search across user name / phone / tran_id / match title
//   page, limit    — pagination
func (h *MatchPaymentHandler) AdminListPayments(c echo.Context) error {
	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	rows, total, err := h.svc.AdminListPayments(c.Request().Context(), service.AdminPaymentFilter{
		Status:       c.QueryParam("status"),
		RefundStatus: c.QueryParam("refund_status"),
		Search:       c.QueryParam("q"),
		Page:         page,
		Limit:        limit,
	})
	if err != nil {
		log.Error().Err(err).Msg("admin list payments failed")
		return response.InternalError(c)
	}
	if limit <= 0 {
		limit = 25
	}
	if page <= 0 {
		page = 1
	}
	return response.OKPaginated(c, rows, response.Meta{Page: page, Limit: limit, Total: total})
}

// POST /super-admin/match-payments/:id/retry-refund
func (h *MatchPaymentHandler) AdminRetryRefund(c echo.Context) error {
	pid, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	if err := h.svc.AdminRetryRefund(c.Request().Context(), pid); err != nil {
		return response.BadRequest(c, err.Error())
	}
	h.recordAudit(c, "match_payment.retry_refund", "match_join_payment", pid.String(), nil, nil)
	return response.OK(c, map[string]string{"status": "queued"})
}

// POST /super-admin/match-payments/:id/mark-refunded
//
// Body: {"note": "optional operator note"}
func (h *MatchPaymentHandler) AdminMarkRefunded(c echo.Context) error {
	pid, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	var req struct {
		Note string `json:"note"`
	}
	_ = c.Bind(&req)
	if err := h.svc.AdminMarkRefunded(c.Request().Context(), pid, req.Note); err != nil {
		return response.BadRequest(c, err.Error())
	}
	h.recordAudit(c, "match_payment.mark_refunded", "match_join_payment", pid.String(),
		nil, map[string]any{"note": req.Note})
	return response.OK(c, map[string]string{"status": "refunded"})
}

// GET /super-admin/match-cancellations
func (h *MatchPaymentHandler) AdminListCancellations(c echo.Context) error {
	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	rows, total, err := h.svc.AdminListCancellations(c.Request().Context(), page, limit)
	if err != nil {
		log.Error().Err(err).Msg("admin list cancellations failed")
		return response.InternalError(c)
	}
	if limit <= 0 {
		limit = 25
	}
	if page <= 0 {
		page = 1
	}
	return response.OKPaginated(c, rows, response.Meta{Page: page, Limit: limit, Total: total})
}

// GET /manager/match-cancellations — cancellations at the caller's pitches.
func (h *MatchPaymentHandler) ManagerListCancellations(c echo.Context) error {
	managerID := c.Get(authmw.UserIDKey).(uuid.UUID)
	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	rows, total, err := h.svc.ManagerListCancellations(c.Request().Context(), managerID, page, limit)
	if err != nil {
		log.Error().Err(err).Msg("manager list cancellations failed")
		return response.InternalError(c)
	}
	if limit <= 0 {
		limit = 25
	}
	if page <= 0 {
		page = 1
	}
	return response.OKPaginated(c, rows, response.Meta{Page: page, Limit: limit, Total: total})
}

// SSLCommerz callback receivers.
//
// Two important changes over the original implementation:
//
//  1. We capture the FULL form payload (not just our 11-field DTO). SSL
//     posts ~30 fields and `verify_key` references field names from that
//     full set (e.g. value_a, currency_amount, risk_level, card_issuer).
//     Looking those up in a partial map fails the HMAC check on every
//     successful payment — which is why HMAC was always rejecting.
//
//  2. The browser-facing endpoints (success / fail / cancel) render a
//     friendly HTML page instead of JSON, with a meta-refresh to a
//     `turfinn://` deep link. The Flutter side opens the gateway in an
//     in-app WebView and intercepts these by URL match — closes the
//     WebView, refreshes the feed, returns the user to the match detail
//     screen. End result: the user never leaves the app.
//
// IPN remains JSON because it's server-to-server.

func (h *MatchPaymentHandler) Success(c echo.Context) error {
	form, _ := c.FormParams()
	params := paramsFromForm(form)
	tranID := params["tran_id"]
	if err := h.svc.HandleSuccessWithParams(c.Request().Context(), params); err != nil {
		log.Error().
			Err(err).
			Str("tran_id", tranID).
			Interface("form_keys", keysOf(params)).
			Msg("match payment success: confirm failed")
		return renderReturnPage(c, "fail", tranID,
			"We received your payment but ran into an issue confirming it. Please re-open the app — we'll retry automatically.")
	}
	log.Info().Str("tran_id", tranID).Msg("match payment success: confirmed")
	return renderReturnPage(c, "success", tranID,
		"Payment received. Returning you to the app…")
}

func (h *MatchPaymentHandler) IPN(c echo.Context) error {
	form, _ := c.FormParams()
	params := paramsFromForm(form)
	if err := h.svc.HandleSuccessWithParams(c.Request().Context(), params); err != nil {
		log.Error().
			Err(err).
			Str("tran_id", params["tran_id"]).
			Interface("form_keys", keysOf(params)).
			Msg("match payment IPN: confirm failed")
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, map[string]string{"status": "ok"})
}

func keysOf(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

func (h *MatchPaymentHandler) Fail(c echo.Context) error {
	form, _ := c.FormParams()
	params := paramsFromForm(form)
	tranID := params["tran_id"]
	_ = h.svc.HandleTerminal(c.Request().Context(), tranID, "failed")
	return renderReturnPage(c, "fail", tranID,
		"Payment failed. Returning you to the app…")
}

func (h *MatchPaymentHandler) Cancel(c echo.Context) error {
	form, _ := c.FormParams()
	params := paramsFromForm(form)
	tranID := params["tran_id"]
	_ = h.svc.HandleTerminal(c.Request().Context(), tranID, "cancelled")
	return renderReturnPage(c, "cancel", tranID,
		"Payment cancelled. Returning you to the app…")
}

// paramsFromForm flattens a multi-valued form into a single-value map.
// SSLCommerz never sends repeated keys, so the first value is the real one.
func paramsFromForm(form url.Values) map[string]string {
	out := make(map[string]string, len(form))
	for k, v := range form {
		if len(v) > 0 {
			out[k] = v[0]
		}
	}
	return out
}

// renderReturnPage emits a tiny themed HTML page that:
//   - Sets <title>TURFINN_PAYMENT_<status></title> so the in-app WebView
//     can detect status via the title-changed event.
//   - meta-refreshes to a turfinn:// deep link (custom scheme handled by
//     Android intent filter) so users reaching the page in a normal
//     browser are bounced back to the app.
//   - Shows a friendly icon + message.
func renderReturnPage(c echo.Context, status, tranID, msg string) error {
	deepLink := "turfinn://payment/match/" + status
	if tranID != "" {
		deepLink += "?tran_id=" + tranID
	}
	html := `<!DOCTYPE html><html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="1;url=` + deepLink + `">
<title>TURFINN_PAYMENT_` + status + `</title>
<style>
body{margin:0;background:#030F0F;color:#fff;font-family:-apple-system,Roboto,sans-serif;
display:flex;align-items:center;justify-content:center;min-height:100vh;text-align:center;padding:24px}
.box{max-width:360px}
.dot{width:54px;height:54px;border-radius:50%;background:#00DF82;display:inline-block;margin-bottom:18px;
position:relative}
.dot.fail{background:#FF6B6B}
.dot.cancel{background:#FFC857}
.dot:after{content:"\2713";color:#000;font-size:30px;font-weight:800;position:absolute;
left:50%;top:50%;transform:translate(-50%,-52%)}
.dot.fail:after{content:"!"}
.dot.cancel:after{content:"\00d7"}
h1{font-size:18px;font-weight:800;margin:0 0 8px}
p{color:#8FA3A3;font-size:14px;line-height:1.5;margin:0}
a{color:#00DF82;font-weight:700;text-decoration:none}
</style></head><body>
<div class="box">
<span class="dot ` + status + `"></span>
<h1>` + msg + `</h1>
<p>If the app doesn't open automatically, <a href="` + deepLink + `">tap here to return</a>.</p>
</div></body></html>`
	return c.HTML(200, html)
}
