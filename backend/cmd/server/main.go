package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"

	"github.com/karam-flutter/humanitarian-backend/internal/assistant"
	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/beneficiary"
	"github.com/karam-flutter/humanitarian-backend/internal/campaigns"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/config"
	"github.com/karam-flutter/humanitarian-backend/internal/dashboard"
	"github.com/karam-flutter/humanitarian-backend/internal/db"
	"github.com/karam-flutter/humanitarian-backend/internal/donations"
	"github.com/karam-flutter/humanitarian-backend/internal/events"
	"github.com/karam-flutter/humanitarian-backend/internal/handlers"
	"github.com/karam-flutter/humanitarian-backend/internal/history"
	"github.com/karam-flutter/humanitarian-backend/internal/inkind"
	"github.com/karam-flutter/humanitarian-backend/internal/listings"
	"github.com/karam-flutter/humanitarian-backend/internal/marketplace"
	"github.com/karam-flutter/humanitarian-backend/internal/marriage"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/reports"
	"github.com/karam-flutter/humanitarian-backend/internal/sponsorships"
	"github.com/karam-flutter/humanitarian-backend/internal/support"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
	"github.com/karam-flutter/humanitarian-backend/internal/volunteers"
)

func main() {
	_ = godotenv.Load()

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	defer pool.Close()
	log.Printf("connected to Postgres")

	// Auto-apply pending SQL migrations when RUN_MIGRATIONS=1 (e.g. on a fresh
	// Railway Postgres). Each file runs at most once, tracked in
	// schema_migrations, so redeploys are no-ops. Off by default to never touch
	// an existing local dev database.
	if os.Getenv("RUN_MIGRATIONS") == "1" {
		dir := config.GetEnvDefault("MIGRATIONS_DIR", "./migrations")
		if err := db.RunMigrations(ctx, pool, dir); err != nil {
			log.Fatalf("migrations: %v", err)
		}
	}

	if cfg.AppEnv == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	tokenStore := auth.NewTokenStore(pool)
	otpStore := auth.NewOTPStore(pool)
	userStore := users.NewStore(pool)
	campaignStore := campaigns.NewStore(pool)
	donationStore := donations.NewStore(pool)
	beneficiaryStore := beneficiary.NewStore(pool)
	marketplaceStore := marketplace.NewStore(pool)
	chatStore := chat.New(pool)
	eventsStore := events.New(pool)
	notifier := notify.New(pool)
	assistantSvc := assistant.New()

	listingsStore := listings.New(pool)
	supportStore := support.New(pool)
	inkindStore := inkind.New(pool)
	marriageStore := marriage.New(pool)
	sponsorshipsStore := sponsorships.New(pool)
	volunteersStore := volunteers.New(pool)
	reportsStore := reports.New(pool)
	dashboardStore := dashboard.New(pool)
	historyStore := history.New(pool)

	// Where uploaded files live on disk; served back at /images/*.
	uploadDir := "./images"

	healthH := handlers.NewHealthHandler(pool)
	// Phase 19 — OTPIQ delivery for real-mode OTP. Returns nil when
	// OTPIQ_API_KEY isn't set; the handler then refuses real-mode but
	// demo mode keeps working.
	otpiqClient := auth.NewOTPIQClient()
	if otpiqClient != nil {
		log.Printf("[otp] OTPIQ enabled (provider=whatsapp-sms by default)")
	} else {
		log.Printf("[otp] OTPIQ disabled (OTPIQ_API_KEY not set; demo mode still works)")
	}
	if assistantSvc.LLMEnabled() {
		log.Printf("[assistant] AI mode enabled (LLM via ANTHROPIC_API_KEY)")
	} else {
		log.Printf("[assistant] local mode (set ANTHROPIC_API_KEY for full AI; keyword engine active)")
	}
	authH := handlers.NewAuthHandler(tokenStore, otpStore, userStore, otpiqClient)
	profileH := handlers.NewProfileHandler(userStore, uploadDir)
	chooseRoleH := handlers.NewChooseRoleHandler(userStore)
	registrationH := handlers.NewRegistrationHandler(userStore)
	registrationAdminH := handlers.NewRegistrationAdminHandler(userStore, notifier)
	campaignsH := handlers.NewCampaignsHandler(campaignStore)
	donationsH := handlers.NewDonationsHandler(donationStore, notifier)
	beneficiaryH := handlers.NewBeneficiaryHandler(beneficiaryStore, userStore, notifier)
	marketplaceH := handlers.NewMarketplaceHandler(marketplaceStore, notifier)
	chatH := handlers.NewChatHandler(chatStore, notifier, pool)
	eventsH := handlers.NewEventsHandler(eventsStore, pool)
	assistantH := handlers.NewAssistantHandler(assistantSvc, pool)
	notificationsH := handlers.NewNotificationsHandler(notifier)
	pushH := handlers.NewPushHandler(notifier)
	kpisH := handlers.NewDashboardKPIsHandler(pool)

	adminListsH := handlers.NewAdminListsHandler(pool)
	adminStatusH := handlers.NewAdminStatusHandler(pool, notifier)
	adminEditH := handlers.NewAdminEditHandler(pool)
	adminCreateH := handlers.NewAdminCreateHandler(pool, notifier)
	adminDeleteH := handlers.NewAdminDeleteHandler(pool)
	adminUploadH := handlers.NewAdminUploadHandler(uploadDir)
	adminDetailH := handlers.NewAdminDetailHandler(pool)
	adminExportH := handlers.NewAdminExportHandler(pool)
	listingsH := handlers.NewListingsHandler(listingsStore)
	usersAdminH := handlers.NewUsersAdminHandler(userStore)
	supportH := handlers.NewSupportHandler(supportStore, notifier)
	inkindH := handlers.NewInKindHandler(inkindStore, notifier)
	marriageH := handlers.NewMarriageHandler(marriageStore, notifier)
	sponsorshipsH := handlers.NewSponsorshipsHandler(sponsorshipsStore, notifier)
	volunteersH := handlers.NewVolunteersHandler(volunteersStore, notifier)
	reportsH := handlers.NewReportsHandler(reportsStore)
	dashboardH := handlers.NewDashboardHandler(dashboardStore, userStore)
	historyH := handlers.NewHistoryHandler(historyStore, userStore)

	r := gin.Default()

	// CORS — the admin dashboard is served from a different origin in production
	// (e.g. dashboard.up.railway.app calling backend.up.railway.app), so the
	// browser needs CORS headers. Auth is via Bearer token (not cookies), so a
	// permissive default is safe; tighten with CORS_ALLOWED_ORIGINS if desired.
	r.Use(corsMiddleware())

	r.GET("/health", healthH.Get)

	// Serve uploaded profile pictures (and any other image assets).
	r.Static("/images", uploadDir)

	api := r.Group("/api")
	{
		api.GET("/health", healthH.Get)

		// Public auth endpoints (no Bearer required).
		api.POST("/auth/login", authH.Login)
		api.POST("/auth/login/", authH.Login) // PHP path had trailing slash
		api.POST("/auth/admin/login", authH.AdminLogin)  // username + password (dashboard)
		api.POST("/auth/admin/login/", authH.AdminLogin) // trailing-slash tolerant
		api.POST("/auth/otp/request", authH.OTPRequest)
		api.POST("/auth/otp/request/", authH.OTPRequest)
		api.POST("/auth/otp/verify", authH.OTPVerify)
		api.POST("/auth/otp/verify/", authH.OTPVerify)

		// Compatibility stub for the existing Flutter CSRF flow.
		// The Go API is Bearer-only, so there's nothing to issue here, but
		// returning a well-formed shape keeps FeaturedCampaignsController
		// happy without any Dart changes.
		csrfStub := func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{
				"status":     "success",
				"csrf_token": "noop",
				"action":     c.DefaultQuery("action", "login"),
				"ttl":        600,
			})
		}
		api.GET("/auth/login/get_token.php", csrfStub)
		api.GET("/auth/login/get_token", csrfStub)

		// Public list of campaigns (read-only).
		api.GET("/campaigns", campaignsH.List)
		api.GET("/campaigns/", campaignsH.List)

		// Public read-only listings (Flutter + public web).
		api.GET("/partners", listingsH.Partners)
		api.GET("/partners/", listingsH.Partners)
		api.GET("/media", listingsH.Media)
		api.GET("/media/", listingsH.Media)
		api.GET("/community", listingsH.Community)
		api.GET("/community/", listingsH.Community)
		api.GET("/marriage", marriageH.Get)
		api.GET("/marriage/", marriageH.Get)
		api.GET("/reports", reportsH.Get)
		api.GET("/reports/", reportsH.Get)
		// /users + /donations moved under admin group below (admin-only).

		// Dual-mode GETs: public read OR auth'd "my own data" view depending on query params.
		dual := api.Group("/")
		dual.Use(auth.OptionalBearer(tokenStore))
		{
			dual.GET("/beneficiary_cases", beneficiaryH.GetCases)
			dual.GET("/beneficiary_cases/", beneficiaryH.GetCases)
			dual.GET("/marketplace", marketplaceH.Get)
			dual.GET("/marketplace/", marketplaceH.Get)
		}

		// Session group — Bearer required but NO approval gate. Endpoints a
		// not-yet-approved (incomplete/pending/rejected) user must still reach:
		// finish/check their registration, read their own account, and log out.
		session := api.Group("/")
		session.Use(auth.RequireBearer(tokenStore))
		{
			session.POST("/auth/logout", authH.Logout)
			session.GET("/auth/me", func(c *gin.Context) {
				u, _ := auth.UserFromGin(c)
				if u == nil {
					c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
					return
				}
				acc, _ := userStore.GetAccountForClient(c.Request.Context(), u.UserID)
				c.JSON(http.StatusOK, gin.H{
					"user_id":             u.UserID,
					"role_id":             u.RoleID,
					"phone":               u.Phone,
					"registration_status": u.RegistrationStatus,
					"account":             acc,
				})
			})

			// New-user onboarding: submit the registration form / poll status.
			session.POST("/registration/submit", registrationH.Submit)
			session.POST("/registration/submit/", registrationH.Submit)
			session.GET("/registration/status", registrationH.Status)
			session.GET("/registration/status/", registrationH.Status)
		}

		// Protected — Bearer + approved registration. Non-approved users get
		// 403 (with registration_status echoed) from RequireApproved.
		authed := api.Group("/")
		authed.Use(auth.RequireBearer(tokenStore), auth.RequireApproved())
		{
			// Profile + role
			authed.GET("/profile/get", profileH.Get)
			authed.GET("/profile/get/", profileH.Get)
			authed.POST("/profile/set", profileH.Set)
			authed.POST("/profile/set/", profileH.Set)
			authed.POST("/choose_role", chooseRoleH.Post)
			authed.POST("/choose_role/", chooseRoleH.Post)

			// Donations
			authed.POST("/donate", donationsH.Create)
			authed.POST("/donate/", donationsH.Create)
			authed.POST("/donate/my_donations", donationsH.My)
			authed.POST("/donate/my_donations/", donationsH.My)
			authed.GET("/donate/my_donations", donationsH.My)
			authed.GET("/donate/my_donations/", donationsH.My)
			// Phase 23 — donor self-cancel for still-registered donations.
			authed.POST("/donate/:id/cancel", donationsH.Cancel)

			// Beneficiary cases — submit (Bearer + role 2)
			authed.POST("/beneficiary_cases", beneficiaryH.PostCase)
			authed.POST("/beneficiary_cases/", beneficiaryH.PostCase)

			// Beneficiary project requests
			authed.GET("/beneficiary_project_requests", beneficiaryH.GetRequests)
			authed.GET("/beneficiary_project_requests/", beneficiaryH.GetRequests)
			authed.POST("/beneficiary_project_requests", beneficiaryH.PostRequest)
			authed.POST("/beneficiary_project_requests/", beneficiaryH.PostRequest)

			// Marketplace — POST (create order)
			authed.POST("/marketplace", marketplaceH.Post)
			authed.POST("/marketplace/", marketplaceH.Post)

			// Beneficiary — view donations made to their own campaigns.
			authed.GET("/beneficiary/campaign-donations", donationsH.BeneficiaryCampaignDonations)
			authed.GET("/beneficiary/campaign-donations/", donationsH.BeneficiaryCampaignDonations)

			// Donor ↔ campaign-owner chat (Phase 28).
			authed.POST("/chats/request", chatH.Request)
			authed.GET("/chats", chatH.List)
			authed.GET("/chats/", chatH.List)
			authed.POST("/chats/:id/accept", chatH.Accept)
			authed.POST("/chats/:id/decline", chatH.Decline)
			authed.GET("/chats/:id/messages", chatH.Messages)
			authed.POST("/chats/:id/messages", chatH.PostMessage)

			// AI Support Assistant (Phase 29).
			authed.POST("/assistant/chat", assistantH.Chat)
			authed.POST("/assistant/chat/", assistantH.Chat)

			// Activity event log (Postgres home of the old Firestore feed).
			authed.POST("/events", eventsH.Log)
			authed.POST("/events/", eventsH.Log)

			// Notifications
			authed.GET("/notifications", notificationsH.List)
			authed.GET("/notifications/", notificationsH.List)
			authed.POST("/notifications", notificationsH.Post)
			authed.POST("/notifications/", notificationsH.Post)

			// Device tokens (FCM)
			authed.POST("/notifications/device", notificationsH.RegisterDevice)
			authed.POST("/notifications/device/", notificationsH.RegisterDevice)
			authed.DELETE("/notifications/device", notificationsH.UnregisterDevice)
			authed.DELETE("/notifications/device/", notificationsH.UnregisterDevice)

			// Phase 3g endpoints
			authed.POST("/support", supportH.Post)
			authed.POST("/support/", supportH.Post)

			authed.GET("/in_kind_donations", inkindH.Get)
			authed.GET("/in_kind_donations/", inkindH.Get)
			authed.POST("/in_kind_donations", inkindH.Post)
			authed.POST("/in_kind_donations/", inkindH.Post)

			authed.POST("/marriage", marriageH.Post)
			authed.POST("/marriage/", marriageH.Post)

			authed.GET("/sponsorships", sponsorshipsH.Get)
			authed.GET("/sponsorships/", sponsorshipsH.Get)
			authed.POST("/sponsorships", sponsorshipsH.Post)
			authed.POST("/sponsorships/", sponsorshipsH.Post)

			authed.GET("/volunteers", volunteersH.Get)
			authed.GET("/volunteers/", volunteersH.Get)
			authed.POST("/volunteers", volunteersH.Post)
			authed.POST("/volunteers/", volunteersH.Post)
			authed.GET("/volunteer_hub", volunteersH.Get)
			authed.GET("/volunteer_hub/", volunteersH.Get)
			authed.POST("/volunteer_hub", volunteersH.Post)
			authed.POST("/volunteer_hub/", volunteersH.Post)
			// Phase 21b — clean REST resource for browsing missions
			// without the joined-missions overlay /volunteer_hub adds.
			authed.GET("/missions", volunteersH.Missions)
			authed.GET("/missions/", volunteersH.Missions)

			authed.GET("/dashboard", dashboardH.Get)
			authed.GET("/dashboard/", dashboardH.Get)
			authed.GET("/history", historyH.Get)
			authed.GET("/history/", historyH.Get)
		}

		// Admin-only routes — Bearer + users.is_admin=1 required. Returns 403
		// for non-admin users; 401 for missing/expired tokens. Defense in depth:
		// the SPA also hides these pages from non-admin users (Phase 8).
		admin := api.Group("/")
		admin.Use(auth.RequireAdmin(tokenStore))
		{
			// Admin-only lists that previously lived on the public API but
			// expose cross-user data — moved here under /admin/*.
			admin.GET("/admin/users", usersAdminH.List)
			admin.GET("/admin/users/", usersAdminH.List)
			admin.GET("/admin/donations", donationsH.AdminList)
			admin.GET("/admin/donations/", donationsH.AdminList)

			// New-user registration approval queue.
			admin.GET("/admin/registrations", registrationAdminH.List)
			admin.GET("/admin/registrations/", registrationAdminH.List)
			admin.POST("/admin/registrations/:id/approve", registrationAdminH.Approve)
			admin.POST("/admin/registrations/:id/reject", registrationAdminH.Reject)

			// Phase 16 — sidebar live notifications. Polled every 5s by the
			// SPA. Returns pending-action counts across all moderated tables
			// in a single query.
			pendingH := handlers.NewPendingCountsHandler(pool)
			admin.GET("/admin/pending-counts", pendingH.Counts)
			admin.GET("/admin/pending-counts/", pendingH.Counts)

			// Live activity feed for the admin dashboard.
			admin.GET("/admin/events", eventsH.AdminList)
			admin.GET("/admin/events/", eventsH.AdminList)

			// Cross-user paginated lists.
			admin.GET("/admin/beneficiary_cases", beneficiaryH.AdminCases)
			admin.GET("/admin/beneficiary_cases/", beneficiaryH.AdminCases)
			admin.GET("/admin/beneficiary_project_requests", beneficiaryH.AdminRequests)
			admin.GET("/admin/beneficiary_project_requests/", beneficiaryH.AdminRequests)
			admin.GET("/admin/marketplace/products", marketplaceH.AdminProducts)
			admin.GET("/admin/marketplace/products/", marketplaceH.AdminProducts)
			admin.GET("/admin/marketplace/orders", marketplaceH.AdminOrders)
			admin.GET("/admin/marketplace/orders/", marketplaceH.AdminOrders)
			admin.GET("/admin/notifications", adminListsH.Notifications)
			admin.GET("/admin/notifications/", adminListsH.Notifications)
			admin.GET("/admin/in_kind_donations", adminListsH.InKindDonations)
			admin.GET("/admin/in_kind_donations/", adminListsH.InKindDonations)
			admin.GET("/admin/support_tickets", adminListsH.SupportTickets)
			admin.GET("/admin/support_tickets/", adminListsH.SupportTickets)
			admin.GET("/admin/volunteer_applications", adminListsH.VolunteerApplications)
			admin.GET("/admin/volunteer_applications/", adminListsH.VolunteerApplications)
			// Phase 21 — moderation of mission signups (the join requests
			// volunteers send for specific missions). Has its own status
			// transitions (approved/joined/completed/no_show etc.) plus
			// timestamp side-effects on checked_in_at + completed_at.
			admin.GET("/admin/volunteer_mission_signups", adminListsH.VolunteerMissionSignups)
			admin.GET("/admin/volunteer_mission_signups/", adminListsH.VolunteerMissionSignups)
			admin.POST("/admin/volunteer_mission_signups/:id/status", adminStatusH.MissionSignup)

			// Phase 24 — per-mission Kanban "Volunteer board" view.
			// Groups signups into 4 lanes (pending/approved/on_mission/
			// completed-30d) per mission for the admin overview screen.
			admin.GET("/admin/volunteer_board", adminListsH.VolunteerBoard)
			admin.GET("/admin/volunteer_board/", adminListsH.VolunteerBoard)

			// Phase 23 — admin action to publish an approved beneficiary
			// project request to the donor-facing campaigns list.
			admin.POST("/admin/beneficiary_project_requests/:id/publish", adminStatusH.PublishProjectRequest)

			// Phase 22 — mission CRUD. Creating a mission with status='open'
			// (or transitioning a draft to open) broadcasts NewVolunteerMissionMsg
			// to all volunteers (role_id=3) in 4 languages.
			admin.GET("/admin/missions", adminListsH.VolunteerMissions)
			admin.GET("/admin/missions/", adminListsH.VolunteerMissions)
			admin.POST("/admin/missions", adminCreateH.Mission)
			admin.POST("/admin/missions/", adminCreateH.Mission)
			admin.PATCH("/admin/missions/:id", adminEditH.Mission)
			admin.POST("/admin/missions/:id/status", adminStatusH.Mission)
			admin.DELETE("/admin/missions/:id", adminDeleteH.VolunteerMission)
			admin.GET("/admin/audit_logs", adminListsH.AuditLogs)
			admin.GET("/admin/audit_logs/", adminListsH.AuditLogs)

			// Push composition + KPIs.
			admin.GET("/admin/push/status", pushH.Status)
			admin.POST("/admin/push/send", pushH.Send)
			// In-app broadcast to every user (works without FCM).
			admin.POST("/admin/notifications/broadcast", pushH.BroadcastInApp)
			admin.POST("/admin/notifications/broadcast/", pushH.BroadcastInApp)

			// Donor ↔ owner chat — admin (support) oversight.
			admin.GET("/admin/chats", chatH.AdminList)
			admin.GET("/admin/chats/", chatH.AdminList)
			admin.GET("/admin/chats/:id/messages", chatH.AdminMessages)
			admin.POST("/admin/chats/:id/messages", chatH.AdminPostMessage)
			admin.GET("/admin/dashboard_kpis", kpisH.Get)
			admin.GET("/admin/dashboard_kpis/", kpisH.Get)

			// Phase 9: status-change mutations. Each endpoint validates the
			// new status against the resource's allowed-values list.
			admin.POST("/admin/beneficiary_cases/:id/status", adminStatusH.BeneficiaryCase)
			admin.POST("/admin/beneficiary_project_requests/:id/status", adminStatusH.ProjectRequest)
			admin.POST("/admin/marketplace/products/:id/status", adminStatusH.MarketplaceProduct)
			admin.POST("/admin/marketplace/orders/:id/status", adminStatusH.MarketplaceOrder)
			admin.POST("/admin/marriage/:id/status", adminStatusH.Marriage)
			admin.POST("/admin/partners/:id/status", adminStatusH.Partner)
			admin.POST("/admin/media/:id/status", adminStatusH.Media)
			admin.POST("/admin/community/:id/status", adminStatusH.Community)
			admin.POST("/admin/volunteer_applications/:id/status", adminStatusH.VolunteerApplication)
			admin.POST("/admin/sponsorships/:id/status", adminStatusH.Sponsorship)
			admin.POST("/admin/in_kind_donations/:id/status", adminStatusH.InKindDonation)
			admin.POST("/admin/support_tickets/:id/status", adminStatusH.SupportTicket)
			admin.POST("/admin/donations/:id/status", adminStatusH.Donation)
			admin.POST("/admin/users/:id/role", adminStatusH.UserRole)
			admin.POST("/admin/users/:id/active", adminStatusH.UserActive)
			admin.POST("/admin/users/:id/admin", adminStatusH.UserAdmin)

			// Phase 10: partial-update (edit modal) endpoints.
			admin.PATCH("/admin/partners/:id", adminEditH.Partner)
			admin.PATCH("/admin/media/:id", adminEditH.Media)
			admin.PATCH("/admin/community/:id", adminEditH.Community)
			admin.PATCH("/admin/marriage/:id", adminEditH.Marriage)
			admin.PATCH("/admin/marketplace/products/:id", adminEditH.MarketplaceProduct)
			admin.PATCH("/admin/marketplace/orders/:id", adminEditH.MarketplaceOrder)
			admin.PATCH("/admin/beneficiary_cases/:id", adminEditH.BeneficiaryCase)
			admin.PATCH("/admin/beneficiary_project_requests/:id", adminEditH.ProjectRequest)
			admin.PATCH("/admin/sponsorships/:id", adminEditH.Sponsorship)
			admin.PATCH("/admin/in_kind_donations/:id", adminEditH.InKindDonation)
			admin.PATCH("/admin/support_tickets/:id", adminEditH.SupportTicket)
			admin.PATCH("/admin/donations/:id", adminEditH.Donation)
			admin.PATCH("/admin/volunteer_applications/:id", adminEditH.VolunteerApplication)
			admin.PATCH("/admin/users/:id", adminEditH.User)

			// Phase 11: create (admin) endpoints.
			admin.POST("/admin/partners", adminCreateH.Partner)
			admin.POST("/admin/media", adminCreateH.Media)
			admin.POST("/admin/community", adminCreateH.Community)
			admin.POST("/admin/marriage", adminCreateH.MarriageProfile)
			admin.POST("/admin/marketplace/products", adminCreateH.MarketplaceProduct)
			admin.POST("/admin/beneficiary_cases", adminCreateH.BeneficiaryCase)
			admin.POST("/admin/beneficiary_project_requests", adminCreateH.ProjectRequest)
			admin.POST("/admin/sponsorships", adminCreateH.Sponsorship)
			admin.POST("/admin/in_kind_donations", adminCreateH.InKindDonation)
			admin.POST("/admin/support_tickets", adminCreateH.SupportTicket)
			admin.POST("/admin/donations", adminCreateH.Donation)
			admin.POST("/admin/volunteer_applications", adminCreateH.VolunteerApplication)

			// Phase 13: hard-delete endpoints.
			admin.DELETE("/admin/partners/:id", adminDeleteH.Partner)
			admin.DELETE("/admin/media/:id", adminDeleteH.Media)
			admin.DELETE("/admin/community/:id", adminDeleteH.Community)
			admin.DELETE("/admin/marriage/:id", adminDeleteH.Marriage)
			admin.DELETE("/admin/marketplace/products/:id", adminDeleteH.MarketplaceProduct)
			admin.DELETE("/admin/marketplace/orders/:id", adminDeleteH.MarketplaceOrder)
			admin.DELETE("/admin/beneficiary_cases/:id", adminDeleteH.BeneficiaryCase)
			admin.DELETE("/admin/beneficiary_project_requests/:id", adminDeleteH.ProjectRequest)
			admin.DELETE("/admin/sponsorships/:id", adminDeleteH.Sponsorship)
			admin.DELETE("/admin/in_kind_donations/:id", adminDeleteH.InKindDonation)
			admin.DELETE("/admin/support_tickets/:id", adminDeleteH.SupportTicket)
			admin.DELETE("/admin/donations/:id", adminDeleteH.Donation)
			admin.DELETE("/admin/volunteer_applications/:id", adminDeleteH.VolunteerApplication)
			admin.DELETE("/admin/users/:id", adminDeleteH.User)

			// Phase 14: campaigns CRUD (admin view of the real `campaigns` table).
			admin.GET("/admin/campaigns", adminListsH.Campaigns)
			admin.GET("/admin/campaigns/", adminListsH.Campaigns)
			admin.POST("/admin/campaigns", adminCreateH.Campaign)
			admin.PATCH("/admin/campaigns/:id", adminEditH.Campaign)
			admin.DELETE("/admin/campaigns/:id", adminDeleteH.Campaign)

			// Phase 15: file uploads. Multipart POST returns a path that the
			// SPA stores in the relevant column (logo_path, image_path, etc.).
			admin.POST("/admin/upload", adminUploadH.Upload)

			// Phase 16: generic detail endpoint. Reads one row from any
			// allowlisted admin resource using SELECT *.
			admin.GET("/admin/detail/:resource/:id", adminDetailH.Detail)

			// Full-DB JSON export (admin backup tool).
			admin.GET("/admin/export/all", adminExportH.ExportAll)
		}
	}

	srv := &http.Server{
		Addr:              ":" + cfg.HTTPPort,
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("listening on http://localhost:%s", cfg.HTTPPort)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Println("shutting down...")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("shutdown: %v", err)
	}
}

// corsMiddleware returns a Gin middleware that adds CORS headers. The allowed
// origins come from CORS_ALLOWED_ORIGINS (comma-separated); when unset or "*",
// any origin is reflected. Auth uses Bearer tokens (no cookies), so credentials
// are not required and "*" is safe.
func corsMiddleware() gin.HandlerFunc {
	raw := strings.TrimSpace(os.Getenv("CORS_ALLOWED_ORIGINS"))
	allowAll := raw == "" || raw == "*"
	allowed := map[string]bool{}
	if !allowAll {
		for _, o := range strings.Split(raw, ",") {
			if o = strings.TrimSpace(o); o != "" {
				allowed[o] = true
			}
		}
	}
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if origin != "" && (allowAll || allowed[origin]) {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
			c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type, Accept")
			c.Header("Access-Control-Max-Age", "86400")
		}
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}
