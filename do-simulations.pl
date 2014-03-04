#!/usr/bin/perl
use strict;
use warnings;
use Thread::Pool::Simple;
use File::Path qw(make_path rmtree);
use File::Copy;

&main;

sub main {
  my $workdir = 'workdir/bla';
  prepare_workdir($workdir);
  create_asc_file($workdir,
                  {
                   'thresh_slow_rel' => [20],
                   'thresh_fast_rel' => [20],
                   'amplitude' => [100, 200],
                   'risetime' => [1, 4, 8],
                   'falltime' => [1, 4, 8 ]
                  });
}

sub prepare_workdir {
  my $workdir = shift;
  rmtree($workdir);
  make_path($workdir);
  while(my $lib = <*.lib>) {
    copy $lib,"$workdir/$lib" or die "can't copy $lib: $!";
  }
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
  my %check = ('multivalue' => 0, '.step' => 0, '.param' => 0);
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
    # uninteresting params...
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

    # always set param to first value
    # if single-valued, comment out .step
    # if multi-valued, set .step to list of values
    if(@vals>0 && $cmd eq '.param') {
      $line = $leading.$cmd.' '.$param.'='.$vals[0].$unit;
    }
    elsif ($cmd eq '.step') {
      if(@vals==1) {
        $line = $leading.';'.$cmd.' '.$rest;
      }
      elsif(@vals>1) {
        $check{'multivalue'}++;
        $line = $leading.$cmd.' param '.$param.' list ';
        for(@vals) {
          $line .= $_.$unit.' ';
        }
      }
    }


    # finally print the modified $line
    print $fh_out "$line\n";
  }
  close $fh_in;
  close $fh_out;
  unless($check{'.param'} == 5 &&
         $check{'.step'} == 5) {
    die "$ascfile does not contain five .param and five .step directives";
  }
  if($check{'multivalue'}>3) {
    die "Spice does not support stepping more than three parameters";
  }
}

