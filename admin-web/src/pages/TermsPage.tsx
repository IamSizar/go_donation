// TermsPage — edit the Terms & Conditions shown in the mobile app. See ContentPage.
//
// This used to be a line-for-line copy of ContentPage with the slug hardcoded,
// which meant it carried its own copy of ContentPage's bugs — including
// treating a 404 ("no row yet") as a hard error, the thing that made
// Our Humanitarian Work look broken. Now it is the same thin wrapper the other
// three content pages already were.
import ContentPage from '../components/ContentPage'

export default function TermsPage() {
  return (
    <ContentPage
      slug="terms"
      titleKey="terms.title"
      subtitleKey="terms.subtitle"
    />
  )
}
