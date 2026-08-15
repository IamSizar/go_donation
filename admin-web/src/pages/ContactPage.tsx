// ContactPage — edit the "Contact Us" content page (#35). See ContentPage.
//
// K13 — `contact` turns on the structured contact-details editor (logo, phone,
// WhatsApp, email, social links, address). It is passed here rather than
// inferred from the slug so a page that is not a Contact page cannot acquire
// six boxes its screen has nowhere to render.
import ContentPage from '../components/ContentPage'

export default function ContactPage() {
  return <ContentPage slug="contact" titleKey="contact.title" subtitleKey="contact.subtitle" contact />
}
