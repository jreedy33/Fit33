-- Enable realtime for friend_activity_feed table
-- This allows Postgres to emit change events so the iOS app can subscribe
-- to INSERT events and update the activity feed in real time.

ALTER PUBLICATION supabase_realtime ADD TABLE friend_activity_feed;
