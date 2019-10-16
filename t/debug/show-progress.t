use strict;
use warnings;

use Test::More;
use DBIx::Class::Storage::Debug::PrettyTrace;

my $cap;
open my $fh, '>', \$cap;

my $pp = DBIx::Class::Storage::Debug::PrettyTrace->new({
   show_progress => 1,
   clear_line    => 'CLEAR',
   executing     => 'GOGOGO',
});

$pp->debugfh($fh);

$pp->query_start('SELECT * FROM frew WHERE id = 1');
is(
   $cap,
   qq(SELECT * FROM frew WHERE id = 1 : \nGOGOGO),
   'SQL Logged'
);
$pp->query_end('SELECT * FROM frew WHERE id = 1');
is(
   $cap,
   qq(SELECT * FROM frew WHERE id = 1 : \nGOGOGOCLEAR),
   'SQL Logged'
);

done_testing;
