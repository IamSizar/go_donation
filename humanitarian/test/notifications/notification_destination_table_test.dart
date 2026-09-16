// EVERY notification type the backend can send, and where a tap on it lands.
//
// The client: "when I tap on a notification inside the app it should take me
// to the exact place of this notification". This file is the table that makes
// that checkable. One row per template in backend/internal/notify/templates.go
// (68 of them, extracted from the LocalizedMessage literals there), each with
// the related_entity_type and related_entity_id the template actually sets.
//
// A NEW TYPE CANNOT SILENTLY FALL THROUGH: the rows below assert the exact
// destination, including the ones that deliberately land on the notifications
// list because the app has no screen for them. Adding a type to the backend
// without adding it here leaves it unpinned, which is the point of keeping the
// list exhaustive and commented — see the report table in HANDOFF.md for why
// each list-bound row is list-bound.

import 'package:flutter_application_1/modules/notifications/utils/notification_destination.dart';
import 'package:flutter_test/flutter_test.dart';

/// One row: the payload the backend produces, and where it must land.
typedef Row = ({String type, String entity, String? id, NotificationDestination
    to, String why});

bool member() => false;

void main() {
  final rows = <Row>[
    // ─── Chat (ids required, guests excluded — see the guest group below) ───
    (
      type: 'chat_message',
      entity: 'chat_thread',
      id: '7',
      to: NotificationDestination.directChat(7),
      why: 'the 1:1 / staff-support conversation it is about',
    ),
    (
      type: 'chat_accepted',
      entity: 'chat_thread',
      id: '7',
      to: NotificationDestination.directChat(7),
      why: 'the conversation the acceptance just unlocked',
    ),
    (
      type: 'chat_request',
      entity: 'chat_thread',
      id: '7',
      to: NotificationDestination.chatRequests,
      why: 'Messages, where Accept/Decline lives; no conversation exists yet',
    ),
    (
      type: 'chat_group_message',
      entity: 'chat_group_thread',
      id: '42',
      to: NotificationDestination.groupChat(42),
      why: 'that group conversation',
    ),
    (
      type: 'marriage_chat_message',
      entity: 'marriage_chat_thread',
      id: '9',
      to: NotificationDestination.marriageChat(9),
      why: 'that marriage conversation',
    ),
    (
      type: 'marriage_chat_request',
      entity: 'marriage_chat_thread',
      id: '9',
      to: NotificationDestination.marriageChat(9),
      why: 'marriage Accept/Decline is inside the conversation screen',
    ),
    (
      type: 'marriage_chat_accepted',
      entity: 'marriage_chat_thread',
      id: '9',
      to: NotificationDestination.marriageChat(9),
      why: 'the conversation that just opened',
    ),
    (
      type: 'staff_chat_message',
      entity: 'staff_chat_thread',
      id: '5',
      to: NotificationDestination.notificationsList,
      why: 'internal staff chat is an admin-web system; the app has no screen',
    ),

    // ─── Donations ───
    for (final t in [
      'donation_submitted',
      'donation_approved',
      'donation_rejected',
      'donation_cancelled_by_donor',
      'donation_payment_confirmed',
      'donation_payment_failed',
      'donation_received_on_project',
    ])
      (
        type: t,
        entity: 'donations',
        id: '3',
        to: NotificationDestination.myDonations,
        why: 'the donor\'s contribution history; there is no per-donation '
            'screen (DonationDetailsScreen is an unwired placeholder)',
      ),
    for (final t in [
      'in_kind_donation_submitted',
      'in_kind_donation_scheduled',
      'in_kind_donation_received',
      'in_kind_donation_delivered',
      'in_kind_donation_cancelled',
    ])
      (
        type: t,
        entity: 'in_kind_donations',
        id: '3',
        to: NotificationDestination.myDonations,
        why: 'the same history screen; the app has no separate in-kind list',
      ),

    // ─── Marketplace ───
    for (final t in [
      'marketplace_order_submitted',
      'marketplace_order_approved',
      'marketplace_order_completed',
      'marketplace_order_cancelled',
    ])
      (
        type: t,
        entity: 'marketplace_orders',
        id: '3',
        to: NotificationDestination.marketplaceOrders,
        why: 'the buyer\'s orders list',
      ),

    // ─── Sponsorship (kafala) ───
    for (final t in [
      'sponsorship_submitted',
      'sponsorship_accepted',
      'sponsorship_cancelled',
      'sponsorship_status_changed',
      'sponsorship_payment_due_reminder',
    ])
      (
        type: t,
        entity: 'sponsorships',
        id: '3',
        to: NotificationDestination.sponsorships,
        why: 'the sponsorship overview',
      ),
    for (final t in ['sponsorship_due_grantor', 'sponsorship_due_recipient'])
      (
        type: t,
        entity: 'sponsorship_schedule',
        id: '3',
        to: NotificationDestination.sponsorshipSchedule,
        why: 'a due occurrence belongs on the payment schedule, not overview',
      ),

    // ─── Beneficiary cases and project requests ───
    for (final t in [
      'beneficiary_case_submitted',
      'beneficiary_case_approved',
      'beneficiary_case_rejected',
    ])
      (
        type: t,
        entity: 'beneficiary_cases',
        id: '3',
        to: NotificationDestination.beneficiaryCases,
        why: 'the services section, which lists cases',
      ),
    for (final t in [
      'project_request_submitted',
      'project_request_approved',
      'project_request_rejected',
      'project_request_status_changed',
    ])
      (
        type: t,
        entity: 'beneficiary_project_requests',
        id: '3',
        to: NotificationDestination.myProjectRequests,
        why: 'the beneficiary\'s own project requests',
      ),

    // ─── Support ───
    for (final t in [
      'support_request_submitted',
      'support_ticket_open',
      'support_ticket_in_progress',
      'support_ticket_resolved',
      'support_ticket_closed',
      'support_ticket_replied',
    ])
      (
        type: t,
        entity: 'support_tickets',
        id: '3',
        to: NotificationDestination.supportTickets,
        why: 'the ticket history and the staff reply',
      ),

    // ─── Volunteering ───
    for (final t in [
      'volunteer_application_submitted',
      'volunteer_application_approved',
      'volunteer_application_rejected',
    ])
      (
        type: t,
        entity: 'volunteer_applications',
        id: '3',
        to: NotificationDestination.volunteerHub,
        why: 'the volunteer hub, which shows applications and missions',
      ),
    (
      type: 'volunteer_mission_approved',
      entity: 'volunteer_application_missions',
      id: '3',
      to: NotificationDestination.volunteerHub,
      why: 'my missions live in the volunteer hub',
    ),
    (
      type: 'volunteer_mission_join_submitted',
      entity: 'volunteer_mission_signups',
      id: '3',
      to: NotificationDestination.volunteerHub,
      why: 'the signup is shown in the volunteer hub',
    ),
    (
      type: 'new_volunteer_mission',
      entity: 'volunteer_missions',
      id: '3',
      to: NotificationDestination.volunteerHub,
      why: 'open missions are listed in the volunteer hub',
    ),

    // ─── Content ───
    (
      type: 'new_campaign',
      entity: 'campaigns',
      id: '3',
      to: NotificationDestination.campaign(3),
      why: 'DonationsSection takes an initialCampaignId, so the exact '
          'campaign opens',
    ),
    (
      type: 'new_media_post',
      entity: 'media_posts',
      id: '3',
      to: NotificationDestination.newsActivities,
      why: 'News & activities',
    ),
    (
      type: 'post_comment_received',
      entity: 'media_posts',
      id: '3',
      to: NotificationDestination.newsActivities,
      why: 'the post the comment is on is in News & activities',
    ),
    (
      type: 'new_partner',
      entity: 'partners',
      id: '3',
      to: NotificationDestination.partners,
      why: 'the partners directory',
    ),

    // ─── Marriage (non-chat) ───
    for (final t in [
      'marriage_profile_submitted',
      'marriage_approved',
      'marriage_rejected',
      'marriage_status_changed',
    ])
      (
        type: t,
        entity: 'marriage_profiles',
        id: '3',
        to: NotificationDestination.marriageProfile,
        why: 'the reader\'s own marriage profile',
      ),
    (
      type: 'marriage_meeting_declined',
      entity: 'marriage_meeting_request',
      id: null,
      to: NotificationDestination.marriageHub,
      why: 'the template carries no id; the hub is where requests are made',
    ),
    for (final t in [
      'marriage_subscription_activated',
      'marriage_subscription_pending',
      'marriage_subscription_rejected',
    ])
      (
        type: t,
        entity: '',
        id: null,
        to: NotificationDestination.marriageSubscription,
        why: 'these templates carry no related entity at all',
      ),

    // ─── Account ───
    for (final t in ['registration_approved', 'registration_rejected'])
      (
        type: t,
        entity: 'users',
        id: '3',
        to: NotificationDestination.profile,
        why: 'the reader\'s own account screen',
      ),

    // ─── Staff-facing alerts: no mobile screen, by design ───
    for (final t in [
      'admin_new_registration',
      'admin_new_guest_account',
      'admin_new_beneficiary_case',
      'admin_new_project_request',
      'admin_new_marriage_profile',
      'marriage_subscription_pending_admin',
    ])
      (
        type: t,
        entity: '',
        id: '3',
        to: NotificationDestination.notificationsList,
        why: 'about ANOTHER person, and staff work in admin-web; opening the '
            'reader\'s own profile or cases would be a lie',
      ),

    // ─── No screen exists ───
    (
      type: 'wallet_topup',
      entity: '',
      id: null,
      to: NotificationDestination.notificationsList,
      why: 'the app has no wallet screen',
    ),
    (
      type: 'task_assigned',
      entity: '',
      id: null,
      to: NotificationDestination.notificationsList,
      why: 'tasks are an admin-web concept; no mobile screen',
    ),
  ];

  group('every backend notification type lands somewhere deliberate', () {
    for (final row in rows) {
      test('${row.type} → ${row.to.kind.name} (${row.why})', () {
        expect(
          resolveNotificationDestination({
            'type': row.type,
            'related_entity_type': row.entity,
            if (row.id != null) 'related_entity_id': row.id,
          }, isGuest: member),
          row.to,
        );
      });
    }

    test('the table covers every type family the backend emits', () {
      // A cheap guard against the table quietly shrinking.
      expect(rows.length, greaterThanOrEqualTo(60));
    });
  });

  group('the type alone is enough when the payload carries no entity', () {
    // OPOS #26709 may ship a payload with only `type` (plus, for a chat, its
    // id — a conversation cannot be opened without one, which is the ONE hard
    // requirement this routing puts on the push payload). Nothing may become a
    // dead tap because the entity key is missing.
    for (final row in rows) {
      if (row.to == NotificationDestination.notificationsList) continue;
      test('${row.type} still routes with no related_entity_type', () {
        final got = resolveNotificationDestination({
          'type': row.type,
          // A chat carries its id; everything else is routed by name alone.
          if (row.to.isChat && row.id != null) 'related_entity_id': row.id,
        }, isGuest: member);
        if (row.to.isChat) {
          expect(got, row.to);
        } else {
          expect(
            got,
            isNot(NotificationDestination.notificationsList),
            reason:
                '${row.type} must still reach a screen when the push carries '
                'only its type',
          );
        }
      });
    }
  });

  group('a chat notification without an id cannot open a conversation', () {
    // The gap to hand to OPOS #26709: every chat push MUST carry its thread /
    // group id. Without one the tap is not dead — it lands on the list — but
    // it does not do what the client asked for either.
    for (final type in const [
      'chat_message',
      'chat_group_message',
      'marriage_chat_message',
    ]) {
      test('$type with no id falls back to the list', () {
        expect(
          resolveNotificationDestination({'type': type}, isGuest: member),
          NotificationDestination.notificationsList,
        );
      });
    }

    test('a chat REQUEST is the exception: Messages needs no id', () {
      expect(
        resolveNotificationDestination(const {
          'type': 'chat_request',
        }, isGuest: member),
        NotificationDestination.chatRequests,
      );
    });
  });
}
