# vim: filetype=perl

sub run_tests {

    my $schema = shift;
    my $artists = $schema->resultset("Artist");

    $artists->delete();
    $artists->create({ artistid=>1, name=>"Joe" });
    $artists->create({ artistid=>2, name=>"Bob" });
    $artists->create({ artistid=>3, name=>"Ted" });
    $artists->create({ artistid=>4, name=>"Ned" });
    $artists->create({ artistid=>5, name=>"Don" });

    $artists = $artists->search(undef,{order_by=>'position'});

    plan tests => 230;

    check_positions($schema);

    my $artist;

    foreach my $position (1..5) {

        $artist = $artists->find({ position=>$position });
        $artist->move_previous();
        check_positions($schema);

        $artist = $artists->find({ position=>$position });
        $artist->move_next();
        check_positions($schema);

        $artist = $artists->find({ position=>$position });
        $artist->move_first();
        check_positions($schema);

        $artist = $artists->find({ position=>$position });
        $artist->move_last();
        check_positions($schema);

        foreach my $to_position (1..5) {

            $artist = $artists->find({ position=>$position });
            $artist->move_to($to_position);
            check_positions($schema);

        }

    }

}

sub check_positions {
    my $schema = shift;
    my $artists = $schema->resultset("Artist")->search(undef,{order_by=>'position'});
    my $expected_position = 0;
    while (my $artist = $artists->next()) {
        $expected_position ++;
        ok( ($artist->position()==$expected_position), 'default positions set as expected' );
    }
}

1;
