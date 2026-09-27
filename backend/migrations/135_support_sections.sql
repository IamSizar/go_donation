-- Client meeting — support is split into two departments: events
-- (الفعاليات, the renamed marriage module) and volunteers (المتطوعين).
--
-- NULL on a ticket / chat is deliberate: rows opened before this split and by
-- app builds that do not send a section stay "unsectioned" and remain visible
-- to every support staff member, so nothing already in the queue disappears.
ALTER TABLE support_tickets
    ADD COLUMN IF NOT EXISTS section TEXT
    CHECK (section IS NULL OR section IN ('events', 'volunteers'));

ALTER TABLE chat_threads
    ADD COLUMN IF NOT EXISTS support_section TEXT
    CHECK (support_section IS NULL OR support_section IN ('events', 'volunteers'));

-- Which support sections a staff member handles. Empty = all of them (the
-- behaviour before the split), so existing staff keep seeing everything until
-- an admin narrows them. Admin-level staff always see everything regardless.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS support_sections TEXT[] NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_support_tickets_section ON support_tickets (section);
CREATE INDEX IF NOT EXISTS idx_chat_threads_support_section ON chat_threads (support_section) WHERE kind = 'support';

-- One chat per donor + owner pair (migration 012) becomes one per pair PER
-- SUPPORT SECTION, so a user can hold an events and a volunteers support chat
-- side by side. Direct chats have no section, so for them this is still
-- exactly one thread per pair.
ALTER TABLE chat_threads DROP CONSTRAINT IF EXISTS uq_chat_pair;
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_pair_section
    ON chat_threads (donor_user_id, owner_user_id, COALESCE(support_section, ''));
