BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;

use DBICTest::Util 'capture_stderr';

use DBICTest;

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

  # this should emit on stderr
  $output = capture_stderr { @arg_capture = () };
};

like(
  $output,
  qr/\QPreventing *MULTIPLE* DESTROY() invocations on DBIx::Class::Storage::TxnScopeGuard/,
  'Proper warning emitted on STDERR'
);

done_testing;
