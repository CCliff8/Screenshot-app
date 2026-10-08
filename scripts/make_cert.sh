#!/bin/zsh
# One-time: creates a local self-signed code-signing identity "Snip Local Signing"
# so rebuilds keep the same identity and macOS keeps the Screen Recording permission.
set -e
NAME="Snip Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then echo "Already exists"; exit 0; fi
T=$(mktemp -d)
cat > $T/o.cnf <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout $T/k.pem -out $T/c.pem -days 3650 -config $T/o.cnf 2>/dev/null
openssl pkcs12 -export -legacy -inkey $T/k.pem -in $T/c.pem -out $T/c.p12 -passout pass:snip 2>/dev/null \
  || openssl pkcs12 -export -inkey $T/k.pem -in $T/c.pem -out $T/c.p12 -passout pass:snip
security import $T/c.p12 -k ~/Library/Keychains/login.keychain-db -P snip -T /usr/bin/codesign
rm -rf $T
echo "Created '$NAME'"
