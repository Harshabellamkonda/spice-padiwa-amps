#!/usr/bin/perl
use strict;
use warnings;
use Thread::Pool::Simple;
use File::Path qw(make_path rmtree);
use File::Copy 'cp';
use Cwd;

&main;

sub main {
  my $pool = Thread::Pool::Simple->new(
                 min => 2,           # at least 3 workers
                 max => 2,           # at most 5 workers
                 load => 10,         # increase worker if on average every worker has 10 jobs waiting
                 #init => [\&init_handle, $arg1, $arg2, ...]   # run before creating worker thread
                 #pre => [\&pre_handle, $arg1, $arg2, ...]   # run after creating worker thread
                 do => [\&do_work],     # job handler for each worker
                 #post => [\&post_handle, $arg1, $arg2, ...] # run before worker threads end
                 passid => 1,        # whether to pass the job id as the first argument to the &do_handle
                 lifespan => 10000,  # total jobs handled by each worker
               );

  $pool->add({
              'thresh_slow_rel' => [20],
              'thresh_fast_rel' => [20],
              'amplitude' => [300],
              'risetime' => [4, 8],
              'falltime' => [4]
             });
  $pool->add({
              'thresh_slow_rel' => [20],
              'thresh_fast_rel' => [20],
              'amplitude' => [300],
              'risetime' => [4, 8],
              'falltime' => [8, 10]
             });

  # wait till all jobs are done
  $pool->join();
}


sub do_work {
  my $id = shift;
  my $params = shift;
  my $workdir = "workdir/$id";
  print "Starting job $id...\n";
  prepare_workdir($workdir);
  create_asc_file($workdir, $params);
  run_ltspice($workdir);
  save_results($workdir, $params);
  print "Finished job $id...\n";
}



sub save_results {
  my $workdir = shift;
  my $params = shift;
  my $tag = 'simu2';
  my $savedir = "data/$tag";
  unless(-d $savedir) {
    make_path($savedir);
  }
  my $date = '2014-03-04-12:00:00'; # Time::Piece::localtime->strftime('%F-%T');
  my $filename =
    sprintf('%s-%s-%03.1f-%03.1f-%04.1f-%03.1f-%03.1f',
            $tag, $date,
            $params->{thresh_fast_rel}->[0],
            $params->{thresh_slow_rel}->[0],
            $params->{amplitude}->[0],
            $params->{risetime}->[0],
            $params->{falltime}->[0]);
  for(qw(log raw)) {
    cp "$workdir/padiwa-amps.$_","$savedir/$filename.$_" or die "can't copy $_ results: $!";
  }
  rmtree($workdir) or die "can't clean $workdir: $!";
}

sub run_ltspice {
  my $workdir = shift;
  my $olddir = getcwd();
  my $cmd = './ltspice.sh'; # runs by default padiwa-amps.asc...
  chdir $workdir;
  system($cmd) == 0
     or die "system $cmd failed: $?";
  chdir $olddir;
}


sub prepare_workdir {
  my $workdir = shift;
  rmtree($workdir);
  make_path($workdir);
  while(my $lib = <*.lib>) {
    cp $lib,"$workdir/$lib" or die "can't copy $lib: $!";
  }
  for(qw(ltspice.sh padiwa-amps.plt)) {
    cp $_, "$workdir/$_" or die "can't copy $_: $!";
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
  if($check{'multivalue'}==0) {
    die "At least one parameter should be stepped to generate a parsable logfile...";
  }
}

