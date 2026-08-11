// MarriageContactPage — edits the "marriage-contact" content page. See ContentPage.
//
// The marriage service and the city guide carry their own About / Contact
// details: the spec requires phone numbers and social links DIFFERENT from the
// humanitarian ones, so they cannot share the global 'about' / 'contact'.
import ContentPage from '../components/ContentPage'

export default function MarriageContactPage() {
  return (
    <ContentPage
      slug="marriage-contact"
      titleKey="marriageContact.title"
      subtitleKey="marriageContact.subtitle"
    />
  )
}
