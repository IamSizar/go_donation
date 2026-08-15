// CityGuideContactPage — edits the "city-guide-contact" content page. See ContentPage.
//
// The marriage service and the city guide carry their own About / Contact
// details: the spec requires phone numbers and social links DIFFERENT from the
// humanitarian ones, so they cannot share the global 'about' / 'contact'.
import ContentPage from '../components/ContentPage'

export default function CityGuideContactPage() {
  return (
    <ContentPage
      slug="city-guide-contact"
      titleKey="cityGuideContact.title"
      subtitleKey="cityGuideContact.subtitle"
      contact
    />
  )
}
