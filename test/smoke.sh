#!/bin/sh
# Functional smoke test against a running Eclaire. Usage: smoke.sh BASE_URL ADMIN_EMAIL ADMIN_PASSWORD [phase]
# phase "seed" (default) writes data; phase "verify" checks it survived.
set -u
B="${1%/}"; E="$2"; P="$3"; PHASE="${4:-seed}"
J=/tmp/eclaire-smoke.cookies; rm -f "$J"
H="Origin: $B"
fail() { echo "FAIL: $*"; exit 1; }
echo "health: $(curl -fsS "$B/health" | head -c 120)" || fail health
c=$(curl -s -o /tmp/su.json -w '%{http_code}' -X POST "$B/api/auth/sign-up/email" -H "$H" -H 'Content-Type: application/json' --data '{"email":"intruder@example.com","password":"intruder-pass-123","name":"x"}')
echo "open sign-up -> HTTP $c $(head -c 120 /tmp/su.json)"; [ "$c" != 200 ] || fail "sign-up is open"
c=$(curl -s -o /tmp/bad.json -w '%{http_code}' -X POST "$B/api/auth/sign-in/email" -H "$H" -H 'Content-Type: application/json' --data "{\"email\":\"$E\",\"password\":\"wrong-password\"}")
echo "wrong password -> HTTP $c"; [ "$c" != 200 ] || fail "wrong password accepted"
c=$(curl -s -c "$J" -o /tmp/si.json -w '%{http_code}' -X POST "$B/api/auth/sign-in/email" -H "$H" -H 'Content-Type: application/json' --data "{\"email\":\"$E\",\"password\":\"$P\"}")
echo "admin sign-in -> HTTP $c"; [ "$c" = 200 ] || fail "admin sign-in: $(head -c 200 /tmp/si.json)"
c=$(curl -s -b "$J" -o /dev/null -w '%{http_code}' "$B/api/notes"); echo "notes without cookie jar? (with) -> $c"
c=$(curl -s -o /dev/null -w '%{http_code}' "$B/api/notes"); echo "notes anonymous -> HTTP $c"; [ "$c" = 401 ] || fail "anonymous API access"
if [ "$PHASE" = seed ]; then
  c=$(curl -s -b "$J" -H "$H" -o /tmp/n.json -w '%{http_code}' -X POST "$B/api/notes" -H 'Content-Type: application/json' --data '{"title":"Railway persistence check","content":"Created by the template smoke test."}')
  echo "create note -> HTTP $c $(head -c 100 /tmp/n.json)"; [ "$c" = 200 ] || [ "$c" = 201 ] || fail "create note"
  printf 'Quarterly plan\n\nThis is a plain text document used to test Eclaire document processing on Railway. It has more than fifty characters so the AI step runs.\n' > /tmp/doc.txt
  c=$(curl -s -b "$J" -H "$H" -o /tmp/d.json -w '%{http_code}' -X POST "$B/api/documents" -F "content=@/tmp/doc.txt;type=text/plain" -F 'metadata={"title":"Smoke document"}')
  echo "upload document -> HTTP $c $(head -c 100 /tmp/d.json)"; [ "$c" = 200 ] || [ "$c" = 201 ] || fail "upload document"
  c=$(curl -s -b "$J" -H "$H" -o /tmp/p.json -w '%{http_code}' -m 120 -X POST "$B/api/prompt" -H 'Content-Type: application/json' --data '{"prompt":"Say hello"}')
  echo "AI prompt -> HTTP $c $(head -c 200 /tmp/p.json)"; [ "$c" = 200 ] || fail "AI prompt"
fi
curl -s -b "$J" "$B/api/notes" | grep -q 'Railway persistence check' && echo "note present" || fail "note missing"
curl -s -b "$J" "$B/api/documents" | grep -q '"originalFilename":"doc.txt"' && echo "document present" || fail "document missing"
echo "PASS ($PHASE)"
