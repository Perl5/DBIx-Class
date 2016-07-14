BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use File::Temp ();

use DBICTest::Util 'tmpdir';
use DBIx::Class::_Util 'scope_guard';

use DBICTest;

open(my $stderr_copy, '>&', *STDERR) or die "Unable to dup STDERR: $!";
my $tf = File::Temp->new( UNLINK => 1, DIR => tmpdir() );

my $output;

# ensure Devel::StackTrace-refcapture-like effects are countered
{
  my $s = DBICTest::Schema->connect('dbi:SQLite::memory:');
  my $g = $s->txn_scope_guard;

  my @arg_capture;
  {
    local $SIG{__WARN__} = sub {
      package DB;
      my $frnum;
      while (my @f = CORE::caller(++$frnum) ) {
        push @arg_capture, @DB::args;
      }
    };

    undef $g;
    1;
  }

  my $guard = scope_guard {
    close STDERR;
    open(STDERR, '>&', $stderr_copy);
    $output = do { local (@ARGV, $/) = $tf; <> };
    close $tf;
    unlink $tf;
    undef $tf;
    close $stderr_copy;
  };

  close STDERR;
  open(STDERR, '>&', $tf) or die "Unable to reopen STDERR: $!";

  # this should emit on stderr
  @arg_capture = ();
}

like(
  $output,
  qr/\QPreventing *MULTIPLE* DESTROY() invocations on DBIx::Class::Storage::TxnScopeGuard/,
  'Proper warning emitted on STDERR'
);

done_testing;
