/**
 * Marriage/Events support — the requests app users send with "Message the
 * staff team" from the events section.
 *
 * WHY IT IS ITS OWN ROUTE AND NOT A TAB ON MESSAGES
 * These are addressed TO staff and are waiting on staff; a donor↔owner thread
 * is two app users talking, which staff only oversee. Mixed into one list the
 * requests were invisible — nothing on the row said which were which — and the
 * page's count meant two different things at once.
 *
 * It is the same component underneath: see MessagesPage's header for why.
 */
import MessagesPage from './MessagesPage'

export default function MarriageSupportPage() {
  return (
    <MessagesPage
      kind="support"
      titleKey="nav.marriage_support"
      icon="🛟"
      filenameBase="marriage_support"
      leftPartyKey="common.support_requester_paren"
      rightPartyKey="common.support_team_paren"
    />
  )
}
