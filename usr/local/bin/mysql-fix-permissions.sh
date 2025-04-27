#!/bin/bash
find /db/mysql/data/* /db/mysql/data/*/. -type d ! -user mysql -print -exec chown -R mysql:mysql "{}" \; 2>/dev/null
find /db/mysql/data/* /db/mysql/data/*/. -type f  ! -user mysql -print0 2>/dev/null | xargs -r0 chown mysql:mysql

