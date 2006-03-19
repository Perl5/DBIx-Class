# vim: filetype=perl

sub run_tests {

    my $schema = shift;
    my $artists = $schema->resultset("Artist")->search({},{order_by=>'position'});

    plan tests => $artists->count();

    my $expected_position = 0;
    while (my $artist = $artists->next()) {
        $expected_position ++;
        ok( ($artist->position()==$expected_position), 'default positions set as expected' );
    }
}

1;
