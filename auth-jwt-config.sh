#! /bin/sh

CERT="$(cat <<EOF
$(cat pem.x509)
EOF
)"

echo $CERT
echo "$CERT"

vault write auth/jwt/config \
    jwt_validation_pubkeys="$CERT"