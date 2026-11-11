#!/bin/bash
# Creates the self-signed code-signing identity used by bundle.sh.
#
# Why: macOS keys every TCC permission grant (Accessibility, Input
# Monitoring, Microphone, ...) to the app's designated requirement. Ad-hoc
# signing pins that requirement to the binary's cdhash, which changes on
# every build — so macOS treats each rebuild as a new app and re-asks for
# everything. A stable certificate makes the requirement
# "bundle id + certificate", which survives any number of rebuilds.
#
# One identity signs any number of apps — apps are told apart by bundle id,
# not by certificate. Run this once per machine; it is idempotent.
set -euo pipefail

IDENTITY="${1:-trj-dev}"
KEYCHAIN=~/Library/Keychains/login.keychain-db

if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "identity '$IDENTITY' already set up — nothing to do"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    # Self-signed root, code-signing EKU, 10 years. Same thing Keychain
    # Access makes via Certificate Assistant → Create a Certificate →
    # Code Signing, only scriptable.
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$TMP/id.key" -out "$TMP/id.crt" \
        -days 3650 -subj "/CN=$IDENTITY" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning"

    # The .p12 must carry a password: macOS's `security import` rejects
    # password-less PKCS#12 files with "MAC verification failed". The
    # password only guards this transient file — once imported, the key
    # lives in the keychain, and the .p12 is deleted with the temp dir.
    openssl pkcs12 -export \
        -inkey "$TMP/id.key" -in "$TMP/id.crt" \
        -out "$TMP/id.p12" -passout pass:notch-setup

    # -T codesign: let codesign use the key without a keychain prompt on
    # every build. The first signing may still show one "Always Allow"
    # dialog — that click is the last one.
    security import "$TMP/id.p12" -k "$KEYCHAIN" -P "notch-setup" -T /usr/bin/codesign
fi

# An imported self-signed cert starts out untrusted (CSSMERR_TP_NOT_TRUSTED)
# and codesign won't list it as a valid identity. Trust it — for code
# signing only, nothing else.
security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$TMP/id.crt"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/id.crt"

echo "==> identity '$IDENTITY' ready:"
security find-identity -v -p codesigning | grep "$IDENTITY"
