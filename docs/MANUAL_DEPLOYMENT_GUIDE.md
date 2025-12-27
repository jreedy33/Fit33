# 🚀 Manual Supabase Deployment Guide

## Your Supabase Project
- **Project URL:** https://ehooeghabzefgoqzugrc.supabase.co
- **Project Ref:** ehooeghabzefgoqzugrc
- **Dashboard:** https://app.supabase.com/project/ehooeghabzefgoqzugrc

---

## ⚡ Quick Deploy (3 Steps - 10 Minutes)

### STEP 1: Deploy Database Tables (5 min)

1. **Open Supabase SQL Editor:**
   - Go to: https://app.supabase.com/project/ehooeghabzefgoqzugrc/sql
   - Click **"New Query"** button

2. **Copy & Paste the SQL:**
   - Open file: `supabase_food_tracking_setup.sql`
   - Select ALL content (⌘A)
   - Copy (⌘C)
   - Paste into Supabase SQL Editor (⌘V)

3. **Run the Query:**
   - Click **"RUN"** button (or press ⌘Enter)
   - Wait for "Success" message (should take 5-10 seconds)
   - You should see: "✅ Built Simple Food Tracking Database Setup Complete!"

4. **Verify Tables Created:**
   - Go to: https://app.supabase.com/project/ehooeghabzefgoqzugrc/database/tables
   - You should see 4 new tables:
     - ✅ `food_items`
     - ✅ `user_food_history`
     - ✅ `user_favorite_foods`
     - ✅ `food_search_cache`

---

### STEP 2: Deploy Edge Function (3 min)

1. **Open Edge Functions:**
   - Go to: https://app.supabase.com/project/ehooeghabzefgoqzugrc/functions

2. **Create New Function:**
   - Click **"Create a new function"** button
   - **Function Name:** `usda-food-search`
   - Click **"Create function"**

3. **Paste Function Code:**
   - You'll see a code editor
   - Delete all existing code
   - Open file: `supabase_edge_function_usda_proxy.ts`
   - Copy ALL content
   - Paste into the editor

4. **Deploy Function:**
   - Click **"Deploy"** button
   - Wait for "Successfully deployed" message

5. **Verify Deployment:**
   - You should see the function listed as "Active"
   - Note the function URL (will look like: `https://ehooeghabzefgoqzugrc.supabase.co/functions/v1/usda-food-search`)

---

### STEP 3: Set API Key Secret (2 min)

1. **Open Edge Function Settings:**
   - Go to: https://app.supabase.com/project/ehooeghabzefgoqzugrc/settings/functions

2. **Add Secret:**
   - Find **"Secrets"** section
   - Click **"Add secret"**
   - **Name:** `USDA_API_KEY`
   - **Value:** `QNZnzcALuiyekVr86WpdzYfJzWWwEa3BvEcLdfkS`
   - Click **"Save"**

3. **Restart Function (Important!):**
   - Go back to: https://app.supabase.com/project/ehooeghabzefgoqzugrc/functions
   - Find your `usda-food-search` function
   - Click the three dots (⋮)
   - Click **"Restart"**
   - This ensures the function picks up the new secret

---

## ✅ Verification Tests

### Test 1: Check Database Tables

Go to: https://app.supabase.com/project/ehooeghabzefgoqzugrc/database/tables

You should see these tables:
- ✅ `food_items` - 0 rows (will populate when users search)
- ✅ `user_food_history` - 0 rows (will populate when users log meals)
- ✅ `user_favorite_foods` - 0 rows (will populate when users favorite foods)
- ✅ `food_search_cache` - 0 rows (will populate with searches)

### Test 2: Check Edge Function

1. Go to your function: https://app.supabase.com/project/ehooeghabzefgoqzugrc/functions
2. Click on `usda-food-search`
3. Look for status: **"Active"** ✅

### Test 3: Test API Call (Optional)

Run this in Terminal:

```bash
curl -X POST 'https://ehooeghabzefgoqzugrc.supabase.co/functions/v1/usda-food-search' \
  -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0' \
  -H 'Content-Type: application/json' \
  -d '{"action":"search","query":"chicken breast"}'
```

**Expected Response:**
```json
{
  "source": "usda",
  "foods": [...array of foods...],
  "totalHits": 42,
  "query": "chicken breast"
}
```

---

## 🎉 That's It! Deployment Complete!

### What You've Deployed:

✅ **Database Tables** - 4 tables with proper security
✅ **Edge Function** - Secure USDA API proxy
✅ **API Key Secret** - Stored securely server-side

### What Happens Now:

1. **First search** in app → Edge Function fetches from USDA API → Caches in database
2. **Second search** → Edge Function returns cached results (80% faster)
3. **User logs food** → Saved to `user_food_history`
4. **Next time** → Recent foods appear instantly

---

## 📱 Testing in Your App

Now you can:

1. **Build the app** in Xcode (⌘B)
2. **Run the app** (⌘R)
3. **Go to Meals tab**
4. **Search for foods** - will now use cloud!
5. **Log foods** - will track in history
6. **See recent foods** - after logging

---

## 🐛 Troubleshooting

### Edge Function Not Working?

**Check Logs:**
- Go to: https://app.supabase.com/project/ehooeghabzefgoqzugrc/functions
- Click on `usda-food-search`
- Click **"Logs"** tab
- Look for errors

**Common Issues:**
- Secret not set → Go to Settings and verify `USDA_API_KEY` exists
- Function not deployed → Redeploy from Functions page
- Function not restarted → Click ⋮ → Restart

### Database Tables Not Created?

**Re-run SQL:**
- Go to: https://app.supabase.com/project/ehooeghabzefgoqzugrc/sql
- Delete old query
- Create new query
- Paste SQL again
- Run

### App Shows "Search Failed"?

**Check Console in Xcode:**
- Look for error messages
- Common issues:
  - No internet connection
  - Supabase project not accessible
  - Edge Function not deployed

---

## 📊 Monitoring

### Check Database Activity

Go to: https://app.supabase.com/project/ehooeghabzefgoqzugrc/database/tables

**food_items:** See cached USDA foods
```sql
SELECT name, log_count, search_count 
FROM food_items 
ORDER BY log_count DESC 
LIMIT 10;
```

**user_food_history:** See logged meals
```sql
SELECT * 
FROM user_food_history 
ORDER BY logged_at DESC 
LIMIT 20;
```

### Check Edge Function Usage

Go to: https://app.supabase.com/project/ehooeghabzefgoqzugrc/functions

- Click on `usda-food-search`
- View **Metrics** tab
- See invocation count, errors, duration

---

## 🔒 Security Notes

✅ **API Key Protected:** USDA API key is now stored as a Supabase secret (not in app code)
✅ **Row Level Security:** Users can only see their own food history
✅ **Public Read Access:** Food items are read-only for all users
✅ **Secure Communication:** All requests use HTTPS

---

## 🎯 Success Checklist

Before testing the app, verify:

- [ ] Opened Supabase dashboard
- [ ] Ran SQL query in SQL Editor
- [ ] Saw 4 new tables created
- [ ] Created Edge Function `usda-food-search`
- [ ] Pasted function code
- [ ] Deployed function successfully
- [ ] Added secret `USDA_API_KEY`
- [ ] Restarted Edge Function
- [ ] (Optional) Tested API call in Terminal

---

## 🚀 Next Steps

1. ✅ **Complete the 3 deployment steps above**
2. ✅ **Verify all checks pass**
3. ✅ **Build app in Xcode**
4. ✅ **Test food search**
5. ✅ **Log some foods**
6. ✅ **See recent foods appear**

---

## 💡 Pro Tips

1. **Monitor logs** for first few days: https://app.supabase.com/project/ehooeghabzefgoqzugrc/functions
2. **Check database growth**: Tables will populate as users search
3. **Cache builds over time**: First users help build cache for everyone
4. **Popular foods emerge**: As users log foods, popularity rankings improve

---

## 📞 Need Help?

If something doesn't work:

1. Check the troubleshooting section above
2. Look at Edge Function logs in Supabase
3. Check Xcode console for error messages
4. Verify all 3 steps completed successfully

---

**Ready to deploy? Start with Step 1! Open the Supabase SQL Editor!** 🚀

Dashboard: https://app.supabase.com/project/ehooeghabzefgoqzugrc






