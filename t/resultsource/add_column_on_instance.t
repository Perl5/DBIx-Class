BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;

use DBICTest;

my $ar = DBICTest->init_schema->resultset("Artist")->find(1);

ok (! $ar->can("not_yet_there_column"), "No accessor for nonexitentcolumn" );

$ar->add_column("not_yet_there_column");
ok ($ar->has_column("not_yet_there_column"), "Metadata correct after nonexitentcolumn addition" );
ok ($ar->can("not_yet_there_column"), "Accessor generated for nonexitentcolumn" );

$ar->not_yet_there_column('I EXIST \o/');

is { $ar->get_columns }->{not_yet_there_column}, 'I EXIST \o/', "Metadata propagates to mutli-column methods";

done_testing;
