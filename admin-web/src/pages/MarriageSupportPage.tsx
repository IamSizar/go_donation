/**
 * Support Chat — every "Message the staff team" thread (Messages tab,
 * `chat_support` tile, POST /api/chats/support), from ANY role, not just
 * the marriage/events section. The route and component name still say
 * "marriage" for history: this page started as the events section's own
 * inbox, back when it was the only caller of that endpoint. It no longer
 * is (see backend/internal/handlers/chat.go SupportThread) — a beneficiary
 * tapping "Contact support" from Messages lands here too, which is exactly
 * why it moved out of the Marriage nav group into Communication & Support
 * (see navLayout.ts) and why its label is now role-neutral ("Support Chat"
 * / محادثة الدعم), not "Events Support". Client note, 2026-09-22.
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
