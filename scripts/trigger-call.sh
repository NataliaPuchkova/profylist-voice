#!/bin/bash
# Fire a real outbound call using the Profylist Lead Announcer assistant.
#
# Prereqs (in addition to VAPI_KEY + VAPI_ASSISTANT_ID from create-assistant.sh):
#   1. Vapi Dashboard → Phone Numbers → buy a Vapi number (~$2/mo, instant) OR
#      import a Twilio number. Copy its `phoneNumberId` from the dashboard URL.
#   2. export VAPI_PHONE_NUMBER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# Usage:
#   ./scripts/trigger-call.sh +17753145678
#
# The number you pass is the CONTRACTOR you want to call. The lead details
# are hard-coded below for testing — swap them out for real values when
# you integrate with the profylist-be lead-matching flow.

set -e

TARGET_PHONE=$1
if [ -z "$TARGET_PHONE" ]; then
  echo "Usage: $0 +1XXXXXXXXXX  (target phone number, E.164 format)"
  exit 1
fi

for v in VAPI_KEY VAPI_ASSISTANT_ID VAPI_PHONE_NUMBER_ID; do
  if [ -z "$(eval echo \$$v)" ]; then
    echo "Error: $v is not set. See create-assistant.sh for setup steps."
    exit 1
  fi
done

REQ=$(cat <<EOF
{
  "assistantId": "$VAPI_ASSISTANT_ID",
  "phoneNumberId": "$VAPI_PHONE_NUMBER_ID",
  "customer": { "number": "$TARGET_PHONE" },
  "assistantOverrides": {
    "variableValues": {
      "contractor_first_name": "Mike",
      "contractor_id":         "test-contractor-uuid-000",
      "lead_id":               "test-lead-uuid-000",
      "lead_service":          "roof leak repair",
      "lead_location":         "Reno, NV",
      "lead_budget":           "\$500 to \$1000",
      "lead_timeline":         "this week",
      "lead_summary":          "water leak on second floor, worst during heavy rain"
    }
  }
}
EOF
)

echo "→ Placing call to $TARGET_PHONE…"
RESP=$(curl -sS -X POST https://api.vapi.ai/call \
  -H "Authorization: Bearer $VAPI_KEY" \
  -H "Content-Type: application/json" \
  -d "$REQ")

CALL_ID=$(echo "$RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))')
if [ -z "$CALL_ID" ]; then
  echo "Failed. Response:"
  echo "$RESP" | python3 -m json.tool
  exit 1
fi

echo "✓ Call queued. Your phone should ring in a few seconds."
echo "  call id: $CALL_ID"
echo ""
echo "Watch webhook events land in the DB:"
echo "  psql \"\$DATABASE_URL\" -c \"SELECT event_type, function_name, outcome, notes, created_at FROM voice_call_log WHERE call_id = '$CALL_ID' ORDER BY created_at\""
