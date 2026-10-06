#!/bin/bash
# Creates a stable, self-signed code-signing identity in the login keychain (one-time).
#
# Why: make_app.sh otherwise ad-hoc signs, and every rebuild then gets a new code signature, so
# macOS treats the app as new and re-prompts for Input Monitoring + Keychain access each time.
# Signing every build with this stable identity keeps those grants across rebuilds.
#
# Local development only — this is a self-signed cert, not trusted for distribution. Idempotent.
set -euo pipefail

IDENTITY="Retrospection Local Signing"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "Identity already exists: $IDENTITY"
    exit 0
fi

echo "Creating self-signed code-signing identity: $IDENTITY"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Retrospection Local Signing
[v3]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/cert.cnf" 2>/dev/null

# -legacy: emit a SHA1/3DES PKCS12 that macOS `security import` accepts (OpenSSL 3 defaults don't).
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:retro -name "$IDENTITY"

# -A: let any tool (codesign) use the key without a password prompt on each build.
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P retro -A -T /usr/bin/codesign

echo "Done. make_app.sh will now sign with '$IDENTITY'."
