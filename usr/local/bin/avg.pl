#!/usr/bin/perl
# PFLOCAL
# PFDISTRIB
$a=0;
$c=0;
while (@ARGV) {
  $arg=shift @ARGV;
  $showcount=1 if ($arg eq '-c');
  $ignorezero=1 if ($arg eq '-z');
}

while(<>){
  chomp;
  if ($_ > 0 || !$ignorezero) {
    $a+=$_;
    $c++;
  }
};
if (!$c) {
  print STDERR "zero values found\n";
  exit 1
}

if ($showcount) {
	print $a/$c."\t$c\n";
} else {
	print $a/$c."\n";
}
exit 0;

