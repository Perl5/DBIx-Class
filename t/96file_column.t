use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;
use IO::File;

my $schema = DBICTest->init_schema();

plan tests => 2;


eval { $schema->resultset('FileColumn')->create({file=>'wrong set'}) };
ok($@, 'FileColumn checking for checks against bad sets');
my $fh = new IO::File('t/96file_column.pm','r');
eval { $schema->resultset('FileColumn')->create({file => {handle => $fh, filename =>'96file_column.pm'}})};
ok(!$@,'FileColumn checking if file handled properly.');
