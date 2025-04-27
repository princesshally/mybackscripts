#!/bin/bash
# PFLOCAL
# PFDISTRIB

for x in $*; do
  cksum=""
  if echo "$x" |egrep -q "(key|pem|rsa)$"; then
    cksum="rsa:"$(openssl rsa -noout -modulus -in "$x" | md5sum | cut -c1-8)
  fi
  if echo "$x" | egrep -q "\.(crt|cer)$"; then
    cksum="rsa:"$(openssl x509 -noout -modulus -in "$x" | md5sum | cut -c1-8)
  fi
  if echo "$x" | egrep -q "\.(csr)$"; then
    cksum="rsa:"$(openssl req -noout -modulus -in "$x" | md5sum | cut -c1-8)
  fi
  if [ -z "$cksum" ]; then
    cksum="file:"$(md5sum "$x" | cut -c1-8)
  fi
  echo -e "${cksum}\t${x}"
done
