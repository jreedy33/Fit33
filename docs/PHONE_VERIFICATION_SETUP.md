# Phone Verification Setup Guide

## Overview
This guide walks you through setting up SMS phone verification for Fit33 using **Twilio Verify** and **Supabase Edge Functions**.

## Cost Breakdown
- **Twilio Verify**: ~$0.05 per verification
- **First 10,000 verifications**: FREE (Twilio trial)
- **No additional Supabase costs** (Edge Functions included)

---

## Step 1: Create Twilio Account

1. Go to [twilio.com](https://www.twilio.com) and sign up
2. Complete account verification (requires phone number)
3. You'll receive **$15 free credit** on trial accounts

## Step 2: Create a Verify Service

1. In Twilio Console, go to **Verify** → **Services**
2. Click **Create New** 
3. Configure your service:
   - **Friendly Name**: `Fit33 Phone Verification`
   - **Code Length**: 6 (default)
   - **Code Expiration**: 10 minutes (default)
4. Click **Create**
5. Copy the **Service SID** (starts with `VA...`)

## Step 3: Get Your Twilio Credentials

From your Twilio Console Dashboard, copy:
- **Account SID** (starts with `AC...`)
- **Auth Token** (click to reveal)

## Step 4: Add Secrets to Supabase

Run these commands in your terminal:

```bash
# Set Twilio credentials as Supabase secrets
supabase secrets set TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
supabase secrets set TWILIO_AUTH_TOKEN=your_auth_token_here
supabase secrets set TWILIO_VERIFY_SERVICE_SID=VAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Or add them in Supabase Dashboard:
1. Go to **Project Settings** → **Edge Functions**
2. Click **Add Secret** for each:
   - `TWILIO_ACCOUNT_SID`
   - `TWILIO_AUTH_TOKEN`
   - `TWILIO_VERIFY_SERVICE_SID`

## Step 5: Deploy Edge Functions

From your project root:

```bash
# Deploy both verification functions
supabase functions deploy send-verification
supabase functions deploy verify-code
```

## Step 6: Run Database Migrations

Execute the SQL in `sql/PHONE_VERIFICATION_SETUP.sql` in Supabase:
1. Go to **SQL Editor** in Supabase Dashboard
2. Paste the contents of the file
3. Click **Run**

---

## Testing

### Test in Development

1. Build and run the app in Xcode
2. Go through onboarding to the phone number step
3. Enter a real phone number (Twilio trial only sends to verified numbers)
4. You should receive an SMS with a 6-digit code
5. Enter the code to verify

### Verify in Twilio Console

1. Go to **Verify** → **Logs** in Twilio Console
2. You should see your verification attempts
3. Check for any failed deliveries

---

## Production Checklist

Before going live:

- [ ] Upgrade Twilio account from trial (removes verified-numbers restriction)
- [ ] Set up rate limiting in Twilio (already configured in Edge Function)
- [ ] Configure fraud protection in Twilio Verify settings
- [ ] Test with multiple carriers (AT&T, Verizon, T-Mobile)
- [ ] Set up Twilio usage alerts to monitor costs

---

## Troubleshooting

### "Twilio credentials not configured"
- Verify secrets are set: `supabase secrets list`
- Redeploy functions after setting secrets

### "Failed to send verification"
- Check phone number format (should be E.164: +15551234567)
- On trial accounts, phone must be verified in Twilio Console
- Check Twilio Verify logs for specific error

### "Invalid verification code"
- Codes expire after 10 minutes
- Check for typos
- User may have requested multiple codes (only latest is valid)

### SMS not received
- Check spam/blocked senders
- Some carriers delay delivery
- Try a different phone number
- Check Twilio deliverability reports

---

## Scaling Tips

When you hit scale (10K+ verifications/month):

1. **Consider Twilio alternatives**:
   - AWS SNS: Cheaper at high volume
   - Vonage: Sometimes better international rates

2. **Implement caching**:
   - Cache verified phone numbers locally
   - Skip re-verification for returning users

3. **Add WhatsApp fallback**:
   - Twilio Verify supports WhatsApp
   - Higher delivery rates in some regions

---

## Files Reference

| File | Purpose |
|------|---------|
| `supabase/functions/send-verification/index.ts` | Edge function to send SMS code |
| `supabase/functions/verify-code/index.ts` | Edge function to verify code |
| `Fit33/PhoneVerificationService.swift` | iOS service to call edge functions |
| `sql/PHONE_VERIFICATION_SETUP.sql` | Database tables and functions |

---

## Support

- Twilio Docs: https://www.twilio.com/docs/verify
- Supabase Edge Functions: https://supabase.com/docs/guides/functions
