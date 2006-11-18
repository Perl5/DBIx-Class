use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 2;

# figure out if we've got a version of sqlite that is older than 3.2.6, in
# which case COUNT(DISTINCT()) doesn't work
my $is_broken_sqlite = 0;
my ($sqlite_major_ver,$sqlite_minor_ver,$sqlite_patch_ver) =
    split /\./, $schema->storage->dbh->get_info(18);
if( $schema->storage->dbh->get_info(17) eq 'SQLite' &&
    ( ($sqlite_major_ver < 3) ||
      ($sqlite_major_ver == 3 && $sqlite_minor_ver < 2) ||
      ($sqlite_major_ver == 3 && $sqlite_minor_ver == 2 && $sqlite_patch_ver < 6) ) ) {
    $is_broken_sqlite = 1;
}


#Bindtest
{
	my $new = $schema->resultset("Artist")->new({
	
		artistid=>25,
		name=>'JohnNapiorkowski',
	});
	
	$new->update_or_insert;
	
	my $resultset = $schema->resultset("Artist")->find({artistid=>25});
	
	is($resultset->id, 25, 'Testing New ID');
	is($resultset->name, 'JohnNapiorkowski', 'Testing New Name');
}


