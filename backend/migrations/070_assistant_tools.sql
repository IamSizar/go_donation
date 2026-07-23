-- 070 — AI Assistant upgrade: tool-calling + admin usage stats. Logs
-- lightweight metadata per chat turn (NOT the message text, for privacy) so
-- admin can see usage volume/trends without storing conversation transcripts.
CREATE TABLE IF NOT EXISTS assistant_chat_log (
  id         BIGSERIAL PRIMARY KEY,
  user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id    INTEGER NOT NULL,
  lang       VARCHAR(8) NOT NULL DEFAULT 'en',
  source     VARCHAR(8) NOT NULL DEFAULT 'local', -- 'ai' | 'local'
  used_tool  BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assistant_chat_log_created_at ON assistant_chat_log (created_at);
CREATE INDEX IF NOT EXISTS idx_assistant_chat_log_user ON assistant_chat_log (user_id);
