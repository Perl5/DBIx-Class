use strict;
use warnings;
no warnings 'once';

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use Path::Class qw/file/;

BEGIN { delete @ENV{qw(DBIC_TRACE DBIC_TRACE_PROFILE DBICTEST_SQLITE_USE_FILE)} }

my $schema = DBICTest->init_schema();

my $lfn = file("t/var/sql-$$.log");
unlink $lfn or die $!
  if -e $lfn;

# make sure we are testing the vanilla debugger and not ::PrettyPrint
require DBIx::Class::Storage::Statistics;
$schema->storage->debugobj(DBIx::Class::Storage::Statistics->new);

ok ( $schema->storage->debug(1), 'debug' );
$schema->storage->debugfh($lfn->openw);
$schema->storage->debugfh->autoflush(1);
$schema->resultset('CD')->count;

my @loglines = $lfn->slurp;
is (@loglines, 1, 'one line of log');
like($loglines[0], qr/^SELECT COUNT/, 'File log via debugfh success');

$schema->storage->debugfh(undef);

{
  local $ENV{DBIC_TRACE} = "=$lfn";
  unlink $lfn;

  $schema->resultset('CD')->count;

  my $schema2 = DBICTest->init_schema(no_deploy => 1);
  $schema2->storage->_do_query('SELECT 1'); # _do_query() logs via standard mechanisms

  my @loglines = $lfn->slurp;
  is(@loglines, 2, '2 lines of log');
  like($loglines[0], qr/^SELECT COUNT/, 'Env log from schema1 success');
  like($loglines[1], qr/^SELECT 1:/, 'Env log from schema2 success');

  $schema->storage->debugobj->debugfh(undef)
}

END {
  unlink $lfn;
}

open(STDERRCOPY, '>&STDERR');
close(STDERR);
dies_ok {
  $schema->resultset('CD')->search({})->count;
} 'Died on closed FH';

open(STDERR, '>&STDERRCOPY');

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

done_testing;
