-- Enable realtime for friend_activity_feed table
-- This allows Supabase to emit INSERT events via WebSocket
-- so friends see workout completions instantly without polling.

ALTER PUBLICATION supabase_realtime ADD TABLE friend_activity_feed;
