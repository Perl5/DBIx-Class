#!/usr/bin/env perl

#
# So you wrote a new mk_hash implementation which passed all tests
# (particularly t/inflate/hri.t) and would like to see how it holds
# up against older (and often buggy) versions of the same. Just run
# this script and wait (no editing necessary)

use warnings;
use strict;

use FindBin;
use lib ("$FindBin::Bin/../../lib", "$FindBin::Bin/../../t/lib");

use Class::Unload '0.07';
use Benchmark ();
use Dumbbench;
use Benchmark::Dumb ':all';
use DBICTest;

# for git reporting to work, and to use it as INC key directly
chdir ("$FindBin::Bin/../../lib");
my $hri_fn = 'DBIx/Class/ResultClass/HashRefInflator.pm';

require Getopt::Long;
my $getopt = Getopt::Long::Parser->new(
  config => [qw/gnu_getopt bundling_override no_ignore_case pass_through/]
);
my $args = {
  'bench-commits' => 2,
  'no-cpufreq-checks' => undef,
};
$getopt->getoptions($args, qw/
  bench-commits
  no-cpufreq-checks
/);

if (
  !$args->{'no-cpufreq-checks'}
    and
  $^O eq 'linux'
    and
  -r '/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq'
) {
  my ($min_freq, $max_freq, $governor) = map { local @ARGV = $_; my $s = <>; chomp $s; $s } qw|
    /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
    /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
    /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
  |;

  if ($min_freq != $max_freq) {
    die "Your OS seems to have an active CPU governor '$governor' -"
      . ' this will render benchmark results meaningless. Disable it'
      . ' by setting /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq'
      . ' to the same value as /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq'
      . " ($min_freq). Alternatively skip this check with --no-cpufreq-checks.\n";
  }
}

my %skip_commits = map { $_ => 1 } qw/
  e1540ee
  a5b2936
  4613ee1
  419ff18
/;
my (@to_bench, $not_latest);
for my $commit (`git log --format=%h HEAD ^8330454^ $hri_fn `) {
  chomp $commit;
  next if $skip_commits{$commit};
  my $diff = `git show -w -U0 --format=%ar%n%b $commit $hri_fn`;
  if ($diff =~ /^ (?: \@\@ \s .+? | [+-] sub \s) \$? mk_hash /xm ) {
    my ($age) = $diff =~ /\A(.+?)\n/;

    push @to_bench, {
      commit => $commit,
      title => $not_latest ? $commit : 'LATEST',
      desc => sprintf ("commit %s (%smade %s)...\t\t",
        $commit,
        $not_latest ? '' : 'LATEST, ',
        $age,
      ),
      code => scalar `git show $commit:lib/DBIx/Class/ResultClass/HashRefInflator.pm`,
    };

    last if @to_bench == $args->{'bench-commits'};
    $not_latest = 1;
  }
}
die "Can't find any commits... something is wrong\n" unless @to_bench;

unshift @to_bench, {
  desc => "the current uncommitted HRI...\t\t\t\t",
  title => 'CURRENT',
  code => do { local (@ARGV, $/) = ($hri_fn); <> },
} if `git status --porcelain $hri_fn`;

printf "\nAbout to benchmark %d HRI variants (%s)\n",
  scalar @to_bench,
  (join ', ', map { $_->{title} } @to_bench),
;

my $schema = DBICTest->init_schema();

# add some extra data for the complex test
$schema->resultset ('Artist')->create({
  name => 'largggge',
  cds => [
    {
      genre => { name => 'massive' },
      title => 'largesse',
      year => 2011,
      tracks => [
        {
          title => 'larguitto',
          cd_single => {
            title => 'mongo',
            year => 2012,
            artist => 1,
            genre => { name => 'massive' },
            tracks => [
              { title => 'yo momma' },
              { title => 'so much momma' },
            ],
          },
        },
      ],
    },
  ],
});

# get what data to feed during benchmarks
{
  package _BENCH_::DBIC::InflateResult::Trap;
  sub inflate_result { shift; return \@_ }
}
my %bench_dataset = (
  simple => do {
    my $rs = $schema->resultset ('Artist')->search ({}, {
      prefetch => { cds => 'tracks' },
      result_class => '_BENCH_::DBIC::InflateResult::Trap',
    });
    [ $rs->all ];
  },
  complex => do {
    my $rs = $schema->resultset ('Artist')->search ({}, {
      prefetch => { cds => [ { tracks => { cd_single => [qw/artist genre tracks/] } }, 'genre' ] },
      result_class => '_BENCH_::DBIC::InflateResult::Trap',
    });
    [ $rs->all ];
  },
);

# benchmark coderefs (num iters is set below)
my %num_iters;
my %bench = ( map { $_ => eval "sub {
  for (1 .. (\$num_iters{$_}||1) ) {
    DBIx::Class::ResultClass::HashRefInflator->inflate_result(\$bench_dataset{$_})
  }
}" } qw/simple complex/ );

$|++;
print "\nPre-timing current HRI to determine iteration counts...";
# crude unreliable and quick test how many to run in the loop
# designed to return a value so that there ~ 1/$div runs in a second
# (based on the current @INC implementation)
my $div = 1;
require DBIx::Class::ResultClass::HashRefInflator;
for (qw/simple complex/) {
  local $SIG{__WARN__} = sub {};
  my $tst = Benchmark::timethis(-1, $bench{$_}, '', 'none');
  $num_iters{$_} ||= int( $tst->[5] / $tst->[1] / $div );
  $num_iters{$_} ||= 1;
}
print " done\n\nBenchmarking - this can taka a LOOOOOONG time\n\n";

my %results;

for my $bch (@to_bench) {
  Class::Unload->unload('DBIx::Class::ResultClass::HashRefInflator');
  eval $bch->{code} or die $@;
  $INC{'DBIx/Class/ResultClass/HashRefInflator.pm'} = $bch->{title};

  for my $t (qw/simple complex/) {
    my $label = "Timing $num_iters{$t} $t iterations of $bch->{desc}";

    my $bench = Dumbbench->new(
      initial_runs => 30,
      target_rel_precision => 0.0005,
    );
    $bench->add_instances( Dumbbench::Instance::PerlSub->new (
      name => $label, code => $bench{$t},
    ));

    print $label;
    $bench->run;

    print(
      ($results{ (substr $t, 0, 1) . "_$bch->{title}" }
        = Benchmark::Dumb->_new( instance => ($bench->instances)[0] ) )
      ->timestr('')
    );
    print "\n";
  }
}

for my $t (qw/s c/) {
  cmpthese ({ map { $_ =~ /^${t}_/ ? ( $_ => $results{$_}) : () } keys %results }, '', '');
}
