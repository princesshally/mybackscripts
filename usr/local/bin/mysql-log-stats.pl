#!/usr/bin/perl
# PFLOCAL
# Revisions:
# 20230608 eschorr: enhanced parameter token dump (-pc for csv output), use -adb Galaxy_Search_YYYYMMDD to print default db name for log entries that didn't supply one



use Time::Local;
#180216  9:26:19 41267182 Query  SET NAMES latin1
#                41267182 Query  SET character_set_results=NULL
#                41267182 Init DB        verizon
#                41267182 Query  CALL `verizon`.`search_phone`(NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '3318564683', 1, 50)
#                41266816 Init DB        verizon
#                41266816 Query  CALL `verizon`.`search_phone`(NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '6627941012', 1, 50)
#                41266842 Init DB        death_20170403
#                41291855 Connect        zabbix@zenoss.cco as anonymous on
#                41286575 Connect        bigip_monitor@10.100.8.103 as anonymous on information_schema
#                30 Query	USE `debt_v2_20190514`
#$debug=1;
$csvhdr=0;
$print_sp_stats=0;
$print_host_stats=0;
$print_user_stats=0;
%t_first_seen=();
%t_last_seen=();
%sp_param_flags=();
%sp_count=();
%db_first_seen=();
%db_last_seen=();
#@pcols=qw/business_20180122.search_business_lte business_20180122.search_business_phone business_20180122.search_business_v2_1 census_20170623.search_census criminal_20180205.search_criminal_v2 death_20170403.search_death debt_20180121.search_debt_lte_v1_1 debt_20180121.search_debt_v1_8 debt_20180212.search_debt_v2 domains.search_domain_v1_3 eviction_20171117.search_eviction_v2_1 fein_20170807.search_fein_v1_2 foreclosure_20171115.search_foreclosure_criteria_v1_2 license_20170831.search_license_criteria_v1_1 mardiv.search_mardiv_v1_3 payday_loans.search_payday_loans_phone phone.search_phone property_re_20170514.search_property_lte property_re_20170514.search_property_v2_1 verizon.search_phone workplace.search_workplace_v1_3/;
@pcols=qw/debt_20190116.search_debt_v2 debt_20190122.search_debt_v2 debt_v2_20190304.search_debt_v2 debt_v2_20190319.search_debt_v2 debt_v2_20190325.search_debt_v2 debt_v2_20190417.search_debt_v2 debt_v2_20190418.search_debt_v2 debt_20190116.search_debt_v2_1 debt_20190122.search_debt_v2_1 debt_v2_20190304.search_debt_v2_1 debt_v2_20190319.search_debt_v2_1 debt_v2_20190325.search_debt_v2_1 debt_v2_20190417.search_debt_v2_1 debt_v2_20190418.search_debt_v2_1/;
@users=qw/pos_ro@mccgalaxy01.cco pos_ro@mccgalaxy02.cco pos_ro@mccgalaxy03.cco pos_ro@mccgalaxy04.cco pos_ro@mccgalaxy05.cco pos_ro@mccgalaxy06.cco pos_ro@mccgalaxy07.cco pos_ro@mccgalaxy08.cco pos_ro@mccgalaxy09.cco pos_ro@mccgalaxy10.cco pos_ro@mccgalaxy11.cco pos_ro@mccgalaxy12.cco pos_ro@mccgalaxy13.cco pos_ro@mccgalaxy14.cco pos_ro@mccgalaxy15.cco pos_ro@mccgalaxy16.cco pos_ro@mccgalaxy17.cco pos_ro@mccgalaxy18.cco pos_ro@mccgalaxy19.cco pos_ro@mccgalaxy20.cco pos_ro@mccgalaxy21.cco pos_ro@mccgalaxy22.cco pos_ro@mccgalaxy23.cco pos_ro@mccgalaxy24.cco pos_ro@mccgalaxy25.cco pos_ro@mccgalaxy26.cco pos_ro@mccgalaxy27.cco pos_ro@mccgalaxy28.cco pos_ro@mccgalaxy29.cco pos_ro@mccgalaxy30.cco pos_ro@mccgalaxy31.cco pos_ro@mccgalaxy32.cco pos_ro@mccgalaxy33.cco pos_ro@mccgalaxy34.cco pos_ro@mccgalaxy35.cco pos_ro@mccgalaxy36.cco pos_ro@mccgalaxy37.cco pos_ro@mccgalaxy38.cco pos_ro@mccgalaxy39.cco pos_ro@mccgalaxy40.cco pos_ro@mccgalaxy41.cco pos_ro@mccgalaxy42.cco pos_ro@mccgalaxy43.cco pos_ro@mccgalaxy44.cco pos_ro@mccgalaxy45.cco pos_ro@mccgalaxy46.cco pos_ro@mccgalaxy47.cco pos_ro@mccgalaxy48.cco pos_ro@mccgalaxy49.cco pos_ro@mccgalaxy50.cco pos_ro@mccgalaxy51.cco pos_ro@mccgalaxy52.cco pos_ro@mccgalaxy53.cco pos_ro@mccgalaxy54.cco pos_ro@mccgalaxy55.cco pos_ro@mccgalaxy56.cco pos_ro@mccgalaxy57.cco pos_ro@mccgalaxy58.cco pos_ro@mccgalaxy59.cco pos_ro@mccgalaxy60.cco pos_ro@mccgalaxy62.cco pos_ro@mccgalaxy63.cco pos_ro@mccgalaxy64.cco pos_ro@mccgalaxy65.cco pos_ro@mccgalaxy66.cco pos_ro@mccgalaxy67.cco pos_ro@mccgalaxy68.cco pos_ro@mccgalaxy69.cco pos_ro@mccgalaxy70.cco pos_ro@mccgalaxyr01.cco pos_ro@stage-galaxy01.cco pos_ro@stage-galaxy02.cco/;

$rlc=0;
$ts="";
$searchdb="";

while ($ARGV[0]) {
	$arg=shift @ARGV;
	if ($arg eq '-s') {
		$print_abs_ts=1;
		next;
	}
	if ($arg eq '-q') {
		$query_re=shift @ARGV;
		print "QRE: $query_re\n";
		next;
	}
	if ($arg eq '-p') {
		$pstats=1;
		print "Print param stats\n";
		next;
	}
	if ($arg eq '-pc') {
		chomp($hostname=`hostname -s`);
		if ( $hostname =~ /([0-9]+)$/) {
			$hostnum=$1;
		}
		$pstats=2;
		print "Print param stats csv\n";
		next;
	}
	if ($arg eq '-adb') {
		$adb=shift @ARGV;
		next;
	}
	if (!$searchdb && !$query_re) {
		$searchdb=$arg;
		print STDERR "Watching connections for access to db $searchdb DB\n";
	}
}

while (<>) {
	$rlc++;
	chomp;
	$line=$_;
	if ($line =~ /^(\d\d)(\d\d)(\d\d)\s(..):(..):(..)\s+/) {
		$year="20".$1;
		$month=$2;
		$day=$3;
		$min=$5;
		$sec=$6;
		($hour=$4) =~ s/^ /0/;
		$ts ="${year}${month}${day}.${hour}${min}${sec}";
		$ts2="${year}-${month}-${day}T${hour}:${min}:${sec}";
		$min10=substr($min,0,1)."0";
#		$tg="${year}-${month}-${day} ${hour}:${min10}:00.00";
		$tg="${year}${month}${day}.${hour}${min10}00";
		$ats=timelocal($sec, $min, $hour, $day, $month-1, $year);
		$line =~ s/^\d\d\d\d\d\d\s..:..:..\s+//;
#		print "### set ts to $ts\n";
	}	
	$line =~ s/^[ \t]*//;
	if ($line =~ /^(\d+) /) {
#                if ($cline) {
#			print ">>> entire line for $ccid: $cline\n";
#		}
		$cid=$1;
		$line =~ s/^\d+ //;
		$cline=$line;
	} else {
#		print "CONTINUED LINE: $line\n";
		$cline=$cline. " $line";
		$ccid=$cid;
		next;
	}
	next if ($ignore_thread{$cid});
	next unless $ts;
#                25076927 Connect        crim_ro@bigip.cco as anonymous on sex_offenders
#                25076927 Query  CALL search_sex_offenders_v1_1('Livingston', 'Marion', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '19900928', 0, 0, 0, false, true, 500)
#                25076927 Quit
	if ($line =~ /Connect\s+(\S+)/) {
		if ($1 =~ /(zenoss|bigip_monitor|zabbix|localhost)/i) {
#		if ($1 =~ /(localhost)/i) {
			$ignore_thread{$cid}=1;
#			print "III IGNORING connection $cid from $1\n" if $debug;
			next;
		}
		$user{$cid}=$1;
		if ($line =~ /Connect.* on (.+)$/) {
			$db=$1;
			tr/`//d;
			$db{$cid}=$db;
			if ($searchdb && $1 eq $searchdb) {
				print "SEARCHDB CONNECT (${cid}\@${ts}) $line\n";
			}
			$db_first_seen{$db}=$ats unless exists ($db_first_seen{$db});
			$db_first_seen2{$db}=$ts unless exists ($db_first_seen2{$db});
			$db_last_seen{$db}=$ats;
			$db_last_seen2{$db}=$ts;
		}
#		print "[[[ $ts Connect from $user{$cid} to $db ]]]\n" if $debug;
		$connect_user{$cid}=$1;
		$user_connect_count{$1}++;
		
		next;
	}
# 30 Query	USE `debt_v2_20190514`
        if ($line =~ /Query.*USE +([^ ]+)/) {
		$db=$1;
		$db =~ tr/`//d;
		$db{$cid}=$db;
		if ($searchdb && $db eq $searchdb) {
			print "SEARCHDB USE (${cid}\@${ts}) $line\n";
		}
		$db_first_seen{$db}=$ats unless exists ($db_first_seen{$db});
		$db_last_seen{$db}=$ats;
		next;
	}
	$t_first_seen{$cid}=$ats if (!exists $t_first_seen{$cid});
	$t_last_seen{$cid}=$ats;
	if ($line =~ /^Init DB\s+(\S+)$/) {
		$db{$cid}=$1;
		if ($searchdb && $1 eq $searchdb) {
			print "SEARCHDB INIT (${cid}\@${ts}) $line\n";
		}
		$db_first_seen{$1}=$ats unless exists ($db_first_seen{$1});
		$db_last_seen{$1}=$ats;
		next;
	}
# ~~25064612 Query~SELECT 1 FROM whitepages.nicknames limit 1
# ~~25051610 Query~select if(count(distinct casenumber)>5,'OK','ERR') as status from sex_offenders where state in ('ca','ny') and first like 'michael' and last like 'jackson'
# ~~26515548 Query~select count(1) from foreclosure_detail where foreclosure_detail.ForeclosureId< 10000
	if ($line =~ /^Query.*SELECT .* from ([^ ]+).*$/i) {
		print ">>> $line\n" if $debug;
		if ($query_re && $line =~ /$query_re/i) {
			print "QRE (${cid}\@${ts}) $line\n";
		}
		$dtmp="";
		$ttmp=$1;
		if ($1 =~ /^(.+)\.(.+)$/) {
			$dtmp=$1;
			$ttmp=$2;
			if ($searchdb && $dtmp eq $searchdb) {
				print "SEARCHDB SELECT (${cid}\@${ts}) $line\n";
			}
			print "EEE1 db $dtmp seen in $line\n" if $debug;
			$db_first_seen{$dtmp}=$ats unless exists ($db_first_seen{$dtmp});
			$db_last_seen{$dtmp}=$ats;
			$queries_per_db{$dtmp}++;
		} else {
			$ttmp=$db{$cid}.".".$ttmp;
			if ($searchdb && $db{$cid} eq $searchdb) {
				print "SEARCHDB SELECT (${cid}\@${ts}) $line\n";
			}
			$queries_per_db{$db{$cid}}++;
		}
		$queries_per_tbl{$ttmp}++;
		$queries_per_cid{$cid}++;
	}
	if ($line =~ /^Query\s+CALL\s+([^(]+)\((.*)\)/i) {
		$c=$1;
		$p=$2;
		$c =~ tr/`//d;
		if ($c =~ /^(.+)\.(.+)$/) {
			$dtmp=$1;
			if ($searchdb && $dtmp eq $searchdb) {
				print "SEARCHDB CALL (${cid}\@${ts}) $line\n";
			}
			print "EEE2 db $dtmp seen in $line\n" if $debug;
			$db_first_seen{$dtmp}=$ats unless exists ($db_first_seen{$dtmp});
			$db_first_seen2{$dtmp}=$ts unless exists ($db_first_seen2{$dtmp});
			$db_last_seen{$dtmp}=$ats;
			$db_last_seen2{$dtmp}=$ts;
			$queries_per_db{$dtmp}++;
			$db{$cid}=$dtmp unless ($db{$cid});
		} else {
			if ($db{$cid}) {
				if ($searchdb && $db{$cid} eq $searchdb) {
					print "SEARCHDB CALL (${cid}\@${ts}) $line\n";
				}
				$queries_per_db{$db{$cid}}++;
				$c=$db{$cid}.".".$c;
#				print "DDD $c\n";
				$db_first_seen{$$db{$cid}}=$ats unless exists ($db_first_seen{$$db{$cid}});
				$db_first_seen2{$$db{$cid}}=$ts unless exists ($db_first_seen2{$$db{$cid}});
				$db_last_seen{$$db{$cid}}=$ats;
				$db_last_seen2{$$db{$cid}}=$ts;
			}
		}
		if ($query_re && $line =~ /$query_re/i) {
			print "QRE (${cid}\@${ts}) $line\n";
		}
		$queries_per_cid{$cid}++;
		if ($p =~ /,(\s*'\s*[0-9-]+[0-9,-]\s*,\s*[0-9,-]*[0-9-]\s*'\s*),/) {
			#			print "MULT found: $1\n"
			$p =~ s/,(\s*'\s*[0-9-]+[0-9,-]\s*,\s*[0-9,-]*[0-9-]\s*'\s*),/,MULT,/;
		}
		@pp=split(/,/, $p);
		for $i (0..scalar(@pp)-1) {
			$pp[$i] =~ s/^ +//g;
			$pp[$i] =~ s/ +$//g;
			if ($pp[$i] eq 'MULT') {
				$pp[$i]="M";
				next;
			}
			if (lc $pp[$i] eq 'false') {
				$pp[$i]="F";
				next;
			}
			if (lc $pp[$i] eq 'true') {
				$pp[$i]="T";
				next;
			}
			if (lc $pp[$i] eq 'null' || $pp[$i] eq '') {
				$pp[$i]="N";
				next;
			}
			if ($pp[$i] eq '0') {
				$pp[$i]='0';
				next;
			}
			if ($pp[$i] =~ /^'?-?[0-9]+'?$/) {
				$pp[$i]='1';
				next;
			}
			if ($pp[$i] eq "''") {
				$pp[$i]='E';
				next;
			}
			$pp[$i] = 'A';
		}
		$p=join('', @pp);

#		$p =~ s/AN{3,}A/M/ if ($p =~ /XXXXXXXXXXXXXXXXXXXXXXXXXXAN{3,}A/);
#		if ($p !~ /ANNNN*A/) {
#			print "CC1\t$tg\t$c\n" if ($pstats);
			print "CC2\t$ts2\t$c\t$p\n" if ($pstats eq 1);
			$db=defined($db{$cid})?$db{$cid}:$adb;
			$c=~ s/${db}\.// if ($c =~ /^$db/);
			$cid2="${hostnum}:${cid}";
			($call=$line) =~ s/^Query\s+//;
			$call=~s/\"/\\\"/g;
			print "_timestamp,galaxy_host,conn_id,db,sp,params,sp_params,raw\n" unless $csvhdr;
			$csvhdr=1;
			print "\"$ts2\",\"${hostname}\",\"$cid2\",\"", defined($db{$cid})?$db{$cid}:$adb,"\",\"$c\",\"$p\",\"${c}-${p}\",\"${call}\"\n" if ($pstats eq 2);
#		}

		$c_active{$c}=1;
		$c_stats{$tg}{$c}++;
		$c_count++;
	}
	if (!$hdr) {
		$hdr=1;
		print "Timegroup\t";
		if ($print_sp_stats) {
#			print join("\t", @pcols);
		}
		if ($print_user_stats) {
			print join("\t", @users);
		}
		print "\n";

	}
	if (!$ltg) {
		$ltg=$tg;
	}
	if ($tg ne $ltg) {
 		print "$ltg";
		if ($print_sp_stats) {
#			for $k (@pcols) {
			for $k (sort keys %{$c_stats{$ltg}}) {
				if ($c_stats{$ltg}{$k}) {
					print "\t${k}:$c_stats{$ltg}{$k}";
				} else {
					print "\t0";
				}
			}
			delete $c_stats{$ltg};
		}
		if ($print_connect_stats) {
			for $k (@users) {
				if ($user_count{$user{$cid}}) {
					print "\t".$user_connect_stats{$ltg}{$k};
				} else {
					print "\t0";
				}
			}
		}
	print "\n";
		
	}
	$ltg=$tg;
	next;
	
#	print "$ats >$line\n";
#	if (!($rlc%1000)) {
#		print "$ats $ts $rlc $c_count\n";
#	}
}
exit if ($pstats eq 2);
$now=time;
print "### queries per db:\n";
for $k (sort keys %queries_per_db) {
	if ($print_abs_ts) {
		print "$k\t$queries_per_db{$k}\t",$db_first_seen2{$k},"\t",$db_last_seen2{$k},"\n";
	} else {
		print "$k\t$queries_per_db{$k}\t",($now-$db_first_seen{$k}),"\t",($now-$db_last_seen{$k}),"\n";
	}
}
print "### queries per table:\n";
for $k (sort keys %queries_per_tbl) {
	print "$k\t$queries_per_tbl{$k}\n";
}
