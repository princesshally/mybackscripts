#!/usr/bin/perl
# PFLOCAL
# PFDISTRIB
# usage: mysql-split-log.pl < mysql.log
$date="20161006";
$lastdate=$date;
$outfile="mysql.log-${date}.gz";
$outfile="mysql.log-${date}-2.gz" if (-f "$outfile");
open OUT, "|gzip -1c > $outfile";
$c=0;
$fc=1;
while(<STDIN>) {
	$c++;
	$raw=$_;
	chomp;
	if (substr($_,0,15) =~ /^\d{6}\s\d{2}:\d{2}:\d{2}/) {
		$date="20".substr($_,0,6);
	}
	if ($date ne $lastdate) {
		print "Date: $date\n";
		close OUT;
		$outfile="mysql.log-${date}.gz";
		$outfile="mysql.log-${date}-2.gz" if (-f "$outfile");
		$fc++;
		open OUT, "|gzip -1c > $outfile";
		$lastdate=$date;
	}
	print OUT $raw;
}
close OUT;

print "split into $fc logfiles.  Please rename/truncate source file now.\n";
exit 0;
