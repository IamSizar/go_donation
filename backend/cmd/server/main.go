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

	"github.com/karam-flutter/humanitarian-backend/internal/appsettings"
	"github.com/karam-flutter/humanitarian-backend/internal/assistant"
	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/beneficiary"
	"github.com/karam-flutter/humanitarian-backend/internal/campaigns"
	"github.com/karam-flutter/humanitarian-backend/internal/casevolchat"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/citysectors"
	"github.com/karam-flutter/humanitarian-backend/internal/config"
	"github.com/karam-flutter/humanitarian-backend/internal/content"
	"github.com/karam-flutter/humanitarian-backend/internal/dashboard"
	"github.com/karam-flutter/humanitarian-backend/internal/db"
	"github.com/karam-flutter/humanitarian-backend/internal/donations"
	"github.com/karam-flutter/humanitarian-backend/internal/events"
	"github.com/karam-flutter/humanitarian-backend/internal/guest"
	"github.com/karam-flutter/humanitarian-backend/internal/handlers"
	"github.com/karam-flutter/humanitarian-backend/internal/history"
	"github.com/karam-flutter/humanitarian-backend/internal/inkind"
	"github.com/karam-flutter/humanitarian-backend/internal/listings"
	"github.com/karam-flutter/humanitarian-backend/internal/marketplace"
	"github.com/karam-flutter/humanitarian-backend/internal/marketplacecategories"
	"github.com/karam-flutter/humanitarian-backend/internal/marriage"
	"github.com/karam-flutter/humanitarian-backend/internal/marriagechat"
	"github.com/karam-flutter/humanitarian-backend/internal/mediacategories"
	"github.com/karam-flutter/humanitarian-backend/internal/moderation"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/partnerratings"
	"github.com/karam-flutter/humanitarian-backend/internal/paymentmethods"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
	"github.com/karam-flutter/humanitarian-backend/internal/postengagement"
	"github.com/karam-flutter/humanitarian-backend/internal/projectcategories"
	"github.com/karam-flutter/humanitarian-backend/internal/reports"
	"github.com/karam-flutter/humanitarian-backend/internal/scheduler"
	"github.com/karam-flutter/humanitarian-backend/internal/search"
	"github.com/karam-flutter/humanitarian-backend/internal/sectioncodes"
	"github.com/karam-flutter/humanitarian-backend/internal/sponsorships"
	"github.com/karam-flutter/humanitarian-backend/internal/staffchat"
	"github.com/karam-flutter/humanitarian-backend/internal/support"
	"github.com/karam-flutter/humanitarian-backend/internal/tasks"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
	"github.com/karam-flutter/humanitarian-backend/internal/volunteers"
	"github.com/karam-flutter/humanitarian-backend/internal/wallet"
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
	loginLockStore := auth.NewLoginLockStore(pool) // Requirement 6c — login brute-force throttle
	userStore := users.NewStore(pool)
	campaignStore := campaigns.NewStore(pool)
	donationStore := donations.NewStore(pool)
	codesStore := sectioncodes.New(pool)
	donationStore.Codes = codesStore // #14 — per-section transaction-code namespaces
	beneficiaryStore := beneficiary.NewStore(pool)
	marketplaceStore := marketplace.NewStore(pool)
	chatStore := chat.New(pool)
	staffChatStore := staffchat.New(pool)     // Note #36 — internal staff-to-staff chat
	caseVolChatStore := casevolchat.New(pool) // Note #36 — Staff↔Volunteer↔Beneficiary chat
	eventsStore := events.New(pool)
	notifier := notify.New(pool)
	walletStore := wallet.New(pool)        // Note #42 — test-phase internal app wallet
	tasksStore := tasks.New(pool)          // Client note — "Task Verification"
	settingsStore := appsettings.New(pool) // #36 — admin-editable app settings.

	listingsStore := listings.New(pool)
	supportStore := support.New(pool)
	inkindStore := inkind.New(pool)
	marriageStore := marriage.New(pool)
	marriageChatStore := marriagechat.New(pool) // Note #35 — staff-mediated marriage chat
	sponsorshipsStore := sponsorships.New(pool)
	volunteersStore := volunteers.New(pool)
	professionStore := volunteers.NewProfessionStore(pool)

	// Client note — AI Assistant "more developed": tool-calling so the model
	// can look up the CALLER'S OWN wallet/donations/marriage/case/volunteer
	// data instead of only offering canned navigation help. Constructed here
	// (after its dependency stores exist) rather than up with the other
	// stores above.
	assistantSvc := assistant.New(assistant.Deps{
		Wallet:      walletStore,
		Donations:   donationStore,
		Marriage:    marriageStore,
		Beneficiary: beneficiaryStore,
		Volunteers:  volunteersStore,
	}, settingsStore)
	projectCatStore := projectcategories.New(pool)
	citySectorStore := citysectors.New(pool)               // #29 — City Guide sectors
	searchStore := search.New(pool)                        // #33 — global search
	mediaCatStore := mediacategories.New(pool)             // #22 — "Our Work" categories
	postEngageStore := postengagement.New(pool)            // #24 — likes/comments/share
	bannedWordsStore := moderation.New(pool)               // #25 — banned-words blocklist
	partnerRatingStore := partnerratings.New(pool)         // #27 — partner ratings
	marketplaceCatStore := marketplacecategories.New(pool) // #28 — marketplace categories
	paymentMethodStore := paymentmethods.New(pool)
	// Section 13 — register admin-added professions so volunteers can be
	// tagged with them (survives restart). Best-effort; a failure just means
	// custom skills won't validate until first added again.
	if err := professionStore.LoadAndRegister(ctx); err != nil {
		log.Printf("[professions] load failed: %v", err)
	}
	reportsStore := reports.New(pool)
	dashboardStore := dashboard.New(pool)
	historyStore := history.New(pool)

	// #20 — sponsorship payment-due reminder scheduler. Off unless
	// RUN_SCHEDULER=1, so deploys are safe until explicitly enabled. Runs in
	// its own goroutine and exits when ctx is cancelled on shutdown.
	if cfg.RunScheduler {
		sched := scheduler.New(sponsorshipsStore, notifier, cfg.SchedulerInterval, cfg.ReminderDaysBefore)
		go sched.Start(ctx)
	} else {
		log.Printf("[scheduler] disabled (set RUN_SCHEDULER=1 to enable reminders)")
	}

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
	// #15 — wire the OTPIQ custom-SMS sender into the donation store so a donation
	// arrival can alert the section's contact (best-effort, nil-safe).
	donationStore.SendSMS = func(ctx context.Context, phone, message string) error {
		if otpiqClient == nil {
			return nil
		}
		_, err := otpiqClient.SendMessage(ctx, phone, message)
		return err
	}
	if assistantSvc.LLMEnabled() {
		log.Printf("[assistant] AI mode enabled (LLM via ANTHROPIC_API_KEY)")
	} else {
		log.Printf("[assistant] local mode (set ANTHROPIC_API_KEY for full AI; keyword engine active)")
	}
	authH := handlers.NewAuthHandler(tokenStore, otpStore, userStore, otpiqClient, loginLockStore, notifier)
	profileH := handlers.NewProfileHandler(userStore, uploadDir)
	chooseRoleH := handlers.NewChooseRoleHandler(userStore)
	registrationH := handlers.NewRegistrationHandler(userStore)
	registrationAdminH := handlers.NewRegistrationAdminHandler(userStore, notifier)
	campaignsH := handlers.NewCampaignsHandler(campaignStore)
	donationsH := handlers.NewDonationsHandler(donationStore, notifier, walletStore)
	beneficiaryH := handlers.NewBeneficiaryHandler(beneficiaryStore, userStore, notifier)
	marketplaceH := handlers.NewMarketplaceHandler(marketplaceStore, notifier, walletStore)
	walletH := handlers.NewWalletHandler(walletStore, notifier)
	tasksH := handlers.NewTasksHandler(tasksStore, notifier)
	chatH := handlers.NewChatHandler(chatStore, notifier, pool)
	staffChatH := handlers.NewStaffChatHandler(staffChatStore, notifier, pool)
	caseVolChatH := handlers.NewCaseVolunteerChatHandler(caseVolChatStore, notifier)
	volunteerCheckinH := handlers.NewVolunteerCheckinHandler(pool, notifier, caseVolChatStore)
	eventsH := handlers.NewEventsHandler(eventsStore, pool)
	assistantH := handlers.NewAssistantHandler(assistantSvc, pool)
	notificationsH := handlers.NewNotificationsHandler(notifier)
	pushH := handlers.NewPushHandler(notifier)
	kpisH := handlers.NewDashboardKPIsHandler(pool)

	adminListsH := handlers.NewAdminListsHandler(pool)
	adminStatusH := handlers.NewAdminStatusHandler(pool, notifier, eventsStore, caseVolChatStore)
	adminEditH := handlers.NewAdminEditHandler(pool)
	adminCreateH := handlers.NewAdminCreateHandler(pool, notifier)
	adminCreateH.Codes = codesStore // #14 — namespace admin-created donation refs too
	adminDeleteH := handlers.NewAdminDeleteHandler(pool)
	adminTrashH := handlers.NewAdminTrashHandler(pool)
	adminUploadH := handlers.NewAdminUploadHandler(uploadDir)
	permStore := permissions.New(pool)
	adminDetailH := handlers.NewAdminDetailHandler(pool, permStore)
	adminExportH := handlers.NewAdminExportHandler(pool)
	// Requirement 6c — stamp the hash chain onto any pre-chain audit rows so the
	// ledger verifies as intact from the first request. Best-effort: a failure
	// here must not stop the server from booting.
	if err := permStore.BackfillChain(ctx); err != nil {
		log.Printf("[audit] chain backfill failed: %v", err)
	}
	adminPermsH := handlers.NewAdminPermissionsHandler(permStore, otpStore, otpiqClient)
	adminProfessionsH := handlers.NewAdminProfessionsHandler(professionStore)
	projectCategoriesH := handlers.NewProjectCategoriesHandler(projectCatStore)
	citySectorsH := handlers.NewCitySectorsHandler(citySectorStore)                                              // #29
	searchH := handlers.NewSearchHandler(searchStore)                                                            // #33
	fieldRulesH := handlers.NewFieldRulesHandler(pool)                                                           // #43
	aidReceiptsH := handlers.NewAidReceiptsHandler(pool)                                                         // #50
	mediaCategoriesH := handlers.NewMediaCategoriesHandler(mediaCatStore)                                        // #22
	mediaEngageH := handlers.NewMediaEngagementHandler(postEngageStore, bannedWordsStore, notifier, eventsStore) // #24/#25
	bannedWordsH := handlers.NewBannedWordsHandler(bannedWordsStore)                                             // #25
	partnerEngageH := handlers.NewPartnerEngagementHandler(partnerRatingStore)                                   // #27
	marketplaceCategoriesH := handlers.NewMarketplaceCategoriesHandler(marketplaceCatStore)                      // #28
	paymentMethodsH := handlers.NewPaymentMethodsHandler(paymentMethodStore)
	guestStore := guest.New(pool)
	guestH := handlers.NewGuestHandler(guestStore)
	contentH := handlers.NewContentHandler(content.New(pool))
	settingsH := handlers.NewSettingsHandler(settingsStore)
	statsH := handlers.NewStatsHandler(pool)
	donationCodesH := handlers.NewDonationCodesHandler(codesStore)
	listingsH := handlers.NewListingsHandler(listingsStore)
	usersAdminH := handlers.NewUsersAdminHandler(userStore)
	supportH := handlers.NewSupportHandler(supportStore, notifier)
	inkindH := handlers.NewInKindHandler(inkindStore, notifier)
	marriageH := handlers.NewMarriageHandler(marriageStore, notifier, walletStore)
	marriageChatH := handlers.NewMarriageChatHandler(marriageChatStore, notifier, pool)
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
		api.POST("/auth/login/", authH.Login)            // PHP path had trailing slash
		api.POST("/auth/admin/login", authH.AdminLogin)  // username + password (dashboard)
		api.POST("/auth/admin/login/", authH.AdminLogin) // trailing-slash tolerant
		api.POST("/auth/google", authH.GoogleLogin)      // Google OAuth (Phase 9 · B-09)
		api.POST("/auth/google/", authH.GoogleLogin)     // trailing-slash tolerant
		api.POST("/auth/otp/request", authH.OTPRequest)
		api.POST("/auth/otp/request/", authH.OTPRequest)
		api.POST("/auth/otp/verify", authH.OTPVerify)
		api.POST("/auth/otp/verify/", authH.OTPVerify)
		// Note #40 — real (username + password) guest accounts.
		api.POST("/auth/guest/register", authH.GuestRegister)
		api.POST("/auth/guest/login", authH.GuestLogin)

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
		// Section 27 — Guest Mode: which screens a signed-out guest may browse.
		// Public (no auth) so the app can read it before login.
		api.GET("/guest/config", guestH.PublicConfig)
		api.GET("/guest/config/", guestH.PublicConfig)
		// #9 — public content pages (Terms & Conditions, etc.) so the app can
		// render them before/without login.
		api.GET("/content/:slug", contentH.PublicContent)
		// #10 — public aggregate impact numbers for the home stats slider
		// (grantors/eligibles/volunteers/completed works/total given). No auth.
		api.GET("/stats/impact", statsH.ImpactStats)
		// #17 — public project categories for the beneficiary submit-project dropdown.
		api.GET("/project-categories", projectCategoriesH.PublicList)
		api.GET("/city-sectors", citySectorsH.PublicList)            // #29 — City Guide filter chips
		api.GET("/search", searchH.Search)                           // #33 — global search
		api.GET("/registration/field-rules", fieldRulesH.PublicList) // #43 — required-field rules
		// #36 — support WhatsApp handoff number. The admin-editable DB value
		// (app_settings) wins; the SUPPORT_WHATSAPP env var is the fallback
		// default. Empty = handoff disabled.
		api.GET("/support/whatsapp", func(c *gin.Context) {
			number := cfg.SupportWhatsApp
			if v, err := settingsStore.Get(c.Request.Context(), appsettings.KeySupportWhatsApp); err == nil && v != "" {
				number = v
			}
			c.JSON(http.StatusOK, gin.H{"success": true, "number": number, "enabled": number != ""})
		})
		api.GET("/media-categories", mediaCategoriesH.PublicList)             // #22
		api.GET("/marketplace/categories", marketplaceCategoriesH.PublicList) // #28
		// #19 — public payment methods for the donate screen.
		api.GET("/payment-methods", paymentMethodsH.PublicList)

		api.GET("/campaigns", campaignsH.List)
		api.GET("/campaigns/", campaignsH.List)

		// Public read-only listings (Flutter + public web).
		api.GET("/partners", listingsH.Partners)
		api.GET("/partners/", listingsH.Partners)
		api.GET("/media", listingsH.Media)
		api.GET("/media/", listingsH.Media)
		// Note #40 — City Directory is restricted for guests even though this
		// route stays public for everyone else: OptionalBearer resolves a
		// token if present (without requiring one), BlockGuestOptional then
		// rejects only a resolved GUEST caller.
		api.GET("/community", auth.OptionalBearer(tokenStore), auth.BlockGuestOptional(), listingsH.Community)
		api.GET("/community/", auth.OptionalBearer(tokenStore), auth.BlockGuestOptional(), listingsH.Community)
		api.GET("/marriage", marriageH.Get)
		api.GET("/marriage/", marriageH.Get)
		// Client note — Marriage "Subscription": public package list.
		api.GET("/marriage/subscription-packages", marriageH.GetSubscriptionPackages)
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
			// Note #40 — Account Upgrade and Conversion. The phone's OTP is
			// sent via the existing public POST /auth/otp/request; this
			// endpoint only consumes that code and attaches the phone to
			// the CURRENT guest's own row.
			authed.POST("/auth/guest/upgrade/verify", auth.RequireGuest(), authH.GuestUpgradeVerify)

			// Profile + role
			authed.GET("/profile/get", profileH.Get)
			authed.GET("/profile/get/", profileH.Get)
			authed.POST("/profile/set", profileH.Set)
			authed.POST("/profile/set/", profileH.Set)
			// #31 — per-user notification switch.
			authed.GET("/profile/notifications", profileH.GetNotificationSetting)
			authed.POST("/profile/notifications", profileH.SetNotificationSetting)
			// #32 — per-user profile field privacy (which fields are hidden).
			authed.GET("/profile/privacy", profileH.GetFieldPrivacy)
			authed.POST("/profile/privacy", profileH.SetFieldPrivacy)
			authed.POST("/choose_role", chooseRoleH.Post)
			authed.POST("/choose_role/", chooseRoleH.Post)

			// #24 — media post engagement (like toggle / comment / share).
			authed.POST("/media/:id/like", mediaEngageH.Like)
			authed.GET("/media/:id/comments", mediaEngageH.Comments)
			authed.POST("/media/:id/comments", mediaEngageH.Comment)
			authed.POST("/media/:id/share", mediaEngageH.Share)

			// #27 — rate a partner (1–5 stars).
			authed.POST("/partners/:id/rate", partnerEngageH.Rate)

			// #30 — suggest a City Guide place (enters the admin queue as pending).
			authed.POST("/community/submit", auth.RequireNotGuest(), listingsH.SubmitCommunity)

			// Donations
			authed.POST("/donate", auth.RequireNotGuest(), donationsH.Create)
			authed.POST("/donate/", auth.RequireNotGuest(), donationsH.Create)
			authed.POST("/donate/my_donations", donationsH.My)
			authed.POST("/donate/my_donations/", donationsH.My)
			authed.GET("/donate/my_donations", donationsH.My)
			authed.GET("/donate/my_donations/", donationsH.My)
			// Phase 23 — donor self-cancel for still-registered donations.
			authed.POST("/donate/:id/cancel", donationsH.Cancel)

			// Note #42 — test-phase internal app wallet. Read-only for the
			// user themselves; crediting is admin-only (see the admin group
			// below).
			authed.GET("/wallet", walletH.GetBalance)
			authed.GET("/wallet/transactions", walletH.ListTransactions)

			// Client note — "Task Verification". Read-only + self-complete for
			// the user themselves; assigning/deleting is admin-only (below).
			authed.GET("/tasks", tasksH.ListMine)
			authed.POST("/tasks/:id/complete", tasksH.Complete)

			// Beneficiary cases — submit (Bearer + role 2)
			authed.POST("/beneficiary_cases", auth.RequireNotGuest(), beneficiaryH.PostCase)
			authed.POST("/beneficiary_cases/", auth.RequireNotGuest(), beneficiaryH.PostCase)

			// Beneficiary project requests
			authed.GET("/beneficiary_project_requests", beneficiaryH.GetRequests)
			authed.GET("/beneficiary_project_requests/", beneficiaryH.GetRequests)
			authed.POST("/beneficiary_project_requests", auth.RequireNotGuest(), beneficiaryH.PostRequest)
			authed.POST("/beneficiary_project_requests/", auth.RequireNotGuest(), beneficiaryH.PostRequest)

			// Marketplace — POST (create order)
			authed.POST("/marketplace", auth.RequireNotGuest(), marketplaceH.Post)
			authed.POST("/marketplace/", auth.RequireNotGuest(), marketplaceH.Post)

			// Beneficiary — view donations made to their own campaigns.
			authed.GET("/beneficiary/campaign-donations", donationsH.BeneficiaryCampaignDonations)
			authed.GET("/beneficiary/campaign-donations/", donationsH.BeneficiaryCampaignDonations)

			// Donor ↔ campaign-owner chat (Phase 28).
			authed.POST("/chats/request", auth.RequireNotGuest(), chatH.Request)
			authed.POST("/chats/support", auth.RequireNotGuest(), chatH.SupportThread) // #45 — direct chat with support/tech
			authed.GET("/chats", chatH.List)
			authed.GET("/chats/", chatH.List)
			authed.POST("/chats/:id/accept", auth.RequireNotGuest(), chatH.Accept)
			authed.POST("/chats/:id/decline", auth.RequireNotGuest(), chatH.Decline)
			authed.GET("/chats/:id/messages", chatH.Messages)
			authed.POST("/chats/:id/messages", auth.RequireNotGuest(), chatH.PostMessage)

			// AI Support Assistant (Phase 29).
			authed.POST("/assistant/chat", auth.RequireNotGuest(), assistantH.Chat)
			authed.POST("/assistant/chat/", auth.RequireNotGuest(), assistantH.Chat)

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
			authed.POST("/in_kind_donations", auth.RequireNotGuest(), inkindH.Post)
			authed.POST("/in_kind_donations/", auth.RequireNotGuest(), inkindH.Post)

			authed.POST("/marriage", auth.RequireNotGuest(), marriageH.Post)
			// #50 — the current user's digital aid-delivery receipts.
			authed.GET("/aid-receipts", aidReceiptsH.MyList)
			// #46 — marriage search: save + request-meeting.
			authed.GET("/marriage/saved", marriageH.SavedList)
			// Note #18 — the current user's own submitted profile(s) + status,
			// so the app can show "pending review" instead of nothing.
			authed.GET("/marriage/mine", marriageH.MyProfiles)
			authed.POST("/marriage/:id/save", marriageH.ToggleSave)
			authed.POST("/marriage/:id/request-meeting", auth.RequireNotGuest(), marriageH.RequestMeeting)
			authed.POST("/marriage/subscription-packages/:id/purchase", auth.RequireNotGuest(), marriageH.PurchaseSubscription)
			authed.POST("/marriage/", auth.RequireNotGuest(), marriageH.Post)

			// Note #35 — staff-mediated marriage chat (identity-masked).
			authed.GET("/marriage/chats", marriageChatH.List)
			authed.GET("/marriage/chats/", marriageChatH.List)
			authed.POST("/marriage/chats/:id/accept", auth.RequireNotGuest(), marriageChatH.Accept)
			authed.POST("/marriage/chats/:id/decline", auth.RequireNotGuest(), marriageChatH.Decline)
			authed.GET("/marriage/chats/:id/messages", marriageChatH.Messages)
			authed.POST("/marriage/chats/:id/messages", auth.RequireNotGuest(), marriageChatH.PostMessage)

			// Note #36 — Staff↔Volunteer↔Beneficiary chat (volunteer/beneficiary side).
			authed.GET("/case-chats", caseVolChatH.List)
			authed.GET("/case-chats/:id/messages", caseVolChatH.Messages)
			authed.POST("/case-chats/:id/messages", caseVolChatH.PostMessage)

			authed.GET("/sponsorships", sponsorshipsH.Get)
			authed.GET("/sponsorships/", sponsorshipsH.Get)
			authed.POST("/sponsorships", auth.RequireNotGuest(), sponsorshipsH.Post)
			authed.POST("/sponsorships/", auth.RequireNotGuest(), sponsorshipsH.Post)

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

			// Note #37 — volunteer self check-in/check-out (GPS + live photo
			// proof). Reuses the admin upload endpoint's exact handler (no admin
			// gate here — any approved app user may upload a photo for their own
			// check-in/out; ownership of the signup itself is still enforced in
			// the handlers below).
			authed.POST("/uploads", adminUploadH.Upload)
			authed.POST("/volunteer_mission_signups/:id/check-in", volunteerCheckinH.CheckIn)
			authed.POST("/volunteer_mission_signups/:id/check-out", volunteerCheckinH.CheckOut)

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
			// 24-a — per-route permission enforcement. Every admin resource
			// route below is gated by the (module, action) matrix via
			// permissions.Store: GET=view, create=add, PATCH/status=edit,
			// DELETE=delete. super_admin & admin pass by default; supervisor/
			// employee are limited per the matrix + any Super-Admin override.
			// Routes already pinned to RequireSuperAdmin / RequireAdminTier keep
			// those (stricter) gates; a few pure-utility endpoints (own-password
			// step-up, upload, generic detail, professions read) stay ungated
			// beyond RequireAdmin.
			perm := func(module, action string) gin.HandlerFunc {
				return auth.RequirePermission(permStore, module, action)
			}

			// Admin-only lists that previously lived on the public API but
			// expose cross-user data — moved here under /admin/*.
			admin.GET("/admin/users", perm("users", "view"), usersAdminH.List)
			admin.GET("/admin/users/", perm("users", "view"), usersAdminH.List)
			admin.GET("/admin/donations", perm("donations", "view"), donationsH.AdminList)
			// #14 — per-section transaction-code namespaces (list + edit prefix).
			admin.GET("/admin/donation-codes", perm("donations", "view"), donationCodesH.List)
			admin.PUT("/admin/donation-codes/:kind", perm("donations", "edit"), donationCodesH.UpdatePrefix)
			admin.GET("/admin/donations/", perm("donations", "view"), donationsH.AdminList)

			// New-user registration approval queue.
			admin.GET("/admin/registrations", perm("registrations", "view"), registrationAdminH.List)
			admin.GET("/admin/registrations/", perm("registrations", "view"), registrationAdminH.List)
			admin.POST("/admin/registrations/:id/approve", perm("registrations", "edit"), registrationAdminH.Approve)
			admin.POST("/admin/registrations/:id/reject", perm("registrations", "edit"), registrationAdminH.Reject)

			// Phase 16 — sidebar live notifications. Polled every 5s by the
			// SPA. Returns pending-action counts across all moderated tables
			// in a single query.
			pendingH := handlers.NewPendingCountsHandler(pool)
			admin.GET("/admin/pending-counts", perm("dashboard", "view"), pendingH.Counts)
			admin.GET("/admin/pending-counts/", perm("dashboard", "view"), pendingH.Counts)

			// Live activity feed / Notification Center for the admin dashboard.
			admin.GET("/admin/events", perm("dashboard", "view"), eventsH.AdminList)
			admin.GET("/admin/events/", perm("dashboard", "view"), eventsH.AdminList)
			// Purging a notification is restricted to the Primary Administrator.
			admin.DELETE("/admin/events/:id", auth.RequireSuperAdmin(), eventsH.AdminDelete)

			// Cross-user paginated lists.
			admin.GET("/admin/beneficiary_cases", perm("beneficiary", "view"), beneficiaryH.AdminCases)
			admin.GET("/admin/beneficiary_cases/", perm("beneficiary", "view"), beneficiaryH.AdminCases)
			admin.GET("/admin/beneficiary_project_requests", perm("beneficiary", "view"), beneficiaryH.AdminRequests)
			admin.GET("/admin/beneficiary_project_requests/", perm("beneficiary", "view"), beneficiaryH.AdminRequests)
			admin.GET("/admin/marketplace/products", perm("marketplace", "view"), marketplaceH.AdminProducts)
			admin.GET("/admin/marketplace/products/", perm("marketplace", "view"), marketplaceH.AdminProducts)
			admin.GET("/admin/marketplace/orders", perm("marketplace", "view"), marketplaceH.AdminOrders)
			admin.GET("/admin/marketplace/orders/", perm("marketplace", "view"), marketplaceH.AdminOrders)
			admin.GET("/admin/notifications", perm("notifications", "view"), adminListsH.Notifications)
			admin.GET("/admin/notifications/", perm("notifications", "view"), adminListsH.Notifications)
			admin.GET("/admin/in_kind_donations", perm("in_kind", "view"), adminListsH.InKindDonations)
			admin.GET("/admin/in_kind_donations/", perm("in_kind", "view"), adminListsH.InKindDonations)
			admin.GET("/admin/support_tickets", perm("support", "view"), adminListsH.SupportTickets)
			admin.GET("/admin/support_tickets/", perm("support", "view"), adminListsH.SupportTickets)
			admin.GET("/admin/volunteer_applications", perm("volunteers", "view"), adminListsH.VolunteerApplications)
			admin.GET("/admin/volunteer_applications/", perm("volunteers", "view"), adminListsH.VolunteerApplications)
			// Phase 21 — moderation of mission signups (the join requests
			// volunteers send for specific missions). Has its own status
			// transitions (approved/joined/completed/no_show etc.) plus
			// timestamp side-effects on checked_in_at + completed_at.
			admin.GET("/admin/volunteer_mission_signups", perm("volunteers", "view"), adminListsH.VolunteerMissionSignups)
			admin.GET("/admin/volunteer_mission_signups/", perm("volunteers", "view"), adminListsH.VolunteerMissionSignups)
			admin.POST("/admin/volunteer_mission_signups/:id/status", perm("volunteers", "edit"), adminStatusH.MissionSignup)
			admin.POST("/admin/volunteer_mission_signups/:id/assign-case", perm("volunteers", "edit"), adminStatusH.AssignSignupCase)

			// Phase 24 — per-mission Kanban "Volunteer board" view.
			// Groups signups into 4 lanes (pending/approved/on_mission/
			// completed-30d) per mission for the admin overview screen.
			admin.GET("/admin/volunteer_board", perm("volunteers", "view"), adminListsH.VolunteerBoard)
			admin.GET("/admin/volunteer_board/", perm("volunteers", "view"), adminListsH.VolunteerBoard)

			// Phase 23 — admin action to publish an approved beneficiary
			// project request to the donor-facing campaigns list.
			admin.POST("/admin/beneficiary_project_requests/:id/publish", perm("beneficiary", "edit"), adminStatusH.PublishProjectRequest)

			// Phase 22 — mission CRUD. Creating a mission with status='open'
			// (or transitioning a draft to open) broadcasts NewVolunteerMissionMsg
			// to all volunteers (role_id=3) in 4 languages.
			admin.GET("/admin/missions", perm("missions", "view"), adminListsH.VolunteerMissions)
			admin.GET("/admin/missions/", perm("missions", "view"), adminListsH.VolunteerMissions)
			admin.POST("/admin/missions", perm("missions", "add"), adminCreateH.Mission)
			admin.POST("/admin/missions/", perm("missions", "add"), adminCreateH.Mission)
			admin.PATCH("/admin/missions/:id", perm("missions", "edit"), adminEditH.Mission)
			admin.POST("/admin/missions/:id/status", perm("missions", "edit"), adminStatusH.Mission)
			admin.DELETE("/admin/missions/:id", perm("missions", "delete"), adminDeleteH.VolunteerMission)
			admin.GET("/admin/audit_logs", perm("audit", "view"), adminListsH.AuditLogs)
			admin.GET("/admin/audit_logs/", perm("audit", "view"), adminListsH.AuditLogs)

			// Push composition + KPIs.
			admin.GET("/admin/push/status", perm("push", "view"), pushH.Status)
			admin.POST("/admin/push/send", perm("push", "add"), pushH.Send)
			// In-app broadcast to every user (works without FCM).
			admin.POST("/admin/notifications/broadcast", perm("notifications", "add"), pushH.BroadcastInApp)
			admin.POST("/admin/notifications/broadcast/", perm("notifications", "add"), pushH.BroadcastInApp)

			// Donor ↔ owner chat — admin (support) oversight.
			admin.GET("/admin/chats", perm("messages", "view"), chatH.AdminList)
			admin.GET("/admin/chats/", perm("messages", "view"), chatH.AdminList)
			admin.GET("/admin/chats/:id/messages", perm("messages", "view"), chatH.AdminMessages)
			admin.POST("/admin/chats/:id/messages", perm("messages", "add"), chatH.AdminPostMessage)
			// Note #36 — claim/release the "Responsible Staff Member" on a thread.
			admin.POST("/admin/chats/:id/claim", perm("messages", "edit"), chatH.AdminClaim)
			admin.POST("/admin/chats/:id/release", perm("messages", "edit"), chatH.AdminRelease)

			// Note #36 — internal staff-to-staff chat. Not perm()-gated: every
			// dashboard tier (employee and up) can use it regardless of assigned
			// module permissions, same as the `admin` group's base requirement.
			admin.GET("/admin/staff-directory", staffChatH.Directory)
			admin.GET("/admin/staff-chats", staffChatH.List)
			admin.POST("/admin/staff-chats/start", staffChatH.Start)
			admin.GET("/admin/staff-chats/:id/messages", staffChatH.Messages)
			admin.POST("/admin/staff-chats/:id/messages", staffChatH.PostMessage)

			// Note #36 — Staff↔Volunteer↔Beneficiary chat oversight.
			admin.GET("/admin/case-chats", perm("volunteers", "view"), caseVolChatH.AdminList)
			admin.GET("/admin/case-chats/:id/messages", perm("volunteers", "view"), caseVolChatH.AdminMessages)
			admin.POST("/admin/case-chats/:id/messages", perm("volunteers", "add"), caseVolChatH.AdminPostMessage)
			admin.POST("/admin/case-chats/:id/claim", perm("volunteers", "edit"), caseVolChatH.AdminClaim)
			admin.POST("/admin/case-chats/:id/release", perm("volunteers", "edit"), caseVolChatH.AdminRelease)

			// Note #35 — marriage meeting-requests inbox + mediated chat oversight.
			admin.GET("/admin/marriage/meeting-requests", perm("marriage", "view"), marriageChatH.AdminListMeetingRequests)
			admin.POST("/admin/marriage/meeting-requests/:id/approve", perm("marriage", "edit"), marriageChatH.AdminApproveMeetingRequest)
			admin.POST("/admin/marriage/meeting-requests/:id/decline", perm("marriage", "edit"), marriageChatH.AdminDeclineMeetingRequest)
			admin.GET("/admin/marriage/chats", perm("marriage", "view"), marriageChatH.AdminList)
			admin.GET("/admin/marriage/chats/:id/messages", perm("marriage", "view"), marriageChatH.AdminMessages)
			admin.POST("/admin/marriage/chats/:id/messages", perm("marriage", "add"), marriageChatH.AdminPostMessage)
			// Client note — Marriage "Subscription": dynamic package CRUD +
			// pending-purchase confirmation queue.
			admin.GET("/admin/marriage/subscription-packages", perm("marriage", "view"), marriageH.AdminListSubscriptionPackages)
			admin.POST("/admin/marriage/subscription-packages", perm("marriage", "add"), marriageH.AdminAddSubscriptionPackage)
			admin.PATCH("/admin/marriage/subscription-packages/:id", perm("marriage", "edit"), marriageH.AdminUpdateSubscriptionPackage)
			admin.POST("/admin/marriage/subscription-packages/reorder", perm("marriage", "edit"), marriageH.AdminReorderSubscriptionPackages)
			admin.DELETE("/admin/marriage/subscription-packages/:id", perm("marriage", "delete"), marriageH.AdminDeleteSubscriptionPackage)
			admin.GET("/admin/marriage/subscription-purchases", perm("marriage", "view"), marriageH.AdminListSubscriptionPurchases)
			admin.POST("/admin/marriage/subscription-purchases/:id/confirm", perm("marriage", "edit"), marriageH.AdminConfirmSubscriptionPurchase)
			admin.POST("/admin/marriage/subscription-purchases/:id/reject", perm("marriage", "edit"), marriageH.AdminRejectSubscriptionPurchase)
			admin.GET("/admin/dashboard_kpis", perm("dashboard", "view"), kpisH.Get)
			admin.GET("/admin/dashboard_kpis/", perm("dashboard", "view"), kpisH.Get)

			// Phase 9: status-change mutations. Each endpoint validates the
			// new status against the resource's allowed-values list.
			admin.POST("/admin/beneficiary_cases/:id/status", perm("beneficiary", "edit"), adminStatusH.BeneficiaryCase)
			admin.POST("/admin/beneficiary_project_requests/:id/status", perm("beneficiary", "edit"), adminStatusH.ProjectRequest)
			admin.POST("/admin/marketplace/products/:id/status", perm("marketplace", "edit"), adminStatusH.MarketplaceProduct)
			admin.POST("/admin/marketplace/orders/:id/status", perm("marketplace", "edit"), adminStatusH.MarketplaceOrder)
			admin.POST("/admin/marriage/:id/status", perm("marriage", "edit"), adminStatusH.Marriage)
			admin.POST("/admin/partners/:id/status", perm("partners", "edit"), adminStatusH.Partner)
			admin.POST("/admin/media/:id/status", perm("media", "edit"), adminStatusH.Media)
			admin.GET("/admin/community", listingsH.CommunityAdmin) // #30 — queue incl. pending
			admin.POST("/admin/community/:id/status", perm("community", "edit"), adminStatusH.Community)
			admin.POST("/admin/volunteer_applications/:id/status", perm("volunteers", "edit"), adminStatusH.VolunteerApplication)
			admin.POST("/admin/sponsorships/:id/status", perm("sponsorships", "edit"), adminStatusH.Sponsorship)
			admin.POST("/admin/in_kind_donations/:id/status", perm("in_kind", "edit"), adminStatusH.InKindDonation)
			admin.POST("/admin/support_tickets/:id/status", perm("support", "edit"), adminStatusH.SupportTicket)
			admin.POST("/admin/donations/:id/status", perm("donations", "edit"), adminStatusH.Donation)
			admin.POST("/admin/users/:id/role", perm("users", "edit"), adminStatusH.UserRole)
			admin.POST("/admin/users/:id/active", perm("users", "edit"), adminStatusH.UserActive)
			admin.POST("/admin/users/:id/admin", perm("users", "edit"), adminStatusH.UserAdmin)
			admin.POST("/admin/users/:id/password", perm("users", "edit"), adminStatusH.UserPassword)
			admin.POST("/admin/users/:id/staff_tier", perm("users", "edit"), adminStatusH.UserStaffTier) // Users #c
			// Note #42 — test-phase wallet top-up (admin credits a user's balance).
			admin.POST("/admin/users/:id/wallet/topup", perm("users", "edit"), walletH.AdminTopUp)
			// Client note — "Task Verification": staff assign tasks to users.
			admin.GET("/admin/tasks", perm("tasks", "view"), tasksH.AdminList)
			admin.POST("/admin/tasks", perm("tasks", "add"), tasksH.AdminCreate)
			admin.DELETE("/admin/tasks/:id", perm("tasks", "delete"), tasksH.AdminDelete)
			// Section 25 — immediate administrative actions (super-admin only).
			admin.POST("/admin/users/:id/force_logout", auth.RequireSuperAdmin(), adminStatusH.UserForceLogout)
			admin.POST("/admin/users/:id/account_status", auth.RequireSuperAdmin(), adminStatusH.UserAccountStatus)
			// Note #4 — Archive is deliberately NOT super-admin-only: it's the
			// non-destructive alternative to Delete that lower tiers can be
			// granted via the Permissions page.
			admin.POST("/admin/users/:id/archive", perm("users", "archive"), adminStatusH.UserArchive)
			admin.POST("/admin/users", perm("users", "add"), adminStatusH.CreateUser) // Users #g (New User)
			// Step-up PIN confirm (own password) for sensitive actions — Phase 7.
			admin.POST("/admin/verify-password", adminStatusH.VerifyPassword)

			// Trash container (Phase 7 · G-06 / A-16). Deletes land here; restore
			// and purge are admin-level (purge additionally re-verifies the PIN).
			admin.GET("/admin/trash", perm("trash", "view"), adminTrashH.List)
			admin.POST("/admin/trash/:id/restore", auth.RequireAdminTier(), adminTrashH.Restore)
			// Permanent deletion is restricted to the Primary Administrator
			// (super_admin) ONLY (Section 25) — still PIN-gated in the handler.
			admin.POST("/admin/trash/:id/purge", auth.RequireSuperAdmin(), adminTrashH.Purge)

			// Phase 10: partial-update (edit modal) endpoints.
			admin.PATCH("/admin/partners/:id", perm("partners", "edit"), adminEditH.Partner)
			admin.PATCH("/admin/media/:id", perm("media", "edit"), adminEditH.Media)
			admin.PATCH("/admin/community/:id", perm("community", "edit"), adminEditH.Community)
			admin.PATCH("/admin/marriage/:id", perm("marriage", "edit"), adminEditH.Marriage)
			admin.PATCH("/admin/marketplace/products/:id", perm("marketplace", "edit"), adminEditH.MarketplaceProduct)
			admin.PATCH("/admin/marketplace/orders/:id", perm("marketplace", "edit"), adminEditH.MarketplaceOrder)
			admin.PATCH("/admin/beneficiary_cases/:id", perm("beneficiary", "edit"), adminEditH.BeneficiaryCase)
			admin.PATCH("/admin/beneficiary_project_requests/:id", perm("beneficiary", "edit"), adminEditH.ProjectRequest)
			admin.PATCH("/admin/sponsorships/:id", perm("sponsorships", "edit"), adminEditH.Sponsorship)
			admin.PATCH("/admin/in_kind_donations/:id", perm("in_kind", "edit"), adminEditH.InKindDonation)
			admin.PATCH("/admin/support_tickets/:id", perm("support", "edit"), adminEditH.SupportTicket)
			admin.PATCH("/admin/donations/:id", perm("donations", "edit"), adminEditH.Donation)
			admin.PATCH("/admin/volunteer_applications/:id", perm("volunteers", "edit"), adminEditH.VolunteerApplication)
			admin.PATCH("/admin/users/:id", perm("users", "edit"), adminEditH.User)

			// Phase 11: create (admin) endpoints.
			admin.POST("/admin/partners", perm("partners", "add"), adminCreateH.Partner)
			admin.POST("/admin/media", perm("media", "add"), adminCreateH.Media)
			admin.POST("/admin/community", perm("community", "add"), adminCreateH.Community)
			admin.POST("/admin/marriage", perm("marriage", "add"), adminCreateH.MarriageProfile)
			admin.POST("/admin/marketplace/products", perm("marketplace", "add"), adminCreateH.MarketplaceProduct)
			admin.POST("/admin/beneficiary_cases", perm("beneficiary", "add"), adminCreateH.BeneficiaryCase)
			admin.POST("/admin/beneficiary_project_requests", perm("beneficiary", "add"), adminCreateH.ProjectRequest)
			admin.POST("/admin/sponsorships", perm("sponsorships", "add"), adminCreateH.Sponsorship)
			admin.POST("/admin/in_kind_donations", perm("in_kind", "add"), adminCreateH.InKindDonation)
			admin.POST("/admin/support_tickets", perm("support", "add"), adminCreateH.SupportTicket)
			admin.POST("/admin/donations", perm("donations", "add"), adminCreateH.Donation)
			admin.POST("/admin/volunteer_applications", perm("volunteers", "add"), adminCreateH.VolunteerApplication)

			// Phase 13: hard-delete endpoints.
			admin.DELETE("/admin/partners/:id", perm("partners", "delete"), adminDeleteH.Partner)
			admin.DELETE("/admin/media/:id", perm("media", "delete"), adminDeleteH.Media)
			admin.DELETE("/admin/community/:id", perm("community", "delete"), adminDeleteH.Community)
			admin.DELETE("/admin/marriage/:id", perm("marriage", "delete"), adminDeleteH.Marriage)
			admin.DELETE("/admin/marketplace/products/:id", perm("marketplace", "delete"), adminDeleteH.MarketplaceProduct)
			admin.DELETE("/admin/marketplace/orders/:id", perm("marketplace", "delete"), adminDeleteH.MarketplaceOrder)
			admin.DELETE("/admin/beneficiary_cases/:id", perm("beneficiary", "delete"), adminDeleteH.BeneficiaryCase)
			admin.DELETE("/admin/beneficiary_project_requests/:id", perm("beneficiary", "delete"), adminDeleteH.ProjectRequest)
			admin.DELETE("/admin/sponsorships/:id", perm("sponsorships", "delete"), adminDeleteH.Sponsorship)
			admin.DELETE("/admin/in_kind_donations/:id", perm("in_kind", "delete"), adminDeleteH.InKindDonation)
			admin.DELETE("/admin/support_tickets/:id", perm("support", "delete"), adminDeleteH.SupportTicket)
			admin.DELETE("/admin/donations/:id", perm("donations", "delete"), adminDeleteH.Donation)
			admin.DELETE("/admin/volunteer_applications/:id", perm("volunteers", "delete"), adminDeleteH.VolunteerApplication)
			// Note #4 — deleting a user account is hard-restricted to the
			// Primary Administrator (Super Admin), not the overridable
			// per-tier permission every other table's delete uses. The
			// client asked for this specifically because employees/
			// supervisors previously saw a live Delete button with no
			// backend enforcement stopping them if the permission happened
			// to be granted. Archive (above) is the reversible action lower
			// tiers get instead.
			admin.DELETE("/admin/users/:id", auth.RequireSuperAdmin(), adminDeleteH.User)

			// Phase 14: campaigns CRUD (admin view of the real `campaigns` table).
			admin.GET("/admin/campaigns", perm("campaigns", "view"), adminListsH.Campaigns)
			admin.GET("/admin/campaigns/", perm("campaigns", "view"), adminListsH.Campaigns)
			admin.POST("/admin/campaigns", perm("campaigns", "add"), adminCreateH.Campaign)
			admin.PATCH("/admin/campaigns/:id", perm("campaigns", "edit"), adminEditH.Campaign)
			admin.DELETE("/admin/campaigns/:id", perm("campaigns", "delete"), adminDeleteH.Campaign)

			// Phase 15: file uploads. Multipart POST returns a path that the
			// SPA stores in the relevant column (logo_path, image_path, etc.).
			admin.POST("/admin/upload", adminUploadH.Upload)

			// Phase 16: generic detail endpoint. Reads one row from any
			// allowlisted admin resource using SELECT *.
			admin.GET("/admin/detail/:resource/:id", adminDetailH.Detail)

			// Full-DB JSON export (admin backup tool) — restricted to the
			// Primary Administrator (super_admin) ONLY (Phase 7 · M-60).
			// POST (Note #27) so the PIN confirmation travels in the body,
			// never in a URL/query string.
			admin.POST("/admin/export/all", auth.RequireSuperAdmin(), adminExportH.ExportAll)

			// Section 24 — Permissions Management. The matrix + audit are
			// super-admin only; /me is any authenticated staff (used to hide
			// unauthorized menu entries in the SPA).
			admin.GET("/admin/permissions", auth.RequireSuperAdmin(), adminPermsH.Matrix)
			admin.POST("/admin/permissions", auth.RequireSuperAdmin(), adminPermsH.SetPermission)
			// Section 24 — phone OTP second factor for permission changes.
			admin.POST("/admin/permissions/otp", auth.RequireSuperAdmin(), adminPermsH.RequestOTP)
			admin.GET("/admin/permissions/audit", auth.RequireSuperAdmin(), adminPermsH.Audit)
			// Requirement 6c — verify the audit ledger's hash chain is intact.
			admin.GET("/admin/permissions/audit/verify", auth.RequireSuperAdmin(), adminPermsH.VerifyAudit)
			admin.GET("/admin/permissions/me", adminPermsH.Effective)
			// Note 31 — per-employee overrides (narrower than a tier-wide
			// change, but just as sensitive — same super-admin gate + OTP).
			admin.GET("/admin/permissions/user/:id", auth.RequireSuperAdmin(), adminPermsH.UserMatrix)
			admin.POST("/admin/permissions/user/:id", auth.RequireSuperAdmin(), adminPermsH.SetUserPermission)

			// Section 13 — admin-added volunteer professions. Any staff can
			// read (to populate the skill dropdown); admin-level staff add.
			admin.GET("/admin/professions", adminProfessionsH.List)
			admin.POST("/admin/professions", auth.RequireAdminTier(), adminProfessionsH.Add)
			admin.PATCH("/admin/professions/:id", auth.RequireAdminTier(), adminProfessionsH.Update)
			admin.POST("/admin/professions/reorder", auth.RequireAdminTier(), adminProfessionsH.Reorder)
			admin.DELETE("/admin/professions/:id", auth.RequireAdminTier(), adminProfessionsH.Delete)
			// #17 — project-category CMS (admin-managed, 4-language, ordered).
			admin.GET("/admin/project-categories", projectCategoriesH.AdminList)
			admin.POST("/admin/project-categories", auth.RequireAdminTier(), projectCategoriesH.Add)
			admin.PATCH("/admin/project-categories/:id", auth.RequireAdminTier(), projectCategoriesH.Update)
			admin.POST("/admin/project-categories/reorder", auth.RequireAdminTier(), projectCategoriesH.Reorder)
			admin.DELETE("/admin/project-categories/:id", auth.RequireAdminTier(), projectCategoriesH.Delete)
			// #29 — City Guide sector CMS (admin-managed, 4-language, ordered).
			// #50 — digital aid-delivery receipts.
			admin.GET("/admin/aid-receipts", aidReceiptsH.AdminList)
			admin.POST("/admin/aid-receipts", auth.RequireAdminTier(), aidReceiptsH.AdminCreate)
			// #43 — registration field rules (required vs optional).
			admin.GET("/admin/registration/field-rules", fieldRulesH.AdminList)
			admin.POST("/admin/registration/field-rules/:key", auth.RequireAdminTier(), fieldRulesH.SetState)
			admin.POST("/admin/registration/field-rules/:key/searchable", auth.RequireAdminTier(), fieldRulesH.SetSearchable)
			admin.GET("/admin/city-sectors", citySectorsH.AdminList)
			admin.POST("/admin/city-sectors", auth.RequireAdminTier(), citySectorsH.Add)
			admin.PATCH("/admin/city-sectors/:id", auth.RequireAdminTier(), citySectorsH.Update)
			admin.POST("/admin/city-sectors/reorder", auth.RequireAdminTier(), citySectorsH.Reorder)
			admin.DELETE("/admin/city-sectors/:id", auth.RequireAdminTier(), citySectorsH.Delete)
			// #19 — payment-method CMS (admin-managed, 4-language, ordered).
			// #22 — "Our Work" media categories (writes gated to admin tier).
			admin.GET("/admin/media-categories", mediaCategoriesH.AdminList)
			admin.POST("/admin/media-categories", auth.RequireAdminTier(), mediaCategoriesH.Add)
			admin.PATCH("/admin/media-categories/:id", auth.RequireAdminTier(), mediaCategoriesH.Update)
			admin.POST("/admin/media-categories/reorder", auth.RequireAdminTier(), mediaCategoriesH.Reorder)
			admin.DELETE("/admin/media-categories/:id", auth.RequireAdminTier(), mediaCategoriesH.Delete)

			// #28 — marketplace categories (gated to the marketplace module).
			admin.GET("/admin/marketplace/categories", perm("marketplace", "view"), marketplaceCategoriesH.AdminList)
			admin.POST("/admin/marketplace/categories", perm("marketplace", "add"), marketplaceCategoriesH.Add)
			admin.PATCH("/admin/marketplace/categories/:id", perm("marketplace", "edit"), marketplaceCategoriesH.Update)
			admin.POST("/admin/marketplace/categories/reorder", perm("marketplace", "edit"), marketplaceCategoriesH.Reorder)
			admin.DELETE("/admin/marketplace/categories/:id", perm("marketplace", "delete"), marketplaceCategoriesH.Delete)

			// #25 — comment moderation queue + status change + delete.
			admin.GET("/admin/media-comments", perm("media", "view"), mediaEngageH.AdminComments)
			admin.POST("/admin/media-comments/:id/status", perm("media", "edit"), adminStatusH.MediaComment)
			admin.DELETE("/admin/media-comments/:id", perm("media", "delete"), mediaEngageH.AdminDeleteComment)

			// #25 — banned-words blocklist (writes gated to admin tier).
			admin.GET("/admin/banned-words", perm("media", "view"), bannedWordsH.List)
			admin.POST("/admin/banned-words", auth.RequireAdminTier(), bannedWordsH.Add)
			admin.DELETE("/admin/banned-words/:id", auth.RequireAdminTier(), bannedWordsH.Delete)

			admin.GET("/admin/payment-methods", paymentMethodsH.AdminList)
			admin.POST("/admin/payment-methods", auth.RequireAdminTier(), paymentMethodsH.Add)
			admin.PATCH("/admin/payment-methods/:id", auth.RequireAdminTier(), paymentMethodsH.Update)
			admin.POST("/admin/payment-methods/reorder", auth.RequireAdminTier(), paymentMethodsH.Reorder)
			admin.DELETE("/admin/payment-methods/:id", auth.RequireAdminTier(), paymentMethodsH.Delete)

			// Section 27 — Guest Mode config. Super-Admin only.
			admin.GET("/admin/guest_settings", auth.RequireSuperAdmin(), guestH.AdminList)
			admin.POST("/admin/guest_settings", auth.RequireSuperAdmin(), guestH.Set)

			// #36 — admin-editable support WhatsApp handoff number (admin tier,
			// like the other CMS settings such as payment methods).
			admin.GET("/admin/settings/support-whatsapp", settingsH.GetSupportWhatsApp)
			admin.PUT("/admin/settings/support-whatsapp", auth.RequireAdminTier(), settingsH.SetSupportWhatsApp)

			admin.GET("/admin/settings/support-user-id", settingsH.GetSupportUserID)
			admin.PUT("/admin/settings/support-user-id", auth.RequireAdminTier(), settingsH.SetSupportUserID)
			// FIB account number — a convenience alias over the FIB payment method
			// (shown on the donate screen), editable from the same settings card.
			admin.GET("/admin/settings/fib-number", settingsH.GetFibNumber)
			admin.PUT("/admin/settings/fib-number", auth.RequireAdminTier(), settingsH.SetFibNumber)

			admin.GET("/admin/settings/assistant", settingsH.GetAssistantSettings)
			admin.PUT("/admin/settings/assistant", auth.RequireAdminTier(), settingsH.SetAssistantSettings)
			admin.GET("/admin/assistant/stats", settingsH.GetAssistantStats)
			// Note #5 — admin dashboard idle-lock duration. GET is open to any
			// authed staff (everyone needs the value to enforce it client-side);
			// only the Main Admin (Super Admin) can change it, per the client's
			// explicit ask — not just "admin tier" like the settings above.
			admin.GET("/admin/settings/session-timeout", settingsH.GetSessionTimeout)
			admin.PUT("/admin/settings/session-timeout", auth.RequireSuperAdmin(), settingsH.SetSessionTimeout)
			// Note #17 — admin-configurable price per Marriage subscription
			// package tier (bronze/silver/gold/diamond/vip). Same tier as the
			// other CMS-style settings above (admin tier, not Super-Admin-only).
			// Client note — Marriage "Subscription": replaced by the dynamic
			// packages CRUD registered below (marriage_subscription.go).
			// Note #29 follow-up — Super-Admin can reorder/regroup the sidebar
			// itself. Open GET (everyone needs it to render their own sidebar);
			// only the Main Admin can change it, same tier as session-timeout.
			admin.GET("/admin/settings/nav-layout", settingsH.GetNavLayout)
			admin.PUT("/admin/settings/nav-layout", auth.RequireSuperAdmin(), settingsH.SetNavLayout)
			// #9 — edit static content pages (Terms & Conditions, etc.).
			admin.PUT("/admin/content/:slug", auth.RequireSuperAdmin(), contentH.AdminUpdateContent)
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
