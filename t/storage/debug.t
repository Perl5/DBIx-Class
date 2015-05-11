BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;
no warnings 'once';

BEGIN {
  delete @ENV{qw(
    DBIC_TRACE
    DBIC_TRACE_PROFILE
    DBICTEST_SQLITE_USE_FILE
    DBICTEST_VIA_REPLICATED
  )};
}

use Test::More;
use Test::Exception;
use Try::Tiny;
use File::Spec;

use DBICTest;
use DBICTest::Util 'slurp_bytes';

my $schema = DBICTest->init_schema();

my $log_fn = "t/var/sql-$$.log";
unlink $log_fn or die $! if -e $log_fn;

# make sure we are testing the vanilla debugger and not ::PrettyPrint
require DBIx::Class::Storage::Statistics;
$schema->storage->debugobj(DBIx::Class::Storage::Statistics->new);

ok ( $schema->storage->debug(1), 'debug' );
{
  open my $dbgfh, '>', $log_fn or die $!;
  $schema->storage->debugfh($dbgfh);
  $schema->storage->debugfh->autoflush(1);
  $schema->resultset('CD')->count;
  $schema->storage->debugfh(undef);
}

my @loglines = slurp_bytes $log_fn;
is (@loglines, 1, 'one line of log');
like($loglines[0], qr/^SELECT COUNT/, 'File log via debugfh success');


{
  local $ENV{DBIC_TRACE} = "=$log_fn";
  unlink $log_fn;

  $schema->resultset('CD')->count;

  my $schema2 = DBICTest->init_schema(no_deploy => 1);
  $schema2->storage->_do_query('SELECT 1'); # _do_query() logs via standard mechanisms

  my @loglines = slurp_bytes $log_fn;
  is(@loglines, 2, '2 lines of log');
  like($loglines[0], qr/^SELECT COUNT/, 'Env log from schema1 success');
  like($loglines[1], qr/^SELECT 1:/, 'Env log from schema2 success');

  $schema->storage->debugobj->debugfh(undef)
}

END {
  unlink $log_fn if $log_fn;
}

open(STDERRCOPY, '>&STDERR');

my $exception_line_number;
# STDERR will be closed, no T::B diag in blocks
my $exception = try {
  close(STDERR);
  $exception_line_number = __LINE__ + 1;  # important for test, do not reformat
  $schema->resultset('CD')->search({})->count;
} catch {
  $_
} finally {
  # restore STDERR
  open(STDERR, '>&STDERRCOPY');
};

ok $exception =~ /
  \QDuplication of STDERR for debug output failed (perhaps your STDERR is closed?)\E
    .+
  \Qat @{[__FILE__]} line $exception_line_number\E$
/xms
  or diag "Unexpected exception text:\n\n$exception\n";

my @warnings;
$exception = try {
  local $SIG{__WARN__} = sub { push @warnings, @_ if $_[0] =~ /character/i };
  close STDERR;
  open(STDERR, '>', File::Spec->devnull) or die $!;
  $schema->resultset('CD')->search({ title => "\x{1f4a9}" })->count;
  '';
} catch {
  $_;
} finally {
  # restore STDERR
  close STDERR;
  open(STDERR, '>&STDERRCOPY');
};

die "How did that fail... $exception"
  if $exception;

is_deeply(\@warnings, [], 'No warnings with unicode on STDERR');

# test debugcb and debugobj protocol
{
  my $rs = $schema->resultset('CD')->search( {
    artist => 1,
    cdid => { -between => [ 1, 3 ] },
    title => { '!=' => \[ '?', undef ] }
  });

  my $sql_trace = 'SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM cd me WHERE ( ( artist = ? AND ( cdid BETWEEN ? AND ? ) AND title != ? ) )';
  my @bind_trace = qw( '1' '1' '3' NULL );  # quotes are in fact part of the trace </facepalm>


  my @args;
  $schema->storage->debugcb(sub { push @args, @_ } );

  $rs->all;

  is_deeply( \@args, [
    "SELECT",
    sprintf( "%s: %s\n", $sql_trace, join ', ', @bind_trace ),
  ]);

  {
    package DBICTest::DebugObj;
    our @ISA = 'DBIx::Class::Storage::Statistics';

    sub query_start {
      my $self = shift;
      ( $self->{_traced_sql}, @{$self->{_traced_bind}} ) = @_;
    }
  }

  my $do = $schema->storage->debugobj(DBICTest::DebugObj->new);

  $rs->all;

  is( $do->{_traced_sql}, $sql_trace );

  is_deeply ( $do->{_traced_bind}, \@bind_trace );
}

# recreate test as seen in DBIx::Class::QueryLog
# the rationale is that if someone uses a non-IO::Handle object
# on CPAN, many are *bound* to use one on darkpan. Thus this
# test to ensure there is no future silent breakage
{
  my $output = "";

  {
    package DBICTest::_Printable;

    sub print {
      my ($self, @args) = @_;
      $output .= join('', @args);
    }
  }

  $schema->storage->debugobj(undef);
  $schema->storage->debug(1);
  $schema->storage->debugfh( bless {}, "DBICTest::_Printable" );
  $schema->storage->txn_do( sub { $schema->resultset('Artist')->count } );

  like (
    $output,
    qr/
      \A
      ^ \QBEGIN WORK\E \s*?
      ^ \QSELECT COUNT( * ) FROM artist me:\E \s*?
      ^ \QCOMMIT\E \s*?
      \z
    /xm
  );

  $schema->storage->debug(0);
  $schema->storage->debugfh(undef);
}

done_testing;
