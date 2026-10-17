#!/bin/bash
# Creates a stable local code-signing identity named "PCP Local".
# Ad-hoc signatures change every build, so macOS asks for the paste
# permission again. This certificate does not.
#
# The identity lives in its own keychain, not the login keychain, so
# codesign can use it without a prompt. The keychain password is not a
# secret: the private key never leaves this Mac, and it can only sign.
set -euo pipefail

NAME="${PCP_SIGN_ID:-PCP Local}"
KEYCHAIN="${HOME}/Library/Keychains/pcp-signing.keychain-db"
KEYCHAIN_PASSWORD="pcp-local"

add_to_search_list() {
    local current
    current=$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')
    case "${current}" in
        *"${KEYCHAIN}"*) ;;
        *) security list-keychains -d user -s "${KEYCHAIN}" ${current} >/dev/null ;;
    esac
}

if security find-certificate -c "${NAME}" "${KEYCHAIN}" >/dev/null 2>&1; then
    security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" >/dev/null
    add_to_search_list
    exit 0
fi

# An earlier attempt imported this name into the login keychain, where
# codesign stops and asks for the login password. Drop that copy.
security delete-identity -c "${NAME}" "${HOME}/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "${work}/cert.conf" << EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = ${NAME}
[ ext ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "${work}/key.pem" -out "${work}/cert.pem" -config "${work}/cert.conf" >/dev/null 2>&1
openssl pkcs12 -export -out "${work}/cert.p12" \
    -inkey "${work}/key.pem" -in "${work}/cert.pem" \
    -name "${NAME}" -passout "pass:${KEYCHAIN_PASSWORD}" >/dev/null 2>&1

if [[ ! -f "${KEYCHAIN}" ]]; then
    security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
fi
# Stay unlocked for the rest of the login session. No timeout lock.
security set-keychain-settings "${KEYCHAIN}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security import "${work}/cert.p12" -k "${KEYCHAIN}" -P "${KEYCHAIN_PASSWORD}" -f pkcs12 -A >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" >/dev/null

# codesign only searches keychains on the user search list.
# find-identity stays empty for a self-signed cert; codesign still accepts it.
add_to_search_list
if ! security find-certificate -c "${NAME}" "${KEYCHAIN}" >/dev/null 2>&1; then
    echo "Created ${KEYCHAIN}, but \"${NAME}\" is missing." >&2
    exit 1
fi

echo "Created codesigning identity \"${NAME}\" in ${KEYCHAIN}."
