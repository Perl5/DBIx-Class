use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 2;

## Real view
my $cds_rs = $schema->resultset('CD')->search( { year => 2000 });
my $year2kcds_rs = $schema->resultset('Year2000CDs');

is($cds_rs->count, $year2kcds_rs->count, 'View Year2000CDs sees all CDs in year 2000');


## Virtual view
my $cds_rs = $schema->resultset('CD')->search( { year => 1999 });
my $year1999cds_rs = $schema->resultset('Year1999CDs');

is($cds_rs->count, $year1999cds_rs->count, 'View Year1999CDs sees all CDs in year 1999');




