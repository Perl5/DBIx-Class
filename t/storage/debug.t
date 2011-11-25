use strict;
use warnings;
no warnings 'once';

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DBIC::DebugObj;
use DBIC::SqlMakerTest;
use Path::Class qw/file/;

BEGIN { delete @ENV{qw(DBIC_TRACE DBIC_TRACE_PROFILE DBICTEST_SQLITE_USE_FILE)} }

my $schema = DBICTest->init_schema();

my $lfn = file('t/var/sql.log');
unlink $lfn or die $!
  if -e $lfn;

# make sure we are testing the vanilla debugger and not ::PrettyPrint
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

open(STDERRCOPY, '>&STDERR');
close(STDERR);
dies_ok {
  $schema->resultset('CD')->search({})->count;
} 'Died on closed FH';

open(STDERR, '>&STDERRCOPY');

# test trace output correctness for bind params
{
    my ($sql, @bind);
    $schema->storage->debugobj(DBIC::DebugObj->new(\$sql, \@bind));

    my @cds = $schema->resultset('CD')->search( { artist => 1, cdid => { -between => [ 1, 3 ] }, } );
    is_same_sql_bind(
        $sql, \@bind,
        "SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM cd me WHERE ( artist = ? AND (cdid BETWEEN ? AND ?) )",
        [qw/'1' '1' '3'/],
        'got correct SQL with all bind parameters (debugcb)'
    );

    @cds = $schema->resultset('CD')->search( { artist => 1, cdid => { -between => [ 1, 3 ] }, } );
    is_same_sql_bind(
        $sql, \@bind,
        "SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM cd me WHERE ( artist = ? AND (cdid BETWEEN ? AND ?) )", ["'1'", "'1'", "'3'"],
        'got correct SQL with all bind parameters (debugobj)'
    );
}

done_testing;
