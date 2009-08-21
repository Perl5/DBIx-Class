use strict;
use warnings; 

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::DebugObj;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();

plan tests => 7;

ok ( $schema->storage->debug(1), 'debug' );
ok ( defined(
       $schema->storage->debugfh(
         IO::File->new('t/var/sql.log', 'w')
       )
     ),
     'debugfh'
   );

$schema->storage->debugfh->autoflush(1);
my $rs = $schema->resultset('CD')->search({});
$rs->count();

my $log = new IO::File('t/var/sql.log', 'r') or die($!);
my $line = <$log>;
$log->close();
ok($line =~ /^SELECT COUNT/, 'Log success');

$schema->storage->debugfh(undef);
$ENV{'DBIC_TRACE'} = '=t/var/foo.log';
$rs = $schema->resultset('CD')->search({});
$rs->count();
$log = new IO::File('t/var/foo.log', 'r') or die($!);
$line = <$log>;
$log->close();
ok($line =~ /^SELECT COUNT/, 'Log success');
$schema->storage->debugobj->debugfh(undef);
delete($ENV{'DBIC_TRACE'});
open(STDERRCOPY, '>&STDERR');
stat(STDERRCOPY); # nop to get warnings quiet
close(STDERR);
eval {
    $rs = $schema->resultset('CD')->search({});
    $rs->count();
};
ok($@, 'Died on closed FH');
open(STDERR, '>&STDERRCOPY');

# test trace output correctness for bind params
{
    my ($sql, @bind);
    $schema->storage->debugobj(DBIC::DebugObj->new(\$sql, \@bind));

    my @cds = $schema->resultset('CD')->search( { artist => 1, cdid => { -between => [ 1, 3 ] }, } );
    is_same_sql_bind(
        $sql, \@bind,
        "SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM cd me WHERE ( artist = ? AND (cdid BETWEEN ? AND ?) ): '1', '1', '3'",
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

1;
