#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql

# Uses diff with options to ignore comments and whitespace in sql scripts
# Author: Erik Schorr
# Version: 20170815

if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$#" -ne 2 ]; then
  echo "Usage:"
  echo "$0 file1.sql file2.sql"
  exit
fi

diff -BENwu -I '^--' -I '^ *#' $*


