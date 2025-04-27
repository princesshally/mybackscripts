#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql
# get-sprocs-from-git.sh
# Author: Erik Schorr
# Version: 20180131
# Rev: 20170105 ES Show context of 'use' statements found in retrieved stored procs
# Rev: 20170517 ES Comment out USE statements, Insert DEFINER in CREATE PROCEDURE statements lacking DEFINER
# Rev: 20170718 ES Insert downloaded date/url at top of file, read optional GITBASE from cfg, error on 404
# Rev: 20170808 ES Add SQLFILTER in cfgfile to pipe downloaded sql file through, e.g. sed
# Rev: 20180131 ES Detect 2-level version numbers (1.2), and append ".000" to them for VERSION variable

# This script reads config parameters from the file get-sprocs.cfg
# get-sprocs.cfg format:
# PROJECT dbprojectname_in_gitlab
# DATABASE local_db_to_install_sprocs_to
# SQLFILTER sed -e "s/call dbname\./call /gi"
# SPROCS space separated list of sproc definition files
# SPROCS more sprocs as needed

# For each listed SPROC, this script grabs the raw definitions from URL:
# http://gitlab.enformion.com/data-engineering/mysql/raw/master/${PROJECT}/${SPROC}.sql
# saves it to the current directory as ${SPROC}-${VERSION}-${DATESTAMP}.sql
# Use this command to install srocs:
#   mysql -c ${DATABASE} < ${SPROC}.sql
# Make sure sproc sql definition does NOT include any "use" statements,
# as these statements override the database name provided in cfg file!

# Edit GITBASE as needed
GITBASE="http://gitlab.enformion.com/data-engineering/mysql/raw/master/"

STRIPUSE=1

#### NO USER-SERVICEABLE CONTENT PAST THIS LINE

flasher() {
  printf '\e[?5h'
  sleep 0.1
  printf '\e[?5l'
}

get_cfg_item() {
  f="$1"; shift
  k="$1"; shift
  if [ -z "$f" ] || [ -z "$k" ]; then
    echo "get_cfg_item: missing argument(s)" >&2
    exit 2
  fi
  if egrep -iq "^${k}[[:space:]=:]{1,}[a-z0-9]" "$f"; then
    v=$(egrep -i "^${k}[[:space:]=:]{1,}[a-z0-9]" "$f" | tr -s "\t =:" " " | cut -d " " -f2-)
    echo "$v"
    return
  fi
}

get_cfg_multi() {
  f="$1"; shift
  k="$1"; shift
  if [ -z "$f" ] || [ -z "$k" ]; then
    echo "get_cfg_item: missing argument(s)" >&2
    exit 2
  fi
  a=""
  if egrep -iq "^${k}[[:space:]=:]{1,}[a-z0-9]" "$f"; then
    v=$(egrep -i "^${k}[[:space:]=:]{1,}[a-z0-9]" "$f" | tr -s "\t =:" " " | cut -d " " -f2- | tr -s " " "\n" | sort |uniq | tr -s "\n" " ")
    if [ "$a" ]; then
      a="$a $v"
    else
      a="$v"
    fi
    echo "$a"
    return
  fi
}

usage() {
  echo "Usage:"
  echo "$0 [-h] [-s] [cfgfile.cfg]"
  echo "  -h : show this help"
  echo "  -s : strip 'USE' commands from downloaded stored proc files"
  echo ""
}

CFG="get-sprocs.cfg"
INVERSE=$(printf '\e[7m')
NORMAL=$(printf '\e[0m')

while [ "$1" ]; do
  arg="$1"
  shift
  if echo "$arg" | grep -q "^-"; then
    if [ "$arg" = "-s" ] || [ "$arg" = "--stripuse" ]; then
      STRIPUSE=1
      continue
    fi
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
      usage
      exit 0
    fi
    echo "Unknown option: $arg"
  fi
  CFG="$arg"
done

if [ -f "$CFG" ]; then
  GITBASE_TMP=$(get_cfg_item "$CFG" GITBASE)
  if [ "$GITBASE_TMP" ]; then
    GITBASE=GITBASE_TMP
  fi
  PROJECT=$(get_cfg_item "$CFG" PROJECT)
  DATABASE=$(get_cfg_item "$CFG" DATABASE)
  SQLFILTER="$(get_cfg_item "$CFG" SQLFILTER)"
  echo "SQLFILTER: $SQLFILTER"
  if [ "$*" ]; then
    echo "Getting sprocs from cmdline args" >&2
    SPROCS="$*"
  else
    SPROCS=$(get_cfg_multi "$CFG" SPROCS?)
  fi
else
  echo "$CFG was not found in this directory.  Exiting." >&2
  exit 1
fi
  
echo "gitbase: $GITBASE"
echo "project: $PROJECT"
echo "database: $DATABASE"
echo "sprocs: $SPROCS"
echo ""

DATE=$(date +%Y%m%d)
for sproc in $SPROCS; do
  # Generate URL to download
  URL=$(echo "${GITBASE}/${PROJECT}/${sproc}.sql" | sed -e 's/\([a-z0-9]\)\/\/*\([a-z0-9]\)/\1\/\2/g')
  # Strip leading directory path stuff from sproc
  sproc=$(echo "$sproc" | sed -e 's/^.*\///g')

  echo "Getting $URL"
  TMP="${sproc}.tmp$$"
  TS=$(date +%Y%m%dT%H%M%S%z)
  SQLFILTERCMD="cat"
  if [ "$SQLFILTER" ]; then
    echo "Using SQLFILTER pipe: $SQLFILTER"
    SQLFILTERCMD="$SQLFILTER"
  fi
  echo "-- Downloaded $TS on $(hostname -s) from $URL" > $TMP
  if curl -s "$URL" | sh -c "$SQLFILTERCMD" >> $TMP; then
    VERSION=$(grep '\*.*Version.*[0-9]\.[0-9]*\.[0-9]*' "$TMP" | head -1 | grep -o '[0-9][0-9.]*\.[0-9.]*[0-9]')
    if [ -z "$VERSION" ]; then
      VERSION=$(grep '\*.*Version.*[0-9]\.[0-9]*' "$TMP" | head -1 | grep -o '[0-9][0-9.]*\.[0-9.]*[0-9]')
      if [ -z "$VERSION" ]; then
        VERSION="unknown"
      fi
    fi
    if echo "$VERSION" | egrep -q '^[0-9]{1,}\.[0-9]{1,}$'; then
      VERSION=${VERSION}.000
    fi
    if grep -q "<h1>404" $TMP; then
      echo ""
      echo "${INVERSE}ERROR: 404 Not Found: ${URL}${NORMAL}"
      echo ""
      flasher; sleep 1
      continue
    fi 
    OUT="${sproc}-${VERSION}-${DATE}.sql"
    if [ "$OUTFILES" ]; then
      OUTFILES="$OUTFILES $OUT"
    else
      OUTFILES="$OUT"
    fi
    mv "$TMP" "$OUT" && echo "$sproc saved to $OUT"
    if egrep -qi "^[[:space:]]*use " "$OUT"; then
      echo "### WARNING: found a USE sql statement in ${OUT}:"
      grep -in2 "^[[:space:]]*use " "$OUT" | sed -e 's/^\([0-9][0-9]*\)[:-]/\1|  /g' -e 's/^/    /g' -e '/[uU][sS][eE] /s/^    />>> /'
      if [ "$STRIPUSE" ]; then
        sed -i "$OUT" -e "s/^ *USE /-- USE /g"
      fi
    fi
    if egrep -qi "^CREATE PROCEDURE" "$OUT"; then
      echo "### WARNING: found a CREATE PROCEDURE statement in ${OUT} without a definer.  Adding DEFINER='dbadmin'@'%'"
      sed -i "$OUT" -e "s/^CREATE PROCEDURE/CREATE DEFINER='dbadmin'@'%' PROCEDURE/i"
    fi
    if egrep -i "^DROP PROCEDURE" "$OUT" | grep -qvi "DROP.*PROCEDURE.*IF.*EXISTS"; then
      echo "### WARNING: found a DROP PROCEDURE statement in ${OUT} without IF EXISTS.  Adding IF EXISTS."
      sed -i "$OUT" -e "s/^DROP PROCEDURE /DROP PROCEDURE IF EXISTS /i" -e "s/IF.*EXISTS.*IF.*EXISTS/IF EXISTS/i"
    fi
  else
    echo "### There was a problem downloading $URL - curl returned error code $?"
    rm -f "$TMP"
  fi
done

echo ""
echo "To install these new stored procedures, run these commands:"
for FILE in $OUTFILES; do
  echo "# mysql -c ${DATABASE} < $FILE"
done

exit 0
