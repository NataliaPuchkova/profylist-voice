#!/bin/bash
# One-shot: create the Profylist Lead Announcer assistant in Vapi.
#
# Prereqs:
#   1. Sign up at https://vapi.ai (free tier: $10 credit)
#   2. Dashboard → Settings → Vapi Public Key OR Private Key → copy it
#   3. Dashboard → Voice Library → pick a Cartesia Sonic-2 voice → copy its voice ID
#      (or use "help-desk-agent" / "friendly-reading-lady" as safe defaults)
#   4. export VAPI_KEY=your-private-key
#      export CARTESIA_VOICE_ID=your-picked-voice-id
#   5. Run:  ./scripts/create-assistant.sh
#
# Output: prints the created assistant's id — save it, you'll need it to
# trigger calls.

set -e

if [ -z "$VAPI_KEY" ]; then
  echo "Error: set VAPI_KEY environment variable (your Vapi private key)"
  exit 1
fi
if [ -z "$CARTESIA_VOICE_ID" ]; then
  echo "Error: set CARTESIA_VOICE_ID (from Vapi's voice library — Cartesia Sonic-2 voice)"
  exit 1
fi

CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vapi/assistant.json"
BODY=$(sed "s/REPLACE_WITH_CARTESIA_VOICE_ID/$CARTESIA_VOICE_ID/g" "$CONFIG_FILE")

echo "→ Creating assistant on Vapi…"
RESP=$(curl -sS -X POST https://api.vapi.ai/assistant \
  -H "Authorization: Bearer $VAPI_KEY" \
  -H "Content-Type: application/json" \
  -d "$BODY")

ASSISTANT_ID=$(echo "$RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))')

if [ -z "$ASSISTANT_ID" ]; then
  echo "Failed. Response:"
  echo "$RESP" | python3 -m json.tool
  exit 1
fi

echo "✓ Assistant created."
echo "  id: $ASSISTANT_ID"
echo ""
echo "Save this in your shell so trigger-call.sh can find it:"
echo "  export VAPI_ASSISTANT_ID=$ASSISTANT_ID"
