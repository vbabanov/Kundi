ALTER TABLE assistant_messages
  DROP CONSTRAINT IF EXISTS chk_assistant_messages_input_mode;

ALTER TABLE assistant_messages
  ADD CONSTRAINT chk_assistant_messages_input_mode
  CHECK (input_mode IN ('text', 'voice'));
