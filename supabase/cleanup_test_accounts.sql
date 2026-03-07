-- Clean up test accounts (emails ending in @fit33test.com)
-- Safe to run at any time. Only affects accounts created by OnboardingTestHelper.
-- Calls the existing delete_user_account RPC for each match.

CREATE OR REPLACE FUNCTION cleanup_test_accounts()
RETURNS TABLE(deleted_count INTEGER, deleted_emails TEXT[]) AS $$
DECLARE
    v_count INTEGER := 0;
    v_emails TEXT[] := '{}';
    v_user RECORD;
BEGIN
    FOR v_user IN
        SELECT id, email FROM auth.users
        WHERE email LIKE '%@fit33test.com'
    LOOP
        PERFORM delete_user_account(v_user.id);
        v_count := v_count + 1;
        v_emails := array_append(v_emails, v_user.email);
    END LOOP;

    deleted_count := v_count;
    deleted_emails := v_emails;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION cleanup_test_accounts() IS
    'Deletes all test accounts created by OnboardingTestHelper (emails *@fit33test.com). Safe to run any time.';

GRANT EXECUTE ON FUNCTION cleanup_test_accounts() TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_test_accounts() TO service_role;
