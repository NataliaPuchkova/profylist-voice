# Testing Checklist — Phase 1: Announce-Lead Call

Do these in order. Each step should take < 5 minutes.

## 1. Vapi signup

- [ ] Go to https://vapi.ai → sign up (Google works)
- [ ] Dashboard → Settings → copy your **Private Key** into a shell env var:
  ```
  export VAPI_KEY=your-private-key-here
  ```

## 2. Pick a voice

- [ ] Dashboard → **Voice Library** → filter by *Cartesia* provider, *sonic-2* model
- [ ] Click each candidate — Vapi has an in-browser preview
- [ ] Pick one. Copy its **voice ID**:
  ```
  export CARTESIA_VOICE_ID=abc123...
  ```

Safe default if you want to skip picking: `bf0a246a-8642-498a-9950-80c35e9276b5` (Cartesia's "Help Desk Agent" — neutral, friendly).

## 3. Create the assistant

```bash
cd ~/Downloads/code/profylist-voice
./scripts/create-assistant.sh
```

Outputs the assistant id. Save it:
```
export VAPI_ASSISTANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

## 4. Get a phone number to place calls from

- [ ] Dashboard → **Phone Numbers** → **Buy Number** (Vapi handles Twilio for you, ~$2/mo, US area code of your choice, live in seconds)
- [ ] Copy its **id** (the UUID in the URL after clicking into it):
  ```
  export VAPI_PHONE_NUMBER_ID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
  ```

## 5. Place a call to yourself

```bash
./scripts/trigger-call.sh +1YOUR_MOBILE_NUMBER
```

Your phone should ring within ~5 seconds. The assistant opens with:
> "Hi Mike, this is Profylist calling. Got a quick minute? A new lead just came in near you."

Try both paths:
- **Accept**: "Yeah go for it" → assistant should confirm, hang up.
- **Decline**: "No thanks, I'm too busy" → assistant should acknowledge, hang up.

## 6. Verify the DB logged everything

```bash
PGPASSWORD='<postgres-password>' psql -h 35.162.236.226 -U postgres -d postgres <<'SQL'
SELECT event_type, function_name, outcome, notes, duration_s, cost_usd, created_at
FROM voice_call_log
ORDER BY created_at DESC
LIMIT 20;
SQL
```

You should see:
- One `status-update` per call state change (queued → ringing → in-progress → ended)
- One `function-call` row per tool call (accept_lead / decline_lead), with `outcome` and `notes` populated
- One `end-of-call-report` row with `duration_s` and `cost_usd`

## 7. Human-ness check

Have someone else you trust call the same test line. Ask them, blind:

> "Was that a bot or a person?"

- If they say **person** → ship it, wire into the real lead-matching flow.
- If they say **bot within 5 seconds** → try a different Cartesia voice, or swap `provider: "cartesia"` → `provider: "elevenlabs"` in `vapi/assistant.json` with an ElevenLabs voice ID and re-create the assistant. Repeat until it passes.
- If they say **bot but they wouldn't have hung up** → probably good enough for MVP.

## What "done" looks like

- [ ] Someone unfamiliar with the project takes the call and doesn't hang up
- [ ] Both accept and decline paths save the outcome to `voice_call_log`
- [ ] Cost per 60 s call from `end-of-call-report` is under $0.20

Then we move to **Phase 2** — hook this into the real lead-matching in `profylist-be` so contractors actually get calls when leads land in their service area.
