#!/usr/bin/perl
use strict;
use warnings;
use Thread::Pool::Simple;
use File::Path qw(make_path);

&main;

sub main {
  create_asc_file('workdir/bla',
                  {
                   'thresh_slow_rel' => [20],
                   'thresh_fast_rel' => [20],
                   'amplitude' => [100, 200],
                   'risetime' => [100, 200],
                   'falltime' => [100, 200]
                  });
}


sub create_asc_file {
  my $workdir = shift;
  my $params = shift;
  make_path($workdir);
  my $ascfile = 'padiwa-amps.asc';
  open(my $fh_in, "<$ascfile") or die "can't open $ascfile: $!";
  open(my $fh_out, ">$workdir/$ascfile") or die "can't open $workdir/$ascfile: $!";
  my $units =
    {
     'thresh_slow_rel' => 'm', # mV
     'thresh_fast_rel' => 'm', # mV
     'amplitude' => 'm',       # mV
     'risetime' => 'n',        # ns
     'falltime' => 'n'         # ns
    };
  my %check; 
  while(my $line = <$fh_in>) {
    unless($line =~ /^TEXT/ &&
           $line =~ /(.*?!);?(\.step|\.param)(.*?)$/) {
      print $fh_out $line;
      next;
    }
    # capture the regex matches
    my $leading = $1; # everything before without optional comment ";"
    my $cmd = $2;
    my $rest = $3;
    $rest =~ s/^\s+|\s+$//g; # trim whitespace
    # extract the param, then skip
    # uninteresting ones...
    my $param;
    if($cmd eq '.step' &&
       $rest =~ /^param\s+(\w+)/) {
      $param = $1;
    }
    elsif($cmd eq '.param' &&
          $rest =~ /^(\w+)\s*?=/) {
      $param = $1;
    }
    unless(defined $param && exists $params->{$param}) {
      print $fh_out $line;
      next;
    }
    $check{$cmd}++;
    my @vals = @{$params->{$param}};
    my $unit = $units->{$param} || '';
    
    print $cmd," ",$param,"\n";

    print $fh_out $line;
  }
  close $fh_in;
  close $fh_out;
  unless($check{'.param'} == 5 &&
         $check{'.step'} == 5) {
    die "$ascfile does not contain five .param and five .step directives";
  }
}

