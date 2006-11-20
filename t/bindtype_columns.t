use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 2;

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

