#!/bin/bash
# PFLOCAL

git ls-files | while read -r x; do TS=$(git log --pretty=format:%cd -n 1 --date=iso -- "$FILE"); echo $TS $x; touch -d "$TS" "$x"; done
