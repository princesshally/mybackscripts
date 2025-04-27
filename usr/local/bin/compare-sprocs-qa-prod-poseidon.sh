# PFLOCAL

diff  -y <(ssh qa-posmysql02 "mysql-proc-summary.sh $1; uptime "  ) <(ssh smf3-posmysql01 "mysql-proc-summary.sh $1; uptime ")
