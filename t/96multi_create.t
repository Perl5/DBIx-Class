use strict;
use warnings;

use Test::More qw(no_plan);
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $cd2 = $schema->resultset('CD')->create({ artist => 
                                   { name => 'Fred Bloggs' },
                                   title => 'Some CD',
                                   year => 1996
                                 });

is(ref $cd2->artist, 'DBICTest::Artist', 'Created CD and Artist object');
is($cd2->artist->name, 'Fred Bloggs', 'Artist created correctly');

my $artist = $schema->resultset('Artist')->create({ name => 'Fred 2',
                                                     cds => [
                                                             { title => 'Music to code by',
                                                               year => 2007,
                                                             },
                                                             ],
                                                     });
is(ref $artist->cds->first, 'DBICTest::CD', 'Created Artist with CDs');
is($artist->cds->first->title, 'Music to code by', 'CD created correctly');

# Add a new CD
$artist->update({cds => [ $artist->cds, 
                          { title => 'Yet another CD',
                            year => 2006,
                          },
                        ],
                });
is(($artist->cds->search({}, { order_by => 'year' }))[0]->title, 'Yet another CD', 'Updated and added another CD');

my $newartist = $schema->resultset('Artist')->find_or_create({ name => 'Fred 2'});

is($newartist->name, 'Fred 2', 'Retrieved the artist');


my $newartist2 = $schema->resultset('Artist')->find_or_create({ name => 'Fred 3',
                                                                cds => [
                                                                        { title => 'Noah Act',
                                                                          year => 2007,
                                                                        },
                                                                       ],

                                                              });

is($newartist2->name, 'Fred 3', 'Created new artist with cds via find_or_create');


CREATE_RELATED1 :{

	my $artist = $schema->resultset('Artist')->first;
	
	my $cd_result = $artist->create_related('cds', {
	
		title => 'TestOneCD1',
		year => 2007,
		tracks => [
		
			{ position=>111,
			  title => 'TrackOne',
			},
			{ position=>112,
			  title => 'TrackTwo',
			}
		],

	});
	
	ok( $cd_result && ref $cd_result eq 'DBICTest::CD', "Got Good CD Class");
	ok( $cd_result->title eq "TestOneCD1", "Got Expected Title");
	
	my $tracks = $cd_result->tracks;
	
	ok( ref $tracks eq "DBIx::Class::ResultSet", "Got Expected Tracks ResultSet");
	
	foreach my $track ($tracks->all)
	{
		ok( $track && ref $track eq 'DBICTest::Track', 'Got Expected Track Class');
	}
}

CREATE_RELATED2 :{

	my $artist = $schema->resultset('Artist')->first;
	
	my $cd_result = $artist->create_related('cds', {
	
		title => 'TestOneCD2',
		year => 2007,
		tracks => [
		
			{ position=>111,
			  title => 'TrackOne',
			},
			{ position=>112,
			  title => 'TrackTwo',
			}
		],

    liner_notes => { notes => 'I can haz liner notes?' },

	});
	
	ok( $cd_result && ref $cd_result eq 'DBICTest::CD', "Got Good CD Class");
	ok( $cd_result->title eq "TestOneCD2", "Got Expected Title");
  ok( $cd_result->notes eq 'I can haz liner notes?', 'Liner notes');
	
	my $tracks = $cd_result->tracks;
	
	ok( ref $tracks eq "DBIx::Class::ResultSet", "Got Expected Tracks ResultSet");
	
	foreach my $track ($tracks->all)
	{
		ok( $track && ref $track eq 'DBICTest::Track', 'Got Expected Track Class');
	}
}
