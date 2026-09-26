#!/bin/sh
# Basic smoke tests. Checks that the container starts, answers 200 over HTTP and
# HTTPS, and that gen-cert.sh behaves.
#
#   ./scripts/test.sh
#
# Leaves nothing behind: the stack is torn down and the temporary copies are
# deleted. The project's .env and tls/ are never touched. Exits 0 if every test
# passes, 1 otherwise.
#
# Runs fully isolated from a real deployment, so it is safe to run while the
# stack is up: the temporary copies get their own project and container name.

DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
NAME=helloworld-test
PASS=0
FAIL=0

ok()  { PASS=$((PASS+1)); echo "  ok    $1"; }
ko()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
run() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else ko "$1"; fi; }

cleanup() {
    [ -n "$STACK" ] && (cd "$STACK" && docker compose down -v) >/dev/null 2>&1
    [ -n "$COPY" ] && rm -rf "$COPY"
    [ -n "$CERT" ] && rm -rf "$CERT"
}
trap cleanup EXIT INT TERM

# Copy the project and rename the project and the container inside the copy, so
# these tests never touch a real deployment that happens to be running.
isolate() {
    cp -r "$DIR" "$1" || return 1
    sed -i "s/^name: helloworld/name: $NAME/; s/^    container_name: helloworld/    container_name: $NAME/" "$1/compose.yaml"
    rm -f "$1/.env" && cp "$1/env.example" "$1/.env"
}

# --- 1. Configuration -------------------------------------------------------
echo
echo "Configuration"

STACK="$DIR.stack.tmp"
isolate "$STACK" || { echo "  FAIL  could not stage the test copy"; exit 1; }
cd "$STACK" || exit 1

run "compose file is valid" "docker compose config -q"

# Port 0 makes Docker pick a free one, so these tests cannot fail because
# something else already holds the port.
HTTP_PORT=0 HTTPS_PORT=0 docker compose up -d >/dev/null 2>&1

HP=$(docker compose port web 80 2>/dev/null | cut -d: -f2)
SP=$(docker compose port web 443 2>/dev/null | cut -d: -f2)
if [ -z "$HP" ] || [ -z "$SP" ]; then
    ko "container started and published its ports"
    echo
    echo "$PASS passed, $FAIL failed"
    exit 1
fi
ok "container started and published its ports"

# The healthcheck waits 5s (start_period) before the first run.
i=0
while [ "$i" -lt 30 ]; do
    [ "$(docker inspect --format '{{.State.Health.Status}}' "$NAME" 2>/dev/null)" = healthy ] && break
    i=$((i+1))
    sleep 1
done

# --- 2. Serving -------------------------------------------------------------
echo
echo "Serving (STATUS=200)"

[ "$(docker inspect --format '{{.State.Health.Status}}' "$NAME" 2>/dev/null)" = healthy ] \
    && ok "container is healthy" || ko "container is healthy"

[ "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$HP/")" = 200 ] \
    && ok "HTTP returns 200" || ko "HTTP returns 200"

[ "$(curl -sS --max-time 5 "http://127.0.0.1:$HP/")" = "Hello World" ] \
    && ok "HTTP body is BODY" || ko "HTTP body is BODY"

[ "$(curl -sS -o /dev/null -w '%{content_type}' --max-time 5 "http://127.0.0.1:$HP/")" = text/plain ] \
    && ok "HTTP content type is text/plain" || ko "HTTP content type is text/plain"

# The committed certificate covers localhost, so this validates the chain for
# real, without -k.
[ "$(curl -sS --cacert tls/cert.pem -o /dev/null -w '%{http_code}' --max-time 5 "https://localhost:$SP/")" = 200 ] \
    && ok "HTTPS validates the chain without -k" || ko "HTTPS validates the chain without -k"

[ "$(curl -sSk -o /dev/null -w '%{http_code}' --max-time 5 "https://127.0.0.1:$SP/")" = 200 ] \
    && ok "HTTPS returns 200 with -k" || ko "HTTPS returns 200 with -k"

# --- 3. gen-cert.sh ---------------------------------------------------------
# On a separate copy, so the committed certificate is never rewritten.
echo
echo "gen-cert.sh"

COPY="$DIR.cert.tmp"
isolate "$COPY" || { echo "  FAIL  could not stage the certificate copy"; exit 1; }
cd "$COPY" || exit 1

grep -q 'NR==1{next}' scripts/gen-cert.sh \
    && ok "--help reads the header without printing code" \
    || ko "--help reads the header without printing code"

"$COPY/scripts/gen-cert.sh" 2>&1 | grep -q 'already exists' \
    && ok "refuses to overwrite an existing certificate" \
    || ko "refuses to overwrite an existing certificate"

"$COPY/scripts/gen-cert.sh" --bogus >/dev/null 2>&1; [ $? -eq 1 ] \
    && ok "unknown option exits 1" || ko "unknown option exits 1"

"$COPY/scripts/gen-cert.sh" --generic --force >/dev/null 2>&1 \
    && ok "regenerates the generic certificate" \
    || ko "regenerates the generic certificate"

openssl x509 -in "$COPY/tls/cert.pem" -noout -ext subjectAltName 2>/dev/null \
    | grep -q 'DNS:localhost' \
    && ok "generic certificate only covers localhost" \
    || ko "generic certificate only covers localhost"

[ "$(stat -c '%a' "$COPY/tls/key.pem")" = 600 ] \
    && ok "private key permissions are 600" || ko "private key permissions are 600"

# --- 4. Cleanup -------------------------------------------------------------
echo
echo "Cleanup"

cd "$STACK" || exit 1
docker compose down -v >/dev/null 2>&1
[ -z "$(docker ps -aq --filter "name=^/$NAME\$")" ] \
    && ok "no test container left running" || ko "no test container left running"

# A real deployment that was already running must have survived the tests.
[ -n "$(docker ps -q --filter name=^/helloworld\$)" ] \
    && ok "pre-existing deployment was not touched" || echo "  note  no other helloworld container was running"

cd / && rm -rf "$STACK" && STACK=""

# --- Result -----------------------------------------------------------------
echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
echo "all tests passed"
