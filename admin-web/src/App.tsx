import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider, RequireAuth } from './lib/auth'
import { GlobalAlertsProvider } from './lib/globalAlerts'
import { PendingCountsProvider } from './lib/pendingCounts'
import { ToastProvider } from './lib/toast'
import { I18nProvider } from './lib/i18n'
import LoginPage from './pages/LoginPage'
import AppShell from './components/AppShell'
import DashboardPage from './pages/DashboardPage'
import UsersPage from './pages/UsersPage'
import RegistrationsPage from './pages/RegistrationsPage'
import DonationsPage from './pages/DonationsPage'
import CampaignsPage from './pages/CampaignsPage'
import SponsorshipsPage from './pages/SponsorshipsPage'
import BeneficiaryPage from './pages/BeneficiaryPage'
import MarketplacePage from './pages/MarketplacePage'
import MarriagePage from './pages/MarriagePage'
import PartnersPage from './pages/PartnersPage'
import MediaPage from './pages/MediaPage'
import CommunityPage from './pages/CommunityPage'
import CityGuidePage from './pages/CityGuidePage'
import MessagesPage from './pages/MessagesPage'
import VolunteersPage from './pages/VolunteersPage'
import VolunteerBoardPage from './pages/VolunteerBoardPage'
import MissionsPage from './pages/MissionsPage'
import InKindPage from './pages/InKindPage'
import SupportPage from './pages/SupportPage'
import NotificationsPage from './pages/NotificationsPage'
import ReportsPage from './pages/ReportsPage'
import AuditLogsPage from './pages/AuditLogsPage'
import PushNotificationsPage from './pages/PushNotificationsPage'
import DetailPage from './pages/DetailPage'

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
            <Route path="campaigns" element={<CampaignsPage />} />
            <Route path="sponsorships" element={<SponsorshipsPage />} />
            <Route path="beneficiary" element={<BeneficiaryPage />} />
            <Route path="marketplace" element={<MarketplacePage />} />
            <Route path="marriage" element={<MarriagePage />} />
            <Route path="partners" element={<PartnersPage />} />
            <Route path="media" element={<MediaPage />} />
            <Route path="community" element={<CommunityPage />} />
            <Route path="city-guide" element={<CityGuidePage />} />
            <Route path="messages" element={<MessagesPage />} />
            <Route path="volunteers" element={<VolunteersPage />} />
            <Route path="volunteer-board" element={<VolunteerBoardPage />} />
            <Route path="missions" element={<MissionsPage />} />
            <Route path="in-kind" element={<InKindPage />} />
            <Route path="support" element={<SupportPage />} />
            <Route path="notifications" element={<NotificationsPage />} />
            <Route path="reports" element={<ReportsPage />} />
            <Route path="audit-logs" element={<AuditLogsPage />} />
            <Route path="push" element={<PushNotificationsPage />} />
            <Route path="detail/:resource/:id" element={<DetailPage />} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
        </GlobalAlertsProvider>
        </PendingCountsProvider>
        </ToastProvider>
      </AuthProvider>
      </I18nProvider>
    </BrowserRouter>
  )
}
