use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 7;

my $rs = $schema->resultset('CD')->search({},
    {
        '+select'   => \ 'COUNT(*)',
        '+as'       => 'count'
    }
);
lives_ok(sub { $rs->first->get_column('count') }, 'additional count rscolumn present');
dies_ok(sub { $rs->first->get_column('nonexistent_column') }, 'nonexistant column requests still throw exceptions');

$rs = $schema->resultset('CD')->search({},
    {
        '+select'   => [ \ 'COUNT(*)', 'title' ],
        '+as'       => [ 'count', 'addedtitle' ]
    }
);
lives_ok(sub { $rs->first->get_column('count') }, 'multiple +select/+as columns, 1st rscolumn present');
lives_ok(sub { $rs->first->get_column('addedtitle') }, 'multiple +select/+as columns, 2nd rscolumn present');

$rs = $schema->resultset('CD')->search({},
    {
        '+select'   => [ \ 'COUNT(*)', 'title' ],
        '+as'       => [ 'count', 'addedtitle' ]
    }
)->search({},
    {
        '+select'   => 'title',
        '+as'       => 'addedtitle2'
    }
);
lives_ok(sub { $rs->first->get_column('count') }, '+select/+as chained search 1st rscolumn present');
lives_ok(sub { $rs->first->get_column('addedtitle') }, '+select/+as chained search 1st rscolumn present');
lives_ok(sub { $rs->first->get_column('addedtitle2') }, '+select/+as chained search 3rd rscolumn present');
