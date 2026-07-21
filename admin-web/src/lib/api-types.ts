// Typed shapes for the Go API responses the SPA consumes.

export type UserProfile = {
  profile_id: number
  full_name: string | null
  gender: string | null
  address: string | null
  profile_picture: string | null
  date_of_birth?: string | null
  // Note #6 — the rest of the registration profile, now editable from the
  // Users table (previously only visible read-only on the Detail page).
  city: string | null
  occupation: string | null
  family_size: number | null
  housing_status: string | null
  monthly_income: string | null
  skills: string | null
  availability: string | null
  experience: string | null
}

export type UserAccount = {
  user_id: number
  phone: string
  role_id: number
  active: number
  is_admin: number
  staff_tier?: string
  account_status?: string
  created_at: string
  profile: UserProfile | null
}

export type PaginationMeta = {
  page: number
  per_page: number
  total_items: number
  total_pages: number
  has_more: boolean
}

export type UsersListResp = {
  status: 'success'
  data: UserAccount[]
  pagination: PaginationMeta
}

export type DonationAdminRow = {
  id: number
  reference_number: string | null
  user_id: number
  donor_phone: string
  donor_full_name: string | null
  campaign_id: number | null
  campaign_title: string | null
  donation_kind: string
  donation_type: string
  amount: string
  currency: string
  payment_status: number
  delivery_status: string
  payment_method: string
  transaction_date: string
}

export type DonationsListResp = {
  success: true
  items: DonationAdminRow[]
  page: number
  per_page: number
  total_items: number
  total_pages: number
  has_more: boolean
}

export type ReportsResp = {
  success: true
  donations: {
    total_count: number
    completed_amount: string
    pending_amount: string
    failed_amount: string
  }
  beneficiary_cases: Array<{ label: string; total: number }>
  project_requests: Array<{ label: string; total: number }>
  expenses: Array<{ expense_type: string; amount: string }>
  volunteers: {
    applications_total: number
    applications_approved: number
    missions_open: number
    missions_completed: number
    signups_pending: number
    signups_active: number
    signups_completed: number
    attended_total: number
    hours_served: string
  }
  volunteer_signup_statuses: Array<{ label: string; total: number }>
}

export function paymentStatusLabel(s: number): string {
  switch (s) {
    case 1:
      return 'success'
    case 2:
      return 'pending'
    case 3:
      return 'failed'
    default:
      return String(s)
  }
}

export type Campaign = {
  id: number
  user_id: number
  title: string
  title_ar: string | null
  category: string
  category_ar: string | null
  summary: string
  summary_ar: string | null
  description: string
  description_ar: string | null
  address: string
  address_ar: string | null
  beneficiary_community_name: string
  beneficiaries: number
  goal_amount: string
  raised_amount: number
  currency: string
  status: string
  like_count: number
  comment_count: number
}

export type CampaignsListResp = {
  status: 'success'
  data: Campaign[]
  pagination: PaginationMeta
}

// Phase 14: the real `campaigns` table (not the legacy project-request shim).
// Served by /api/admin/campaigns. Mirrors the columns in 001_full_v2.sql:325.
// Phase 15 adds `is_active` (1=visible / 0=hidden) and Phase 15.1 adds the
// 3-value `status` lifecycle — see migrations 003 & 004. `is_active` is
// retained as a derived mirror (1 only when status='active').
export type AdminCampaign = {
  id: number
  title: string
  title_ar: string
  title_sorani: string | null
  title_badini: string | null
  description: string
  description_ar: string
  description_sorani: string | null
  description_badini: string | null
  address: string
  beneficiaries: string
  goal_amount: string
  raised_amount: string
  is_active: number       // derived mirror of status === 'active'
  status: CampaignStatus  // 'active' | 'hidden' | 'finished'
  // Beneficiary owner — set when published from a project request
  owner_user_id: number | null
  owner_phone: string | null
  owner_name: string | null
}

export type CampaignStatus = 'active' | 'hidden' | 'finished'

export type Sponsorship = {
  id: number
  donor_user_id: number | null
  donor_phone: string | null
  donor_full_name: string | null
  beneficiary_case_id: number | null
  project_request_id: number | null
  sponsorship_type: string
  amount: string
  currency: string
  schedule_interval: string
  next_due_date: string | null
  status: string
  notes: string | null
  created_at: string
  project_title: string
  project_title_ar: string
}

export type SponsorshipsListResp = {
  success: true
  items: Sponsorship[]
}

export type BeneficiaryCase = {
  id: number
  user_id: number | null
  case_code: string
  public_title: string
  public_title_ar: string | null
  full_name: string | null
  national_id: string | null
  phone: string | null
  gender: string | null
  date_of_birth: string | null
  marital_status: string | null
  city: string | null
  district: string | null
  address: string | null
  family_members_count: number | null
  income_amount: string | null
  housing_status: string | null
  work_status: string | null
  health_status: string | null
  education_status: string | null
  actual_needs: string | null
  priority_level: string
  // Note #15 — nullable now: legacy self-submitted cases can have SQL NULL
  // here (the backend used to crash the whole list on such a row instead).
  verification_status: string | null
  public_visibility: string
  review_notes: string | null
  created_at: string
  updated_at: string
}

export type ProjectRequest = {
  id: number
  user_id: number
  project_title: string
  project_title_ar: string | null
  category: string
  category_ar: string | null
  summary: string
  summary_ar: string | null
  amount_needed: string
  raised_amount: number
  currency: string
  location: string
  location_ar: string | null
  beneficiary_community_name: string
  beneficiary_community_name_ar: string | null
  people_affected_total: number | null
  status: string
  like_count: number
  comment_count: number
  created_at: string
  updated_at: string
}

export type AdminPageResp<T> = {
  success: true
  items: T[]
  page: number
  per_page: number
  total_items: number
  total_pages: number
  has_more: boolean
}

// New-user registration awaiting admin approval.
export type AdminRegistration = {
  user_id: number
  phone: string
  role_id: number
  registration_status: string // pending | rejected
  full_name: string
  address: string
  date_of_birth: string       // "YYYY-MM-DD" or ""
  submitted_at: string | null
  reject_reason: string | null
  created_at: string
}

export type Product = {
  id: number
  seller_user_id: number | null
  beneficiary_case_id: number | null
  name: string
  name_ar: string | null
  name_sorani: string | null
  name_badini: string | null
  description: string | null
  description_ar: string | null
  description_sorani: string | null
  description_badini: string | null
  category: string | null
  price: string
  currency: string
  image_path: string | null
  stock_quantity: number | null
  status: string
  // #28 — CMS category + SKU + specs + labels.
  category_slug: string | null
  sku: string | null
  specs: string | null
  labels: string[] | null
}

export type MarketplaceCategory = {
  id: number
  slug: string
  name_en: string
  name_ar: string
  name_ckb: string
  name_kmr: string
  display_order: number
  active: boolean
}

export type MarketOrder = {
  id: number
  product_id: number
  buyer_user_id: number | null
  quantity: number
  total_amount: string
  currency: string
  status: string
  buyer_note: string | null
  created_at: string
  updated_at: string
  name: string | null
  name_ar: string | null
  category: string | null
  image_path: string | null
}

export type MarriageProfile = {
  id: number
  profile_code: string
  gender: string | null
  age: number | null
  city: string | null
  social_summary: string | null
  visibility_level: string
  subscription_status: string
  status: string
  created_at: string
}

export type Partner = {
  id: number
  name: string
  name_ar: string | null
  name_sorani: string | null
  name_badini: string | null
  partner_type: string | null
  contact_phone: string | null
  website: string | null
  description: string | null
  description_ar: string | null
  description_sorani: string | null
  description_badini: string | null
  logo_path: string | null
  status: string
  // #26 — contact + location.
  email: string | null
  social_links: string | null
  location: string | null
  location_ar: string | null
  location_sorani: string | null
  location_badini: string | null
  // #27 — rating aggregate.
  avg_rating: number | null
  rating_count: number
}

export type MediaPost = {
  id: number
  title: string
  title_ar: string | null
  title_sorani: string | null
  title_badini: string | null
  body: string | null
  body_ar: string | null
  body_sorani: string | null
  body_badini: string | null
  post_type: string
  media_url: string | null
  link_url: string | null
  event_date: string | null
  status: string
  created_at: string
  // #22 — "Our Work" category tag.
  category_slug: string | null
  // #23 — 4-language location + media gallery.
  location: string | null
  location_ar: string | null
  location_sorani: string | null
  location_badini: string | null
  gallery: string[] | null
}

export type CommunityEntry = {
  id: number
  name: string
  name_ar: string | null
  name_sorani: string | null
  name_badini: string | null
  category: string
  city: string | null
  address: string | null
  phone: string | null
  email: string | null
  website: string | null
  description: string | null
  description_ar: string | null
  description_sorani: string | null
  description_badini: string | null
  latitude: string | null
  longitude: string | null
  // #29 — City Guide sectors, 4-language opening hours, photo gallery.
  sectors: string[] | null
  opening_hours: string | null
  opening_hours_ar: string | null
  opening_hours_sorani: string | null
  opening_hours_badini: string | null
  gallery: string[] | null
  status?: string
  approx_location?: string // #48 — 'exact' | 'approx'
  // Note #19 — mandatory classification: 'government' | 'private'.
  sector_type: string
}

export type CitySector = {
  id: number
  slug: string
  name_en: string
  name_ar: string
  name_ckb: string
  name_kmr: string
  display_order: number
  active: boolean
}

export type AdminNotification = {
  id: number
  user_id: number | null
  role_id: number | null
  title: string
  title_ar: string | null
  body: string
  body_ar: string | null
  notification_type: string | null
  notification_category: string
  priority: number
  is_read: number
  created_at: string
  read_at: string | null
}

export type AdminInKind = {
  id: number
  donor_user_id: number | null
  donor_phone: string | null
  donor_full_name: string | null
  category: string
  item_name: string
  quantity: string | null
  condition_note: string | null
  pickup_address: string | null
  status: string
  notes: string | null
  created_at: string
}

export type AdminTicket = {
  id: number
  user_id: number | null
  user_phone: string | null
  user_full_name: string | null
  subject: string
  message: string
  status: string
  created_at: string
  updated_at: string
}

// Phase 24 — volunteer board (Kanban view). Returned by GET /api/admin/volunteer_board.
// One row per signup-on-the-board; the page groups them by mission then by lane.
export type AdminBoardSignup = {
  id: number
  user_id: number
  full_name: string | null
  phone: string | null
  status: 'pending' | 'approved' | 'joined' | 'completion_requested' | 'completed'
  notes: string | null
  checked_in_at: string | null
  completed_at: string | null
  completion_requested_at: string | null
  hours_served: string
  created_at: string
  // Volunteer-to-case assignment — the foundation for the future
  // Staff↔Volunteer↔Beneficiary chat.
  beneficiary_case_id: number | null
  beneficiary_case_code: string | null
  beneficiary_case_title: string | null
  // Note #37 — self check-in/check-out evidence (GPS + live photo).
  checkin_lat: number | null
  checkin_lng: number | null
  checkin_photo_path: string | null
  checkout_lat: number | null
  checkout_lng: number | null
  checkout_photo_path: string | null
}

export type AdminBoardMission = {
  id: number
  title: string
  title_ar: string | null
  title_sorani: string | null
  title_badini: string | null
  city: string | null
  mission_date: string | null
  needed_volunteers: number | null
  status: 'open' | 'closed' | 'completed' | 'cancelled'
  lanes: {
    pending: AdminBoardSignup[]
    approved: AdminBoardSignup[]
    on_mission: AdminBoardSignup[]   // joined + completion_requested
    completed: AdminBoardSignup[]    // last 30 days only
  }
  counts: {
    pending: number
    approved: number
    on_mission: number
    completed: number
  }
}

export type AdminVolunteerBoard = {
  success: boolean
  missions: AdminBoardMission[]
  totals: {
    missions: number
    pending: number
    approved: number
    on_mission: number
    completed: number
  }
}

// Phase 22 — volunteer_missions row from /api/admin/missions. Includes per-row
// signup counts so the admin sees "5 approved / 8 needed" at a glance.
export type AdminMission = {
  id: number
  title: string
  title_ar: string | null
  title_sorani: string | null
  title_badini: string | null
  description: string | null
  description_ar: string | null
  description_sorani: string | null
  description_badini: string | null
  city: string | null
  mission_date: string | null            // YYYY-MM-DD or null
  needed_volunteers: number | null
  status: 'draft' | 'open' | 'closed' | 'completed' | 'cancelled'
  project_request_id: number | null
  accepted_volunteers: number
  pending_volunteers: number
  created_at: string
}

// Phase 21 — one volunteer's join request for a specific mission. Returned
// by GET /api/admin/volunteer_mission_signups. Status lifecycle:
//   pending → approved → joined → completed
//                                 → no_show
//                     → rejected
//                     → cancelled
// + completion_requested (volunteer claims they finished; admin confirms).
export type AdminMissionSignup = {
  id: number
  user_id: number
  user_full_name: string | null
  user_phone: string | null
  mission_id: number
  mission_title: string
  mission_city: string | null
  mission_date: string | null              // YYYY-MM-DD
  status: 'pending' | 'approved' | 'rejected' | 'joined'
        | 'completion_requested' | 'cancelled' | 'completed' | 'no_show'
  hours_served: string                     // numeric → stringified
  checked_in_at: string | null             // ISO-8601 UTC
  completed_at: string | null
  completion_requested_at: string | null
  notes: string | null
  volunteer_completion_note: string | null
  created_at: string
}

// Phase 26 — structured availability/skills. `skill_tags` aligns with the
// 28-key catalogue (lib/skillCatalogue.ts); `availability_schedule` is one
// row per day of week the volunteer marked themselves available, ordered
// mon..sun by the backend.
export type VolunteerScheduleRow = {
  day: string  // 'mon' | 'tue' | ... | 'sun'
  from: string // 'HH:MM' (24h)
  to: string
}

export type AdminVolunteerApp = {
  id: number
  user_id: number | null
  user_phone: string | null
  full_name: string
  phone: string | null
  city: string | null
  skills: string | null
  skills_ar: string | null
  skills_sorani: string | null
  skills_badini: string | null
  skill_tags: string[]
  experience: string | null
  availability: string | null
  availability_schedule: VolunteerScheduleRow[]
  status: string
  created_at: string
}

export type AdminAuditLog = {
  id: number
  user_id: number
  actor_source: string
  actor_user_id: number | null
  changed_field: string
  old_value: string | null
  new_value: string | null
  metadata_json: string | null
  created_at: string
}

export type KPITrend = {
  this_month: number
  last_month: number
  pct_change: number
}

export type MoneyTrend = {
  this_month: string
  last_month: string
  pct_change: number
}

export type DashboardKPIs = {
  signups: KPITrend
  donations_count: KPITrend
  donations_amount: MoneyTrend
  active_campaigns: number
  open_missions: number
  open_tickets: number
  donations_30d: Array<{
    date: string
    completed_amount: string
    pending_amount: string
    count: number
  }>
}

export type DashboardKPIsResp = {
  success: true
  kpis: DashboardKPIs
}

export type PushStatusResp = {
  success: true
  fcm_enabled: boolean
  // Phase 27.4 — total number of currently-active device tokens. -1
  // means the backend couldn't load the count (DB blip), the SPA
  // hides the badge in that case.
  active_devices: number
}

export type PushSendResultRow = {
  device_token: string
  ok: boolean
  message_name?: string
  error?: string
}

export type PushSendResp = {
  success: true
  sent: number
  attempts: number
  results: PushSendResultRow[]
}

export function roleLabel(roleId: number): string {
  switch (roleId) {
    case 1:
      return 'donor'
    case 2:
      return 'beneficiary'
    case 3:
      return 'volunteer'
    case 4:
      return 'employee'
    case 0:
      return '—'
    default:
      return `role ${roleId}`
  }
}
