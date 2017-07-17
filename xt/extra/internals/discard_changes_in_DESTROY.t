BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;

use DBICTest;

my $schema = DBICTest->init_schema();

{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_; };
    {
        # Test that this doesn't cause infinite recursion.
        local *DBICTest::Artist::DESTROY;
        local *DBICTest::Artist::DESTROY = sub { $_[0]->discard_changes };

        my $artist = $schema->resultset("Artist")->create( {
            artistid    => 10,
            name        => "artist number 10",
        });

        $artist->name("Wibble");

        print "# About to call DESTROY\n";
    }
    is_deeply \@warnings, [];
}

done_testing;
