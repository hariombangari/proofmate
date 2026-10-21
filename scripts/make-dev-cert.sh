#!/bin/bash
# Creates a self-signed "ProofMate Dev" code-signing identity in the login keychain.
# bundle.sh signs with it when present, so the Accessibility grant survives rebuilds.
# Only needed if you rebuild often; a one-off build works fine with ad-hoc signing.
set -euo pipefail

NAME="ProofMate Dev"
if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "\"$NAME\" identity already exists."
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null

PASS=$(openssl rand -hex 12)
LEGACY=""
openssl version | grep -q "^OpenSSL 3" && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/dev.p12" -passout "pass:$PASS"

security import "$WORK/dev.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PASS" -T /usr/bin/codesign

echo "Created \"$NAME\". Rebuild with scripts/bundle.sh, then re-enable ProofMate in"
echo "System Settings > Privacy & Security > Accessibility one last time."
