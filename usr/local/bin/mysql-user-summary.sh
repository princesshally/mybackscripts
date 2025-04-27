#!/bin/bash
# PFLOCAL
# PFDISTRIB

mysql $* mysql -e "select concat(user.user,'@',user.host) as login, if(length(password)>0,'Y','N') as Has_PW, Super_priv as Super, if('Y' in (user.Grant_priv,user.Alter_priv,user.Drop_priv,user.Create_priv,user.Create_view_priv,user.Trigger_priv,user.Lock_tables_priv), 'Y','N') as G_Admin,user.Select_priv as G_Read, if(user.Insert_priv='Y' or user.Update_priv='Y' or user.Delete_priv='Y','Y','N') as G_Write, user.Execute_priv as G_Exec, group_concat(if(db.Select_priv='Y',db.db,NULL) order by db.db asc separator ',') as DB_Select, group_concat(if(db.Insert_priv='Y',db.db,NULL) order by db.db asc separator ',') as DB_Insert, group_concat(if(db.Execute_priv='Y',db.db,NULL) order by db.db asc separator ',') as DB_Exec  from user left outer join db on db.Host=user.Host and db.User=user.User group by login;"
