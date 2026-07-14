# profylist-voice

Voice/phone integrations for Profylist:

- **Outbound "announce lead" calls** — bot dials a matching contractor when a new lead lands and tells them the details.
- **Inbound Profylist phone number** — homeowners and contractors can call/text one number; the bot handles common questions, escalates to a human when needed.
- **Human-sounding voice** — the bar is "caller doesn't hang up realizing it's a bot on the first sentence."

Kept separate from `profylist-be` so the voice pipeline can iterate independently — different vendor stack, different latency requirements, different deployment cadence.

## Chosen stack (planned, not yet built)

| Layer | Choice | Why |
|---|---|---|
| STT | Deepgram Nova-3 | ~150 ms transcription, best-in-class for phone audio |
| LLM | Claude Haiku 4.5 (Sonnet 4.6 for edge cases) | already the model backing every AI lambda in `profylist-be` |
| TTS | ElevenLabs Flash *or* Cartesia Sonic | barely distinguishable from human, sub-500 ms first-token |
| Orchestration + telephony | Vapi (BYO Twilio number) | pre-wired STT+LLM+TTS pipeline, webhook per turn |
| Backend hooks | AWS Lambda (`profylist-voice-*`) in us-east-1 | co-located with Amazon Connect + close to Vapi's US region |

End-to-end turn latency budget: **~600 ms**.

## Alternative stack (rejected — kept for reference)

**Amazon Connect + Amazon Q + Polly Generative** — cheaper (~$0.03/min vs ~$0.15/min) and AWS-native, but voice quality is still detectably synthetic and turn latency is ~1.5 s. Fails the "sounds human" bar. Kept the Amazon Connect instance around for future call-center features (queues, IVR, live-agent transfer) but not for the AI conversation layer.

## AWS Amazon Connect instance (dormant, for future call-center use only)

| | |
|---|---|
| Region | us-east-1 (N. Virginia) |
| Directory | `profylist` |
| Access URL | `https://profylist.my.connect.aws` |
| Instance ARN | `arn:aws:connect:us-east-1:033661488709:instance/c0171299-b654-4e03-a1ed-8badc0baf373` |
| Service-linked role | `AWSServiceRoleForAmazonConnect_9Y1gDRBKTeD7LetIvNJi` |

## Phased build

### Phase 1 — Outbound "announce lead" call (~2 hrs)
- Vapi Assistant with prompt: *"You're calling a contractor about a new lead near them. Read the lead details, ask if they want to claim it, wait for yes/no."*
- Vapi tool `record_response(accept: bool, notes: string)` — POSTs to `POST /profylist-voice/lead-response` webhook.
- New lambda `profylist-voice-lead-response` → updates `lead.accepted_by_contractor_id`.
- Triggered from `profylist-team` (or wherever leads get matched) via Vapi's REST API `POST /call`.

### Phase 2 — Inbound Profylist number (~4 hrs)
- Buy Twilio DID, point at Vapi.
- Vapi Assistant with different prompt: *"You are the Profylist support line. Ask the caller if they're a homeowner, a contractor, or need to talk to someone at the office."*
- Escalation path: Vapi tool `escalate_to_human` → SMS/Slack to admin, or Connect voice transfer if we ever spin up Connect queues.

### Phase 3 — SMS (~2 hrs)
- Same Twilio number, inbound SMS webhook.
- Vapi supports async chat + voice sessions on the same phone number.

## Cost projection

Assume 500 outbound lead calls per month, avg 60 s each → 500 min voice.
- Vapi + Deepgram + Claude + ElevenLabs bundle ≈ $0.15 / min → **~$75 / month**
- Twilio DID ≈ **$1 / month**
- No AWS voice costs while Connect is dormant.

## Repo layout

```
profylist-voice/
├── README.md                    ← you are here
├── docs/
│   ├── vapi-assistant-config.md ← Vapi assistant prompts + tools (TBD)
│   └── testing-checklist.md     ← what to verify before we consider it live
├── lambdas/                      ← AWS Lambda webhooks Vapi calls into
│   └── (empty — Phase 1 to add profylist-voice-lead-response.py)
└── infra/                        ← (future) Terraform / bootstrap scripts
```

## Status

- [ ] Phase 1 — outbound announce-lead call
- [ ] Phase 2 — inbound Profylist number
- [ ] Phase 3 — SMS

Vapi account not yet created. Twilio number not yet purchased.
