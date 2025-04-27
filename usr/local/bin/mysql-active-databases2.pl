#!/usr/bin/perl
$debug=0;
$verbose=0;
$auditpath="/db/mysql/data";
if ( -d "/db/audit" ) {
	$auditpath="/db/audit";
}

sub dprint {
  my $x=shift;
  printf STDERR "DEBUG: $x\n" if ($debug);
}

while($ARGV[0]) {
  $arg=$ARGV[0];
  shift @ARGV;
  if ($arg eq '-D') {
    $debug=1;
    next;
  }
  if ($arg eq '-v') {
    $verbose=1;
    next;
  }
}

open CMD, "cat ${auditpath}/server_audit.log.* ${auditpath}/server_audit.log  | grep -Ehiva 'SCHEMA|zenoss|_schema|zabbix|bigip.mon' | cut -d, -f 1,8 | uniq  |";
while(<CMD>){
  chomp;
  ($t,$d)=split(/,/);
  next unless $d;
  $t=~y/://d;
  $t=~y/ /-/;
  if (!exists($red{$d})) {
    dprint("loading cache for $d");
    if (-e "/var/log/mysql/last-access/$d") {
      open TMP, "</var/log/mysql/last-access/$d";
      $ok=0;
      while(<TMP>) {
        chomp;
	tr/\t/ /s;
	if (/^(2\d{7})[ -]+(\d{6})[ -]+(\d+)$/) {
	  ($td,$tt,$c)=($1,$2,$3);
          $lat{$d}=$td."-".$tt;
          dprint("/var/log/mysql/last-access/$d found with datestamp $lat{$d} (count $c)");
          $ok=1;
        }
      }
      close TMP;
      if (!$ok) {
        dprint("/var/log/mysql/last-access/$d didn't contain valid date");
      }
    } else {
      dprint("/var/log/mysql/last-access/$d doesn't exist");
    }
    $red{$d}=1;
    if (!$ok) {
      $lat{$d}="00000000-000000";
      dprint("Set LAT for $d to 00000000-000000 because no cache was found - probably new database")
    }
  }
  if ($t gt $lat{$d}) {
    $lat{$d}=$t;
    $c{$d}++;
  }
}

for (sort keys %lat) {
  if (/[a-z]/i) {
    if ($verbose) {
      print "$_\t$lat{$_}\t$c{$_}\n";
    } else {
      dprint("$_\t$lat{$_}\t$c{$_}");
    }
    #/var/log/mysql/last-access
    open OUT, ">/var/log/mysql/last-access/$_" or printf STDERR "open OUT: $!\n";
    print OUT "$lat{$_}\t$c{$_}\n";
    close OUT;
  }
}

