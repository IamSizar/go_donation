// Maps a DetailPage :resource URL segment → its human label, its list-page
// path, and the nav section that owns it. Shared by DetailPage.tsx (page
// title + breadcrumb) and AppShell.tsx (keeping the sidebar highlighted while
// on a /detail/:resource/:id subpage) so the mapping only lives in one place.
// Several resource keys don't textually match their section's path (e.g.
// `products`/`orders` both live under /marketplace) — inferring the section
// from the URL text would be wrong, this table is the source of truth.
export const RESOURCE_LABELS: Record<string, { labelKey: string; list: string; sectionKey: string }> = {
  partners:                     { labelKey: 'noun.partner',               list: '/partners',    sectionKey: 'nav.partners' },
  media:                        { labelKey: 'noun.media_post',            list: '/media',        sectionKey: 'nav.media' },
  community:                    { labelKey: 'noun.community_entry',       list: '/community',    sectionKey: 'nav.community' },
  marriage:                     { labelKey: 'noun.profile',               list: '/marriage',     sectionKey: 'nav.marriage' },
  products:                     { labelKey: 'noun.product',               list: '/marketplace',  sectionKey: 'nav.marketplace' },
  orders:                       { labelKey: 'noun.order',                 list: '/marketplace',  sectionKey: 'nav.marketplace' },
  beneficiary_cases:            { labelKey: 'noun.case',                  list: '/beneficiary',  sectionKey: 'nav.beneficiary' },
  beneficiary_project_requests: { labelKey: 'noun.project_request',       list: '/beneficiary',  sectionKey: 'nav.beneficiary' },
  sponsorships:                 { labelKey: 'noun.sponsorship',           list: '/sponsorships', sectionKey: 'nav.sponsorships' },
  in_kind_donations:            { labelKey: 'noun.in_kind_donation',      list: '/in-kind',       sectionKey: 'nav.in_kind' },
  support_tickets:              { labelKey: 'noun.support_ticket',        list: '/support',       sectionKey: 'nav.support' },
  donations:                    { labelKey: 'noun.donation',              list: '/donations',     sectionKey: 'nav.donations' },
  volunteer_applications:       { labelKey: 'noun.volunteer_application', list: '/volunteers',    sectionKey: 'nav.volunteers' },
  volunteer_missions:           { labelKey: 'noun.mission',               list: '/missions',      sectionKey: 'nav.missions' },
  campaigns:                    { labelKey: 'noun.campaign',              list: '/campaigns',     sectionKey: 'nav.campaigns' },
  users:                        { labelKey: 'noun.user',                  list: '/users',         sectionKey: 'nav.users' },
}
