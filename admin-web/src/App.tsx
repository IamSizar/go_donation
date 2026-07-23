import { lazy, Suspense } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider, RequireAuth } from './lib/auth'
import { GlobalAlertsProvider } from './lib/globalAlerts'
import { PendingCountsProvider } from './lib/pendingCounts'
import { ToastProvider } from './lib/toast'
import { I18nProvider, useI18n } from './lib/i18n'
import LoginPage from './pages/LoginPage'
import AppShell from './components/AppShell'

// Route-level code-splitting (Phase 10 · 10d). Each page becomes its own chunk
// so the initial bundle only ships the login screen + shell; pages load on
// demand. Cuts the >1 MB single-bundle down to small per-route chunks.
const DashboardPage = lazy(() => import('./pages/DashboardPage'))
const UsersPage = lazy(() => import('./pages/UsersPage'))
const RegistrationsPage = lazy(() => import('./pages/RegistrationsPage'))
const DonationsPage = lazy(() => import('./pages/DonationsPage'))
const CampaignsPage = lazy(() => import('./pages/CampaignsPage'))
const SponsorshipsPage = lazy(() => import('./pages/SponsorshipsPage'))
const BeneficiaryPage = lazy(() => import('./pages/BeneficiaryPage'))
const MarketplacePage = lazy(() => import('./pages/MarketplacePage'))
const MarriagePage = lazy(() => import('./pages/MarriagePage'))
const MarriageMeetingRequestsPage = lazy(() => import('./pages/MarriageMeetingRequestsPage'))
const MarriageChatsPage = lazy(() => import('./pages/MarriageChatsPage'))
const PartnersPage = lazy(() => import('./pages/PartnersPage'))
const MediaPage = lazy(() => import('./pages/MediaPage'))
const CommunityPage = lazy(() => import('./pages/CommunityPage'))
const CityGuidePage = lazy(() => import('./pages/CityGuidePage'))
const CitySectorsPage = lazy(() => import('./pages/CitySectorsPage'))
const MessagesPage = lazy(() => import('./pages/MessagesPage'))
const StaffChatPage = lazy(() => import('./pages/StaffChatPage'))
const CaseVolunteerChatsPage = lazy(() => import('./pages/CaseVolunteerChatsPage'))
const VolunteersPage = lazy(() => import('./pages/VolunteersPage'))
const VolunteerBoardPage = lazy(() => import('./pages/VolunteerBoardPage'))
const MissionsPage = lazy(() => import('./pages/MissionsPage'))
const InKindPage = lazy(() => import('./pages/InKindPage'))
const SupportPage = lazy(() => import('./pages/SupportPage'))
const NotificationsPage = lazy(() => import('./pages/NotificationsPage'))
const ReportsPage = lazy(() => import('./pages/ReportsPage'))
const AuditLogsPage = lazy(() => import('./pages/AuditLogsPage'))
const PushNotificationsPage = lazy(() => import('./pages/PushNotificationsPage'))
const TrashPage = lazy(() => import('./pages/TrashPage'))
const PermissionsPage = lazy(() => import('./pages/PermissionsPage'))
const GuestAccessPage = lazy(() => import('./pages/GuestAccessPage'))
const SettingsPage = lazy(() => import('./pages/SettingsPage'))
const TermsPage = lazy(() => import('./pages/TermsPage'))
const AboutPage = lazy(() => import('./pages/AboutPage'))
const HumanitarianWorkPage = lazy(() => import('./pages/HumanitarianWorkPage'))
const FieldRulesPage = lazy(() => import('./pages/FieldRulesPage'))
const ReceiptsPage = lazy(() => import('./pages/ReceiptsPage'))
const ContactPage = lazy(() => import('./pages/ContactPage'))
const DonationCodesPage = lazy(() => import('./pages/DonationCodesPage'))
const ProjectCategoriesPage = lazy(() => import('./pages/ProjectCategoriesPage'))
const MediaCategoriesPage = lazy(() => import('./pages/MediaCategoriesPage'))
const CommentsPage = lazy(() => import('./pages/CommentsPage'))
const BannedWordsPage = lazy(() => import('./pages/BannedWordsPage'))
const MarketplaceCategoriesPage = lazy(() => import('./pages/MarketplaceCategoriesPage'))
const PaymentMethodsPage = lazy(() => import('./pages/PaymentMethodsPage'))
const TasksPage = lazy(() => import('./pages/TasksPage'))
const MarriageSubscriptionsPage = lazy(() => import('./pages/MarriageSubscriptionsPage'))
const DetailPage = lazy(() => import('./pages/DetailPage'))

function PageFallback() {
  const { t } = useI18n()
  return (
    <div
      style={{
        display: 'grid',
        placeItems: 'center',
        minHeight: '60vh',
        color: 'var(--color-muted, #888)',
      }}
    >
      {t('common.loading')}
    </div>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <I18nProvider>
      <AuthProvider>
        <ToastProvider>
        {/* PendingCountsProvider owns ONE 5-second poll timer shared by the
            sidebar (badges), dashboard banners, and anything else that needs
            "what's awaiting admin action right now". Mounted inside Auth so
            the hook can skip polling cleanly when signed out. */}
        <PendingCountsProvider>
        {/* GlobalAlertsProvider owns ONE Firestore subscription that fires
            chimes + toasts + OS notifications on new events from ANY page.
            Must be inside BrowserRouter (uses useNavigate) and AuthProvider
            (skips subscription when signed out). */}
        <GlobalAlertsProvider>
        <Suspense fallback={<PageFallback />}>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route
            path="/"
            element={
              <RequireAuth>
                <AppShell />
              </RequireAuth>
            }
          >
            <Route index element={<DashboardPage />} />
            <Route path="users" element={<UsersPage />} />
            <Route path="registrations" element={<RegistrationsPage />} />
            <Route path="donations" element={<DonationsPage />} />
            <Route path="donation-codes" element={<DonationCodesPage />} />
            <Route path="project-categories" element={<ProjectCategoriesPage />} />
            <Route path="media-categories" element={<MediaCategoriesPage />} />
            <Route path="comments" element={<CommentsPage />} />
            <Route path="banned-words" element={<BannedWordsPage />} />
            <Route path="marketplace-categories" element={<MarketplaceCategoriesPage />} />
            <Route path="payment-methods" element={<PaymentMethodsPage />} />
            <Route path="campaigns" element={<CampaignsPage />} />
            <Route path="sponsorships" element={<SponsorshipsPage />} />
            <Route path="beneficiary" element={<BeneficiaryPage />} />
            <Route path="marketplace" element={<MarketplacePage />} />
            <Route path="marriage" element={<MarriagePage />} />
            <Route path="marriage-requests" element={<MarriageMeetingRequestsPage />} />
            <Route path="marriage-chats" element={<MarriageChatsPage />} />
            <Route path="partners" element={<PartnersPage />} />
            <Route path="media" element={<MediaPage />} />
            <Route path="community" element={<CommunityPage />} />
            <Route path="city-guide" element={<CityGuidePage />} />
            <Route path="city-sectors" element={<CitySectorsPage />} />
            <Route path="messages" element={<MessagesPage />} />
            <Route path="staff-chat" element={<StaffChatPage />} />
            <Route path="case-volunteer-chats" element={<CaseVolunteerChatsPage />} />
            <Route path="volunteers" element={<VolunteersPage />} />
            <Route path="volunteer-board" element={<VolunteerBoardPage />} />
            <Route path="tasks" element={<TasksPage />} />
            <Route path="marriage-subscriptions" element={<MarriageSubscriptionsPage />} />
            <Route path="missions" element={<MissionsPage />} />
            <Route path="in-kind" element={<InKindPage />} />
            <Route path="support" element={<SupportPage />} />
            <Route path="notifications" element={<NotificationsPage />} />
            <Route path="reports" element={<ReportsPage />} />
            <Route path="audit-logs" element={<AuditLogsPage />} />
            <Route path="push" element={<PushNotificationsPage />} />
            <Route path="trash" element={<TrashPage />} />
            <Route path="permissions" element={<PermissionsPage />} />
            <Route path="guest-access" element={<GuestAccessPage />} />
            <Route path="settings" element={<SettingsPage />} />
            <Route path="terms" element={<TermsPage />} />
            <Route path="about" element={<AboutPage />} />
            <Route path="humanitarian-work" element={<HumanitarianWorkPage />} />
            <Route path="field-rules" element={<FieldRulesPage />} />
            <Route path="receipts" element={<ReceiptsPage />} />
            <Route path="contact" element={<ContactPage />} />
            <Route path="detail/:resource/:id" element={<DetailPage />} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
        </Suspense>
        </GlobalAlertsProvider>
        </PendingCountsProvider>
        </ToastProvider>
      </AuthProvider>
      </I18nProvider>
    </BrowserRouter>
  )
}
