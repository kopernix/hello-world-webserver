#!/bin/sh
# Generates the self-signed test certificate in ./tls.
#
#   ./scripts/gen-cert.sh              -> generic certificate (recommended)
#   ./scripts/gen-cert.sh --host       -> also adds this machine's name and IPs,
#                                         so it matches by name
#   ./scripts/gen-cert.sh --force      -> regenerate even if one already exists
#
# The generic certificate is the one that gets committed: it contains no data
# from the machine that created it, so it is identical on every server. With it,
# a client can only validate the chain against localhost:
#
#   curl --cacert tls/cert.pem https://localhost:8443/     # validates, no -k
#   curl -k https://my-server:8443/                        # by real IP or name
#
# For real HTTPS, place your own pair at ./tls/cert.pem and ./tls/key.pem and
# you do not need this script.

set -eu

DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/tls"
DAYS="${DAYS:-3650}"
FORCE=""
MODE=generic

for arg in "$@"; do
    case "$arg" in
        --host)  MODE=host ;;
        --force) FORCE=1 ;;
        --generic) MODE=generic ;;
        # --help prints this very script's comment header: from line 2 while the
        # lines are comments, stopping at the first one that is not. Without
        # relying on line numbers, which go out of sync as soon as a comment is
        # edited.
        -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg (use --help)" >&2; exit 1 ;;
    esac
done

if [ -f "$DIR/cert.pem" ] && [ -z "$FORCE" ]; then
    echo "$DIR/cert.pem already exists. Use --force to regenerate it."
    exit 0
fi

command -v openssl >/dev/null 2>&1 || {
    echo "openssl is required on the host." >&2
    exit 1
}

# The generic certificate mentions neither the host nor its IPs, so the same
# file works on any server and leaks nothing when committed.
CN="helloworld"
SAN="DNS:localhost,IP:127.0.0.1"

if [ "$MODE" = host ]; then
    CN="$(hostname)"
    SAN="DNS:localhost,DNS:$CN"
    if command -v hostname >/dev/null 2>&1; then
        for ip in $(hostname -I 2>/dev/null || true); do
            SAN="$SAN,IP:$ip"
        done
    fi
fi

mkdir -p "$DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no

[dn]
CN = $CN
O  = helloworld (self-signed test certificate)

[v3]
subjectAltName   = $SAN
basicConstraints = critical,CA:FALSE
keyUsage         = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
EOF

openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
    -days "$DAYS" -config "$tmp/cnf" \
    -keyout "$DIR/key.pem" -out "$DIR/cert.pem" 2>/dev/null

chmod 600 "$DIR/key.pem"
chmod 644 "$DIR/cert.pem"

echo "Certificate ($MODE) created in $DIR: CN=$CN, $DAYS days."
if [ "$MODE" = generic ]; then
    echo "It contains no data from this machine. Identical on every server."
else
    echo "It contains this machine's name and IPs: do not commit it."
fi
echo "Replace it with your real certificate so clients validate the chain without -k."
