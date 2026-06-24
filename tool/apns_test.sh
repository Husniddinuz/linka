#!/usr/bin/env bash
# Direct APNs sandbox push test using your .p8 auth key.
# Proves the device token + key + sandbox endpoint work, independent of Firebase.
#
# Fill these in (all from Apple Developer + your build):
P8_PATH="$(dirname "$0")/../AuthKey_QZATQGKWST.p8"  # newly created APNs key
KEY_ID="QZATQGKWST"                             # valid APNs key (Sandbox & Production, team-scoped)
TEAM_ID="F8MMZ9RQ8D"                            # Apple Team ID (from Xcode project)
BUNDLE_ID="com.mukhammadisakhon.linka"          # apns-topic
DEVICE_TOKEN="B565D9C6FC882FB5408DEF63377489396FBB1668BE40D24B404A7F81CC09F465"  # from flutter logs
# ----------------------------------------------------------------------------

set -euo pipefail

# Build an ES256 JWT for APNs (raw R||S signature, not DER).
JWT="$(ruby - "$P8_PATH" "$KEY_ID" "$TEAM_ID" <<'RUBY'
require 'openssl'; require 'base64'; require 'json'
path, kid, iss = ARGV
ec = OpenSSL::PKey::EC.new(File.read(path))
b64 = ->(d){ Base64.urlsafe_encode64(d).delete('=') }
header  = b64.call({alg:'ES256', kid:kid}.to_json)
payload = b64.call({iss:iss, iat:Time.now.to_i}.to_json)
input   = "#{header}.#{payload}"
der     = ec.sign(OpenSSL::Digest::SHA256.new, input)
a       = OpenSSL::ASN1.decode(der)
r       = [a.value[0].value.to_s(16).rjust(64,'0')].pack('H*')
s       = [a.value[1].value.to_s(16).rjust(64,'0')].pack('H*')
puts "#{input}.#{b64.call(r + s)}"
RUBY
)"

echo "Sending to APNs sandbox..."
curl -v --http2 \
  --header "authorization: bearer $JWT" \
  --header "apns-topic: $BUNDLE_ID" \
  --header "apns-push-type: alert" \
  --header "apns-priority: 10" \
  --data '{"aps":{"alert":{"title":"Linka test","body":"Direct APNs sandbox push"},"sound":"default"}}' \
  "https://api.sandbox.push.apple.com/3/device/$DEVICE_TOKEN"
echo
echo "HTTP 200 = delivered. 400 BadDeviceToken = wrong env/token. 403 = key/team/topic mismatch."
