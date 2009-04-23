use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 13;

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

# Tests a regression in ResultSetColumn wrt +select
$rs = $schema->resultset('CD')->search(undef,
    {
        '+select'   => [ \'COUNT(*) AS year_count' ],
		order_by => 'year_count'
	}
);
my @counts = $rs->get_column('cdid')->all;
ok(scalar(@counts), 'got rows from ->all using +select');

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


# test the from search attribute (gets between the FROM and WHERE keywords, allows arbitrary subselects)
# also shows that outer select attributes are ok (i.e. order_by)
#
# from doesn't seem to be useful without using a scalarref - there were no initial tests >:(
#
my $cds = $schema->resultset ('CD')->search ({}, { order_by => 'me.cdid'}); # make sure order is consistent
cmp_ok ($cds->count, '>', 2, 'Initially populated with more than 2 CDs');

my $table = $cds->result_source->name;
my $subsel = $cds->search ({}, {
    columns => [qw/cdid title/],
    from => \ "(SELECT cdid, title FROM $table LIMIT 2) me",
});

is ($subsel->count, 2, 'Subselect correctly limited the rs to 2 cds');
is ($subsel->next->title, $cds->next->title, 'First CD title match');
is ($subsel->next->title, $cds->next->title, 'Second CD title match');

is($schema->resultset('CD')->current_source_alias, "me", '$rs->current_source_alias returns "me"');
