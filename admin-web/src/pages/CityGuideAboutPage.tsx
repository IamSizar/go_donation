// CityGuideAboutPage — edits the "city-guide-about" content page. See ContentPage.
//
// The marriage service and the city guide carry their own About / Contact
// details: the spec requires phone numbers and social links DIFFERENT from the
// humanitarian ones, so they cannot share the global 'about' / 'contact'.
import ContentPage from '../components/ContentPage'

export default function CityGuideAboutPage() {
  return (
    <ContentPage
      slug="city-guide-about"
      titleKey="cityGuideAbout.title"
      subtitleKey="cityGuideAbout.subtitle"
    />
  )
}
