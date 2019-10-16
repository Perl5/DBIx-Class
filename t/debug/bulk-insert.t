use strict;
use warnings;

use Test::More;
use DBIx::Class::Storage::Debug::PrettyTrace;

my $cap;
open my $fh, '>', \$cap;

my $pp = DBIx::Class::Storage::Debug::PrettyTrace->new({
   profile => 'none',
   fill_in_placeholders => 1,
   placeholder_surround => [qw(' ')],
   show_progress => 0,
});

$pp->debugfh($fh);

$pp->query_start('INSERT INTO self_ref_alias (alias, self_ref) VALUES ( ?, ? )', qw('__BULK_INSERT__' '1'));
is(
   $cap,
   qq{INSERT INTO self_ref_alias( alias, self_ref ) VALUES( ?, ? ) : '__BULK_INSERT__', '1'\n},
   'SQL Logged'
);

done_testing;
