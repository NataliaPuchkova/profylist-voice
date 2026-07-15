# profylist-voice

Voice/phone integrations for Profylist:

- **Outbound "announce lead" calls** — bot dials a matching contractor when a new lead lands and tells them the details.
- **Inbound Profylist phone number** — homeowners and contractors can call/text one number; the bot handles common questions, escalates to a human when needed.
- **Human-sounding voice** — the bar is "caller doesn't hang up realizing it's a bot on the first sentence."

Kept separate from `profylist-be` so the voice pipeline can iterate independently — different vendor stack, different latency requirements, different deployment cadence.

---

## Status

- [x] Phase 1 — outbound announce-lead call **(READY TO TEST — see [docs/testing-checklist.md](docs/testing-checklist.md))**
- [ ] Phase 2 — hook into real lead-matching in `profylist-be`
- [ ] Phase 3 — inbound Profylist number (voice + SMS)

## Repo layout

```
profylist-voice/
├── README.md
├── docs/
│   └── testing-checklist.md         ← start here to test Phase 1
├── vapi/
│   └── assistant.json               ← the assistant config we POST to Vapi
├── scripts/
│   ├── create-assistant.sh          ← one-shot: create the assistant on Vapi
│   └── trigger-call.sh              ← place a real outbound test call
└── (webhook lambda lives in profylist-be/lambdas/profylist-voice-webhook.py)
```

---

## Architecture (Phase 1)

```
   your app / cron                Vapi                  contractor's phone
        │                          │                            │
        │  POST /call              │                            │
        │  (assistantId,           │                            │
        │   phoneNumberId,         │                            │
        │   customer.number,       │                            │
        │   assistantOverrides)    │                            │
        ├─────────────────────────▶│                            │
        │                          │  Twilio outbound dial      │
        │                          ├───────────────────────────▶│
        │                          │                            │  ring…ring…
        │                          │                            │  "Hello?"
        │                          │◀──────────────audio────────┤
        │                          │  Deepgram STT              │
        │                          │  → Claude Haiku 4.5        │
        │                          │  → Cartesia Sonic-2 TTS    │
        │                          ├──audio─▶│  "Hi Mike, this is Profylist…"
        │                          │                            │
        │                          │  contractor says "yes"     │
        │                          │  → LLM emits tool call     │
        │                          │                            │
        │                          │  POST /profylist-voice-webhook
        │                          │  { message: { type: "function-call",
        │                          │      functionCall: { name: "accept_lead",
        │                          │        parameters: { notes: "..." }}}}
        │                          ├─▶ AWS API Gateway ─▶ Lambda
        │                          │                            │
        │                          │◀── { result: "..." } ──────┤
        │                          │  LLM speaks the reply      │
        │                          │  hangup                    │
        │                          │  ⋮                         │
        │                          │  end-of-call-report        │
        │                          ├─▶ webhook logs duration_s + cost_usd
```

The webhook (`profylist-voice-webhook`) is a Lambda in `profylist-be`, exposed at
`POST https://xibb6u88vd.execute-api.us-west-2.amazonaws.com/dev/profylist-voice-webhook`.
It writes every event to `voice_call_log` (JSONB payload + parsed fields) and
returns a reply that the assistant speaks back.

## Chosen stack

| Layer | Choice | Why |
|---|---|---|
| STT | Deepgram Nova-3 | ~150 ms transcription, best for phone audio |
| LLM | Claude Haiku 4.5 | already the model backing every AI lambda in `profylist-be` |
| TTS | Cartesia Sonic-2 (swappable → ElevenLabs Flash v2.5 or Sesame CSM when their API is available) | ~90 ms first-token, sub-detectable synthetic quality |
| Orchestration + telephony | Vapi with bundled Twilio numbers | pre-wired pipeline, webhook per turn, $2/mo per DID |
| Backend hooks | AWS Lambda (`profylist-voice-webhook`) in us-west-2 | co-located with the DB |

End-to-end turn latency budget: **~600 ms**.

## Rejected

**Amazon Connect + Amazon Q + Polly Generative** — cheaper (~$0.03/min vs ~$0.15/min) and AWS-native, but voice quality is still detectably synthetic and turn latency is ~1.5 s. Failed the "sounds human" bar in every internal test.

The Amazon Connect instance stays around for future call-center features (agent queues, IVR, live transfer). It's not part of the AI voice path.

## AWS Amazon Connect instance (dormant)

| | |
|---|---|
| Region | us-east-1 (N. Virginia) |
| Directory | `profylist` |
| Access URL | `https://profylist.my.connect.aws` |
| Instance ARN | `arn:aws:connect:us-east-1:033661488709:instance/c0171299-b654-4e03-a1ed-8badc0baf373` |

## Cost model

Assume 500 outbound lead calls per month, avg 60 s each → 500 min voice.

| Line item | $/min | $/mo @ 500 min |
|---|---:|---:|
| Vapi platform fee | 0.05 | 25 |
| Deepgram Nova-3 STT | 0.004 | 2 |
| Claude Haiku 4.5 (via Anthropic API) | 0.01 | 5 |
| Cartesia Sonic-2 TTS | 0.05 | 25 |
| Twilio outbound (via Vapi bundled) | 0.02 | 10 |
| Vapi phone number | — | 2 |
| **Total** | **~$0.13** | **~$70 / month** |

Swap Cartesia → ElevenLabs Flash: costs jump to ~$0.18/min, ~$95/mo. Swap → Sesame CSM (when GA): expect similar.

## Testing Phase 1

See [docs/testing-checklist.md](docs/testing-checklist.md). Whole flow (signup → first test call) takes ~15 minutes.

## Next steps after Phase 1 clears the human-ness bar

1. Wire the trigger. In `profylist-be`, whenever a lead is created and matched to a contractor via `service_types` + `service_area`, POST to Vapi's `/call` endpoint with:
   - `assistantId` = `VAPI_ASSISTANT_ID` (stored as Lambda env var)
   - `customer.number` = the contractor's `phone`
   - `assistantOverrides.variableValues` = lead + contractor details
2. Set `contractor.lead_notifications_enabled` = false to opt out.
3. In `voice_call_log`, roll up outcomes weekly for a contractor (`accepted` vs `declined` vs `no-answer`) to feed back into the routing heuristic (skip contractors who decline >80%).
