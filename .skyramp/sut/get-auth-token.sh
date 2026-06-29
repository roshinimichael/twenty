#!/bin/sh
# Authenticates against the Twenty CRM server and prints a Bearer token to stdout.
# All debug output is sent to stderr so only the token reaches stdout.
# Default credentials are pre-populated by SIGN_IN_PREFILLED=true in the container.

set -euo pipefail

SERVER_URL="${SERVER_URL:-http://localhost:3000}"
EMAIL="${TESTBOT_EMAIL:-tim@apple.dev}"
PASSWORD="${TESTBOT_PASSWORD:-tim@apple.dev}"
TIMEOUT=300

# Wait for the server to be healthy
echo "Waiting for server at ${SERVER_URL}/healthz ..." >&2
elapsed=0
until curl -sf "${SERVER_URL}/healthz" > /dev/null 2>&1; do
  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    echo "ERROR: Server did not become healthy within ${TIMEOUT}s" >&2
    exit 1
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done
echo "Server is healthy." >&2

# Step 1: Get login token from credentials (origin is the external server URL)
LOGIN_RESPONSE=$(curl -sf -X POST "${SERVER_URL}/metadata" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"mutation { getLoginTokenFromCredentials(email: \\\"${EMAIL}\\\", password: \\\"${PASSWORD}\\\", origin: \\\"${SERVER_URL}\\\") { loginToken { token } } }\"}" \
  2>/dev/null)

LOGIN_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.getLoginTokenFromCredentials.loginToken.token // empty')

if [ -z "$LOGIN_TOKEN" ]; then
  echo "ERROR: Failed to get login token. Response: ${LOGIN_RESPONSE}" >&2
  exit 1
fi
echo "Got login token." >&2

# Step 2: Exchange login token for access token (origin required here too)
AUTH_RESPONSE=$(curl -sf -X POST "${SERVER_URL}/metadata" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"mutation { getAuthTokensFromLoginToken(loginToken: \\\"${LOGIN_TOKEN}\\\", origin: \\\"${SERVER_URL}\\\") { tokens { accessOrWorkspaceAgnosticToken { token } } } }\"}" \
  2>/dev/null)

ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.data.getAuthTokensFromLoginToken.tokens.accessOrWorkspaceAgnosticToken.token // empty')

if [ -z "$ACCESS_TOKEN" ]; then
  echo "ERROR: Failed to get access token. Response: ${AUTH_RESPONSE}" >&2
  exit 1
fi
echo "Authenticated successfully." >&2

# Print only the token to stdout
printf '%s' "$ACCESS_TOKEN"
