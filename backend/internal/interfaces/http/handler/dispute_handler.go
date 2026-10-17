package handler

import (
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/interfaces/dto"
	mw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type DisputeHandler struct {
	disputeRepo domain.DisputeRepository
	verifyRepo  domain.VerificationRepository
	userRepo    domain.UserRepository
}

func NewDisputeHandler(dr domain.DisputeRepository, vr domain.VerificationRepository, ur domain.UserRepository) *DisputeHandler {
	return &DisputeHandler{disputeRepo: dr, verifyRepo: vr, userRepo: ur}
}

// ── Disputes ─────────────────────────────────────────────────────────────────

func (h *DisputeHandler) ListDisputes(c echo.Context) error {
	page, limit := paginationDefaults(c)
	status := c.QueryParam("status")
	items, total, err := h.disputeRepo.ListDisputes(c.Request().Context(), status, page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.DisputeResponse, len(items))
	for i, d := range items {
		r := dto.DisputeResponse{
			ID: d.ID.String(), BookingID: d.BookingID.String(),
			RaisedByID: d.RaisedByUserID.String(), AgainstUserID: d.AgainstUserID.String(),
			Reason: d.Reason, Description: d.Description, EvidenceURLs: d.EvidenceURLs,
			Status: d.Status, Resolution: d.Resolution, InternalNotes: d.InternalNotes,
			CreatedAt: d.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
		if d.RaisedBy != nil {
			r.RaisedByName = d.RaisedBy.Name
		}
		if d.ResolvedAt != nil {
			r.ResolvedAt = d.ResolvedAt.Format("2006-01-02T15:04:05Z")
		}
		resp[i] = r
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *DisputeHandler) GetDispute(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	d, err := h.disputeRepo.GetDispute(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "dispute not found")
	}
	r := dto.DisputeResponse{
		ID: d.ID.String(), BookingID: d.BookingID.String(),
		RaisedByID: d.RaisedByUserID.String(), AgainstUserID: d.AgainstUserID.String(),
		Reason: d.Reason, Description: d.Description, EvidenceURLs: d.EvidenceURLs,
		Status: d.Status, Resolution: d.Resolution, InternalNotes: d.InternalNotes,
		CreatedAt: d.CreatedAt.Format("2006-01-02T15:04:05Z"),
	}
	if d.RaisedBy != nil {
		r.RaisedByName = d.RaisedBy.Name
	}
	return response.OK(c, r)
}

func (h *DisputeHandler) CreateDispute(c echo.Context) error {
	var req dto.CreateDisputeRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	bookingID, _ := uuid.Parse(req.BookingID)
	againstID, _ := uuid.Parse(req.AgainstUserID)

	d := &entity.Dispute{
		BookingID: bookingID, RaisedByUserID: callerID, AgainstUserID: againstID,
		Reason: req.Reason, Description: req.Description, EvidenceURLs: req.EvidenceURLs,
		Status: "open",
	}
	if err := h.disputeRepo.CreateDispute(c.Request().Context(), d); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": d.ID.String()})
}

func (h *DisputeHandler) ResolveDispute(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	var req dto.ResolveDisputeRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)

	d, err := h.disputeRepo.GetDispute(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "dispute not found")
	}
	now := time.Now()
	d.Status = "resolved"
	d.Resolution = req.Resolution
	d.ResolvedBy = callerID
	d.ResolvedAt = &now
	if req.Note != "" {
		d.InternalNotes = req.Note
	}
	if err := h.disputeRepo.UpdateDispute(c.Request().Context(), d); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"id": id.String(), "status": "resolved"})
}

// ── Support Tickets ──────────────────────────────────────────────────────────

func (h *DisputeHandler) ListTickets(c echo.Context) error {
	page, limit := paginationDefaults(c)
	status := c.QueryParam("status")
	items, total, err := h.disputeRepo.ListTickets(c.Request().Context(), status, page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.TicketResponse, len(items))
	for i, t := range items {
		r := dto.TicketResponse{
			ID: t.ID.String(), UserID: t.UserID.String(), Category: t.Category,
			Subject: t.Subject, Description: t.Description, Priority: t.Priority,
			Status: t.Status, CreatedAt: t.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
		if t.User != nil {
			r.UserName = t.User.Name
		}
		if t.AssignedTo != uuid.Nil {
			r.AssignedTo = t.AssignedTo.String()
		}
		if t.ResolvedAt != nil {
			r.ResolvedAt = t.ResolvedAt.Format("2006-01-02T15:04:05Z")
		}
		resp[i] = r
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *DisputeHandler) GetTicket(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	t, err := h.disputeRepo.GetTicket(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "ticket not found")
	}
	msgs := make([]dto.TicketMsgResponse, len(t.Messages))
	for i, m := range t.Messages {
		senderName := ""
		if m.Sender != nil {
			senderName = m.Sender.Name
		}
		msgs[i] = dto.TicketMsgResponse{
			ID: m.ID.String(), SenderName: senderName, SenderID: m.SenderID.String(),
			Body: m.Body, IsInternal: m.IsInternal, CreatedAt: m.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	userName := ""
	if t.User != nil {
		userName = t.User.Name
	}
	resp := dto.TicketResponse{
		ID: t.ID.String(), UserName: userName, UserID: t.UserID.String(),
		Category: t.Category, Subject: t.Subject, Description: t.Description,
		Priority: t.Priority, Status: t.Status, Messages: msgs,
		CreatedAt: t.CreatedAt.Format("2006-01-02T15:04:05Z"),
	}
	return response.OK(c, resp)
}

func (h *DisputeHandler) ReplyTicket(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	var req dto.ReplyTicketRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	msg := &entity.TicketMessage{
		TicketID: id, SenderID: callerID, Body: req.Body, IsInternal: req.IsInternal,
	}
	if err := h.disputeRepo.CreateTicketMessage(c.Request().Context(), msg); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": msg.ID.String()})
}

func (h *DisputeHandler) AssignTicket(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	var req dto.AssignTicketRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	assigneeID, _ := uuid.Parse(req.AssignedTo)

	t, err := h.disputeRepo.GetTicket(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "ticket not found")
	}
	t.AssignedTo = assigneeID
	t.Status = "in_progress"
	if err := h.disputeRepo.UpdateTicket(c.Request().Context(), t); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"id": id.String(), "assigned_to": req.AssignedTo})
}

// ── Review Moderation ────────────────────────────────────────────────────────

func (h *DisputeHandler) ListFlaggedReviews(c echo.Context) error {
	page, limit := paginationDefaults(c)
	items, total, err := h.verifyRepo.ListFlaggedReviews(c.Request().Context(), page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.AdminReviewResponse, len(items))
	for i, r := range items {
		pitchName, userName := "", ""
		if r.Pitch != nil {
			pitchName = r.Pitch.Name
		}
		if r.User != nil {
			userName = r.User.Name
		}
		bookingID := ""
		if r.BookingID != nil {
			bookingID = r.BookingID.String()
		}
		resp[i] = dto.AdminReviewResponse{
			ID: r.ID.String(), BookingID: bookingID, PitchName: pitchName,
			PitchID: r.PitchID.String(), UserName: userName, UserID: r.UserID.String(),
			Rating: int(r.Rating), Comment: r.Comment, Status: r.Status,
			FlaggedReason: r.FlaggedReason, CreatedAt: r.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *DisputeHandler) ModerateReview(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	var req dto.ModerateReviewRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)

	r, err := h.verifyRepo.GetReview(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "review not found")
	}
	switch req.Action {
	case "approve":
		r.Status = "active"
	case "remove":
		r.Status = "removed"
		r.FlaggedReason = req.Reason
	}
	r.ModeratedBy = &callerID
	if err := h.verifyRepo.UpdateReview(c.Request().Context(), r); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"id": id.String(), "status": r.Status})
}

// ── User Warnings & Bans ────────────────────────────────────────────────────

func (h *DisputeHandler) WarnUser(c echo.Context) error {
	userID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	var req dto.WarnUserRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	action := &entity.UserAction{
		UserID: userID, ActionType: "warning", Reason: req.Reason, IssuedBy: callerID,
	}
	if err := h.disputeRepo.CreateUserAction(c.Request().Context(), action); err != nil {
		return response.InternalError(c)
	}

	// Auto-suspend after 3 warnings
	count, _ := h.disputeRepo.CountWarnings(c.Request().Context(), userID)
	if count >= 3 {
		expires := time.Now().AddDate(0, 0, 7)
		suspend := &entity.UserAction{
			UserID: userID, ActionType: "suspend", Reason: "auto-suspend: 3 warnings reached",
			IssuedBy: callerID, ExpiresAt: &expires,
		}
		_ = h.disputeRepo.CreateUserAction(c.Request().Context(), suspend)
	}

	return response.Created(c, map[string]string{"id": action.ID.String(), "warnings_total": string(rune(count + 1))})
}

func (h *DisputeHandler) BanUser(c echo.Context) error {
	userID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	var req dto.WarnUserRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	action := &entity.UserAction{
		UserID: userID, ActionType: "ban", Reason: req.Reason, IssuedBy: callerID,
	}
	if err := h.disputeRepo.CreateUserAction(c.Request().Context(), action); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": action.ID.String()})
}

func (h *DisputeHandler) UnbanUser(c echo.Context) error {
	userID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	action := &entity.UserAction{
		UserID: userID, ActionType: "unban", Reason: "unbanned by admin", IssuedBy: callerID,
	}
	if err := h.disputeRepo.CreateUserAction(c.Request().Context(), action); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": action.ID.String()})
}

// ── KYC ──────────────────────────────────────────────────────────────────────

func (h *DisputeHandler) ListKYC(c echo.Context) error {
	page, limit := paginationDefaults(c)
	status := c.QueryParam("status")
	items, total, err := h.verifyRepo.ListKYC(c.Request().Context(), status, page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.KYCResponse, len(items))
	for i, k := range items {
		r := dto.KYCResponse{
			ID: k.ID.String(), UserID: k.UserID.String(), NIDNumber: k.NIDNumber,
			NIDPhotoFrontURL: k.NIDPhotoFrontURL, NIDPhotoBackURL: k.NIDPhotoBackURL,
			SelfieURL: k.SelfieURL, BusinessName: k.BusinessName,
			PayoutAccount: k.PayoutAccount, Status: k.Status, ReviewNote: k.ReviewNote,
		}
		if k.User != nil {
			r.UserName = k.User.Name
			if k.User.Phone != nil {
				r.UserPhone = *k.User.Phone
			}
		}
		if k.SubmittedAt != nil {
			r.SubmittedAt = k.SubmittedAt.Format("2006-01-02T15:04:05Z")
		}
		if k.ReviewedAt != nil {
			r.ReviewedAt = k.ReviewedAt.Format("2006-01-02T15:04:05Z")
		}
		resp[i] = r
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *DisputeHandler) GetKYC(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	k, err := h.verifyRepo.GetKYC(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "kyc not found")
	}
	r := dto.KYCResponse{
		ID: k.ID.String(), UserID: k.UserID.String(), NIDNumber: k.NIDNumber,
		NIDPhotoFrontURL: k.NIDPhotoFrontURL, NIDPhotoBackURL: k.NIDPhotoBackURL,
		SelfieURL: k.SelfieURL, BusinessName: k.BusinessName,
		PayoutAccount: k.PayoutAccount, Status: k.Status, ReviewNote: k.ReviewNote,
	}
	if k.User != nil {
		r.UserName = k.User.Name
		if k.User.Phone != nil {
			r.UserPhone = *k.User.Phone
		}
	}
	return response.OK(c, r)
}

func (h *DisputeHandler) ApproveKYC(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	k, err := h.verifyRepo.GetKYC(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "kyc not found")
	}
	now := time.Now()
	k.Status = "approved"
	k.ReviewedBy = &callerID
	k.ReviewedAt = &now
	if err := h.verifyRepo.UpdateKYC(c.Request().Context(), k); err != nil {
		return response.InternalError(c)
	}

	// Promote user to manager role
	user, err := h.userRepo.FindByID(c.Request().Context(), k.UserID)
	if err == nil {
		user.Role = entity.RoleManager
		_ = h.userRepo.Update(c.Request().Context(), user)
	}

	return response.OK(c, map[string]string{"id": id.String(), "status": "approved"})
}

func (h *DisputeHandler) RejectKYC(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	var req dto.RejectKYCRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	k, err := h.verifyRepo.GetKYC(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "kyc not found")
	}
	now := time.Now()
	k.Status = "rejected"
	k.ReviewedBy = &callerID
	k.ReviewedAt = &now
	k.ReviewNote = req.Reason
	if err := h.verifyRepo.UpdateKYC(c.Request().Context(), k); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"id": id.String(), "status": "rejected"})
}
