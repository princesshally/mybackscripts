diff  -y <(ssh qa-posmysql02 "mysql-row-count.sh $1; uptime "  ) <(ssh smf3-posmysql03 "mysql-row-count.sh $1; uptime ")
