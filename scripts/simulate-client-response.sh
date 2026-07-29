#!/usr/bin/env bash
# Stand in for the agent/client returning the completed Security Attributes page.
#
# The Agent Confirmation process waits on a message ("Wait for client response") correlated
# by CUSIP. This script publishes that message to your Camunda 8 REST API with the values
# the client "filled in", which resumes the waiting instance.
#
# In production the same message would be published by whatever channel actually receives the
# reply: an inbound connector, your mail or portal integration, or a call from your own service.
#
# Usage:
#   ./scripts/simulate-client-response.sh 123456789
#   ./scripts/simulate-client-response.sh 123456789 2027-03-15 2032-03-15 4.25 SEMI_ANNUAL
#
# Config (or copy .env.example to .env and edit):
#   C8_REST_BASE   default http://localhost:8080   (Camunda 8 Run)
#   C8_AUTH        default demo:demo               (empty string if auth is disabled)
set -euo pipefail

CUSIP="${1:-}"
if [[ -z "$CUSIP" ]]; then
  echo "Usage: $0 <cusip> [firstPaymentDate] [maturityDate] [interestRate] [paymentFrequency]" >&2
  echo "The CUSIP must match the one entered in the offering capture step (it is the correlation key)." >&2
  exit 1
fi

FIRST_PAYMENT="${2:-2027-03-15}"
MATURITY="${3:-2032-03-15}"
RATE="${4:-4.25}"
FREQUENCY="${5:-SEMI_ANNUAL}"

# Load .env if present (without overriding anything already exported).
if [[ -f .env ]]; then set -a; . ./.env; set +a; fi
C8_REST_BASE="${C8_REST_BASE:-http://localhost:8080}"
C8_AUTH="${C8_AUTH-demo:demo}"

read -r -d '' PAYLOAD <<JSON || true
{
  "name": "ClientSecurityAttributesReturned",
  "correlationKey": "${CUSIP}",
  "timeToLive": 600000,
  "variables": {
    "clientFirstPaymentDate": "${FIRST_PAYMENT}",
    "clientMaturityDate": "${MATURITY}",
    "clientInterestRate": ${RATE},
    "clientPaymentFrequency": "${FREQUENCY}"
  }
}
JSON

AUTH_ARGS=()
[[ -n "$C8_AUTH" ]] && AUTH_ARGS=(-u "$C8_AUTH")

echo "Publishing ClientSecurityAttributesReturned for CUSIP ${CUSIP} to ${C8_REST_BASE}"
HTTP_CODE=$(curl -s -o /tmp/c8-msg-response.txt -w '%{http_code}' \
  -X POST "${C8_REST_BASE}/v2/messages/publication" \
  -H 'Content-Type: application/json' \
  "${AUTH_ARGS[@]}" \
  -d "$PAYLOAD")

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
  echo "Published. The waiting instance should now advance to Compare to Closing Docs."
  cat /tmp/c8-msg-response.txt 2>/dev/null; echo
else
  echo "Publish failed with HTTP ${HTTP_CODE}:" >&2
  cat /tmp/c8-msg-response.txt >&2; echo >&2
  echo >&2
  echo "Common causes:" >&2
  echo "  - No instance is waiting yet. Complete the Send Confirmation Email task first." >&2
  echo "  - The CUSIP does not match the one entered in offering capture (it is the correlation key)." >&2
  echo "  - Auth: Camunda 8 Run defaults to demo/demo. Set C8_AUTH='' if you disabled auth." >&2
  exit 1
fi
