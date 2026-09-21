#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${1:-Telephone Local Development}"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "\"$IDENTITY_NAME\""; then
  echo "Code-signing identity already exists: $IDENTITY_NAME"
  exit 0
fi

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required to create a local code-signing identity." >&2
  exit 1
}

cat > "$TMP_DIR/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = code_signing
prompt = no

[ dn ]
CN = $IDENTITY_NAME

[ code_signing ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -nodes \
  -days 3650 \
  -config "$TMP_DIR/openssl.cnf" \
  -keyout "$TMP_DIR/key.pem" \
  -out "$TMP_DIR/cert.pem"

P12_PASSWORD="$(openssl rand -hex 24)"
openssl pkcs12 \
  -export \
  -inkey "$TMP_DIR/key.pem" \
  -in "$TMP_DIR/cert.pem" \
  -name "$IDENTITY_NAME" \
  -out "$TMP_DIR/identity.p12" \
  -passout "pass:$P12_PASSWORD"

security import "$TMP_DIR/identity.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign

security add-trusted-cert \
  -d \
  -r trustRoot \
  -k "$KEYCHAIN" \
  "$TMP_DIR/cert.pem"

echo
echo "Created local code-signing identity:"
echo "  $IDENTITY_NAME"
echo
echo "Use it for Telephone builds with:"
echo "  export TELEPHONE_CODE_SIGN_IDENTITY=\"$IDENTITY_NAME\""
echo
security find-identity -v -p codesigning "$KEYCHAIN" | grep -F "$IDENTITY_NAME" || true
