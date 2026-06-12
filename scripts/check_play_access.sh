#!/usr/bin/env bash
# Checks whether the Play Console service account can list the install-reports
# bucket. Uses only openssl + curl + python3 (no gcloud required).
set -euo pipefail

KEY="${1:-$HOME/Downloads/linka-499114-003d1ee25098.json}"
BUCKET="pubsite_prod_4790145822126622778"
PREFIX="stats/installs/"

[[ -f "$KEY" ]] || { echo "❌ key not found: $KEY"; exit 1; }

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

client_email=$(python3 -c "import json;print(json.load(open('$KEY'))['client_email'])")
private_key=$(python3 -c "import json;print(json.load(open('$KEY'))['private_key'])")

now=$(date +%s); exp=$((now + 3600))
header='{"alg":"RS256","typ":"JWT"}'
claims="{\"iss\":\"$client_email\",\"scope\":\"https://www.googleapis.com/auth/devstorage.read_only\",\"aud\":\"https://oauth2.googleapis.com/token\",\"iat\":$now,\"exp\":$exp}"

signing_input="$(printf '%s' "$header" | b64url).$(printf '%s' "$claims" | b64url)"
sig=$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign <(printf '%s' "$private_key") -binary | b64url)
jwt="$signing_input.$sig"

token=$(curl -s -X POST https://oauth2.googleapis.com/token \
  -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$jwt" \
  | python3 -c "import json,sys;print(json.load(sys.stdin).get('access_token',''))")

[[ -n "$token" ]] || { echo "❌ could not obtain access token (bad key?)"; exit 1; }

resp=$(curl -s "https://storage.googleapis.com/storage/v1/b/$BUCKET/o?prefix=$PREFIX" \
  -H "Authorization: Bearer $token")

count=$(printf '%s' "$resp" | python3 -c "import json,sys;d=json.load(sys.stdin);print(len(d.get('items',[]))) if 'error' not in d else print('ERR')")

if [[ "$count" == "ERR" ]]; then
  echo "❌ STILL 403 — permission not propagated yet."
  printf '%s\n' "$resp" | python3 -c "import json,sys;print('   '+json.load(sys.stdin)['error']['message'])" 2>/dev/null || true
  exit 2
else
  echo "✅ SUCCESS — service account can read the bucket. $count objects under $PREFIX"
  printf '%s' "$resp" | python3 -c "import json,sys;[print('   '+i['name']) for i in json.load(sys.stdin).get('items',[])[:15]]"
fi
