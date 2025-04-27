#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql
# get-sprocs.sh
# Author: Erik Schorr
# Version: 20190213
# Rev: 20170105 Show context of 'use' statements found in retrieved stored procs
# Rev: 20170517 Comment out USE statements, Insert DEFINER in CREATE PROCEDURE statements lacking DEFINER
# Rev: 20170718 Insert downloaded date/url at top of file, read optional GITBASE from cfg, error on 404
# Rev: 20170808 Add SQLFILTER in cfgfile to pipe downloaded sql file through, e.g. sed
# Rev: 20180225 Fix to allow requesting specific sprocs on cmdline
# Rev: 20180307 Strip spaces and tabs from immediately before end-of-line, to work around a DELIMITER bug.  DELIMITER is parsed improperly when the previous line contains whitespace at end-of-line.  See JIRA:WEB-2209
# Rev: 20180820 Add POSTCMD exec functionality: runs command specified on POSTCMD lines in cfg, after procs are downloaded
# Rev: 20190213 search /db/mysql/meta/poseiden-data-processing-CURRENT/$PROJECT/mysql for requested search proc before downloading
# Rev: 20200625 add ability to specify a search path to copy from (SRCDIR in get-sprocs.cfg)

# This script reads config parameters from the file get-sprocs.cfg
# get-sprocs.cfg format:
# PROJECT dbprojectname_in_gitlab
# DATABASE local_db_to_install_sprocs_to
# SQLFILTER sed -e "s/call dbname\./call /gi"
# SPROC space separated list of sproc definition files
# SPROC more sprocs as needed
# POSTCMD command to run after proc downloads, understands $DATABASE and $PROJECT and $SPROCS

# For each listed SPROC, this script grabs the raw definitions from search path or this URL:
# http://gitlab.enformion.com/data-engineering/mysql/raw/master/${PROJECT}/${SPROC}.sql
# saves it to the current directory as ${SPROC}-${VERSION}-${DATESTAMP}.sql
# Use this command to install srocs:
#   mysql -c ${DATABASE} < ${SPROC}.sql
# Make sure sproc sql definition does NOT include any "use" statements,
# as these statements override the database name provided in cfg file!

# Edit GITBASE as needed
GITBASE="http://gitlab.enformion.com/data-engineering/mysql/raw/master/"
GITDOWNLOAD=0
STRIPUSE=1
SLEEP=0

# Escape '$' to ensure it's not expanded at this point.  will be evaluated later in script
DEFAULTSRCDIR="/db/mysql/meta/poseiden-data-processing-CURRENT/\${PROJECT}/mysql/"

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
  if egrep -iq "^${k}[[:space:]=]{1,}[a-z0-9]" "$f"; then
    v=$(egrep -i "^${k}[[:space:]=]{1,}[a-z0-9]" "$f" | tr -s "\t =" " " | cut -d " " -f2-)
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
  if egrep -iq "^${k}[[:space:]=]{1,}[a-z0-9/]" "$f"; then
    v=$(egrep -i "^${k}[[:space:]=]{1,}[a-z0-9/]" "$f" | tr -s "\t =" " " | cut -d " " -f2- | tr -s " " "\n" | sort |uniq | tr -s "\n" " ")
    if [ "$a" ]; then
      a="$a $v"
    else
      a="$v"
    fi
    echo "$a" | sed -e 's/  *$//'
    return
  fi
}

get_cfg_postcmd() {
  f="$1"; shift
  cat "$f" | grep "^POSTCMD" | sed -e 's/^POSTCMD[\t ]*//g' | while read -r cmd; do sh -vc "$cmd" ; done
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
    if [ "$arg" = "-g" ]; then
      GITDOWNLOAD=1
      continue
    fi
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
      usage
      exit 0
    fi
    echo "Unknown option: $arg"
  fi
  if [ "$SPLIST" ]; then
    SPLIST="$SPLIST|$arg"
  else
    SPLIST="$arg"
  fi
done

if [ -f "$CFG" ]; then
  GITBASE_TMP=$(get_cfg_item "$CFG" GITBASE)
  if [ "$GITBASE_TMP" ]; then
    GITBASE=$GITBASE_TMP
  fi
  PROJECT=$(get_cfg_item "$CFG" PROJECT); export PROJECT
  DATABASE=$(get_cfg_item "$CFG" DATABASE); export DATABASE
  SQLFILTER="$(get_cfg_item "$CFG" SQLFILTER)"
  [ "$SQLFILTER" ] && echo "SQLFILTER: $SQLFILTER"
#  if [ "$SPLIST" ]; then
#    echo "Getting sprocs from cmdline args" >&2
#    SPROCS="$SPLIST"
#  else
  SPROCS=$(get_cfg_multi "$CFG" SPROCS?); export SPROCS
  SRCDIR=$(get_cfg_multi "$CFG" SRCDIR); export SRCDIR

#  fi
else
  echo "$CFG was not found in this directory.  Exiting." >&2
  exit 1
fi

SPROCS=$(echo "$SPROCS" | sed -e 's/\.sql//g'); export SPROCS
  
if [ "$SRCDIR" ]; then
  SRCDIR="$SRCDIR $DEFAULTSRCDIR"
else
  SRCDIR="$DEFAULTSRCDIR"
fi
#echo "gitbase: $GITBASE"
echo "project: $PROJECT"
echo "database: $DATABASE"
echo "sprocs: $SPROCS"

DATE=$(date +%Y%m%d)
SQLFILTERCMD="cat"
if [ "$SQLFILTER" ]; then
  echo "Using SQLFILTER pipe: $SQLFILTER"
  SQLFILTERCMD="$SQLFILTER"
fi
if echo "$SRCDIR" | egrep -q '\$|`.*`'; then
  eval SRCDIRS=\"$SRCDIR\"
else
  SRCDIRS="$SRCDIR"
fi
echo "Searching for sprocs in ($SRCDIRS)"
echo ""
for sproc in $SPROCS; do
  TS=$(date +%Y%m%dT%H%M%S%z)
  if [ "$SPLIST" ]; then
    if echo "$sproc" | egrep "\b(${SPLIST})\b"; then
      echo "Getting specific sproc $sproc"
    else
      echo "Skipping sproc $sproc"
      continue
    fi
  fi
  TMP="${sproc}.tmp$$"
  spname="$sproc"
  FOUND=0
  for TMPD in ${SRCDIRS}; do
    if [ -f "$TMPD/${spname}.sql" ]; then
      grep -iq "^CREATE " "$TMPD/${spname}.sql" || echo "WARNING: No valid CREATE commands in $TMPD/${spname}.sql"
      echo ""
      echo "-- $TS $(hostname -s) copied $spname from $TMPD" | tee $TMP
      cat "$TMPD/${spname}.sql" | sh -c "$SQLFILTERCMD" >> $TMP
      # Mayank's "verison" typo!
      VERSION=$(grep -i '\*.*Ver[si][si]on.*[0-9]\.[0-9]*\.[0-9]*' "$TMP" | head -1 | grep -o '[0-9][0-9._]*[0-9]' | head -1)
      if [ -z "$VERSION" ]; then
        VERSION=$(grep -i '\*.*Ver[si][si]on.*[0-9][0-9_.]*[0-9]' "$TMP" | head -1 | grep -o '[0-9][0-9._]*[0-9]' | head -1)
        if [ -z "$VERSION" ]; then
          VERSION="unknown"
        fi
      fi
      if echo "$VERSION" | egrep -q '^[0-9]{1,}\.[0-9]{1,}$'; then
        VERSION=${VERSION}.000
      fi
      FOUND=1
    fi
  done
  
  [ "$FOUND" = 0 ] && echo "Didn't find ${spname}.sql in ($SRCDIRS)"
  if [ "$FOUND" = 0 ] && [ "$GITDOWNLOAD" = 1 ]; then
    if echo "$sproc" | grep -q '^https*:.*sql$'; then
      URL=$(echo "$sproc" | sed -e 's/mysql\/blob/mysql\/raw/g' -e 's/\([a-z0-9]\)\/\/*\([a-z0-9]\)/\1\/\2/g')
      spname=$(echo "$sproc" | rev | cut -d/ -f1 | rev | sed -e 's/\.sql$//')
      echo "Using predefined URL $URL"
    else
      # Generate URL to download
      URL=$(echo "${GITBASE}/${PROJECT}/${sproc}.sql" | sed -e 's/\([a-z0-9]\)\/\/*\([a-z0-9]\)/\1\/\2/g')
    fi
    # Strip leading directory path stuff from sproc
    sproc=$(echo "$sproc" | sed -e 's/^.*\///g')

    echo "Getting $URL"
    echo "-- Downloaded $TS on $(hostname -s) from $URL" > $TMP
    if curl -s "$URL" | sh -c "$SQLFILTERCMD" >> $TMP; then
      VERSION=$(grep -i '\*.*Ver[si][si]on.*[0-9]\.[0-9][0-9]*\.[0-9]*' "$TMP" | head -1 | grep -io '[0-9][0-9._]*[0-9]')
      if [ -z "$VERSION" ]; then
        VERSION=$(grep -i '\*.*Ver[si][si]on.*[0-9][0-9_.][0-9]' "$TMP" | head -1 | grep -io '[0-9][0-9._]*[0-9]')
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
        flasher; [ "$SLEEP" ] && sleep $SLEEP
        continue
      fi 
      FOUND=1
    fi
  fi

  if [ "$FOUND" = 1 ]; then
    OUT="${spname}-${VERSION}-${DATE}.sql"
    if [ "$OUTFILES" ]; then
      OUTFILES="$OUTFILES $OUT"
    else
      OUTFILES="$OUT"
    fi
    mv "$TMP" "$OUT" && echo "$sproc saved to $OUT"
    if egrep -qi "[[:space:]]$" "$OUT"; then
      _c=$(egrep -c "[[:space:]]$" "$OUT")
      echo "### WARNING: found ${_c} lines containing whitespace at EOL.  Please fix upstream."
      echo "### Removing redundant whitespace at EOL"
      sed -i "$OUT" -e "s/[ \t]*$//g"
      sleep 1
    fi
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
    echo ""
    echo "${INVERSE}Could not find sp $spname specified in $CFG and -g not specified${NORMAL}"
    echo ""
    flasher; sleep 1
    rm -f "$TMP"
  fi
done

if grep -q "^POSTCMD" $CFG; then
  echo ""
  echo "Running POSTCMD commands"
  get_cfg_postcmd "$CFG"
fi

echo ""
echo "To install these new stored procedures, run these commands:"
for FILE in $OUTFILES; do
  echo "# mysql -c ${DATABASE} < $FILE"
done

exit 0
