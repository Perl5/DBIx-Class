use strict;
use warnings; 

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 5;

ok ( $schema->storage->debug(1), 'debug' );
ok ( defined(
       $schema->storage->debugfh(
         IO::File->new('t/var/sql.log', 'w')
       )
     ),
     'debugfh'
   );

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

1;
